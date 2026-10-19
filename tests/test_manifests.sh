#!/usr/bin/env bash
# Plugin manifests: .claude-plugin/plugin.json and .claude-plugin/marketplace.json.
# Needs jq only (no claude CLI, no network).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"

PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"

assert_exit 0 jq -e . "$PLUGIN"
assert_exit 0 jq -e . "$MARKET"

assert_eq "rx" "$(jq -r '.name' "$PLUGIN" 2>/dev/null)" "plugin name is rx"

version="$(jq -r '.version' "$PLUGIN" 2>/dev/null)"
assert_exit 0 bash -c 'printf "%s" "$1" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$"' _ "$version"

assert_eq "rx" "$(jq -r '[.plugins[]? | select(.name == "rx")] | .[0].name' "$MARKET" 2>/dev/null)" "marketplace lists plugin rx"
assert_eq "./" "$(jq -r '[.plugins[]? | select(.name == "rx")] | .[0].source' "$MARKET" 2>/dev/null)" "rx source is repo root"

echo "test_manifests: ok"
