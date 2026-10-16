#!/usr/bin/env bash
# rx-spec skill and templates: line caps, required headings, state.md keys, SKILL.md contract.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

SKILL_DIR="$ROOT/skills/rx-spec"
SKILL="$SKILL_DIR/SKILL.md"
TPL="$SKILL_DIR/templates"

# lines <file>: newline count (0 if the file is missing)
lines() { wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

# headings <file>: all `## ` headings, comma-joined
headings() { grep '^## ' "$1" 2>/dev/null | sed 's/^## //' | paste -sd, - ; }

# template:cap:expected headings
SPECS="requirements:60:Problem,Requirements,Acceptance criteria,Out of scope
plan:100:Approach,Options considered,Design,Architecture changes,Risks
tasks:40:Tasks
review:60:QA,Security,Verdict
quick:30:Change,Acceptance criteria,Tasks
state:30:Log"

for spec in $(printf '%s\n' "$SPECS" | tr ' ' '_'); do
  spec="$(printf '%s' "$spec" | tr '_' ' ')"
  name="${spec%%:*}"; rest="${spec#*:}"; cap="${rest%%:*}"; want="${rest#*:}"
  f="$TPL/$name.md"
  [ -f "$f" ] || { assert_eq "exists" "missing" "template $name.md exists"; continue; }
  n="$(lines "$f")"
  [ "$n" -le "$cap" ] && [ "$n" -gt 0 ] || assert_eq "1..$cap" "$n" "$name.md line count within cap"
  [ "$(tail -c1 "$f" | wc -l | tr -d ' ')" = "1" ] || assert_eq "trailing newline" "none" "$name.md ends with newline"
  assert_eq "$want" "$(headings "$f")" "$name.md headings"
  assert_eq "---" "$(sed -n 1p "$f")" "$name.md frontmatter opens"
  if [ "$name" != "state" ]; then
    assert_eq "status: draft" "$(sed -n 2p "$f")" "$name.md status: draft"
    assert_eq "---" "$(sed -n 3p "$f")" "$name.md frontmatter closes after one key"
  fi
done

# state.md: eight keys in order with allowed values
S="$TPL/state.md"
if [ -f "$S" ]; then
  i=2
  for key in feature phase status g1 g2 g3 bump next; do
    line="$(sed -n "${i}p" "$S")"
    assert_eq "$key" "${line%%:*}" "state.md line $i key"
    val="${line#*: }"
    case "$key" in
      phase)  printf '%s' "$val" | grep -Eq '^(intake|requirements|plan|build|verify|close|done)$' || assert_eq "valid phase" "$val" "state.md phase" ;;
      status) printf '%s' "$val" | grep -Eq '^(draft|awaiting-human|approved|blocked)$' || assert_eq "valid status" "$val" "state.md status" ;;
      g1|g2|g3) printf '%s' "$val" | grep -Eq '^(none|approved:[^:]+:[0-9]{4}-[0-9]{2}-[0-9]{2})$' || assert_eq "valid gate" "$val" "state.md $key" ;;
      bump)   printf '%s' "$val" | grep -Eq '^(none|patch|minor|major)$' || assert_eq "valid bump" "$val" "state.md bump" ;;
    esac
    i=$((i + 1))
  done
  assert_eq "---" "$(sed -n 10p "$S")" "state.md frontmatter closes after eight keys"
  assert_eq "phase: intake" "$(sed -n 3p "$S")" "state.md ships at intake"
  assert_eq "status: draft" "$(sed -n 4p "$S")" "state.md ships draft"
  assert_eq "g1: none g2: none g3: none bump: none" "$(sed -n 5,7p "$S" | tr '\n' ' ')$(sed -n 8p "$S")" "state.md gates and bump ship as none"
fi

