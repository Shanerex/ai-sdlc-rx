#!/usr/bin/env bash
# scripts/rx-check.sh specs: caps, headings, frontmatter, IDs, template lookup, dispatcher.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

CHECK="$ROOT/scripts/rx-check.sh"
TPL="$ROOT/skills/rx-spec/templates"

# run_script <script> <dir> [args...]: sets OUT, ERR, RC (cwd=<dir>).
run_script() {
  local s="$1" d="$2" ef
  shift 2
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && "$s" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# run_check <dir> [args...]: the repo script, specs/shared/done etc. passed as args.
run_check() {
  local d="$1"
  shift
  run_script "$CHECK" "$d" "$@"
}

new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  fixture_config "$d/r"
  printf '%s\n' "$d/r"
}

# mkfeat <repo> <id>: state, requirements, plan, tasks, review from the REAL templates.
mkfeat() {
  local f
  mkdir -p "$1/specs/$2"
  sed -e "s/^feature: .*/feature: $2/" "$TPL/state.md" > "$1/specs/$2/state.md"
  for f in requirements plan tasks review; do
    cp "$TPL/$f.md" "$1/specs/$2/$f.md"
  done
}

# mkquick <repo> <id>: state + quick only (quick is the alternative to requirements).
mkquick() {
  mkdir -p "$1/specs/$2"
  sed -e "s/^feature: .*/feature: $2/" "$TPL/state.md" > "$1/specs/$2/state.md"
  cp "$TPL/quick.md" "$1/specs/$2/quick.md"
}

# nlines <file>: line count the way the contract counts (CR stripped, last partial line counts).
nlines() { tr -d '\r' < "$1" | awk 'END{print NR}'; }

# pad_to <file> <n>: append plain lines until the file has exactly n lines.
pad_to() {
  local cur
  cur="$(nlines "$1")"
  while [ "$cur" -lt "$2" ]; do
    printf 'pad %s\n' "$cur" >> "$1"
    cur=$((cur + 1))
  done
}

to_crlf() {
  awk '{printf "%s\r\n", $0}' "$1" > "$1.crlf" && mv "$1.crlf" "$1"
}

strip_final_newline() {
  local t
  t="$(cat "$1")"
  printf '%s' "$t" > "$1"
}

# ---------- clean features built from the REAL templates ----------
R="$(new_repo)"
mkfeat "$R" x
run_check "$R" specs x
assert_eq "" "$OUT" "real templates (requirements flow): no output"
assert_eq "" "$ERR" "real templates (requirements flow): quiet stderr"
assert_eq "0" "$RC" "real templates (requirements flow): rc 0"

R="$(new_repo)"
mkquick "$R" q
run_check "$R" specs q
assert_eq "" "$OUT$ERR" "real templates (quick flow): silent"
assert_eq "0" "$RC" "real templates (quick flow): rc 0"

# ---------- dispatcher ----------
R="$(new_repo)"
run_check "$R"
assert_eq "1" "$(printf '%s\n' "$ERR" | grep -c 'usage: rx-check.sh')" "no subcommand: usage on stderr"
assert_eq "" "$OUT" "no subcommand: stdout empty"
assert_eq "2" "$RC" "no subcommand: rc 2"
run_check "$R" bogus
assert_contains "$ERR" "usage: rx-check.sh" "unknown subcommand: usage"
assert_eq "2" "$RC" "unknown subcommand: rc 2"
run_check "$R" shared
assert_eq "rx-check: 'shared' not implemented" "$ERR" "shared: not implemented message"
assert_eq "" "$OUT" "shared: stdout empty"
assert_eq "2" "$RC" "shared: rc 2"
run_check "$R" done
assert_eq "rx-check: 'done' not implemented" "$ERR" "done: not implemented message"
assert_eq "2" "$RC" "done: rc 2"
run_check "$R" specs a b
assert_contains "$ERR" "usage: rx-check.sh" "specs with two args: usage"
assert_eq "2" "$RC" "specs with two args: rc 2"

