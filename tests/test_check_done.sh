#!/usr/bin/env bash
# scripts/rx-check.sh done: close-out gate (specs + shared + gates + tasks + test_cmd + lint_cmd).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

CHECK="$ROOT/scripts/rx-check.sh"
TPL="$ROOT/skills/rx-spec/templates"
NL=$'\n'
CHK_ENV=""

# run_check <dir> [args...]: sets OUT, ERR, RC (cwd=<dir>). $CHK_ENV may hold an `env ...` prefix.
run_check() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && $CHK_ENV "$CHECK" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# Helper scripts for the user's commands (outside the repos, so they never show up as changes).
SCR="$(cd "$(fixture_tmpdir)" && pwd -P)"
# emit.sh <lines> <exit>: <lines> numbered lines on stdout, a last line on stderr.
cat > "$SCR/emit.sh" <<'EOS'
i=1
while [ "$i" -le "$1" ]; do echo "line $i"; i=$((i + 1)); done
echo "stderr-last" >&2
exit "$2"
EOS
# crlf.sh: CRLF line endings, UTF-8 and a raw 0xFF byte, no trailing newline; exit 1.
cat > "$SCR/crlf.sh" <<'EOS'
printf 'one\r\ncaf\303\251\r\n\377 raw'
exit 1
EOS
# hang.sh <pidfile>: a background child that outlives its parent unless the tree is killed.
cat > "$SCR/hang.sh" <<'EOS'
sleep 31 &
echo $! > "$1"
echo started
wait
EOS
# where.sh: prints the cwd and exits 1.
cat > "$SCR/where.sh" <<'EOS'
pwd
exit 1
EOS

# One template repo: main has CLAUDE.md and code; feature/x adds a complete, passing feature
# built from the REAL templates (all files finalized: status: final). The config is excluded from git so each case can rewrite it.
TEMPLATE="$(cd "$(fixture_tmpdir)" && pwd -P)/t"
fixture_repo "$TEMPLATE"
mkdir -p "$TEMPLATE/src"
printf 'claude\n' > "$TEMPLATE/CLAUDE.md"
printf 'class A {}\n' > "$TEMPLATE/src/a.java"
printf '.rx/local/\n' > "$TEMPLATE/.gitignore"
printf '.rx/config.yml\n' >> "$TEMPLATE/.git/info/exclude"
git -C "$TEMPLATE" add -A
git -C "$TEMPLATE" commit -q -m base
git -C "$TEMPLATE" checkout -q -b feature/x
mkdir -p "$TEMPLATE/specs/x"
sed -e 's/<feature-id>/x/' -e 's/^phase: .*/phase: close/' -e 's/^status: .*/status: approved/' \
  -e 's/^g1: .*/g1: approved:rex:2026-10-16/' -e 's/^g2: .*/g2: approved:rex:2026-10-16/' \
  -e 's/^g3: .*/g3: approved:rex:2026-10-16/' -e 's/^bump: .*/bump: minor/' \
  -e 's/^next: .*/next: merge/' -e 's/<YYYY-MM-DD>/2026-10-16/' "$TPL/state.md" > "$TEMPLATE/specs/x/state.md"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' -e 's/<what the system must do>/do it/' \
  -e 's/<observable pass\/fail condition>/it is done/' "$TPL/requirements.md" > "$TEMPLATE/specs/x/requirements.md"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' "$TPL/plan.md" > "$TEMPLATE/specs/x/plan.md"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' "$TPL/review.md" > "$TEMPLATE/specs/x/review.md"
{
  sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' \
    -e 's/^- \[ \] T-1 (AC-1): .*/- [x] T-1 (AC-1): first step/' "$TPL/tasks.md"
  printf -- '- [x] T-2 (AC-1): second step\n'
} > "$TEMPLATE/specs/x/tasks.md"
git -C "$TEMPLATE" add -A
git -C "$TEMPLATE" commit -q -m feature
rm -rf "$TEMPLATE/.git/hooks"

# fresh [config key=value...]: copy of the template on feature/x with the config written; prints its path.
fresh() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)/r"
  mkdir -p "$d"
  cp -R "$TEMPLATE/." "$d/"
  fixture_config "$d" "$@"
  printf '%s\n' "$d"
}
# sedf <file> <sed-args...>: edit a file in place (BSD-safe).
sedf() {
  local f="$1"
  shift
  sed "$@" "$f" > "$f.new" && mv "$f.new" "$f"
}

