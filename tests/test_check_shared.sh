#!/usr/bin/env bash
# scripts/rx-check.sh shared: merge-safety gate (feature branches must not touch shared files).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

CHECK="$ROOT/scripts/rx-check.sh"
NL=$'\n'

# run_check <dir> [args...]: sets OUT, ERR, RC (cwd=<dir>).
run_check() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && "$CHECK" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# One template repo (on main, base_branch=main), copied per case: no git calls per copy.
TEMPLATE="$(cd "$(fixture_tmpdir)" && pwd -P)/t"
fixture_repo "$TEMPLATE"
fixture_config "$TEMPLATE"
mkdir -p "$TEMPLATE/docs/knowledge/decisions" "$TEMPLATE/docs/knowledge/learnings" \
  "$TEMPLATE/specs/x" "$TEMPLATE/specs/y" "$TEMPLATE/src" "$TEMPLATE/.rx/scripts"
printf 'claude\n' > "$TEMPLATE/CLAUDE.md"
printf 'agents\n' > "$TEMPLATE/AGENTS.md"
printf '<v>1</v>\n' > "$TEMPLATE/pom.xml"
printf 'arch\n' > "$TEMPLATE/docs/knowledge/architecture.md"
printf 'd1\n' > "$TEMPLATE/docs/knowledge/decisions/d1.md"
printf 'l1\n' > "$TEMPLATE/docs/knowledge/learnings/l1.md"
printf 'sx\n' > "$TEMPLATE/specs/x/state.md"
printf 'sy\n' > "$TEMPLATE/specs/y/state.md"
printf 'class A {}\n' > "$TEMPLATE/src/a.java"
printf '#!/bin/sh\n' > "$TEMPLATE/.rx/scripts/x.sh"
printf '.rx/local/\n' > "$TEMPLATE/.gitignore"
git -C "$TEMPLATE" add -A
git -C "$TEMPLATE" commit -q -m "base"
rm -rf "$TEMPLATE/.git/hooks"   # sample hooks only slow the per-case copies down

# fresh: copy of the template on main; prints its path.
fresh() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)/r"
  mkdir -p "$d"
  cp -R "$TEMPLATE/." "$d/"
  printf '%s\n' "$d"
}
# feat <repo>: create and switch to feature/x.
feat() { git -C "$1" checkout -q -b feature/x; }
# ci <repo>: commit everything.
ci() { git -C "$1" add -A && git -C "$1" commit -q -m c; }
# append <repo> <path>: modify a tracked file.
append() { printf 'more\n' >> "$1/$2"; }
# newfile <repo> <path>: create a file (and its directory).
newfile() { mkdir -p "$(dirname "$1/$2")" && printf 'new\n' > "$1/$2"; }
# idx_commit <repo> <path>: commit a file straight into the index (path need not exist on disk).
idx_commit() {
  local h
  h="$(printf 'x\n' | git -C "$1" hash-object -w --stdin)"
  git -C "$1" update-index --add --cacheinfo "100644,$h,$2"
  git -C "$1" commit -q -m c
}

# pass_case <label>: the last run was clean.
pass_case() {
  assert_eq "" "$OUT" "$1: no output"
  assert_eq "" "$ERR" "$1: quiet stderr"
  assert_eq "0" "$RC" "$1: rc 0"
}
# fail_case <label> <expected stdout>: the last run reported exactly these violations.
fail_case() {
  assert_eq "$2" "$OUT" "$1: violations"
  assert_eq "" "$ERR" "$1: quiet stderr"
  assert_eq "1" "$RC" "$1: rc 1"
}
# err_case <label> <expected stderr>: the last run was a usage/environment error.
err_case() {
  assert_eq "$2" "$ERR" "$1: stderr"
  assert_eq "" "$OUT" "$1: stdout empty"
  assert_eq "2" "$RC" "$1: rc 2"
}

SHARED="shared file modified"
KNOW="only new decision/learning files may be added under docs/knowledge/"
OTHER="another feature's spec modified"

# ---------- clean branches ----------
R="$(fresh)"; feat "$R"
run_check "$R" shared
pass_case "no changes at all"

