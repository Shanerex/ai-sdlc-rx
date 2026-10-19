#!/usr/bin/env bash
# README.md lint: size cap and the topics a first-time reader needs, plus agreement with the code
# (every config key the scripts read is documented, every command and script it names exists).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

R="$ROOT/README.md"
[ -f "$R" ] || { _rx_fail "README.md missing"; echo "test_readme: ok"; exit; }
n="$(wc -l < "$R" | tr -d ' ')"
[ "$n" -le 150 ] || _rx_fail "README.md has $n lines (cap 150)"

for needle in '/rx:init' '/rx:feature' '/rx:next' '/rx:status' '--quick' '--refresh-scripts' 'claude --plugin-dir' \
              'G1' 'G2' 'G3' 'RX_SHARED_OK' 'CODEOWNERS' '--no-verify' 'Codex' 'jq' '.rx/config.yml' \
              'merge-safety' 'agents/' 'skills/' 'hooks/hooks.json' 'tests/run.sh' 'test_timeout' 'test_globs'; do
  grep -qF -- "$needle" "$R" || _rx_fail "README.md: must mention $needle"
done

# every config key a script reads appears in the README
keys="$(grep -ho 'rx_\(cfg\|require_cfg\) [a-z_]*' "$ROOT"/scripts/*.sh | awk '{print $2}' | grep -v '^k$' | sort -u)"
for k in $keys; do
  grep -q "\`$k\`" "$R" || _rx_fail "README.md: config key $k is read by a script but not documented"
done

# every /rx:<name> the README names is a real command file
for c in $(grep -o '/rx:[a-z]*' "$R" | sort -u | sed 's#/rx:##'); do
  [ -f "$ROOT/commands/$c.md" ] || _rx_fail "README.md names /rx:$c but commands/$c.md does not exist"
done
echo "test_readme: ok"
