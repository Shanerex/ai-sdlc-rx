#!/usr/bin/env bash
# scripts/rx-status.sh: active-feature block, --all remote listing, stale-script warning, no-op.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

STATUS="$ROOT/scripts/rx-status.sh"
TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"

# run_status <dir> [args...]: sets OUT, ERR, RC (script run by absolute path, cwd=<dir>).
run_status() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && "$STATUS" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# run_script <script> <dir> [args...]: same, with an explicit script path.
run_script() {
  local s="$1" d="$2" ef
  shift 2
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && "$s" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  fixture_config "$d/r"
  printf '%s\n' "$d/r"
}

# mkstate <repo> <id> <phase> <status> <g1> <g2> <g3> <bump> <next>: built from the REAL template.
mkstate() {
  mkdir -p "$1/specs/$2"
  sed -e "s/^feature: .*/feature: $2/" \
      -e "s/^phase: .*/phase: $3/" \
      -e "s/^status: .*/status: $4/" \
      -e "s/^g1: .*/g1: $5/" \
      -e "s/^g2: .*/g2: $6/" \
      -e "s/^g3: .*/g3: $7/" \
      -e "s/^bump: .*/bump: $8/" \
      -e "s/^next: .*/next: $9/" \
      "$TPL_STATE" > "$1/specs/$2/state.md"
}

TASKS3='# Tasks: x

## Tasks
- [x] T-1 (AC-1): first
- [ ] T-2 (AC-1): second
- [ ] T-3 (AC-2): third
- [x] not a task line
  - [x] T-9 (AC-1): indented, not counted
'

# ---------- exact active block ----------
R="$(new_repo)"
git -C "$R" checkout -q -b feature/x
mkstate "$R" x build awaiting-human approved:rex:2026-10-16 none none minor "write the code"
printf '%s' "$TASKS3" > "$R/specs/x/tasks.md"
run_status "$R"
want="feature: x
phase:   build (awaiting-human)
gates:   g1=approved:rex:2026-10-16 g2=none g3=none
bump:    minor
tasks:   1/3
next:    write the code"
assert_eq "$want" "$OUT" "active block exact output"
assert_eq "0" "$RC" "active block rc"
assert_eq "" "$ERR" "active block quiet"

# default template values, no approvals
mkstate "$R" x intake draft none none none none "do it"
run_status "$R"
assert_contains "$OUT" "gates:   g1=none g2=none g3=none" "gates none verbatim"
assert_contains "$OUT" "phase:   intake (draft)" "phase draft"

# tasks.md missing
rm -f "$R/specs/x/tasks.md"
run_status "$R"
assert_contains "$OUT" "tasks:   -" "tasks missing prints dash"
assert_eq "0" "$RC" "tasks missing rc"

# CRLF and no final newline
printf -- '- [x] T-1 (AC-1): a\r\n- [ ] T-2 (AC-1): b\r\n- [x] T-3 (AC-2): c' > "$R/specs/x/tasks.md"
run_status "$R"
assert_contains "$OUT" "tasks:   2/3" "crlf + no final newline counted"
printf -- '- [ ] T-1 (AC-1): a' > "$R/specs/x/tasks.md"
run_status "$R"
assert_contains "$OUT" "tasks:   0/1" "single unticked task, no final newline"
: > "$R/specs/x/tasks.md"
run_status "$R"
assert_contains "$OUT" "tasks:   0/0" "empty tasks.md"

# from a subdirectory
printf '%s' "$TASKS3" > "$R/specs/x/tasks.md"
mkdir -p "$R/src/deep"
run_status "$R/src/deep"
assert_contains "$OUT" "feature: x" "run from subdirectory: feature"
assert_contains "$OUT" "tasks:   1/3" "run from subdirectory: tasks"

