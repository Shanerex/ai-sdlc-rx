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
# /rx:init: the script does the deterministic part, the model only writes drafts that go through it
needs init 50 '!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-init-files.sh' 'allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-init-files.sh' \
  '--install-config' '--install-claude-md' '--install-architecture' '--refresh-scripts' '.rx/local/draft' \
  'test_cmd' 'source_globs' 'branch_pattern' 'base_branch' 'no coverage' '60 lines' '80 lines' '@import' 'brownfield' \
  'rx:feature' 'Do not commit' 'present'
# the guard blocks agent writes to these, so init must not tell the model to Edit or Write them
grep -Eq '(Edit|Write)[^.]*(\.rx/config\.yml|CLAUDE\.md|architecture\.md)' "$CM/init.md" && _rx_fail "init.md: must install config/CLAUDE.md/architecture.md through the script, not Edit/Write"
# /rx:next: table-driven dispatch. Every (lane, phase) a feature can be in has one table row.
N="$CM/next.md"
needs next 110 '!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh' 'rx:pm' 'rx:architect' 'rx:dev' 'rx:qa' 'rx:security' 'SendMessage' \
  'review.qa.md' 'review.security.md' 'review.md' 'explicit' 'quick.md' 'rx-check.sh done' 'git config user.name' 'AskUserQuestion'
for row in "full intake" "full requirements" "full plan" "full build" "full verify" "full close" "full done" \
           "quick plan" "quick build" "quick verify" "quick close" "quick done"; do
  grep -q "^| $row |" "$N" || _rx_fail "next.md: dispatch table has no row '| $row |'"
done
# agents run in the project and may not read the plugin dir: templates come from the init copy
grep -q '`.rx/scripts/templates/`' "$N" || _rx_fail "next.md: templates must point at .rx/scripts/templates/"
grep -q 'CLAUDE_PLUGIN_ROOT}/skills' "$N" && _rx_fail "next.md: agents cannot read the plugin dir; use .rx/scripts/templates/"
# the architect plans against the real code: its spawn prompt carries source_globs
grep -q 'source_globs' "$N" || _rx_fail "next.md: architect spawn prompt must carry source_globs"
# gates are written only after a human yes, by the orchestrator (this command), in the documented form
grep -q 'approved:<approver>:<YYYY-MM-DD>' "$N" || _rx_fail "next.md: gate value format"
# close calls done only (done already runs specs and shared)
grep -q 'rx-check.sh shared' "$N" && _rx_fail "next.md: close must call rx-check.sh done only"
grep -q 'rx-check.sh specs' "$N" && _rx_fail "next.md: close must call rx-check.sh done only"
# fallback when SendMessage resume is unavailable
grep -qi 'unavailable' "$N" || _rx_fail "next.md: SendMessage fallback"
# auto fix loops capped at 2
grep -q 'at most 2' "$N" || _rx_fail "next.md: fix loops capped at 2"
echo "test_commands: ok"
