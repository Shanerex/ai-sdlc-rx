#!/usr/bin/env bash
# hooks/hooks.json: guard on PreToolUse, test gate on Stop and SubagentStop.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

H="$ROOT/hooks/hooks.json"
assert_exit 0 jq -e . "$H"
q() { jq -r "$1" "$H"; }

assert_eq "Edit|Write|MultiEdit|NotebookEdit" "$(q '.hooks.PreToolUse[0].matcher')" "PreToolUse matcher covers every file-edit tool"
assert_eq '"${CLAUDE_PLUGIN_ROOT}/scripts/rx-guard.sh"' "$(q '.hooks.PreToolUse[0].hooks[0].command')" "PreToolUse runs the guard"
assert_eq "1" "$(q '.hooks.PreToolUse | length')" "one PreToolUse entry"
for ev in Stop SubagentStop; do
  assert_eq '"${CLAUDE_PLUGIN_ROOT}/scripts/rx-gate-tests.sh"' "$(q ".hooks.$ev[0].hooks[0].command")" "$ev runs the test gate"
  assert_eq "command" "$(q ".hooks.$ev[0].hooks[0].type")" "$ev hook type"
  # The hook must outlive test_cmd's own limit (test_timeout, default 600) so a slow suite
  # is reported by the gate, not killed by the host (which can orphan the test process group).
  t="$(q ".hooks.$ev[0].hooks[0].timeout")"
  case "$t" in ''|null|*[!0-9]*) _rx_fail "$ev timeout must be an integer, got '$t'" ;; *) [ "$t" -ge 660 ] || _rx_fail "$ev timeout $t < 600 + 60 margin" ;; esac
done
t="$(q '.hooks.PreToolUse[0].hooks[0].timeout')"
case "$t" in ''|null|*[!0-9]*) _rx_fail "guard timeout must be an integer, got '$t'" ;; *) [ "$t" -le 60 ] || _rx_fail "guard timeout $t is too long for a fast check" ;; esac

# every referenced script exists and is executable (the placeholder is double-quoted in the
# hook command so a plugin path with spaces still works; `claude plugin validate` asks for it)
for cmd in $(jq -r '.. | .command? // empty' "$H" | tr -d '"'); do
  f="${cmd/'${CLAUDE_PLUGIN_ROOT}'/$ROOT}"
  case "$cmd" in '${CLAUDE_PLUGIN_ROOT}/scripts/'*) ;; *) _rx_fail "command must start with \${CLAUDE_PLUGIN_ROOT}/scripts/: $cmd" ;; esac
  [ -x "$f" ] || _rx_fail "not an executable script: $cmd"
done
echo "test_hooks_json: ok"
