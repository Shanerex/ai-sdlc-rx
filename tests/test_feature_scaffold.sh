#!/usr/bin/env bash
# scripts/rx-new-feature.sh: deterministic scaffold behind /rx:feature.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

NEW="$ROOT/scripts/rx-new-feature.sh"
NL=$'\n'
LIB="$ROOT/scripts/rx-lib.sh"

# run_new <dir> [args...]: sets OUT, ERR, RC. RX_DATE pins the date.
run_new() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && RX_DATE=2026-10-16 "${SCRIPT:-$NEW}" "$@" 2>"$ef")"
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
branch_of() { git -C "$1" symbolic-ref --short HEAD; }
valid() { ( cd "$1" && . "$LIB" && rx_state_valid "$2" ); }

# ---------- full lane ----------
R="$(new_repo)"
run_new "$R" "Add health endpoint!"
assert_eq "0" "$RC" "scaffold: rc 0"; assert_eq "" "$ERR" "scaffold: stderr empty"
assert_eq "id: 2026-10-16-add-health-endpoint${NL}branch: feature/2026-10-16-add-health-endpoint${NL}lane: full" "$OUT" "scaffold: report"
ID=2026-10-16-add-health-endpoint
assert_eq "feature/$ID" "$(branch_of "$R")" "scaffold: on the new branch"
S="$R/specs/$ID/state.md"
[ -f "$S" ] || _rx_fail "scaffold: state.md missing"
assert_exit 0 valid "$R" "$ID"
assert_eq "intake" "$(sed -n 's/^phase: //p' "$S")" "scaffold: phase intake"
assert_eq "draft" "$(sed -n 's/^status: //p' "$S")" "scaffold: status draft"
assert_eq "$ID" "$(sed -n 's/^feature: //p' "$S")" "scaffold: feature key"
for g in g1 g2 g3 bump; do assert_eq "none" "$(sed -n "s/^$g: //p" "$S")" "scaffold: $g none"; done
grep -Eq '<feature-id>|<one-line next action>|<YYYY-MM-DD> intake' "$S" && _rx_fail "scaffold: placeholder left in state.md"
assert_contains "$(cat "$S")" "2026-10-16 intake: feature created" "scaffold: log line dated"
[ -n "$(sed -n 's/^next: //p' "$S")" ] || _rx_fail "scaffold: next set"
[ -e "$R/specs/$ID/quick.md" ] && _rx_fail "scaffold: full lane has no quick.md"
assert_eq "1" "$(ls "$R/specs/$ID" | wc -l | tr -d ' ')" "scaffold: only state.md"
assert_eq "" "$(git -C "$R" log --oneline main..HEAD)" "scaffold: nothing committed"
assert_contains "$(git -C "$R" status --short)" "specs/" "scaffold: new files left uncommitted"

# collision: same id again, nothing changes
before="$(cat "$S")"
git -C "$R" checkout -q main
run_new "$R" "Add health endpoint"
assert_eq "1" "$RC" "collision: rc 1"; assert_contains "$ERR" "already exists" "collision: message"
assert_eq "$before" "$(cat "$S")" "collision: state.md untouched"
assert_eq "main" "$(branch_of "$R")" "collision: stayed on main"
# directory without branch, and branch without directory
rm -rf "$R/specs/$ID"; git -C "$R" branch -q "feature/$ID" 2>/dev/null || true
run_new "$R" "Add health endpoint"
assert_eq "1" "$RC" "branch exists: rc 1"; assert_contains "$ERR" "already exists" "branch exists: message"
[ -e "$R/specs/$ID" ] && _rx_fail "branch exists: no spec dir created"
# spec dir without a branch
git -C "$R" branch -q -D "feature/$ID"; mkdir -p "$R/specs/$ID"; echo keep > "$R/specs/$ID/mine.md"
run_new "$R" "Add health endpoint"
assert_eq "1" "$RC" "spec dir exists: rc 1"; assert_contains "$ERR" "already exists" "spec dir exists: message"
assert_eq "keep" "$(cat "$R/specs/$ID/mine.md")" "spec dir exists: contents untouched"
git -C "$R" rev-parse --verify -q "refs/heads/feature/$ID" >/dev/null && _rx_fail "spec dir exists: no branch created"