# ---------- no config: silent no-op for any subcommand ----------
R="$(new_repo)"
mkfeat "$R" x
printf 'x\n' > "$R/specs/x/state.md"
rm -f "$R/.rx/config.yml"
run_check "$R" specs x
assert_eq "" "$OUT$ERR" "no config: specs silent"
assert_eq "0" "$RC" "no config: specs rc 0"
run_check "$R" bogus
assert_eq "" "$OUT$ERR" "no config: unknown subcommand silent"
assert_eq "0" "$RC" "no config: unknown subcommand rc 0"
run_check "$R"
assert_eq "0" "$RC" "no config: no subcommand rc 0"

# ---------- line caps: state.md ----------
R="$(new_repo)"
mkfeat "$R" x
S="$R/specs/x/state.md"
pad_to "$S" 30
run_check "$R" specs x
assert_eq "" "$OUT" "state.md at cap 30: pass"
assert_eq "0" "$RC" "state.md at cap 30: rc 0"
pad_to "$S" 31
run_check "$R" specs x
assert_eq "specs/x/state.md: 31 lines exceeds cap 30" "$OUT" "state.md cap+1: violation"
assert_eq "1" "$RC" "state.md cap+1: rc 1"

# ---------- line caps: tasks.md (also CRLF and no final newline at the boundary) ----------
R="$(new_repo)"
mkfeat "$R" x
T="$R/specs/x/tasks.md"
pad_to "$T" 40
run_check "$R" specs x
assert_eq "" "$OUT" "tasks.md at cap 40: pass"
pad_to "$T" 41
run_check "$R" specs x
assert_eq "specs/x/tasks.md: 41 lines exceeds cap 40" "$OUT" "tasks.md cap+1: violation"
assert_eq "1" "$RC" "tasks.md cap+1: rc 1"

# CRLF at the boundary: CR is not counted as extra, headings and frontmatter still work
R="$(new_repo)"
mkfeat "$R" x
T="$R/specs/x/tasks.md"
pad_to "$T" 40
to_crlf "$T"
run_check "$R" specs x
assert_eq "" "$OUT" "tasks.md CRLF at cap 40: pass"
assert_eq "0" "$RC" "tasks.md CRLF at cap 40: rc 0"
cp "$TPL/tasks.md" "$T"
pad_to "$T" 41
to_crlf "$T"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: 41 lines exceeds cap 40" "$OUT" "tasks.md CRLF cap+1: violation"

# whole feature in CRLF is clean
R="$(new_repo)"
mkfeat "$R" x
for f in state requirements plan tasks review; do to_crlf "$R/specs/x/$f.md"; done
run_check "$R" specs x
assert_eq "" "$OUT$ERR" "all-CRLF feature: clean"
assert_eq "0" "$RC" "all-CRLF feature: rc 0"

# no final newline at the boundary
R="$(new_repo)"
mkfeat "$R" x
T="$R/specs/x/tasks.md"
pad_to "$T" 40
strip_final_newline "$T"
run_check "$R" specs x
assert_eq "" "$OUT" "tasks.md no final newline, 40 lines: pass"
assert_eq "0" "$RC" "tasks.md no final newline, 40 lines: rc 0"
printf '\npad 40' >> "$T"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: 41 lines exceeds cap 40" "$OUT" "tasks.md no final newline, 41 lines: violation"

# ---------- the other caps ----------
R="$(new_repo)"
mkfeat "$R" x
pad_to "$R/specs/x/requirements.md" 60
pad_to "$R/specs/x/plan.md" 100
pad_to "$R/specs/x/review.md" 60
run_check "$R" specs x
assert_eq "" "$OUT" "requirements 60 / plan 100 / review 60: all at cap pass"
pad_to "$R/specs/x/requirements.md" 61
pad_to "$R/specs/x/plan.md" 101
pad_to "$R/specs/x/review.md" 61
run_check "$R" specs x
assert_eq "specs/x/requirements.md: 61 lines exceeds cap 60
specs/x/plan.md: 101 lines exceeds cap 100
specs/x/review.md: 61 lines exceeds cap 60" "$OUT" "requirements/plan/review cap+1 violations in file order"
assert_eq "1" "$RC" "other caps: rc 1"