pass_case() {
  assert_eq "" "$OUT" "$1: no output"
  assert_eq "" "$ERR" "$1: quiet stderr"
  assert_eq "0" "$RC" "$1: rc 0"
}
fail_case() {
  assert_eq "$2" "$OUT" "$1: violations"
  assert_eq "" "$ERR" "$1: quiet stderr"
  assert_eq "1" "$RC" "$1: rc 1"
}
err_case() {
  assert_eq "$2" "$ERR" "$1: stderr"
  assert_eq "" "$OUT" "$1: stdout empty"
  assert_eq "2" "$RC" "$1: rc 2"
}

# ---------- full clean pass ----------
R="$(fresh)"
run_check "$R" done
pass_case "clean feature"
run_check "$R" done x
pass_case "clean feature, explicit id"
R="$(fresh lint_cmd=true test_timeout=30)"
run_check "$R" done
pass_case "clean feature with lint_cmd and test_timeout"
R="$(fresh 'test_cmd=sh -c "exit 0"' lint_cmd=)"
run_check "$R" done
pass_case "empty lint_cmd is skipped"
R="$(fresh)"
mkdir -p "$R/src/deep"
run_check "$R/src/deep" done
pass_case "clean feature, run from a subdirectory"

# ---------- tests: test_cmd ----------
R="$(fresh "test_cmd=sh $SCR/emit.sh 3 4")"
run_check "$R" done
fail_case "test_cmd fails" "tests: test_cmd failed (exit 4)
  | line 1
  | line 2
  | line 3
  | stderr-last"
R="$(fresh "test_cmd=sh $SCR/emit.sh 30 3")"
run_check "$R" done
fail_case "test_cmd fails with long output: last 15 lines only" "tests: test_cmd failed (exit 3)
  | line 17
  | line 18
  | line 19
  | line 20
  | line 21
  | line 22
  | line 23
  | line 24
  | line 25
  | line 26
  | line 27
  | line 28
  | line 29
  | line 30
  | stderr-last"
R="$(fresh "test_cmd=sh $SCR/emit.sh 15 1")"
run_check "$R" done
assert_eq "15" "$(printf '%s\n' "$OUT" | grep -c '^  | ')" "exactly 15 tail lines"
assert_eq "tests: test_cmd failed (exit 1)" "$(printf '%s\n' "$OUT" | sed -n 1p)" "header first"
R="$(fresh 'test_cmd=exit 5')"
run_check "$R" done
fail_case "test_cmd fails with no output" "tests: test_cmd failed (exit 5)"
R="$(fresh "test_cmd=sh $SCR/crlf.sh")"
run_check "$R" done
assert_eq "$(printf 'tests: test_cmd failed (exit 1)\n  | one\n  | caf\303\251\n  | \377 raw')" "$OUT" "CR stripped, other bytes passed through"
assert_eq "1" "$RC" "crlf output: rc 1"
R="$(fresh "test_cmd=sh $SCR/where.sh")"
mkdir -p "$R/src"
run_check "$R/src" done
fail_case "test_cmd runs from the repo root" "tests: test_cmd failed (exit 1)
  | $R"
R="$(fresh 'test_cmd=exit 5' lint_cmd=false)"
run_check "$R" done
assert_eq "tests: test_cmd failed (exit 5)${NL}lint: lint_cmd failed (exit 1)" "$OUT" "test and lint failures are both reported"

# test_cmd hangs: timeout violation, the whole process tree is gone
rm -f "$SCR/pidA" "$SCR/pidB"
R="$(fresh test_timeout=1 "test_cmd=sh $SCR/hang.sh $SCR/pidA")"
t0=$SECONDS
run_check "$R" done
fail_case "test_cmd hangs" "tests: test_cmd timed out after 1s"
[ $((SECONDS - t0)) -le 4 ] || _rx_fail "timeout took $((SECONDS - t0))s for a 1s limit"
kill -0 "$(cat "$SCR/pidA" 2>/dev/null || echo 999999)" 2>/dev/null && _rx_fail "orphan child of test_cmd survived"
[ -s "$SCR/pidA" ] || _rx_fail "hang.sh never ran"

