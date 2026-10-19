#!/usr/bin/env bash
# Fixture helpers (bash 3.2 / BSD userland compatible).
# Requires assert.sh (sourced here if not already loaded).

if ! type rx_add_exit_hook >/dev/null 2>&1; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assert.sh"
fi

# Fixtures must not depend on the developer's global or system git config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# One temp root per test process; removed on exit. Created at source time so
# fixture_tmpdir stays usable inside $(...) subshells.
RX_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rx-fixture.XXXXXX")"
_rx_fixture_cleanup() {
  [ -n "${RX_TMP_ROOT:-}" ] && [ -d "$RX_TMP_ROOT" ] && rm -rf "$RX_TMP_ROOT"
  return 0
}
rx_add_exit_hook _rx_fixture_cleanup

# fixture_tmpdir: print a fresh empty directory under the per-process root.
fixture_tmpdir() {
  mktemp -d "$RX_TMP_ROOT/d.XXXXXX"
}

# fixture_repo <dir>: git repo on branch main with one commit. Sets a local
# identity so it works with no global git config.
fixture_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.name "RX Fixture"
  git -C "$dir" config user.email "fixture@rx.invalid"
  git -C "$dir" config commit.gpgsign false
  printf '# fixture\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "initial commit"
}

# fixture_config <dir> [key=value...]: write <dir>/.rx/config.yml (flat
# `key: value` lines). Defaults below; key=value args override, and keys that
# are not defaults are appended.
fixture_config() {
  local dir="$1" pair key val def dkey line found out=""
  shift
  local defaults=(
    "test_cmd=true"
    "source_globs=src/**"
    "branch_pattern=feature/{id}"
    "base_branch=main"
    "enforce_plan_first=true"
    "feature_id=date-slug"
    "version_bump=release"
    "version_file=pom.xml"
    "security_review=verify"
  )
  for def in "${defaults[@]}"; do
    dkey="${def%%=*}"
    val="${def#*=}"
    for pair in "$@"; do
      if [ "${pair%%=*}" = "$dkey" ]; then
        val="${pair#*=}"
      fi
    done
    out="${out}${dkey}: ${val}"$'\n'
  done
  for pair in "$@"; do
    key="${pair%%=*}"
    found=0
    for def in "${defaults[@]}"; do
      [ "${def%%=*}" = "$key" ] && found=1
    done
    if [ "$found" -eq 0 ]; then
      out="${out}${key}: ${pair#*=}"$'\n'
    fi
  done
  mkdir -p "$dir/.rx"
  printf '%s' "$out" > "$dir/.rx/config.yml"
}