# unknown argument
run_status "$R" --bogus
assert_eq "2" "$RC" "unknown arg rc 2"
assert_eq "" "$OUT" "unknown arg no stdout"
assert_contains "$ERR" "usage" "unknown arg usage on stderr"
run_status "$R" --all extra
assert_eq "2" "$RC" "extra arg rc 2"

# ---------- no active feature / active file ----------
N="$(new_repo)"
run_status "$N"
assert_eq "no active feature" "$OUT" "no active feature output"
assert_eq "0" "$RC" "no active feature rc"
assert_eq "" "$ERR" "no active feature quiet"

mkstate "$N" fromfile plan approved approved:a:2026-01-02 approved:b:2026-02-03 none patch "next step"
mkdir -p "$N/.rx/local"
printf 'fromfile\n' > "$N/.rx/local/active"
run_status "$N"
assert_contains "$OUT" "feature: fromfile" "active file fallback"
assert_contains "$OUT" "gates:   g1=approved:a:2026-01-02 g2=approved:b:2026-02-03 g3=none" "two approvals shown"
assert_contains "$OUT" "tasks:   -" "active file fallback, no tasks.md"

# ---------- invalid / missing state ----------
I="$(new_repo)"
git -C "$I" checkout -q -b feature/bad
run_status "$I"
assert_eq "state.md invalid: not found" "$OUT" "missing state.md on stdout"
assert_eq "1" "$RC" "missing state.md rc 1"
assert_eq "" "$ERR" "missing state.md nothing on stderr"
mkstate "$I" bad foo draft none none none none n
run_status "$I" --all
assert_eq "state.md invalid: unknown phase 'foo'" "$OUT" "invalid state line on stdout, exits before --all"
assert_eq "1" "$RC" "invalid state rc 1"
assert_eq "" "$ERR" "invalid state stderr empty"

# ---------- no-op without config ----------
Z="$(cd "$(fixture_tmpdir)" && pwd -P)"
fixture_repo "$Z/r"
git -C "$Z/r" checkout -q -b feature/x
mkstate "$Z/r" x build draft none none none none n
run_status "$Z/r"
assert_eq "" "$OUT$ERR" "no config: silent"
assert_eq "0" "$RC" "no config: rc 0"
run_status "$Z/r" --all
assert_eq "" "$OUT$ERR" "no config --all: silent"
assert_eq "0" "$RC" "no config --all: rc 0"

# ---------- --all ----------
T="$(cd "$(fixture_tmpdir)" && pwd -P)"
git init -q --bare "$T/origin.git"
fixture_repo "$T/r"
fixture_config "$T/r"
A="$T/r"
git -C "$A" remote add origin "$T/origin.git"
git -C "$A" push -q origin main 2>/dev/null
for id in b a; do
  git -C "$A" checkout -q -b "feature/$id" main
  mkstate "$A" "$id" build awaiting-human none none none none "next $id"
  printf -- '- [x] T-1 (AC-1): one\n- [ ] T-2 (AC-1): two\n' > "$A/specs/$id/tasks.md"
  git -C "$A" add specs
  git -C "$A" commit -q -m "spec $id"
  git -C "$A" push -q origin "feature/$id" 2>/dev/null
done
# b: richer data on the remote
git -C "$A" checkout -q feature/b
mkstate "$A" b verify approved approved:rex:2026-10-16 approved:sam:2026-10-17 none minor "ship b"
printf -- '- [x] T-1 (AC-1): one\n- [x] T-2 (AC-1): two\n- [x] T-3 (AC-2): three\n' > "$A/specs/b/tasks.md"
git -C "$A" commit -q -am "b progress"
git -C "$A" push -q origin feature/b 2>/dev/null
# c: remote branch without state.md; release/1: not a feature branch
git -C "$A" checkout -q -b feature/c main
git -C "$A" push -q origin feature/c 2>/dev/null
git -C "$A" checkout -q -b release/1 main
git -C "$A" push -q origin release/1 2>/dev/null
# b exists only remotely
git -C "$A" checkout -q feature/a
git -C "$A" branch -q -D feature/b feature/c release/1
git -C "$A" fetch -q origin