# ---------- lint: lint_cmd ----------
R="$(fresh "lint_cmd=sh $SCR/emit.sh 2 2")"
run_check "$R" done
fail_case "lint_cmd fails" "lint: lint_cmd failed (exit 2)
  | line 1
  | line 2
  | stderr-last"
R="$(fresh test_timeout=1 "lint_cmd=sh $SCR/hang.sh $SCR/pidB")"
run_check "$R" done
fail_case "lint_cmd hangs" "lint: lint_cmd timed out after 1s"
kill -0 "$(cat "$SCR/pidB" 2>/dev/null || echo 999999)" 2>/dev/null && _rx_fail "orphan child of lint_cmd survived"
[ -s "$SCR/pidB" ] || _rx_fail "lint hang.sh never ran"
R="$(fresh test_timeout=1 "test_cmd=sh $SCR/hang.sh $SCR/pidA" "lint_cmd=sh $SCR/hang.sh $SCR/pidB")"
run_check "$R" done
fail_case "both hang" "tests: test_cmd timed out after 1s${NL}lint: lint_cmd timed out after 1s"

# ---------- gates ----------
for g in g1 g2 g3; do
  R="$(fresh)"
  sedf "$R/specs/x/state.md" "s/^$g: .*/$g: none/"
  run_check "$R" done
  fail_case "$g none" "specs/x/state.md: $g not approved"
done
R="$(fresh)"
sedf "$R/specs/x/state.md" -e 's/^g1: .*/g1: none/' -e 's/^g2: .*/g2: none/' -e 's/^g3: .*/g3: none/'
run_check "$R" done
fail_case "all gates none" "specs/x/state.md: g1 not approved
specs/x/state.md: g2 not approved
specs/x/state.md: g3 not approved"
R="$(fresh)"
sedf "$R/specs/x/state.md" 's/^g2: .*/g2: yes/'
run_check "$R" done
fail_case "malformed gate: specs says why, done says not approved" "specs/x/state.md: bad g2 'yes'
specs/x/state.md: g2 not approved"
# bump: every valid value counts as recorded, none included; an invalid one is a specs violation
for b in none patch minor major; do
  R="$(fresh)"
  sedf "$R/specs/x/state.md" "s/^bump: .*/bump: $b/"
  run_check "$R" done
  pass_case "bump $b"
done
R="$(fresh)"
sedf "$R/specs/x/state.md" 's/^bump: .*/bump: /'
run_check "$R" done
fail_case "bump blank" "specs/x/state.md: unknown bump ''"
R="$(fresh)"
rm "$R/specs/x/state.md"
run_check "$R" done
fail_case "no state.md" "specs/x/state.md: not found
specs/x/state.md: required for full lane
specs/x/state.md: g1 not approved
specs/x/state.md: g2 not approved
specs/x/state.md: g3 not approved"

# ---------- tasks ----------
R="$(fresh)"
{
  sed -e 's/^- \[x\] T-2.*//' "$R/specs/x/tasks.md" | sed -e 's/^- \[x\] T-1/- [ ] T-1/'
  printf -- '- [ ] T-2 (AC-1): second step\n- [x] T-3 (AC-1): third\n- [ ] T-10 (AC-1): tenth\n'
} > "$R/specs/x/tasks.new"
mv "$R/specs/x/tasks.new" "$R/specs/x/tasks.md"
run_check "$R" done
fail_case "unticked tasks, one line each" "specs/x/tasks.md: T-1 not done
specs/x/tasks.md: T-2 not done
specs/x/tasks.md: T-10 not done"
R="$(fresh)"
sedf "$R/specs/x/tasks.md" 's/$/'"$(printf '\r')"'/'
sedf "$R/specs/x/tasks.md" 's/^- \[x\] T-2/- [ ] T-2/'
run_check "$R" done
fail_case "CRLF tasks.md" "specs/x/tasks.md: T-2 not done"
R="$(fresh)"
rm "$R/specs/x/tasks.md"
run_check "$R" done
fail_case "no tasks.md and no quick.md" "specs/x/tasks.md: required for full lane"
R="$(fresh)"
sedf "$R/specs/x/tasks.md" '/^- \[/d'
run_check "$R" done
fail_case "tasks.md without task lines" "specs/x/tasks.md: no tasks found"
R="$(fresh)"
sedf "$R/specs/x/tasks.md" 's/^- \[x\] T-2/- [ ] T-2/; s/T-1 (AC-1)/T-1 (AC-9)/'
run_check "$R" done
fail_case "specs problems in tasks.md are specs's, the unticked one is done's" "specs/x/tasks.md: T-1 cites unknown AC-9
specs/x/tasks.md: T-2 not done"