R="$(fresh)"; feat "$R"
append "$R" src/a.java
newfile "$R" src/b.java
newfile "$R" src/deep/er/c.java
newfile "$R" specs/x/plan.md
append "$R" specs/x/state.md
newfile "$R" docs/knowledge/decisions/d2.md
newfile "$R" docs/knowledge/learnings/l2.md
ci "$R"
run_check "$R" shared
pass_case "clean branch: code + own specs + new decision and learning (committed)"
run_check "$R" shared x
pass_case "clean branch, explicit id"

R="$(fresh)"; feat "$R"
append "$R" src/a.java
newfile "$R" specs/x/plan.md
newfile "$R" docs/knowledge/decisions/d2.md
git -C "$R" add -A
newfile "$R" docs/knowledge/learnings/l2.md
newfile "$R" src/b.java
run_check "$R" shared
pass_case "clean branch: staged + unstaged + untracked"

# a new decision committed earlier and edited again before the next commit is still new
R="$(fresh)"; feat "$R"
newfile "$R" docs/knowledge/decisions/d2.md
ci "$R"
append "$R" docs/knowledge/decisions/d2.md
run_check "$R" shared
pass_case "new decision edited unstaged after its commit"
git -C "$R" add -A
run_check "$R" shared
pass_case "new decision edited and staged after its commit"
rm "$R/docs/knowledge/decisions/d2.md"
run_check "$R" shared
pass_case "new decision removed again before commit"

# a renamed code file is a delete plus an add of code: allowed
R="$(fresh)"; feat "$R"
git -C "$R" mv src/a.java src/c.java
ci "$R"
run_check "$R" shared
pass_case "renamed code file"

# a code file renamed INTO a protected place is an add there (no rename detection)
R="$(fresh)"; feat "$R"
git -C "$R" mv src/a.java docs/knowledge/zzz.md
ci "$R"
run_check "$R" shared
fail_case "code file renamed into docs/knowledge/" "docs/knowledge/zzz.md: $KNOW"
R="$(fresh)"; feat "$R"
git -C "$R" mv src/a.java .rx/new.yml
git -C "$R" mv docs/knowledge/decisions/d1.md src/d1.md
run_check "$R" shared
fail_case "renames staged: into .rx/, out of decisions/" ".rx/new.yml: $SHARED
docs/knowledge/decisions/d1.md: $KNOW"

# ---------- protected files: any change, in every form ----------
for f in CLAUDE.md AGENTS.md docs/knowledge/architecture.md pom.xml .rx/config.yml .rx/scripts/x.sh; do
  want="$f: $SHARED"
  R="$(fresh)"; feat "$R"; append "$R" "$f"; ci "$R"
  run_check "$R" shared
  fail_case "$f edit committed" "$want"
  R="$(fresh)"; feat "$R"; append "$R" "$f"; git -C "$R" add -A
  run_check "$R" shared
  fail_case "$f edit staged only" "$want"
  R="$(fresh)"; feat "$R"; append "$R" "$f"
  run_check "$R" shared
  fail_case "$f edit unstaged only" "$want"
  # (deleting .rx/config.yml disables rx altogether: the dispatcher no-ops without it)
  [ "$f" = ".rx/config.yml" ] && continue
  R="$(fresh)"; feat "$R"; git -C "$R" rm -q "$f"; ci "$R"
  run_check "$R" shared
  fail_case "$f deleted" "$want"
  R="$(fresh)"; feat "$R"; rm "$R/$f"
  run_check "$R" shared
  fail_case "$f deleted in the working tree only" "$want"
done

# the protected file is reported alone next to allowed changes
R="$(fresh)"; feat "$R"
append "$R" CLAUDE.md
append "$R" src/a.java
newfile "$R" specs/x/plan.md
ci "$R"
run_check "$R" shared
fail_case "CLAUDE.md among allowed changes" "CLAUDE.md: $SHARED"