R="$(new_repo)"
mkquick "$R" q
pad_to "$R/specs/q/quick.md" 30
run_check "$R" specs q
assert_eq "" "$OUT" "quick.md at cap 30: pass"
pad_to "$R/specs/q/quick.md" 31
run_check "$R" specs q
assert_eq "specs/q/quick.md: 31 lines exceeds cap 30" "$OUT" "quick.md cap+1: violation"

# review.qa.md / review.security.md: cap 30, frontmatter rule, no heading check
R="$(new_repo)"
mkfeat "$R" x
for f in review.qa review.security; do
  printf -- '---\nstatus: draft\n---\n# QA\n' > "$R/specs/x/$f.md"
  pad_to "$R/specs/x/$f.md" 30
done
run_check "$R" specs x
assert_eq "" "$OUT" "review.qa/security at cap 30 with no template headings: pass"
pad_to "$R/specs/x/review.qa.md" 31
pad_to "$R/specs/x/review.security.md" 31
run_check "$R" specs x
assert_eq "specs/x/review.qa.md: 31 lines exceeds cap 30
specs/x/review.security.md: 31 lines exceeds cap 30" "$OUT" "review.qa/security cap+1: violations"
printf 'no frontmatter\n' > "$R/specs/x/review.qa.md"
printf -- '---\nstatus: bogus\n---\n' > "$R/specs/x/review.security.md"
run_check "$R" specs x
assert_eq "specs/x/review.qa.md: missing frontmatter
specs/x/review.security.md: frontmatter status must be draft|final" "$OUT" "review.qa/security follow the frontmatter rule"

# files that are not on the list are ignored
R="$(new_repo)"
mkfeat "$R" x
seq 1 500 > "$R/specs/x/notes.md"
seq 1 500 > "$R/specs/x/architecture.md"
run_check "$R" specs x
assert_eq "" "$OUT" "unlisted files ignored"
assert_eq "0" "$RC" "unlisted files ignored: rc 0"

# ---------- required headings ----------
R="$(new_repo)"
mkfeat "$R" x
grep -v '^## Risks' "$R/specs/x/plan.md" > "$R/specs/x/plan.md.new" && mv "$R/specs/x/plan.md.new" "$R/specs/x/plan.md"
run_check "$R" specs x
assert_eq "specs/x/plan.md: missing heading '## Risks'" "$OUT" "plan.md missing heading"
assert_eq "1" "$RC" "missing heading: rc 1"

# every template heading of every templated file is required (derived, not hardcoded)
for f in state requirements plan tasks review quick; do
  R="$(new_repo)"
  if [ "$f" = quick ]; then mkquick "$R" x; else mkfeat "$R" x; fi
  while IFS= read -r h; do
    cp "$TPL/$f.md" "$R/specs/x/$f.md"
    [ "$f" = state ] && sed -e "s/^feature: .*/feature: x/" "$TPL/state.md" > "$R/specs/x/state.md"
    grep -vxF "$h" "$R/specs/x/$f.md" > "$R/specs/x/$f.md.new"
    mv "$R/specs/x/$f.md.new" "$R/specs/x/$f.md"
    run_check "$R" specs x
    assert_contains "$OUT" "specs/x/$f.md: missing heading '$h'" "$f.md without '$h' is flagged"
  done <<EOF2
$(grep '^## ' "$TPL/$f.md")
EOF2
done

# extra headings and different order are allowed
R="$(new_repo)"
mkfeat "$R" x
{
  printf -- '---\nstatus: final\n---\n# Plan: x\n\n## Risks\n\n## Extra stuff\n\n### Sub\n\n## Architecture changes\n## Design\n## Options considered\n## Approach\n'
} > "$R/specs/x/plan.md"
run_check "$R" specs x
assert_eq "" "$OUT" "extra headings and any order allowed"
assert_eq "0" "$RC" "extra headings: rc 0"