# quick lane: state + quick.md, no requirements/plan/tasks
quick_lane() {
  rm "$1/specs/x/requirements.md" "$1/specs/x/plan.md" "$1/specs/x/tasks.md" "$1/specs/x/review.md"
  sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' -e 's/<what and why[^>]*>/tiny/' \
    -e 's/<observable pass\/fail condition>/it works/' \
    -e 's/^- \[ \] T-1 (AC-1): .*/- [x] T-1 (AC-1): do it/' "$TPL/quick.md" > "$1/specs/x/quick.md"
}
R="$(fresh)"
quick_lane "$R"
run_check "$R" done
pass_case "quick lane, all ticked"
R="$(fresh)"
quick_lane "$R"
sedf "$R/specs/x/quick.md" 's/^- \[x\] T-1/- [ ] T-1/'
run_check "$R" done
fail_case "quick lane, unticked" "specs/x/quick.md: T-1 not done"
R="$(fresh)"
quick_lane "$R"
sedf "$R/specs/x/quick.md" '/^- \[/d'
run_check "$R" done
fail_case "quick lane, no task lines" "specs/x/quick.md: no tasks found"
R="$(fresh)"
quick_lane "$R"
rm "$R/specs/x/quick.md"
run_check "$R" done
fail_case "quick.md missing: the full lane is required" "specs/x/requirements.md: required for full lane
specs/x/plan.md: required for full lane
specs/x/tasks.md: required for full lane
specs/x/review.md: required for full lane"


# ---------- lanes ----------
# quick lane: g2 is its only gate; g1 and g3 are not required
R="$(fresh)"
quick_lane "$R"
sedf "$R/specs/x/state.md" -e 's/^g1: .*/g1: none/' -e 's/^g3: .*/g3: none/'
run_check "$R" done
pass_case "quick lane: g1 and g3 not required"
sedf "$R/specs/x/state.md" 's/^g2: .*/g2: none/'
run_check "$R" done
fail_case "quick lane: g2 required" "specs/x/state.md: g2 not approved"
# an optional review.md is fine in the quick lane (and must be final)
R="$(fresh)"
quick_lane "$R"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' "$TPL/review.md" > "$R/specs/x/review.md"
run_check "$R" done
pass_case "quick lane with a final review.md"
sedf "$R/specs/x/review.md" 's/^status: final/status: draft/'
run_check "$R" done
fail_case "quick lane with a draft review.md" "specs/x/review.md: status must be final"
# quick lane: missing quick.md's partner state.md
R="$(fresh)"
quick_lane "$R"
rm "$R/specs/x/state.md"
run_check "$R" done
fail_case "quick lane without state.md" "specs/x/state.md: not found
specs/x/state.md: required for quick lane
specs/x/state.md: g2 not approved"

# full lane: all five files are required
for f in requirements plan tasks review; do
  R="$(fresh)"
  rm "$R/specs/x/$f.md"
  run_check "$R" done
  assert_contains "$OUT" "specs/x/$f.md: required for full lane" "full lane without $f.md"
  assert_eq "1" "$RC" "full lane without $f.md: rc 1"
done
R="$(fresh)"
rm "$R/specs/x/review.md"
run_check "$R" done
fail_case "full lane without review.md" "specs/x/review.md: required for full lane"
R="$(fresh)"
rm "$R/specs/x/requirements.md" "$R/specs/x/plan.md" "$R/specs/x/review.md"
run_check "$R" done
assert_contains "$OUT" "specs/x/requirements.md: required for full lane
specs/x/plan.md: required for full lane
specs/x/review.md: required for full lane" "several missing files, one line each, fixed order"