head_before="$(git -C "$A" rev-parse HEAD)"
branch_before="$(git -C "$A" symbolic-ref HEAD)"
status_before="$(git -C "$A" status --porcelain)"
branches_before="$(git -C "$A" branch --list)"
ls_before="$(ls "$A/specs")"

run_status "$A" --all
want="feature: a
phase:   build (awaiting-human)
gates:   g1=none g2=none g3=none
bump:    none
tasks:   1/2
next:    next a

* a  build/awaiting-human  1/2  g1=none g2=none g3=none
  b  verify/approved  3/3  g1=approved:rex:2026-10-16 g2=approved:sam:2026-10-17 g3=none
  c  (no state.md)"
assert_eq "$want" "$OUT" "--all output: block, blank line, sorted lines, marker on active"
assert_eq "0" "$RC" "--all rc"
assert_eq "" "$ERR" "--all quiet"
assert_eq "$head_before" "$(git -C "$A" rev-parse HEAD)" "--all leaves HEAD"
assert_eq "$branch_before" "$(git -C "$A" symbolic-ref HEAD)" "--all leaves current branch"
assert_eq "$status_before" "$(git -C "$A" status --porcelain)" "--all leaves worktree status"
assert_eq "$branches_before" "$(git -C "$A" branch --list)" "--all creates no local branches"
assert_eq "$ls_before" "$(ls "$A/specs")" "--all leaves specs dir (b and c not checked out)"

# without --all no remote lines
run_status "$A"
case "$OUT" in
  *"verify/approved"*) assert_eq "no remote lines" "remote lines present" "plain run omits --all lines" ;;
esac

# no active feature + --all
git -C "$A" checkout -q main
run_status "$A" --all
case "$OUT" in
  "no active feature
"*) ;;
  *) assert_eq "starts with no active feature" "$OUT" "no active + --all starts with message" ;;
esac
assert_contains "$OUT" "
  a  build/awaiting-human  1/2  g1=none g2=none g3=none" "no active: no marker on a"
assert_contains "$OUT" "
  b  verify/approved" "no active: b listed"
git -C "$A" checkout -q feature/a

# no fetch: a branch pushed by someone else is not shown until fetched
git clone -q "$T/origin.git" "$T/other" 2>/dev/null
git -C "$T/other" config user.name o
git -C "$T/other" config user.email o@rx.invalid
git -C "$T/other" config commit.gpgsign false
git -C "$T/other" checkout -q -b feature/z main
git -C "$T/other" commit -q --allow-empty -m z
git -C "$T/other" push -q origin feature/z 2>/dev/null
run_status "$A" --all
case "$OUT" in
  *"  z  "*) assert_eq "z absent" "z present" "--all does not fetch" ;;
esac

# --all with no origin remote
NR="$(new_repo)"
git -C "$NR" checkout -q -b feature/x
mkstate "$NR" x build draft none none none none "n"
run_status "$NR"
plain="$OUT"
run_status "$NR" --all
assert_eq "$plain" "$OUT" "--all without origin prints nothing extra"
assert_eq "0" "$RC" "--all without origin rc 0"
assert_eq "" "$ERR" "--all without origin quiet"

# --all with origin but no matching branches
NM="$(new_repo)"
git init -q --bare "$(dirname "$NM")/o.git"
git -C "$NM" remote add origin "$(dirname "$NM")/o.git"
git -C "$NM" push -q origin main 2>/dev/null
git -C "$NM" fetch -q origin
run_status "$NM" --all
assert_eq "no active feature" "$OUT" "--all with no matching remote branch prints nothing extra"
assert_eq "0" "$RC" "--all no matching rc 0"