# heading must be a whole line: prefix/suffix variants do not count, trailing whitespace and CR do
R="$(new_repo)"
mkfeat "$R" x
printf -- '---\nstatus: draft\n---\n## Approach\n## Options considered\n## Design\n## Architecture changes\n## Risks and more\n' > "$R/specs/x/plan.md"
run_check "$R" specs x
assert_eq "specs/x/plan.md: missing heading '## Risks'" "$OUT" "heading is a whole-line match"
printf -- '---\nstatus: draft\n---\n## Approach  \n## Options considered\t\n## Design\r\n## Architecture changes\n## Risks\n' > "$R/specs/x/plan.md"
run_check "$R" specs x
assert_eq "" "$OUT" "heading tolerates trailing whitespace and CR"

# a heading-less file reports each missing heading in template order
R="$(new_repo)"
mkfeat "$R" x
printf -- '---\nstatus: draft\n---\n' > "$R/specs/x/review.md"
run_check "$R" specs x
assert_eq "specs/x/review.md: missing heading '## QA'
specs/x/review.md: missing heading '## Security'
specs/x/review.md: missing heading '## Verdict'" "$OUT" "all headings missing: template order"

# ---------- frontmatter (non-state) ----------
R="$(new_repo)"
mkfeat "$R" x
sed -e '1,3d' "$TPL/tasks.md" > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: missing frontmatter" "$OUT" "no frontmatter at all"
printf -- '---\nstatus: draft\n# Tasks\n## Tasks\n' > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: missing frontmatter" "$OUT" "unterminated frontmatter"
: > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_contains "$OUT" "specs/x/tasks.md: missing frontmatter" "empty file: missing frontmatter"

for v in draft final; do
  sed -e "s/^status: .*/status: $v/" "$TPL/tasks.md" > "$R/specs/x/tasks.md"
  run_check "$R" specs x
  assert_eq "" "$OUT" "status $v accepted"
done
for v in done wip "" Draft '"draft"'; do
  sed -e "s/^status: .*/status: $v/" "$TPL/tasks.md" > "$R/specs/x/tasks.md"
  run_check "$R" specs x
  assert_eq "specs/x/tasks.md: frontmatter status must be draft|final" "$OUT" "status '$v' rejected"
done
printf -- '---\nowner: me\n---\n# Tasks\n## Tasks\n' > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: frontmatter status must be draft|final" "$OUT" "status key absent"
# a status: line outside the frontmatter does not count
printf -- '---\nowner: me\n---\nstatus: final\n## Tasks\n' > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: frontmatter status must be draft|final" "$OUT" "status outside frontmatter ignored"
# CRLF frontmatter ok
printf -- '---\r\nstatus: final\r\n---\r\n# Tasks\r\n## Tasks\r\n' > "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "" "$OUT" "CRLF frontmatter with status final ok"

# ---------- state.md invalid surfaces with the stripped prefix ----------
R="$(new_repo)"
mkfeat "$R" x
sed -e "s/^phase: .*/phase: bogus/" "$R/specs/x/state.md" > "$R/specs/x/state.md.new" && mv "$R/specs/x/state.md.new" "$R/specs/x/state.md"
run_check "$R" specs x
assert_eq "specs/x/state.md: unknown phase 'bogus'" "$OUT" "state.md invalid: prefix stripped"
assert_eq "1" "$RC" "state.md invalid: rc 1"
printf 'no fm\n## Log\n' > "$R/specs/x/state.md"
run_check "$R" specs x
assert_eq "specs/x/state.md: no frontmatter" "$OUT" "state.md without frontmatter"
sed -e "s/^feature: .*/feature: x/" "$TPL/state.md" | grep -v '^g2:' > "$R/specs/x/state.md"
run_check "$R" specs x
assert_eq "specs/x/state.md: missing key g2" "$OUT" "state.md missing key"
# a valid but over-cap and heading-less state.md reports all of its problems
sed -e "s/^feature: .*/feature: x/" "$TPL/state.md" | grep -v '^## Log' > "$R/specs/x/state.md"
run_check "$R" specs x
assert_eq "specs/x/state.md: missing heading '## Log'" "$OUT" "state.md missing heading"