# new files in protected places (absent from the base)
R="$(fresh)"
git -C "$R" rm -q CLAUDE.md AGENTS.md docs/knowledge/architecture.md pom.xml
git -C "$R" commit -q -m "drop"
feat "$R"
newfile "$R" CLAUDE.md
ci "$R"
run_check "$R" shared
fail_case "new CLAUDE.md committed" "CLAUDE.md: $SHARED"
git -C "$R" reset -q --hard main
newfile "$R" CLAUDE.md
run_check "$R" shared
fail_case "new CLAUDE.md untracked" "CLAUDE.md: $SHARED"
rm "$R/CLAUDE.md"
newfile "$R" docs/knowledge/architecture.md
run_check "$R" shared
fail_case "new architecture.md untracked" "docs/knowledge/architecture.md: $SHARED"
rm "$R/docs/knowledge/architecture.md"
newfile "$R" AGENTS.md
newfile "$R" pom.xml
run_check "$R" shared
fail_case "new AGENTS.md and version file untracked" "AGENTS.md: $SHARED
pom.xml: $SHARED"

# only the REPO ROOT CLAUDE.md/AGENTS.md are protected; same names elsewhere are code
R="$(fresh)"; feat "$R"
newfile "$R" src/CLAUDE.md
newfile "$R" docs/AGENTS.md
newfile "$R" docs/knowledge-base/architecture.md
newfile "$R" sub/pom.xml
run_check "$R" shared
pass_case "same names outside their protected location are code"

# ---------- version file ----------
R="$(fresh)"
fixture_config "$R" version_file=
git -C "$R" commit -q -am "no version file"
feat "$R"; append "$R" pom.xml; newfile "$R" version.txt
run_check "$R" shared
pass_case "empty version_file: nothing checked for it"

R="$(fresh)"
fixture_config "$R" version_file=./app/version.txt
mkdir -p "$R/app"; printf '1\n' > "$R/app/version.txt"
git -C "$R" add -A; git -C "$R" commit -q -m "nested version file"
feat "$R"; append "$R" app/version.txt
run_check "$R" shared
fail_case "nested version_file with ./ prefix" "app/version.txt: $SHARED"

R="$(fresh)"
fixture_config "$R" version_file=
git -C "$R" commit -q -am "no version file"
sed -e '/^version_file:/d' "$R/.rx/config.yml" > "$R/.rx/c.new" && mv "$R/.rx/c.new" "$R/.rx/config.yml"
git -C "$R" commit -q -am "no version_file key"
feat "$R"; append "$R" pom.xml
run_check "$R" shared
pass_case "version_file key absent: nothing checked for it"

# ---------- docs/knowledge ----------
for f in docs/knowledge/decisions/d1.md docs/knowledge/learnings/l1.md; do
  want="$f: $KNOW"
  R="$(fresh)"; feat "$R"; append "$R" "$f"; ci "$R"
  run_check "$R" shared
  fail_case "existing $f edited committed" "$want"
  R="$(fresh)"; feat "$R"; append "$R" "$f"
  run_check "$R" shared
  fail_case "existing $f edited unstaged" "$want"
  R="$(fresh)"; feat "$R"; append "$R" "$f"; git -C "$R" add -A
  run_check "$R" shared
  fail_case "existing $f edited staged" "$want"
  R="$(fresh)"; feat "$R"; git -C "$R" rm -q "$f"; ci "$R"
  run_check "$R" shared
  fail_case "existing $f deleted" "$want"
  R="$(fresh)"; feat "$R"; rm "$R/$f"
  run_check "$R" shared
  fail_case "existing $f deleted in the working tree only" "$want"
done

# renaming an existing decision: the old name is a delete, the new name is a new file
R="$(fresh)"; feat "$R"
git -C "$R" mv docs/knowledge/decisions/d1.md docs/knowledge/decisions/d9.md
ci "$R"
run_check "$R" shared
fail_case "existing decision renamed" "docs/knowledge/decisions/d1.md: $KNOW"

# new files with a shape that is not allowed
for f in docs/knowledge/decisions/sub/x.md docs/knowledge/learnings/a/b/x.md \
  docs/knowledge/decisions/x.txt docs/knowledge/decisions/x docs/knowledge/decisions/.md \
  docs/knowledge/x.md docs/knowledge/notes/x.md docs/knowledge/decisions.md \
  docs/knowledge/Decisions/x.md Docs/Knowledge/decisions/x.md docs/knowledge/architecture.md.bak; do
  R="$(fresh)"; feat "$R"
  # wrong-case names cannot be created on a case-insensitive filesystem: commit them to the index
  case "$f" in
    *[A-Z]*) idx_commit "$R" "$f" ;;
    *) newfile "$R" "$f"; ci "$R" ;;
  esac
  run_check "$R" shared
  fail_case "new $f committed" "$f: $KNOW"