# lanes are exclusive
R="$(fresh)"
quick_lane "$R"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' "$TPL/plan.md" > "$R/specs/x/plan.md"
run_check "$R" done
fail_case "quick.md with plan.md" "specs/x: quick and full lane files cannot be mixed"
R="$(fresh)"
quick_lane "$R"
sed -e 's/<feature-id>/x/' -e 's/^status: draft/status: final/' -e '/^- AC-/d' "$TPL/requirements.md" > "$R/specs/x/requirements.md"
run_check "$R" done
fail_case "quick.md with requirements.md" "specs/x: quick and full lane files cannot be mixed"
R="$(fresh)"
quick_lane "$R"
printf -- '---\nstatus: final\n---\n# Tasks: x\n\n## Tasks\n- [x] T-5 (AC-1): other\n' > "$R/specs/x/tasks.md"
run_check "$R" done
fail_case "quick.md with tasks.md" "specs/x: quick and full lane files cannot be mixed"
R="$(fresh)"
cp "$TPL/quick.md" "$R/specs/x/quick.md"
sedf "$R/specs/x/quick.md" -e 's/^status: draft/status: final/' -e 's/^- \[ \]/- [x]/'
run_check "$R" done
assert_contains "$OUT" "specs/x: quick and full lane files cannot be mixed" "full lane files plus quick.md"

# ---------- status: final ----------
R="$(fresh)"
for f in requirements plan tasks review; do sedf "$R/specs/x/$f.md" 's/^status: final/status: draft/'; done
run_check "$R" done
fail_case "all draft" "specs/x/requirements.md: status must be final
specs/x/plan.md: status must be final
specs/x/tasks.md: status must be final
specs/x/review.md: status must be final"
for f in requirements plan tasks review; do
  R="$(fresh)"
  sedf "$R/specs/x/$f.md" 's/^status: final/status: draft/'
  run_check "$R" done
  fail_case "$f.md draft" "specs/x/$f.md: status must be final"
done
R="$(fresh)"
sedf "$R/specs/x/state.md" 's/^status: .*/status: draft/'
run_check "$R" done
pass_case "state.md is not subject to the final rule"
R="$(fresh)"
quick_lane "$R"
sedf "$R/specs/x/quick.md" 's/^status: final/status: draft/'
run_check "$R" done
fail_case "quick.md draft" "specs/x/quick.md: status must be final"
R="$(fresh)"
sedf "$R/specs/x/plan.md" '1,3d'
run_check "$R" done
assert_contains "$OUT" "specs/x/plan.md: status must be final" "no frontmatter at all is not final"

# ---------- leftover qa/security files ----------
for f in review.qa.md review.security.md; do
  R="$(fresh)"
  printf -- '---\nstatus: draft\n---\n# findings\n' > "$R/specs/x/$f"
  run_check "$R" done
  fail_case "leftover $f" "specs/x/$f: merge into review.md and delete"
done
R="$(fresh)"
printf -- '---\nstatus: draft\n---\n' > "$R/specs/x/review.qa.md"
cp "$R/specs/x/review.qa.md" "$R/specs/x/review.security.md"
run_check "$R" done
fail_case "both leftovers" "specs/x/review.qa.md: merge into review.md and delete
specs/x/review.security.md: merge into review.md and delete"

# ---------- unticked checkboxes cannot hide ----------
R="$(fresh)"
printf -- '- [ ] fix the remaining failing tests\n' >> "$R/specs/x/tasks.md"
run_check "$R" done
fail_case "loose unticked checkbox" "specs/x/tasks.md: malformed task line '- [ ] fix the remaining failing tests'"
R="$(fresh)"
printf -- '1. [ ] T-2 (AC-1): hidden\n' >> "$R/specs/x/tasks.md"
run_check "$R" done
fail_case "numbered unticked checkbox" "specs/x/tasks.md: malformed task line '1. [ ] T-2 (AC-1): hidden'"
R="$(fresh)"
quick_lane "$R"
printf -- '* [ ] one more thing\n' >> "$R/specs/x/quick.md"
run_check "$R" done
fail_case "loose unticked checkbox in quick.md" "specs/x/quick.md: malformed task line '* [ ] one more thing'"