# task / AC line formats, and tasks.md cites an AC that requirements.md defines
TASK_RE='^- \[ \] T-[0-9]+ \(AC-[0-9]+(, AC-[0-9]+)*\): '
for name in tasks quick; do
  grep -Eq "$TASK_RE" "$TPL/$name.md" 2>/dev/null || assert_eq "task line" "none" "$name.md has a T-n line"
  grep -Eq '^- AC-1: ' "$TPL/$name.md" 2>/dev/null || [ "$name" = "tasks" ] || assert_eq "AC-1 line" "none" "$name.md has AC-1"
done
grep -Eq '^- R-1: ' "$TPL/requirements.md" 2>/dev/null || assert_eq "R-1 line" "none" "requirements.md has R-1"
grep -Eq '^- AC-1: ' "$TPL/requirements.md" 2>/dev/null || assert_eq "AC-1 line" "none" "requirements.md has AC-1"
cited="$(grep -Eo '\(AC-[0-9]+' "$TPL/tasks.md" 2>/dev/null | head -1 | tr -d '(')"
if [ -n "$cited" ]; then
  grep -Eq "^- $cited: " "$TPL/requirements.md" 2>/dev/null || assert_eq "$cited in requirements.md" "absent" "tasks.md cites an existing AC"
else
  assert_eq "cited AC" "none" "tasks.md cites an AC"
fi

# SKILL.md contract
if [ -f "$SKILL" ]; then
  n="$(lines "$SKILL")"
  [ "$n" -le 80 ] || assert_eq "<=80" "$n" "SKILL.md line count"
  assert_eq "name: rx-spec" "$(sed -n 2p "$SKILL")" "SKILL.md name"
  grep -Eq '^description: .+' "$SKILL" || assert_eq "description" "none" "SKILL.md description"
  for row in 'state.md|30' 'requirements.md|60' 'plan.md|100' 'tasks.md|40' 'review.md|60' 'quick.md|30' \
             'review.qa.md|30' 'review.security.md|30' 'architecture.md|80' 'CLAUDE.md|60' 'AGENTS.md|60'; do
    grep -Fq "| \`${row%%|*}\` | ${row#*|} |" "$SKILL" || assert_eq "table row ${row}" "missing" "SKILL.md cap table"
  done
  grep -Fq '| decision entry | 6 |' "$SKILL" || assert_eq "decision row" "missing" "SKILL.md cap table"
  grep -Fq '| learning entry | 5 |' "$SKILL" || assert_eq "learning row" "missing" "SKILL.md cap table"
  grep -Fq 'first line `tags: [a, b]`' "$SKILL" || assert_eq "tags-first-line rule" "missing" "SKILL.md knowledge entry shape"
  grep -Fq 'cap counts the whole file' "$SKILL" || assert_eq "whole-file cap rule" "missing" "SKILL.md knowledge entry cap"
  grep -Fq 'collapse older log lines into one summary line' "$SKILL" || assert_eq "log collapse rule" "missing" "SKILL.md log overflow"
  for phrase in '## Lanes' 'Full lane' 'Quick lane' 'only gate is `g2`' 'there is no `g3`' 'never mix' \
                'status: final' 'Finalized by' 'review.qa.md' 'required `## ` headings' 'every checkbox line'; do
    grep -Fqi -- "$phrase" "$SKILL" || assert_eq "$phrase" "missing" "SKILL.md lane contract mentions: $phrase"
  done
  ! grep -Fq 'add none, drop none' "$SKILL" || assert_eq "reworded" "add none, drop none" "SKILL.md heading rule wording"
  for tok in 'R-' 'AC-' 'T-' UNDERSTANDING OPTIONS ASSUMPTIONS QUESTIONS 'templates/' 'tags:'; do
    grep -Fq -- "$tok" "$SKILL" || assert_eq "$tok" "missing" "SKILL.md mentions $tok"
  done
else
  assert_eq "exists" "missing" "SKILL.md exists"
fi

[ "$RX_FAILS" -eq 0 ] && echo "test_templates: ok"
exit 0