done
R="$(fresh)"; feat "$R"
newfile "$R" docs/knowledge/decisions/sub/x.md
run_check "$R" shared
fail_case "nested decision untracked" "docs/knowledge/decisions/sub/x.md: $KNOW"

# ---------- specs ----------
R="$(fresh)"; feat "$R"; append "$R" specs/y/state.md; ci "$R"
run_check "$R" shared
fail_case "other feature's spec edited" "specs/y/state.md: $OTHER"
R="$(fresh)"; feat "$R"; newfile "$R" specs/y/plan.md
run_check "$R" shared
fail_case "other feature's spec: new untracked file" "specs/y/plan.md: $OTHER"
R="$(fresh)"; feat "$R"; newfile "$R" specs/z/deep/er/plan.md; git -C "$R" add -A
run_check "$R" shared
fail_case "unknown feature dir, nested, staged" "specs/z/deep/er/plan.md: $OTHER"
R="$(fresh)"; feat "$R"; git -C "$R" rm -q specs/y/state.md; ci "$R"
run_check "$R" shared
fail_case "other feature's spec deleted" "specs/y/state.md: $OTHER"
R="$(fresh)"; feat "$R"; newfile "$R" specs/NOTES.md
run_check "$R" shared
fail_case "top-level file under specs/" "specs/NOTES.md: $SHARED"
R="$(fresh)"; feat "$R"; newfile "$R" specs/z
run_check "$R" shared z
fail_case "file named like the feature id directly under specs/" "specs/z: $SHARED"
R="$(fresh)"; feat "$R"; newfile "$R" specs/xx/plan.md; newfile "$R" specs/x.old/plan.md
run_check "$R" shared
fail_case "dir names that merely start with the id" "specs/x.old/plan.md: $OTHER
specs/xx/plan.md: $OTHER"
R="$(fresh)"; feat "$R"; newfile "$R" notspecs/y/a.md; newfile "$R" src/specs/y/a.md
run_check "$R" shared
pass_case "specs/ elsewhere in the tree is code"
R="$(fresh)"; feat "$R"; idx_commit "$R" Specs/y/a.md
run_check "$R" shared
fail_case "wrong-case Specs/ is not the active feature" "Specs/y/a.md: $OTHER"

# ---------- .rx/ ----------
R="$(fresh)"; feat "$R"
rm "$R/.gitignore"   # .rx/local/ is normally gitignored; here it must pass on its own merit
newfile "$R" .rx/local/foo
newfile "$R" .rx/local/deep/bar
run_check "$R" shared
pass_case ".rx/local/ files, untracked and not ignored"
git -C "$R" add -A
run_check "$R" shared
pass_case ".rx/local/ files, staged"
ci "$R"
run_check "$R" shared
pass_case ".rx/local/ files, committed"
R="$(fresh)"; feat "$R"
newfile "$R" .rx/new.yml
newfile "$R" .rx/scripts/y.sh
newfile "$R" .rx/locale/x
newfile "$R" .rx/local
run_check "$R" shared
fail_case "other .rx/ paths" ".rx/local: $SHARED
.rx/locale/x: $SHARED
.rx/new.yml: $SHARED
.rx/scripts/y.sh: $SHARED"
R="$(fresh)"; feat "$R"; idx_commit "$R" ".RX/scripts/zz.sh"
run_check "$R" shared
fail_case "wrong-case .RX/" ".RX/scripts/zz.sh: $SHARED"

# ---------- case-insensitive names of protected files ----------
R="$(fresh)"
git -C "$R" rm -q CLAUDE.md; git -C "$R" commit -q -m drop
feat "$R"; idx_commit "$R" claude.md
run_check "$R" shared
fail_case "claude.md (wrong case) committed" "claude.md: $SHARED"