# ---------- ticket ids and slugs ----------
R="$(new_repo)"
run_new "$R" PROJ-123
assert_eq "id: PROJ-123${NL}branch: feature/PROJ-123${NL}lane: full" "$OUT" "ticket key kept as is"
R="$(new_repo)"
run_new "$R" proj-123
assert_contains "$OUT" "id: 2026-10-16-proj-123" "lowercase key is a name, not a ticket"
R="$(new_repo)"
run_new "$R" "  Fix: the   Café (v2)  "
assert_contains "$OUT" "id: 2026-10-16-fix-the-caf-v2" "slug: lowercase, collapsed, ascii only"
R="$(new_repo)"
run_new "$R" "$(printf 'word-%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
id="$(printf '%s\n' "$OUT" | sed -n 's/^id: 2026-10-16-//p')"
[ "${#id}" -le 40 ] || _rx_fail "slug capped at 40 chars, got ${#id}"
case "$id" in *-) _rx_fail "slug must not end with '-'" ;; esac
R="$(new_repo)"
run_new "$R" '!!! ???'
assert_eq "2" "$RC" "empty slug: rc 2"; assert_contains "$ERR" "name" "empty slug: message"
[ -d "$R/specs" ] && _rx_fail "empty slug: nothing created"
run_new "$R"
assert_eq "2" "$RC" "no argument: rc 2"; assert_contains "$ERR" "usage" "no argument: usage"
run_new "$R" --bogus x
assert_eq "2" "$RC" "unknown option: rc 2"

# ---------- branch handling ----------
R="$(new_repo)"; git -C "$R" checkout -q -b other; printf 'x\n' > "$R/other.txt"; git -C "$R" add -A; git -C "$R" commit -q -m other
run_new "$R" "from base"
assert_eq "0" "$RC" "from another branch: rc 0"
assert_eq "" "$(git -C "$R" rev-list main..HEAD)" "new branch starts at base_branch, not the current branch"
[ -e "$R/other.txt" ] && _rx_fail "other branch's files must not leak in"
R="$(new_repo)"; fixture_config "$R" "branch_pattern=ft/{id}"
run_new "$R" PROJ-9
assert_eq "ft/PROJ-9" "$(branch_of "$R")" "custom branch_pattern"
R="$(new_repo)"; fixture_config "$R" "base_branch=nosuch"
run_new "$R" thing
assert_eq "2" "$RC" "missing base branch: rc 2"; assert_contains "$ERR" "nosuch" "missing base branch: named"
[ -d "$R/specs" ] && _rx_fail "missing base branch: nothing created"
D="$(cd "$(fixture_tmpdir)" && pwd -P)"; mkdir -p "$D/n"; fixture_config "$D/n"
run_new "$D/n" thing
assert_eq "2" "$RC" "not a git repo: rc 2"; assert_contains "$ERR" "git" "not a git repo: message"

# ---------- quick lane ----------
R="$(new_repo)"
run_new "$R" --quick "Rename button"
assert_eq "0" "$RC" "quick: rc 0"
ID=2026-10-16-rename-button
assert_eq "id: $ID${NL}branch: feature/$ID${NL}lane: quick" "$OUT" "quick: report"
assert_exit 0 valid "$R" "$ID"
Q="$R/specs/$ID/quick.md"
assert_contains "$(cat "$Q")" "# Quick: $ID" "quick.md: feature id filled"
assert_eq "draft" "$(sed -n 's/^status: //p' "$Q")" "quick.md: status draft"
assert_eq "2" "$(ls "$R/specs/$ID" | wc -l | tr -d ' ')" "quick: state.md + quick.md only"
run_new "$R" "Rename button" --quick
assert_eq "1" "$RC" "quick: collision refused (option after the name too)"

# ---------- no-op, subdirectory, installed copy ----------
R="$(new_repo)"; rm "$R/.rx/config.yml"
run_new "$R" thing
assert_eq "0" "$RC" "no config: rc 0"; assert_eq "" "$OUT$ERR" "no config: silent"; [ -d "$R/specs" ] && _rx_fail "no config: nothing created"
R="$(new_repo)"; mkdir "$R/sub"
run_new "$R/sub" thing
assert_eq "0" "$RC" "subdirectory: rc 0"; [ -f "$R/specs/2026-10-16-thing/state.md" ] || _rx_fail "subdirectory: specs created at the repo root"
# the copy that /rx:init installs: scripts + templates side by side, no plugin around
R="$(new_repo)"; mkdir -p "$R/.rx/scripts"; cp "$ROOT"/scripts/*.sh "$R/.rx/scripts/"; cp -R "$ROOT/skills/rx-spec/templates" "$R/.rx/scripts/templates"
SCRIPT="$R/.rx/scripts/rx-new-feature.sh" run_new "$R" thing
assert_eq "0" "$RC" "installed copy: rc 0"; assert_exit 0 valid "$R" 2026-10-16-thing
echo "test_feature_scaffold: ok"
