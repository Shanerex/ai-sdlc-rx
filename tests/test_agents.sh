#!/usr/bin/env bash
# agents/*.md lint: frontmatter, tool list, model, body length, rx contract keywords.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

AG="$ROOT/agents"

# fm <file> <key>: frontmatter value ('' if absent). body <file>: lines after the closing ---.
fm() { awk -v k="$2" 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 { i=index($0,":"); if (i>0 && substr($0,1,i-1)==k) { v=substr($0,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t\r]+$/,"",v); print v; exit } }' "$1"; }
body() { awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; next} !infm {print}' "$1"; }
has_tool() { case ", $(fm "$1" tools), " in *", $2, "*) return 0 ;; esac; return 1; }

# agent <name> <tools|ALL> <model> <output-file...>: structural expectations per agent
check() {
  local name="$1" tools="$2" model="$3" f="$AG/$1.md" n t
  shift 3
  [ -f "$f" ] || { _rx_fail "$name: agents/$name.md missing"; return; }
  assert_eq "$name" "$(fm "$f" name)" "$name: name matches the file name"
  [ -n "$(fm "$f" description)" ] || _rx_fail "$name: description missing"
  assert_eq "$model" "$(fm "$f" model)" "$name: model"
  if [ "$tools" = ALL ]; then
    assert_eq "" "$(fm "$f" tools)" "$name: full tools means no tools key"
  else
    assert_eq "$tools" "$(fm "$f" tools)" "$name: tools"
  fi
  n="$(body "$f" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  [ "$n" -le 25 ] || _rx_fail "$name: body has $n non-blank lines (cap 25)"
  [ "$n" -ge 5 ] || _rx_fail "$name: body suspiciously short ($n lines)"
  for t in "Inputs:" "Output:" "Return:" "Must:" "Must not:"; do
    body "$f" | grep -q "^$t" || _rx_fail "$name: body lacks a '$t' line"
  done
  body "$f" | grep -q "rx-spec" || _rx_fail "$name: body must point at the rx-spec skill"
  body "$f" | grep -Eq "at most 15 lines" || _rx_fail "$name: body must cap the final message at 15 lines"
  body "$f" | grep -Eq "UNDERSTANDING|OPTIONS|ASSUMPTIONS" && _rx_fail "$name: brief format is referenced, not restated"
  for t in "$@"; do
    body "$f" | grep -q "$t" || _rx_fail "$name: body must name $t"
  done
}

check pm "Read, Grep, Glob, Write" sonnet "requirements.md" "at most 10 lines"
check architect "Read, Grep, Glob, Write" opus "plan.md" "tasks.md" "at most 10 lines" "architecture.md" "source_globs"
check dev ALL sonnet "tasks.md" "status: blocked" "test_cmd"
check qa "Read, Grep, Glob, Bash, Write" sonnet "review.qa.md"
check security "Read, Grep, Glob, Bash, Write" opus "review.security.md"

# reviewers: no Edit, exactly one output file, never the other reviewer's
for a in qa security; do
  has_tool "$AG/$a.md" Edit && _rx_fail "$a: must not have Edit"
  has_tool "$AG/$a.md" MultiEdit && _rx_fail "$a: must not have MultiEdit"
done
assert_eq "0" "$(body "$AG/qa.md" | grep -c 'review.security.md')" "qa never names the security file"
assert_eq "0" "$(body "$AG/security.md" | grep -c 'review.qa.md')" "security never names the qa file"
body "$AG/security.md" | grep -q "base_branch" || _rx_fail "security: reviews the diff against base_branch"
# the brief owners never touch code or state
for a in pm architect; do
  has_tool "$AG/$a.md" Edit && _rx_fail "$a: must not have Edit"
  has_tool "$AG/$a.md" Bash && _rx_fail "$a: must not have Bash"
done
# nobody but the human edits architecture.md (the architect only proposes it inside plan.md)
body "$AG/dev.md" | grep -q "Must not:.*architecture.md" || _rx_fail "dev: must not edit architecture.md"
body "$AG/dev.md" | grep -Eq "g1.*g3|g1-g3" || _rx_fail "dev: must not touch g1-g3"
# the set of agents is exactly these five
assert_eq "architect dev pm qa security" "$(ls "$AG" | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')" "agent set"
echo "test_agents: ok"