# ---------- multiple violations: sorted by path, one line each ----------
R="$(fresh)"; feat "$R"
append "$R" pom.xml
append "$R" docs/knowledge/decisions/d1.md
append "$R" specs/y/state.md
append "$R" CLAUDE.md
append "$R" AGENTS.md
append "$R" .rx/config.yml
ci "$R"
append "$R" CLAUDE.md
git -C "$R" add -A
append "$R" CLAUDE.md
newfile "$R" docs/knowledge/zzz.md
run_check "$R" shared
fail_case "many violations" ".rx/config.yml: $SHARED
AGENTS.md: $SHARED
CLAUDE.md: $SHARED
docs/knowledge/decisions/d1.md: $KNOW
docs/knowledge/zzz.md: $KNOW
pom.xml: $SHARED
specs/y/state.md: $OTHER"

# ---------- history: net change since the merge base ----------
R="$(fresh)"; feat "$R"
append "$R" CLAUDE.md; ci "$R"
git -C "$R" checkout -q main -- CLAUDE.md; ci "$R"
run_check "$R" shared
pass_case "violation committed then reverted before HEAD (net-zero)"

R="$(fresh)"; feat "$R"
append "$R" CLAUDE.md; ci "$R"
git -C "$R" checkout -q main -- CLAUDE.md
run_check "$R" shared
fail_case "violation committed, reverted in the working tree only" "CLAUDE.md: $SHARED"

# base moved on after the branch point: only the branch's own changes count
R="$(fresh)"; feat "$R"
append "$R" src/a.java; ci "$R"
git -C "$R" checkout -q main
append "$R" CLAUDE.md; append "$R" specs/y/state.md; ci "$R"
git -C "$R" checkout -q feature/x
run_check "$R" shared
pass_case "changes made on base after the branch point are not ours"

# ---------- paths with spaces and newlines ----------
R="$(fresh)"; feat "$R"
newfile "$R" "docs/knowledge/decisions/my decision.md"
newfile "$R" "docs/knowledge/learnings/a${NL}b.md"
newfile "$R" "src/my file.java"
newfile "$R" "specs/x/my notes.md"
ci "$R"
newfile "$R" "src/other file.java"
run_check "$R" shared
pass_case "spaces and a newline in allowed locations"

R="$(fresh)"; feat "$R"
newfile "$R" "specs/y/my notes.md"
newfile "$R" "docs/knowledge/decisions/sub dir/x y.md"
newfile "$R" "docs/knowledge/notes/a${NL}b.md"
newfile "$R" ".rx/my script.sh"
ci "$R"
run_check "$R" shared
fail_case "spaces and a newline in violating locations, verbatim" ".rx/my script.sh: $SHARED
docs/knowledge/decisions/sub dir/x y.md: $KNOW
docs/knowledge/notes/a${NL}b.md: $KNOW
specs/y/my notes.md: $OTHER"

# ---------- run from a subdirectory: paths are repo-root relative ----------
R="$(fresh)"; feat "$R"
newfile "$R" docs/knowledge/zzz.md
append "$R" src/a.java
run_check "$R/src" shared
fail_case "run from a subdirectory (untracked + unstaged)" "docs/knowledge/zzz.md: $KNOW"

# ---------- base branch ----------
R="$(fresh)"; feat "$R"; append "$R" CLAUDE.md; ci "$R"
git -C "$R" branch -q -m main old-main
run_check "$R" shared
err_case "base branch missing" "rx-check: base branch 'main' not found"

R="$(fresh)"
fixture_config "$R" base_branch=develop
git -C "$R" commit -q -am cfg
feat "$R"; append "$R" CLAUDE.md; ci "$R"
run_check "$R" shared
err_case "configured base branch does not exist" "rx-check: base branch 'develop' not found"

R="$(fresh)"
fixture_config "$R" base_branch=develop
git -C "$R" commit -q -am cfg
git -C "$R" branch -q develop
feat "$R"; append "$R" CLAUDE.md; ci "$R"
run_check "$R" shared
fail_case "configured base_branch other than main" "CLAUDE.md: $SHARED"

