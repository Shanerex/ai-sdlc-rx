#!/usr/bin/env bash
# rx-precommit.sh: what the git pre-commit wrapper runs (installed in .rx/scripts by /rx:init, so it
# works with no plugin present). Exit 0 lets the commit through, anything else stops it.
#   - base_branch (or rx not set up): nothing to check. Shared files change there through reviewed
#     merges; direct commits are branch protection's job.
#   - a feature (branch matching branch_pattern, or .rx/local/active): rx-guard.sh --staged
#     (plan-first), rx-check.sh shared (merge-safety) and rx-gate-tests.sh (red tests block the
#     build phase). `specs` is not run here: it is per feature dir, and drafts are allowed to be
#     incomplete until /rx:next closes the feature with rx-check.sh done.
#   - detached HEAD (rebase) with no active feature: allowed.
#   - any other branch: refused, because rx-check.sh shared cannot tell what it may change. A human
#     landing a shared-file change (CLAUDE.md, architecture.md, .rx/) sets RX_SHARED_OK=1 for that
#     commit. This is a speed bump, not a lock: `git commit --no-verify` skips it, so CI must run
#     the base branch's copy of rx-check.sh and CODEOWNERS must cover the shared files.
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-precommit: rx-lib.sh not found\n' >&2
  exit 1
fi
rx_noop_unless_enabled
cd "$(rx_root)" || exit 1

cur="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || cur=""
[ "$cur" != "$(rx_cfg base_branch main)" ] || exit 0

if ID="$(rx_feature_id)"; then
  "$SCRIPT_DIR/rx-guard.sh" --staged </dev/null || exit 1
  "$SCRIPT_DIR/rx-check.sh" shared "$ID" || exit 1
  "$SCRIPT_DIR/rx-gate-tests.sh" </dev/null || exit 1
  exit 0
fi

[ -n "$cur" ] || exit 0
if [ "${RX_SHARED_OK-}" = 1 ]; then
  printf 'rx-precommit: RX_SHARED_OK=1, skipping merge-safety on %s\n' "$cur" >&2
  exit 0
fi
printf 'rx-precommit: branch %s is not a feature branch (branch_pattern %s), so shared files cannot be checked. Work on a feature branch (/rx:feature), or set RX_SHARED_OK=1 for a human-only change to CLAUDE.md, architecture.md or .rx/.\n' \
  "$cur" "$(rx_cfg branch_pattern)" >&2
exit 1
