#!/usr/bin/env bash
# rx_glob_match: source_globs matcher shared by the guard and the test gate.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"
. "$ROOT/scripts/rx-lib.sh"

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
echo "test_glob: ok"
