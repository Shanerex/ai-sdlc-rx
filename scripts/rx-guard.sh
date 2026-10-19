#!/usr/bin/env bash
# rx-guard.sh: PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit. Reads the hook JSON on
# stdin (tool_name, tool_input.file_path or .notebook_path, cwd, agent_id).
# Exit 0 allows. Exit 2 blocks, with a one-line `rx-guard: <reason>` on stderr.
# Blocks:
#   - docs/knowledge/architecture.md (human-only; propose changes in plan.md)
#   - .rx/config.yml and .rx/scripts/** (an agent must not reconfigure or rewrite the gates)
#   - from a subagent (hook JSON has agent_id): any change to a g1-g3 line of specs/<id>/state.md.
#     The orchestrator runs in the main thread (no agent_id), so it may write them.
#   - when enforce_plan_first is true (default) and a feature is active: paths matching
#     source_globs while g2 is not approved:*. specs/, docs/ and .rx/ are never plan-first blocked.
# Allows (never blocks): no active feature (a branch outside branch_pattern and no
# .rx/local/active means "no active feature"), paths outside the repo, an invalid or
# missing state.md (a warning is printed instead), an unreadable payload, other tools.
# `rx-guard.sh --staged` is the git pre-commit form: no stdin; blocks (exit 2) when a staged path
# (deletions too) matches source_globs while g2 is not approved. Does nothing on base_branch.
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-guard: rx-lib.sh not found\n' >&2
  exit 2
fi
rx_noop_unless_enabled

_g_block() {
  printf 'rx-guard: %s\n' "$*" >&2
  exit 2
}
_g_warn() { printf 'rx-guard: warning: %s\n' "$*" >&2; }

# _g_plan_first_paths: NUL-separated paths on stdin, minus the ones plan-first never blocks.
_g_plan_first_paths() {
  local path
  while IFS= read -r -d '' path; do
    case "$path" in
      specs/*|docs/*|.rx/*) ;;
      *) printf '%s\0' "$path" ;;
    esac
  done
}

if [ "${1-}" = "--staged" ]; then
  # Git pre-commit mode: plan-first over the staged paths (deletions included). No stdin.
  cd "$(rx_root)" 2>/dev/null || exit 0
  case "$(rx_cfg enforce_plan_first true)" in
    false|False|FALSE|no|No|NO|off|Off|OFF|0) exit 0 ;;
  esac
  # On the base branch there is no active feature, whatever .rx/local/active says.
  [ "$(git symbolic-ref --short -q HEAD 2>/dev/null)" != "$(rx_cfg base_branch main)" ] || exit 0
  ID="$(rx_feature_id)" || exit 0
  if ! reason="$(rx_state_valid "$ID" 2>&1)"; then
    _g_warn "$reason"
    exit 0
  fi
  case "$(rx_state_get "$ID" g2)" in
    approved:*) exit 0 ;;
  esac
  # One batch glob pass over the staged paths (a per-path rx_glob_match costs about 25 ms a file).
  hit="$(git diff --cached --name-only -z --no-renames 2>/dev/null | _g_plan_first_paths \
    | RX_GLOB_NOSTAT=1 rx_glob_filter source_globs | head -n 1)"
  if [ -n "$hit" ]; then
    _g_block "G2 (plan approval) is not recorded for feature $ID; finish requirements and plan first (/rx:next) before committing $hit"
  fi
  exit 0
fi

INPUT="$(cat)"
case "$INPUT" in
  *[![:space:]]*) ;;
  *) exit 0 ;;
esac
if ! command -v jq >/dev/null 2>&1; then
  _g_warn "jq not found, guard skipped"
  exit 0
fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  _g_warn "unreadable hook payload, guard skipped"
  exit 0
fi
_g_jq() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }

TOOL="$(_g_jq '.tool_name // ""')"
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac
FILE="$(_g_jq '.tool_input.file_path // .tool_input.notebook_path // ""')"
[ -n "$FILE" ] || exit 0
PCWD="$(_g_jq '.cwd // ""')"
AGENT="$(_g_jq '.agent_id // ""')"
if [ -n "$PCWD" ] && [ -d "$PCWD" ]; then
  cd "$PCWD" 2>/dev/null || true
fi
rx_noop_unless_enabled

# _g_norm <path>: collapse //, . and .. textually (the path may not exist yet).
_g_norm() {
  local p="$1" seg out="" old_ifs="$IFS" n
  local -a parts=() stack=()
  IFS=/
  # shellcheck disable=SC2206
  parts=($p)
  IFS="$old_ifs"
  for seg in "${parts[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..)
        n=${#stack[@]}
        if [ "$n" -gt 0 ]; then unset "stack[$((n - 1))]"; fi
        ;;
      *) stack[${#stack[@]}]="$seg" ;;
    esac
  done
  for seg in ${stack[@]+"${stack[@]}"}; do out="$out/$seg"; done
  printf '%s\n' "${out:-/}"
}

# _g_resolve <abs-normalised-path>: resolve symlinks in the longest existing ancestor
# directory (macOS /var -> /private/var), append the not-yet-existing rest.
_g_resolve() {
  local p="$1" head="$1" tail="" phys
  while [ "$head" != "/" ] && [ ! -d "$head" ]; do
    tail="/${head##*/}$tail"
    head="${head%/*}"
    [ -n "$head" ] || head="/"
  done
  phys="$(cd -P -- "$head" 2>/dev/null && pwd -P)" || { printf '%s\n' "$p"; return 0; }
  [ "$phys" = "/" ] && phys=""
  printf '%s%s\n' "$phys" "$tail"
}