# ---------- IDs: duplicates ----------
R="$(new_repo)"
mkfeat "$R" x
printf -- '- AC-1: again\n' >> "$R/specs/x/requirements.md"
run_check "$R" specs x
assert_eq "specs/x/requirements.md: duplicate AC-1" "$OUT" "duplicate AC in requirements.md"
assert_eq "1" "$RC" "duplicate AC: rc 1"

R="$(new_repo)"
mkfeat "$R" x
printf -- '- R-1: again\n- R-2: fine\n' >> "$R/specs/x/requirements.md"
run_check "$R" specs x
assert_eq "specs/x/requirements.md: duplicate R-1" "$OUT" "duplicate R in requirements.md"

R="$(new_repo)"
mkfeat "$R" x
printf -- '- [x] T-1 (AC-1): again\n' >> "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: duplicate T-1" "$OUT" "duplicate T in tasks.md"

# distinct ids pass; AC-1 vs AC-10 are different ids
R="$(new_repo)"
mkfeat "$R" x
printf -- '- AC-10: ten\n- AC-2: two\n' >> "$R/specs/x/requirements.md"
printf -- '- [ ] T-10 (AC-10): ten\n- [x] T-2 (AC-2): two\n' >> "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "" "$OUT" "AC-1 vs AC-10 and T-1 vs T-10 are distinct"

# AC and T ids must be unique across requirements.md + quick.md / tasks.md + quick.md
R="$(new_repo)"
mkfeat "$R" x
cp "$TPL/quick.md" "$R/specs/x/quick.md"
run_check "$R" specs x
assert_eq "specs/x/quick.md: duplicate AC-1
specs/x/quick.md: duplicate T-1" "$OUT" "feature-wide duplicates across requirements/tasks and quick"

# ---------- IDs: task lines ----------
R="$(new_repo)"
mkfeat "$R" x
T="$R/specs/x/tasks.md"
for bad in \
  '- [ ] T-2 (AC-1) missing colon' \
  '- [ ] T-2 AC-1: no parens' \
  '- [ ] T-2 (AC-1,AC-1): no space after comma' \
  '- [ ] T-2 (): empty cites' \
  '- [ ] T-2 (AC-1):' \
  '- [ ] T-2 (AC-1): ' \
  '- [x] T-x (AC-1): non numeric id' \
  '- [ ] T- (AC-1): empty id' \
  '- [ ] T-2  (AC-1): double space' \
  '- [ ] T-2 (AC-1, ): trailing comma'
do
  { cat "$TPL/tasks.md"; printf '%s\n' "$bad"; } > "$T"
  run_check "$R" specs x
  want="specs/x/tasks.md: malformed task line '$(printf '%s' "$bad" | cut -c1-40)'"
  assert_eq "$want" "$OUT" "malformed: $bad"
  assert_eq "1" "$RC" "malformed rc: $bad"
done
# truncated to 40 chars
{ cat "$TPL/tasks.md"; printf -- '- [ ] T-2 (AC-1) %s\n' "this description is long and has no colon"; } > "$T"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: malformed task line '- [ ] T-2 (AC-1) this description is lon'" "$OUT" "malformed line shows first 40 chars"
# CR is not part of the shown line
{ cat "$TPL/tasks.md"; printf -- '- [ ] T-2 (AC-1) nope\r\n'; } > "$T"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: malformed task line '- [ ] T-2 (AC-1) nope'" "$OUT" "malformed line CR stripped"
# lines that merely look like tasks but are not at column 0 or lack T- are ignored
{ cat "$TPL/tasks.md"; printf -- '  - [ ] T-9 (nope): indented\n- [ ] not a task\n- [x] done thing\nT-9 (AC-9): plain\n'; } > "$T"
run_check "$R" specs x
assert_eq "" "$OUT" "non-task lines ignored"
# well-formed lines, incl. two ACs and a ticked task
{ cat "$TPL/tasks.md"; printf -- '- [x] T-2 (AC-1, AC-2): two cites\n'; } > "$T"
printf -- '- AC-2: second\n' >> "$R/specs/x/requirements.md"
run_check "$R" specs x
assert_eq "" "$OUT" "T citing two existing ACs passes"
assert_eq "0" "$RC" "T citing two ACs: rc 0"

