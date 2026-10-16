#!/usr/bin/env bash
# commands/*.md lint: frontmatter, size caps, the scripts each command must call.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

CM="$ROOT/commands"
fm() { awk -v k="$2" 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 { i=index($0,":"); if (i>0 && substr($0,1,i-1)==k) { v=substr($0,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t\r]+$/,"",v); print v; exit } }' "$1"; }
lines() { wc -l < "$1" | tr -d ' '; }

# every command: a description, and it is one of the known set
for f in "$CM"/*.md; do
  [ -e "$f" ] || continue
  [ -n "$(fm "$f" description)" ] || _rx_fail "$(basename "$f"): description missing"
done

# needs <command> <max-lines> <needle...>
needs() {
  local f="$CM/$1.md" max="$2" n
  shift 2
  [ -f "$f" ] || { _rx_fail "commands/$(basename "$f") missing"; return; }
  [ "$(lines "$f")" -le "$max" ] || _rx_fail "$(basename "$f"): $(lines "$f") lines (cap $max)"
  for n in "$@"; do
    grep -qF -- "$n" "$f" || _rx_fail "$(basename "$f"): must mention $n"
  done
}
needs feature 40 '${CLAUDE_PLUGIN_ROOT}/scripts/rx-new-feature.sh' '--quick' '/rx:init' 'why' 'who' 'done-when' 'state.md' '/rx:next'
needs status 12 '!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh' 'allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh' 'verbatim' '/rx:init'
echo "test_commands: ok"