# ---------- version_bump ----------
R="$(fresh version_bump=feature)"
run_check "$R" done
pass_case "version_bump feature"
R="$(fresh version_bump=sometimes)"
run_check "$R" done
err_case "invalid version_bump" "rx-check: invalid version_bump 'sometimes' (release|feature)"

# ---------- fail closed on an unexpected status from specs/shared ----------
PATCHED="$(fixture_tmpdir)"
mkdir -p "$PATCHED/scripts"
cp "$ROOT"/scripts/*.sh "$PATCHED/scripts/"
cp -R "$ROOT/skills" "$PATCHED/skills"
# patch <stub>: insert a stub function before the dispatcher runs
patch_check() {
  awk -v stub="$1" '/^SUB=/ { print stub } { print }' "$ROOT/scripts/rx-check.sh" > "$PATCHED/scripts/rx-check.sh"
}
R="$(fresh)"
patch_check '_chk_specs() { return 3; }'
run_script() { local ef; ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"; OUT="$(cd "$1" && "$PATCHED/scripts/rx-check.sh" "${@:2}" 2>"$ef")"; RC=$?; ERR="$(cat "$ef")"; rm -f "$ef"; }
run_script "$R" done
err_case "specs returns 3" "rx-check: unexpected status 3 from specs"
patch_check '_chk_specs() { return 1; }'
run_script "$R" done
err_case "specs returns 1 without output" "rx-check: unexpected status 1 from specs"
patch_check '_chk_shared() { return 1; }'
run_script "$R" done
err_case "shared returns 1 without output" "rx-check: unexpected status 1 from shared"
patch_check '_chk_shared() { return 139; }'
run_script "$R" done
err_case "shared returns 139" "rx-check: unexpected status 139 from shared"
patch_check '_chk_shared() { echo "x: y"; return 1; }'
run_script "$R" done
fail_case "shared output with 1 is a normal violation" "x: y"
patch_check ':'
run_script "$R" done
pass_case "unpatched copy still passes"

# ---------- bubbling up specs and shared ----------
R="$(fresh)"
{ cat "$R/specs/x/plan.md"; i=0; while [ "$i" -lt 100 ]; do printf 'filler\n'; i=$((i + 1)); done; } > "$R/specs/x/plan.new"
mv "$R/specs/x/plan.new" "$R/specs/x/plan.md"
n="$(awk 'END { print NR }' "$R/specs/x/plan.md")"
run_check "$R" done
fail_case "specs violation (cap)" "specs/x/plan.md: $n lines exceeds cap 100"
R="$(fresh)"
printf 'more\n' >> "$R/CLAUDE.md"
run_check "$R" done
fail_case "shared violation" "CLAUDE.md: shared file modified"

# collect-all: every check runs, in a fixed order, one report
R="$(fresh "test_cmd=sh $SCR/emit.sh 2 3" lint_cmd=false)"
sedf "$R/specs/x/plan.md" 's/^status: final/status: wip/'
printf 'more\n' >> "$R/CLAUDE.md"
sedf "$R/specs/x/state.md" 's/^g2: .*/g2: none/'
sedf "$R/specs/x/tasks.md" 's/^- \[x\] T-1/- [ ] T-1/'
run_check "$R" done
fail_case "everything wrong at once" "specs/x/plan.md: frontmatter status must be draft|final
CLAUDE.md: shared file modified
specs/x/plan.md: status must be final
specs/x/state.md: g2 not approved
specs/x/tasks.md: T-1 not done
tests: test_cmd failed (exit 3)
  | line 1
  | line 2
  | stderr-last
lint: lint_cmd failed (exit 1)"

# ---------- which feature ----------
R="$(fresh)"
run_check "$R" done z
assert_eq "1" "$RC" "explicit id overrides the branch: rc 1"
assert_contains "$OUT" "specs/z: not found" "explicit id overrides the branch: z is checked"
assert_eq "" "$ERR" "explicit id overrides the branch: quiet stderr"
R="$(fresh)"
git -C "$R" checkout -q -b work
mkdir -p "$R/.rx/local"
printf 'x\n' > "$R/.rx/local/active"
run_check "$R" done
pass_case "id from .rx/local/active"
R="$(fresh)"
git -C "$R" checkout -q main
run_check "$R" done
err_case "no id on the base branch" "rx-check: done needs a feature id (none resolved); pass one explicitly"
git -C "$R" checkout -q -b scratch
run_check "$R" done
err_case "no id on another branch" "rx-check: done needs a feature id (none resolved); pass one explicitly"
run_check "$R" done ../x
err_case "bad id" "rx-check: invalid feature id '../x'"
run_check "$R" done x y
assert_contains "$ERR" "usage: rx-check.sh" "two ids: usage"
assert_eq "2" "$RC" "two ids: rc 2"