# unknown AC
R="$(new_repo)"
mkfeat "$R" x
printf -- '- [ ] T-2 (AC-9): lost\n' >> "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: T-2 cites unknown AC-9" "$OUT" "T citing unknown AC"
assert_eq "1" "$RC" "unknown AC: rc 1"
printf -- '- [ ] T-3 (AC-1, AC-8, AC-9): partly lost\n' >> "$R/specs/x/tasks.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: T-2 cites unknown AC-9
specs/x/tasks.md: T-3 cites unknown AC-8
specs/x/tasks.md: T-3 cites unknown AC-9" "$OUT" "each unknown AC reported once per task"

# tasks.md without requirements.md and quick.md: every cited AC unknown
R="$(new_repo)"
mkfeat "$R" x
rm -f "$R/specs/x/requirements.md"
run_check "$R" specs x
assert_eq "specs/x/tasks.md: T-1 cites unknown AC-1" "$OUT" "tasks.md without requirements.md"
assert_eq "1" "$RC" "tasks.md without requirements: rc 1"

# quick.md is its own AC source (tasks.md may cite quick.md ACs; quick tasks cite them too)
R="$(new_repo)"
mkquick "$R" q
printf -- '- AC-2: extra\n' >> "$R/specs/q/quick.md"
sed -e 's/AC-1/AC-2/' -e 's/T-1/T-7/' "$TPL/tasks.md" > "$R/specs/q/tasks.md"
run_check "$R" specs q
assert_eq "" "$OUT" "tasks.md cites AC from quick.md"
printf -- '- [ ] T-5 (AC-7): lost\n' >> "$R/specs/q/quick.md"
run_check "$R" specs q
assert_eq "specs/q/quick.md: T-5 cites unknown AC-7" "$OUT" "quick.md task citing unknown AC"
{ cat "$TPL/quick.md"; printf -- '- AC-1: dup\n- [ ] T-1 (AC-1): dup\n- [ ] T-3 (AC-1) bad\n'; } > "$R/specs/q/quick.md"
rm -f "$R/specs/q/tasks.md"
run_check "$R" specs q
assert_eq "specs/q/quick.md: duplicate AC-1
specs/q/quick.md: duplicate T-1
specs/q/quick.md: malformed task line '- [ ] T-3 (AC-1) bad'" "$OUT" "quick.md duplicates and malformed"

# ---------- which feature: argument, branch, active file, all dirs ----------
R="$(new_repo)"
mkfeat "$R" good
mkfeat "$R" bad
printf -- '- [ ] T-2 (AC-9): lost\n' >> "$R/specs/bad/tasks.md"
mkfeat "$R" other
printf -- '- AC-1: dup\n' >> "$R/specs/other/requirements.md"
run_check "$R" specs
assert_eq "specs/bad/tasks.md: T-2 cites unknown AC-9
specs/other/requirements.md: duplicate AC-1" "$OUT" "all-dirs mode (on main): every dir, sorted, only bad lines"
assert_eq "1" "$RC" "all-dirs mode: rc 1"
run_check "$R" specs good
assert_eq "" "$OUT" "argument selects the good feature"
assert_eq "0" "$RC" "argument good: rc 0"
run_check "$R" specs bad
assert_eq "specs/bad/tasks.md: T-2 cites unknown AC-9" "$OUT" "argument selects the bad feature"
assert_eq "1" "$RC" "argument bad: rc 1"