# missing base_branch key
R="$(fresh)"; feat "$R"
grep -v '^base_branch:' "$R/.rx/config.yml" > "$R/.rx/c.new" && mv "$R/.rx/c.new" "$R/.rx/config.yml"
run_check "$R" shared
assert_eq "rx: missing config key: base_branch" "$ERR" "no base_branch key: message"
assert_eq "" "$OUT" "no base_branch key: stdout empty"
assert_eq "2" "$RC" "no base_branch key: rc 2"
printf 'base_branch:\n' >> "$R/.rx/config.yml"
run_check "$R" shared x
assert_eq "rx: missing config key: base_branch" "$ERR" "empty base_branch value, explicit id: message"
assert_eq "2" "$RC" "empty base_branch value: rc 2"

# origin/<base> fallback when the local base is gone
R="$(fresh)"
ORIGIN="$(fixture_tmpdir)/origin.git"
git init -q --bare "$ORIGIN"
git -C "$R" remote add origin "$ORIGIN"
git -C "$R" push -q origin main 2>/dev/null
git -C "$R" fetch -q origin
feat "$R"
append "$R" src/a.java; newfile "$R" docs/knowledge/decisions/d2.md; ci "$R"
git -C "$R" branch -q -D main
run_check "$R" shared
pass_case "origin/main fallback, clean branch"
append "$R" AGENTS.md; ci "$R"
run_check "$R" shared
fail_case "origin/main fallback, violation" "AGENTS.md: $SHARED"
# a local base wins over origin
git -C "$R" branch -q main HEAD
run_check "$R" shared
pass_case "a local base is used in preference to origin/main"

# not a git repo
D="$(fixture_tmpdir)"
fixture_config "$D"
run_check "$D" shared x
err_case "not a git repository" "rx-check: not a git repository"

# ---------- which feature ----------
# on the base branch, no id: silent pass (even with a dirty tree)
R="$(fresh)"
append "$R" CLAUDE.md
run_check "$R" shared
pass_case "base branch, no id"
# an explicit id on the base branch is checked: committed diff is empty, the working tree is not
run_check "$R" shared x
fail_case "base branch, explicit id, dirty tree" "CLAUDE.md: $SHARED"
git -C "$R" checkout -q -- CLAUDE.md
run_check "$R" shared x
pass_case "base branch, explicit id, clean tree"

# non-feature branch / detached HEAD: needs an id
MSG="rx-check: shared needs a feature id (none resolved); pass one explicitly"
R="$(fresh)"; git -C "$R" checkout -q -b hotfix
append "$R" CLAUDE.md
run_check "$R" shared
err_case "non-feature branch, no id" "$MSG"
run_check "$R" shared x
fail_case "non-feature branch, explicit id" "CLAUDE.md: $SHARED"
mkdir -p "$R/.rx/local"; printf 'x\n' > "$R/.rx/local/active"
run_check "$R" shared
fail_case "non-feature branch, id from .rx/local/active" "CLAUDE.md: $SHARED"
R="$(fresh)"; git -C "$R" checkout -q --detach
run_check "$R" shared
err_case "detached HEAD, no id" "$MSG"
run_check "$R" shared x
pass_case "detached HEAD, explicit id"

# the explicit id overrides the branch
R="$(fresh)"; feat "$R"
newfile "$R" specs/y/plan.md
newfile "$R" specs/x/plan.md
run_check "$R" shared
fail_case "branch id x: specs/y is foreign" "specs/y/plan.md: $OTHER"
run_check "$R" shared y
fail_case "explicit id y overrides branch x" "specs/x/plan.md: $OTHER"

# bad ids and arity
R="$(fresh)"; feat "$R"
for bad in '../x' 'a/b' '-x' '.x' 'a b' ''; do
  run_check "$R" shared "$bad"
  assert_eq "" "$OUT" "bad id '$bad': stdout empty"
  assert_eq "rx-check: invalid feature id '$bad'" "$ERR" "bad id '$bad': message"
  assert_eq "2" "$RC" "bad id '$bad': rc 2"
done
run_check "$R" shared x y
assert_contains "$ERR" "usage: rx-check.sh" "two args: usage"
assert_eq "2" "$RC" "two args: rc 2"

# ---------- no config: silent no-op ----------
R="$(fresh)"; feat "$R"; append "$R" CLAUDE.md
rm -f "$R/.rx/config.yml"
run_check "$R" shared
assert_eq "" "$OUT$ERR" "no config: silent"
assert_eq "0" "$RC" "no config: rc 0"

exit 0