case "$FILE" in
  /*) ABS="$FILE" ;;
  *) ABS="$PWD/$FILE" ;;
esac
ABS="$(_g_resolve "$(_g_norm "$ABS")")"
ROOT="$(cd -P -- "$(rx_root)" 2>/dev/null && pwd -P)" || ROOT="$(rx_root)"
case "$ABS" in
  "$ROOT"/*) REL="${ABS#"$ROOT"/}" ;;
  *) exit 0 ;;
esac

case "$REL" in
  docs/knowledge/architecture.md)
    _g_block "docs/knowledge/architecture.md is human-only; propose the change in specs/<id>/plan.md"
    ;;
  .rx/config.yml)
    _g_block ".rx/config.yml is human-only; edit it yourself, not through an agent"
    ;;
  .rx/scripts|.rx/scripts/*)
    _g_block ".rx/scripts is installed by /rx:init; refresh it with /rx:init --refresh-scripts"
    ;;
esac

# Gate lines: a subagent may never change g1-g3.
case "$REL" in
  specs/*/state.md)
    SID="${REL#specs/}"
    SID="${SID%/state.md}"
    if [ -n "$AGENT" ] && rx_valid_id "$SID"; then
      NEWTEXT="$(_g_jq '[.tool_input.new_string?, .tool_input.content?, (.tool_input.edits[]?.new_string?)] | map(select(type == "string")) | join("\n")')"
      while IFS= read -r line; do
        line="${line%$'\r'}"
        case "$line" in
          g[123]:*) ;;
          *) continue ;;
        esac
        key="${line%%:*}"
        new="$(_rx_trim "${line#*:}")"
        cur="$(rx_state_get "$SID" "$key")" || cur=""
        [ -n "$cur" ] || cur="none"
        if [ "$new" != "$cur" ]; then
          _g_block "$key in $REL is written by the orchestrator after a human yes, not by a subagent"
        fi
      done <<GATE_LINES
$NEWTEXT
GATE_LINES
    fi
    ;;
esac

# Plan-first.
case "$(rx_cfg enforce_plan_first true)" in
  false|False|FALSE|no|No|NO|off|Off|OFF|0) exit 0 ;;
esac
case "$REL" in
  specs/*|docs/*|.rx/*) exit 0 ;;
esac
ID="$(rx_feature_id)" || exit 0
if ! reason="$(rx_state_valid "$ID" 2>&1)"; then
  _g_warn "$reason"
  exit 0
fi
G2="$(rx_state_get "$ID" g2)"
case "$G2" in
  approved:*) exit 0 ;;
esac
if rx_glob_match "$REL"; then
  _g_block "G2 (plan approval) is not recorded for feature $ID; finish requirements and plan first (/rx:next) before editing $REL"
fi
exit 0