git -C "$R" checkout -q -b feature/bad
run_check "$R" specs
assert_eq "specs/bad/tasks.md: T-2 cites unknown AC-9" "$OUT" "id from branch beats all-dirs"
git -C "$R" checkout -q -b feature/good
run_check "$R" specs
assert_eq "" "$OUT" "id from branch: good feature"
assert_eq "0" "$RC" "id from branch: rc 0"
run_check "$R" specs bad
assert_eq "specs/bad/tasks.md: T-2 cites unknown AC-9" "$OUT" "argument beats branch"
git -C "$R" checkout -q main
mkdir -p "$R/.rx/local"
printf 'bad\n' > "$R/.rx/local/active"
run_check "$R" specs
assert_eq "specs/bad/tasks.md: T-2 cites unknown AC-9" "$OUT" "id from .rx/local/active"

# all-dirs ordering is by name; non-directory entries are ignored
R="$(new_repo)"
mkfeat "$R" b
mkfeat "$R" a
mkfeat "$R" c
printf -- '- AC-1: dup\n' >> "$R/specs/c/requirements.md"
printf -- '- AC-1: dup\n' >> "$R/specs/a/requirements.md"
printf 'stray\n' > "$R/specs/README.md"
run_check "$R" specs
assert_eq "specs/a/requirements.md: duplicate AC-1
specs/c/requirements.md: duplicate AC-1" "$OUT" "all-dirs sorted by name, files in specs/ ignored"
# a directory whose name is not a valid id is a violation, not silently skipped
mkdir -p "$R/specs/bad name"
run_check "$R" specs
assert_eq "specs/a/requirements.md: duplicate AC-1
specs/bad name: invalid feature id
specs/c/requirements.md: duplicate AC-1" "$OUT" "invalid directory name reported"

# not found
R="$(new_repo)"
mkfeat "$R" x
run_check "$R" specs nope
assert_eq "specs/nope: not found" "$OUT" "argument without a directory: not found"
assert_eq "1" "$RC" "not found: rc 1"
git -C "$R" checkout -q -b feature/ghost
run_check "$R" specs
assert_eq "specs/ghost: not found" "$OUT" "branch id without a directory: not found"
assert_eq "1" "$RC" "branch not found: rc 1"
# a feature dir without any checked file is clean
mkdir -p "$R/specs/empty"
run_check "$R" specs empty
assert_eq "" "$OUT" "empty feature dir: nothing to check"
assert_eq "0" "$RC" "empty feature dir: rc 0"

# no specs/ dir at all
R="$(new_repo)"
run_check "$R" specs
assert_eq "" "$OUT$ERR" "no specs dir, no id: silent"
assert_eq "0" "$RC" "no specs dir: rc 0"
mkdir -p "$R/specs"
run_check "$R" specs
assert_eq "" "$OUT$ERR" "empty specs dir: silent"
assert_eq "0" "$RC" "empty specs dir: rc 0"
rmdir "$R/specs"
run_check "$R" specs x
assert_eq "specs/x: not found" "$OUT" "no specs dir but an id: not found"
assert_eq "1" "$RC" "no specs dir with id: rc 1"

# bad id arguments
R="$(new_repo)"
mkfeat "$R" x
for bad in '../x' 'a/b' '-x' '.x' 'a b' ''; do
  run_check "$R" specs "$bad"
  assert_eq "" "$OUT" "bad id '$bad': stdout empty"
  assert_eq "2" "$RC" "bad id '$bad': rc 2"
  assert_contains "$ERR" "rx-check:" "bad id '$bad': message on stderr"
done

