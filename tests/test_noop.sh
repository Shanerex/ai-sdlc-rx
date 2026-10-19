#!/usr/bin/env bash
# Every shipped script exits 0 silently when .rx/config.yml is absent (an unconfigured repo must never be
# blocked or nagged). rx-lib.sh is sourced, not run, and rx-init-files.sh is what creates the config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

D="$(cd "$(fixture_tmpdir)" && pwd -P)"
fixture_repo "$D/r"
count=0
for s in "$ROOT"/scripts/*.sh; do
  name="$(basename "$s")"
  case "$name" in rx-lib.sh|rx-init-files.sh) continue ;; esac
  count=$((count + 1))
  for args in "" "specs" "shared" "done" "--staged" "--all"; do
    out="$(cd "$D/r" && "$s" $args </dev/null 2>&1)"; rc=$?
    # an unknown subcommand may be a usage error, but only if the script got past the no-op check, which it must not
    assert_eq "0" "$rc" "$name $args: rc 0 without config"
    assert_eq "" "$out" "$name $args: silent without config"
  done
done
[ "$count" -ge 6 ] || _rx_fail "expected at least 6 runnable scripts, found $count"
echo "test_noop: ok"
