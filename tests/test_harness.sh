#!/usr/bin/env bash
# Self-test for the test harness: assertions, fixtures, and tests/run.sh itself.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

# --- assertions pass on good input
assert_eq "a" "a" "assert_eq equal"
assert_exit 0 true
assert_exit 3 bash -c 'exit 3'
assert_contains "hello world" "lo wo"

# --- assertions can FAIL (each runs in a subshell and must exit non-zero)
rc=0; ( assert_eq "a" "b" "expected failure" ) >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "assert_eq mismatch exits 1"
rc=0; ( assert_exit 0 false ) >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "assert_exit wrong code exits 1"
rc=0; ( assert_contains "abc" "zzz" ) >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "assert_contains missing needle exits 1"

# --- fixture_repo: git repo on main with one commit, independent of global git config
d="$(fixture_tmpdir)"
HOME=/nonexistent GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 fixture_repo "$d/r"
assert_eq "main" "$(git -C "$d/r" symbolic-ref --short HEAD)" "fixture_repo branch is main"
assert_eq "1" "$(git -C "$d/r" rev-list --count HEAD)" "fixture_repo has one commit"
assert_eq "clean" "$([ -z "$(git -C "$d/r" status --porcelain)" ] && echo clean || echo dirty)" "fixture_repo is clean"
assert_contains "$(git -C "$d/r" config --local user.email)" "@" "fixture_repo sets local identity"

# --- fixture_config: defaults
fixture_config "$d/c"
cfg="$d/c/.rx/config.yml"
assert_exit 0 test -f "$cfg"
expected='test_cmd: true
source_globs: src/**
branch_pattern: feature/{id}
base_branch: main
enforce_plan_first: true
feature_id: date-slug
version_bump: release
version_file: pom.xml
security_review: verify'
assert_eq "$expected" "$(cat "$cfg")" "fixture_config defaults"

# --- fixture_config: overrides (default keys replaced in place, unknown keys appended)
fixture_config "$d/o" test_cmd="make test" base_branch=develop extra_key=1
assert_contains "$(cat "$d/o/.rx/config.yml")" "test_cmd: make test"
assert_contains "$(cat "$d/o/.rx/config.yml")" "base_branch: develop"
assert_contains "$(cat "$d/o/.rx/config.yml")" "extra_key: 1"
assert_eq "1" "$(grep -c '^test_cmd:' "$d/o/.rx/config.yml")" "override does not duplicate key"

# --- fixtures ignore the developer's global git config
t="$(mktemp -d)"
printf '[user]\n\tname = Global Person\n' > "$t/.gitconfig"
cat > "$t/probe.sh" <<PROBE
. "$HERE/lib/fixture.sh"
git config --get user.name
PROBE
assert_eq "" "$(HOME="$t" XDG_CONFIG_HOME="$t" bash "$t/probe.sh")" "fixture.sh isolates global git config"
rm -rf "$t"

# --- fixture_tmpdir cleanup on exit
t="$(mktemp -d)"
cat > "$t/probe.sh" <<PROBE
. "$HERE/lib/fixture.sh"
fixture_tmpdir > "$t/path.txt"
PROBE
bash "$t/probe.sh"
assert_exit 1 test -d "$(cat "$t/path.txt")"
rm -rf "$t"

# --- run.sh: passing dir -> 0, failing file -> non-zero, FAIL reported
t="$(fixture_tmpdir)"
mkdir -p "$t/ok" "$t/bad"
printf '#!/usr/bin/env bash\nexit 0\n' > "$t/ok/test_a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$t/bad/test_a.sh"
printf '#!/usr/bin/env bash\n. "%s/lib/assert.sh"\nassert_eq 1 2 "boom"\n' "$HERE" > "$t/bad/test_b.sh"
out="$(bash "$HERE/run.sh" "$t/ok" 2>&1)"; rc=$?
assert_eq "0" "$rc" "run.sh passes when all pass"
assert_contains "$out" "PASS test_a.sh"
out="$(bash "$HERE/run.sh" "$t/bad" 2>&1)"; rc=$?
assert_eq "1" "$rc" "run.sh exits 1 when a file fails"
assert_contains "$out" "FAIL test_b.sh"
assert_contains "$out" "PASS test_a.sh"
assert_contains "$out" "1 failed"

# --- run.sh: no test files found is an error, not a green run
mkdir -p "$t/empty" "$t/other"
printf 'x\n' > "$t/other/notatest.sh"
for e in "$t/empty" "$t/other" "$t/missing"; do
  ef="$t/err.txt"
  out="$(bash "$HERE/run.sh" "$e" 2>"$ef")"; rc=$?
  assert_eq "1" "$rc" "run.sh exits 1 when it finds no test files ($(basename "$e"))"
  assert_contains "$(cat "$ef")" "no test files" "run.sh says so on stderr ($(basename "$e"))"
  assert_eq "" "$out" "run.sh prints no PASS/summary when it finds none ($(basename "$e"))"
done

# --- a swallowed assertion failure still fails the file (EXIT trap)
printf '. "%s/lib/assert.sh"\nassert_eq 1 2 swallowed || true\nexit 0\n' "$HERE" > "$t/swallow.sh"
rc=0; bash "$t/swallow.sh" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "ignored assertion failure still exits non-zero"

echo "test_harness: ok"