# ---------- template lookup ----------
# copy layout: <tmp>/.rx/scripts/{rx-check.sh,rx-lib.sh,templates/}
R="$(new_repo)"
mkfeat "$R" x
mkdir -p "$R/.rx/scripts/templates"
cp "$ROOT"/scripts/*.sh "$R/.rx/scripts/"
cp "$TPL"/*.md "$R/.rx/scripts/templates/"
run_script "$R/.rx/scripts/rx-check.sh" "$R" specs x
assert_eq "" "$OUT$ERR" "copy layout: clean feature passes"
assert_eq "0" "$RC" "copy layout: rc 0"
grep -v '^## Risks' "$R/specs/x/plan.md" > "$R/specs/x/plan.md.new" && mv "$R/specs/x/plan.md.new" "$R/specs/x/plan.md"
run_script "$R/.rx/scripts/rx-check.sh" "$R" specs x
assert_eq "specs/x/plan.md: missing heading '## Risks'" "$OUT" "copy layout: templates actually used"

# the copy layout reads the copied templates: change one there and the rule changes
cp "$TPL/plan.md" "$R/specs/x/plan.md"
printf '## Extra required\n' >> "$R/.rx/scripts/templates/plan.md"
run_script "$R/.rx/scripts/rx-check.sh" "$R" specs x
assert_eq "specs/x/plan.md: missing heading '## Extra required'" "$OUT" "copy layout: headings derived from the copied template"

# RX_TEMPLATES takes precedence
CUSTOM="$(fixture_tmpdir)"
cp "$TPL"/*.md "$CUSTOM/"
printf '## Custom heading\n' >> "$CUSTOM/plan.md"
RX_TEMPLATES="$CUSTOM" run_check "$R" specs x
assert_eq "specs/x/plan.md: missing heading '## Custom heading'" "$OUT" "RX_TEMPLATES wins over the copy layout"
# RX_TEMPLATES lacking one template falls through to the next location
rm -f "$CUSTOM/plan.md"
cp "$TPL/plan.md" "$R/.rx/scripts/templates/plan.md"
RX_TEMPLATES="$CUSTOM" run_check "$R" specs x
assert_eq "" "$OUT$ERR" "RX_TEMPLATES missing a template falls through"

# repo layout via RX_TEMPLATES when the script has no templates beside it
R2="$(new_repo)"
mkfeat "$R2" x
mkdir -p "$R2/.rx/scripts"
cp "$ROOT"/scripts/*.sh "$R2/.rx/scripts/"
RX_TEMPLATES="$TPL" run_script "$R2/.rx/scripts/rx-check.sh" "$R2" specs x
assert_eq "" "$OUT$ERR" "RX_TEMPLATES alone suffices"
assert_eq "0" "$RC" "RX_TEMPLATES alone: rc 0"

# not found anywhere: exit 2, stderr message, nothing on stdout (not a spec violation)
run_script "$R2/.rx/scripts/rx-check.sh" "$R2" specs x
assert_eq "rx-check: rx-spec templates not found" "$ERR" "templates missing: message"
assert_eq "" "$OUT" "templates missing: stdout empty"
assert_eq "2" "$RC" "templates missing: rc 2"
# ... even when a violation was already found in an earlier file
printf 'junk\n' > "$R2/specs/x/state.md"
run_script "$R2/.rx/scripts/rx-check.sh" "$R2" specs x
assert_eq "" "$OUT" "templates missing after a violation: stdout still empty"
assert_eq "2" "$RC" "templates missing after a violation: rc 2"
# RX_TEMPLATES set to a nonexistent dir is not found either
RX_TEMPLATES="$R2/nope" run_script "$R2/.rx/scripts/rx-check.sh" "$R2" specs x
assert_eq "2" "$RC" "RX_TEMPLATES nonexistent: rc 2"
# nothing to check: templates are not needed
R3="$(new_repo)"
mkdir -p "$R3/.rx/scripts"
cp "$ROOT"/scripts/*.sh "$R3/.rx/scripts/"
run_script "$R3/.rx/scripts/rx-check.sh" "$R3" specs
assert_eq "" "$OUT$ERR" "no features: templates not needed"
assert_eq "0" "$RC" "no features: rc 0"

[ "$RX_FAILS" -eq 0 ] && echo "test_check_specs: ok"
exit 0