# ---------- stale-script warning ----------
# plugin layout in a temp dir so the plugin version is controlled
mkplugin() { # <dir> <version>
  mkdir -p "$1/scripts" "$1/.claude-plugin"
  cp "$ROOT/scripts/rx-lib.sh" "$ROOT/scripts/rx-status.sh" "$1/scripts/" 2>/dev/null
  chmod 755 "$1/scripts/rx-status.sh" 2>/dev/null
  printf '{"name":"rx","version":"%s"}\n' "$2" > "$1/.claude-plugin/plugin.json"
}
S="$(new_repo)"
git -C "$S" checkout -q -b feature/x
mkstate "$S" x build draft none none none none "n"
PL="$(cd "$(fixture_tmpdir)" && pwd -P)/plugin"
mkplugin "$PL" 0.2.0
mkdir -p "$S/.rx/scripts"

printf '0.1.0\n' > "$S/.rx/scripts/.rx-version"
run_script "$PL/scripts/rx-status.sh" "$S"
WARN="warning: .rx/scripts is v0.1.0, plugin is v0.2.0; run /rx:init --refresh-scripts"
assert_eq "0" "$RC" "stale: rc 0"
case "$OUT" in
  *"
$WARN") ;;
  *) assert_eq "ends with warning" "$OUT" "stale: mismatch prints exact warning last" ;;
esac
assert_eq "1" "$(printf '%s\n' "$OUT" | grep -c '^warning:')" "stale: exactly one warning"

printf '0.2.0\n' > "$S/.rx/scripts/.rx-version"
run_script "$PL/scripts/rx-status.sh" "$S"
case "$OUT" in *warning*) assert_eq "no warning" "$OUT" "stale: match is silent" ;; esac

printf '  0.2.0 \r\n' > "$S/.rx/scripts/.rx-version"
run_script "$PL/scripts/rx-status.sh" "$S"
case "$OUT" in *warning*) assert_eq "no warning" "$OUT" "stale: whitespace/CRLF trimmed" ;; esac

printf '0.1.0' > "$S/.rx/scripts/.rx-version"
run_script "$PL/scripts/rx-status.sh" "$S" --all
assert_contains "$OUT" "$WARN" "stale: warning without final newline in .rx-version, with --all"

rm -f "$S/.rx/scripts/.rx-version"
run_script "$PL/scripts/rx-status.sh" "$S"
case "$OUT" in *warning*) assert_eq "no warning" "$OUT" "stale: missing .rx-version is silent" ;; esac

# run from the .rx/scripts copy: no ../.claude-plugin/plugin.json -> silent
printf '0.1.0\n' > "$S/.rx/scripts/.rx-version"
cp "$PL/scripts/rx-lib.sh" "$PL/scripts/rx-status.sh" "$S/.rx/scripts/"
run_script "$S/.rx/scripts/rx-status.sh" "$S"
assert_contains "$OUT" "feature: x" "copy run works"
case "$OUT" in *warning*) assert_eq "no warning" "$OUT" "stale: silent from the .rx/scripts copy" ;; esac

# stale check also runs for "no active feature"
printf '0.1.0\n' > "$S/.rx/scripts/.rx-version"
git -C "$S" checkout -q main
run_script "$PL/scripts/rx-status.sh" "$S"
assert_eq "no active feature
$WARN" "$OUT" "stale: warning after 'no active feature'"
assert_eq "0" "$RC" "stale: no active feature rc 0"

# but not after the invalid-state exit
git -C "$S" checkout -q -b feature/broken
run_script "$PL/scripts/rx-status.sh" "$S"
assert_eq "state.md invalid: not found" "$OUT" "stale: not printed after invalid state"
assert_eq "1" "$RC" "stale: invalid state rc 1"

# no-op without config, even when stale
rm -f "$S/.rx/config.yml"
run_script "$PL/scripts/rx-status.sh" "$S" --all
assert_eq "" "$OUT$ERR" "no config: stale check silent too"
assert_eq "0" "$RC" "no config: rc 0"

[ "$RX_FAILS" -eq 0 ] && echo "test_status: ok"
exit 0