# ---------- environment errors (exit 2, nothing on stdout) ----------
R="$(fresh base_branch=nope)"
run_check "$R" done
err_case "base branch missing" "rx-check: base branch 'nope' not found"
R="$(fresh test_cmd=)"
run_check "$R" done
err_case "test_cmd missing" "rx: missing config key: test_cmd"
for v in abc 0 -5 1.5 600s 007 1234567890; do
  R="$(fresh "test_timeout=$v")"
  run_check "$R" done
  err_case "test_timeout '$v'" "rx-check: invalid test_timeout '$v' (expected a positive integer number of seconds)"
done
R="$(fresh)"
git -C "$R" checkout -q --orphan feature/x2
git -C "$R" commit -q -m orphan
run_check "$R" done x2
err_case "no merge base" "rx-check: cannot diff against base branch 'main': no merge base with HEAD"
D="$(fixture_tmpdir)"
fixture_config "$D"
run_check "$D" done x
err_case "not a git repository" "rx-check: not a git repository"

# ---------- temp files are removed on every path ----------
TD="$(fixture_tmpdir)"
R="$(fresh)"
TMPDIR="$TD" run_check "$R" done
pass_case "temp cleanup: clean run"
assert_eq "" "$(ls -A "$TD")" "temp cleanup: nothing left after a clean run"
R="$(fresh "test_cmd=sh $SCR/emit.sh 40 1")"
printf 'more\n' >> "$R/CLAUDE.md"
TMPDIR="$TD" run_check "$R" done
assert_eq "1" "$RC" "temp cleanup: violating run rc 1"
assert_eq "" "$(ls -A "$TD")" "temp cleanup: nothing left after a violating run"
R="$(fresh base_branch=nope)"
TMPDIR="$TD" run_check "$R" done
assert_eq "2" "$RC" "temp cleanup: shared error run rc 2"
assert_eq "" "$(ls -A "$TD")" "temp cleanup: nothing left after an exit-2 run"
R="$(fresh test_cmd=)"
TMPDIR="$TD" run_check "$R" done
assert_eq "2" "$RC" "temp cleanup: config error run rc 2"
assert_eq "" "$(ls -A "$TD")" "temp cleanup: nothing left after a config error"
R="$(fresh test_timeout=1 "test_cmd=sh $SCR/hang.sh $SCR/pidA")"
TMPDIR="$TD" run_check "$R" done
assert_eq "1" "$RC" "temp cleanup: timeout run rc 1"
assert_eq "" "$(ls -A "$TD")" "temp cleanup: nothing left after a timeout"

# ---------- the user's commands see the user's locale, not the gate's LC_ALL=C ----------
R="$(fresh 'test_cmd=echo "L=${LC_ALL-UNSET}"; exit 1' 'lint_cmd=echo "L=${LC_ALL-UNSET}"; exit 1')"
CHK_ENV="env LC_ALL=POSIX"
run_check "$R" done
fail_case "LC_ALL set originally" "tests: test_cmd failed (exit 1)
  | L=POSIX
lint: lint_cmd failed (exit 1)
  | L=POSIX"
CHK_ENV="env LC_ALL="
run_check "$R" done
fail_case "LC_ALL set but empty originally" "tests: test_cmd failed (exit 1)
  | L=
lint: lint_cmd failed (exit 1)
  | L="
CHK_ENV="env -u LC_ALL"
run_check "$R" done
fail_case "LC_ALL unset originally" "tests: test_cmd failed (exit 1)
  | L=UNSET
lint: lint_cmd failed (exit 1)
  | L=UNSET"
CHK_ENV=""

# ---------- no config: silent no-op ----------
R="$(fresh)"
rm "$R/.rx/config.yml"
run_check "$R" done
pass_case "no config"
