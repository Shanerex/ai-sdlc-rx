#!/usr/bin/env bash
# rx-gate-tests.sh: Stop / SubagentStop hook. In the build phase it blocks stopping (exit 2)
# while test_cmd is red; otherwise exit 0 (stdout stays empty). Reads the hook JSON on stdin
# (stop_hook_active, cwd).
#   - Acts only when a feature is active, its state.md is valid, phase is build and status
#     is not blocked (dev stops on a blocker with red tests on purpose).
#   - stop_hook_active true => exit 0: the gate blocks a stop once, never in a loop.
#   - Skips when the files matching source_globs and test_globs (tracked + untracked, not
#     ignored) plus test_cmd and the globs hash like the last green run
#     (.rx/local/test-hash). No git => no cache, the tests run every time.
#   - Otherwise runs test_cmd (limited to test_timeout seconds, default 600, in the
#     caller's locale). Green stores the hash. Red or timeout exits 2 with a one-line header
#     and the last 15 lines of output on stderr. A missing test_cmd exits 2 with a message.
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-gate: rx-lib.sh not found\n' >&2
  exit 2
fi
rx_noop_unless_enabled
rx_locale_c

INPUT="$(cat)"
PCWD=""
ACTIVE=""
if command -v jq >/dev/null 2>&1 && printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  PCWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)"
fi
[ "$ACTIVE" != true ] || exit 0
if [ -n "$PCWD" ] && [ -d "$PCWD" ]; then
  cd "$PCWD" 2>/dev/null || true
fi
rx_noop_unless_enabled

ID="$(rx_feature_id)" || exit 0
if ! reason="$(rx_state_valid "$ID" 2>&1)"; then
  printf 'rx-gate: warning: %s\n' "$reason" >&2
  exit 0
fi
[ "$(rx_state_get "$ID" phase)" = build ] || exit 0
[ "$(rx_state_get "$ID" status)" != blocked ] || exit 0

CMD="$(rx_cfg test_cmd)"
if [ -z "$CMD" ]; then
  printf 'rx-gate: test_cmd is missing in .rx/config.yml; set it so the build phase can be gated\n' >&2
  exit 2
fi
TIMEOUT="$(rx_cfg test_timeout 600)"
case "$TIMEOUT" in
  ''|*[!0123456789]*|0|00*) TIMEOUT=600 ;;
esac

ROOT="$(rx_root)"
HASHFILE="$ROOT/.rx/local/test-hash"
HASH=""
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  # Sorted file list (NUL-safe), content ids from git, plus the command and globs.
  HASH="$(
    cd "$ROOT" || exit 0
    {
      printf 'cmd=%s\nsrc=%s\ntest=%s\n' "$CMD" "$(rx_cfg source_globs)" "$(rx_cfg test_globs)"
      git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -z | while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        if rx_glob_match "$f" || rx_glob_match_key test_globs "$f"; then
          printf '%s %s\n' "$(git hash-object -- "$f")" "$f"
        fi
      done
    } | shasum -a 256 | cut -d' ' -f1
  )"
  if [ -n "$HASH" ] && [ -f "$HASHFILE" ]; then
    LAST=""
    IFS= read -r LAST < "$HASHFILE" || true
    [ "$LAST" != "$HASH" ] || exit 0
  fi
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rx-gate.XXXXXX")" || exit 0
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT" || exit 0
rx_locale_user
rx_run_timeout "$TIMEOUT" "$TMP/out" "$CMD"
rc=$?
rx_locale_c
tail15() { tr -d '\r' < "$TMP/out" | tail -n 15; }
if [ "$RX_RT_STATE" = timeout ]; then
  printf 'rx-gate: tests timed out after %ss; fix or speed up test_cmd before stopping\n' "$TIMEOUT" >&2
  tail15 >&2
  exit 2
fi
if [ "$rc" -ne 0 ]; then
  printf 'rx-gate: tests failed (exit %s); fix them before stopping\n' "$rc" >&2
  tail15 >&2
  exit 2
fi
if [ -n "$HASH" ]; then
  mkdir -p "$ROOT/.rx/local" 2>/dev/null && printf '%s\n' "$HASH" > "$HASHFILE"
fi
exit 0
