#!/usr/bin/env bash
# rx_glob_match: source_globs matcher shared by the guard and the test gate.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"
. "$ROOT/scripts/rx-lib.sh"

NL=$'\n'
D="$(cd "$(fixture_tmpdir)" && pwd -P)"
fixture_repo "$D/r"
cd "$D/r" || exit 1

# glob_case <globs> <path> <yes|no>
glob_case() {
  fixture_config "$D/r" "source_globs=$1"
  local rc=0
  rx_glob_match "$2" || rc=$?
  if [ "$3" = yes ]; then
    assert_eq "0" "$rc" "globs '$1' should match '$2'"
  else
    assert_eq "1" "$rc" "globs '$1' should not match '$2'"
  fi
}

glob_case 'src/**' src/a.java yes
glob_case 'src/**' src/a/b/c.java yes
glob_case 'src/**' srcx/a.java no
glob_case 'src/**' src no
glob_case 'src/**' README.md no
glob_case 'src/**' 'src/my file.js' yes
glob_case '**/*.ts' a.ts yes
glob_case '**/*.ts' x/y/a.ts yes
glob_case '**/*.ts' a.tsx no
glob_case '*.java' A.java yes
glob_case '*.java' src/A.java no
glob_case 'a?c' abc yes
glob_case 'a?c' a/c no
glob_case 'a.b' axb no
glob_case 'a.b' a.b yes
glob_case 'src/a+b(1)[x].c' 'src/a+b(1)[x].c' yes
glob_case 'src/**, lib/*.sh' lib/x.sh yes
glob_case 'src/**,lib/*.sh' lib/sub/x.sh no
glob_case './src/**' src/a.java yes
glob_case 'src/**' ./src/a.java yes
glob_case '' src/a.java no
glob_case 'nothing/**' src/a.java no
# missing key
rm "$D/r/.rx/config.yml"
rc=0
rx_glob_match src/a.java || rc=$?
assert_eq "1" "$rc" "no config: nothing matches"
# rx_glob_filter <key>...: NUL-separated paths on stdin, matching existing regular files out, one per line
fixture_config "$D/r" "source_globs=src/**" "test_globs=tests/*.sh, docs/a b.md"
mkdir -p "$D/r/src/deep" "$D/r/tests" "$D/r/docs"
: > "$D/r/src/A.java"; : > "$D/r/src/deep/B.java"; : > "$D/r/tests/t.sh"; : > "$D/r/tests/sub.txt"; : > "$D/r/docs/a b.md"; : > "$D/r/README.md"
got="$(printf 'src/A.java\0src/deep/B.java\0src/gone.java\0tests/t.sh\0tests/sub.txt\0docs/a b.md\0README.md\0src/deep\0' | rx_glob_filter source_globs test_globs)"
assert_eq "src/A.java${NL}src/deep/B.java${NL}tests/t.sh${NL}docs/a b.md" "$got" "rx_glob_filter: matches either key, drops missing files and directories, keeps order"
got="$(printf 'src/A.java\0' | rx_glob_filter test_globs)"
assert_eq "" "$got" "rx_glob_filter: only the named keys count"
got="$(printf 'src/A.java\0' | rx_glob_filter nokey)"
assert_eq "" "$got" "rx_glob_filter: unset key matches nothing"
echo "test_glob: ok"
