#!/usr/bin/env bash
# rx-new-feature.sh [--quick] <name-or-ticket>: deterministic scaffold behind /rx:feature.
#   - id: a ticket key (UPPERCASE-123) is used as is; any other name becomes
#     <date>-<slug> (slug: lowercase ascii, words joined by `-`, at most 40 chars)
#   - refuses (exit 1) when specs/<id>/ or the branch already exists
#   - creates the branch from branch_pattern, started at base_branch (never at the current
#     branch), then specs/<id>/state.md (phase intake) and, with --quick, quick.md.
#     Nothing is committed.
#   - prints three lines: `id: <id>`, `branch: <branch>`, `lane: full|quick`
# Exit codes: 0 ok, 1 id/branch already exists, 2 usage or environment error.
# RX_DATE=YYYY-MM-DD pins the date (tests). Targets macOS bash 3.2 + BSD userland.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-new-feature: rx-lib.sh not found\n' >&2
  exit 2
fi
rx_noop_unless_enabled
rx_locale_c

_nf_die() {
  printf 'rx-new-feature: %s\n' "$*" >&2
  exit 2
}
QUICK=0
NAME=""
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    -*) printf 'usage: rx-new-feature.sh [--quick] <name-or-ticket>\n' >&2; exit 2 ;;
    *) NAME="${NAME:+$NAME }$arg" ;;
  esac
done
NAME="$(_rx_trim "$NAME")"
if [ -z "$NAME" ]; then
  printf 'usage: rx-new-feature.sh [--quick] <name-or-ticket>\n' >&2
  exit 2
fi

TPL=""
for d in "$SCRIPT_DIR/templates" "$SCRIPT_DIR/../skills/rx-spec/templates"; do
  if [ -f "$d/state.md" ] && [ -f "$d/quick.md" ]; then TPL="$d"; break; fi
done
[ -n "$TPL" ] || _nf_die "templates not found next to $SCRIPT_DIR"

DATE="${RX_DATE:-$(date +%F)}"
if printf '%s' "$NAME" | grep -Eq '^[A-Z][A-Z0-9]*-[0-9]+$'; then
  ID="$NAME"
else
  SLUG="$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | tr -s '-' | sed -e 's/^-//' -e 's/-$//' | cut -c1-40 | sed 's/-$//')"
  [ -n "$SLUG" ] || _nf_die "name '$NAME' has no letters or digits to build an id from"
  ID="$DATE-$SLUG"
fi
rx_valid_id "$ID" || _nf_die "cannot build a valid feature id from '$NAME'"

ROOT="$(rx_root)"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || _nf_die "a git repository is required"
BRANCH="$(rx_id_branch "$ID")" || _nf_die "branch_pattern in .rx/config.yml must contain exactly one {id}"
BASE="$(rx_cfg base_branch main)"
git -C "$ROOT" rev-parse --verify -q "refs/heads/$BASE" >/dev/null || _nf_die "base branch '$BASE' not found"

if [ -e "$ROOT/specs/$ID" ]; then
  printf 'rx-new-feature: specs/%s already exists\n' "$ID" >&2
  exit 1
fi
if git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
  printf 'rx-new-feature: branch %s already exists\n' "$BRANCH" >&2
  exit 1
fi

git -C "$ROOT" checkout -q -b "$BRANCH" "$BASE" || _nf_die "could not create branch $BRANCH"
mkdir -p "$ROOT/specs/$ID" || _nf_die "could not create specs/$ID"
sed -e "s|<feature-id>|$ID|g" \
    -e "s|<one-line next action>|answer the intake: why / who / done-when|" \
    -e "s|<YYYY-MM-DD>|$DATE|g" "$TPL/state.md" > "$ROOT/specs/$ID/state.md"
LANE=full
if [ "$QUICK" -eq 1 ]; then
  LANE=quick
  sed -e "s|<feature-id>|$ID|g" "$TPL/quick.md" > "$ROOT/specs/$ID/quick.md"
fi
printf 'id: %s\nbranch: %s\nlane: %s\n' "$ID" "$BRANCH" "$LANE"
