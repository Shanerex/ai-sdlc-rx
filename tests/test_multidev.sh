#!/usr/bin/env bash
# Multi-developer merge-safety: parallel feature branches that follow the rules merge with no conflicts
# and pass `rx-check.sh shared`; a branch that touches a shared file fails it, and a control pair that
# both edit one shared file really does conflict (so the clean merge above is not vacuous).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"
APPROVED="approved:rex:2026-10-16"

# new_repo: main with rx installed (scripts copied from a plugin copy that is then removed), committed.
new_repo() {
  local d plugin
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  plugin="$d/plugin"
  mkdir -p "$plugin"
  cp -R "$ROOT/scripts" "$ROOT/skills" "$ROOT/.claude-plugin" "$plugin/"
  fixture_repo "$d/r"
  fixture_config "$d/r"
  printf '# project\n' > "$d/r/CLAUDE.md"
  mkdir -p "$d/r/docs/knowledge/decisions" "$d/r/docs/knowledge/learnings" "$d/r/src"
  printf '# arch\n' > "$d/r/docs/knowledge/architecture.md"
  printf 'tags: [base]\nDecision: start.\n' > "$d/r/docs/knowledge/decisions/2026-10-01-start.md"
  printf 'class Base {}\n' > "$d/r/src/Base.java"
  (cd "$d/r" && "$plugin/scripts/rx-init-files.sh" >/dev/null 2>&1) || _rx_fail "setup: init failed"
  git -C "$d/r" add -A >/dev/null 2>&1
  git -C "$d/r" commit -q -m "rx setup" 2>/dev/null || _rx_fail "setup commit failed"
  rm -rf "$plugin"
  printf '%s\n' "$d/r"
}

# add_feature <repo> <id> <class>: branch from main with its spec, code, one decision and one learning; committed.
add_feature() {
  local r="$1" id="$2" cls="$3"
  git -C "$r" checkout -q -b "feature/$id" main || return 1
  mkdir -p "$r/specs/$id"
  sed -e "s/^feature: .*/feature: $id/" -e "s/^phase: .*/phase: build/" \
      -e "s/^g2: .*/g2: $APPROVED/" "$TPL_STATE" > "$r/specs/$id/state.md"
  mkdir -p "$r/docs/knowledge/decisions" "$r/docs/knowledge/learnings"
  printf 'class %s {}\n' "$cls" > "$r/src/$cls.java"
  printf 'tags: [%s]\nDecision: %s uses its own class.\nWhy: isolation.\n' "$id" "$id" > "$r/docs/knowledge/decisions/2026-10-16-$id.md"
  printf 'tags: [%s]\nLearning: %s needed no shared file.\n' "$id" "$id" > "$r/docs/knowledge/learnings/2026-10-16-$id.md"
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" commit -q -m "feat: $id" 2>"$r/../commit-$id.err" || { _rx_fail "commit on feature/$id refused: $(cat "$r/../commit-$id.err")"; return 1; }
}

# ---------- two compliant branches ----------
R="$(new_repo)"
add_feature "$R" 2026-10-16-alpha Alpha
add_feature "$R" 2026-10-16-beta Beta
for b in alpha beta; do
  git -C "$R" checkout -q "feature/2026-10-16-$b"
  out="$(cd "$R" && .rx/scripts/rx-check.sh shared 2>&1)"; rc=$?
  assert_eq "0" "$rc" "shared passes on feature $b ($out)"
done
git -C "$R" checkout -q main
git -C "$R" merge -q --no-ff -m "merge alpha" feature/2026-10-16-alpha >/dev/null 2>&1
assert_eq "0" "$?" "merge alpha"
git -C "$R" merge -q --no-ff -m "merge beta" feature/2026-10-16-beta >/dev/null 2>&1
assert_eq "0" "$?" "merge beta: no conflicts with alpha"
assert_eq "" "$(git -C "$R" status --porcelain)" "main is clean after both merges"
assert_eq "3" "$(ls "$R/docs/knowledge/decisions" | wc -l | tr -d ' ')" "decisions: base + one per feature"
assert_eq "2" "$(ls "$R/docs/knowledge/learnings" | wc -l | tr -d ' ')" "learnings: one per feature"
assert_exit 0 test -f "$R/src/Alpha.java"
assert_exit 0 test -f "$R/src/Beta.java"

# ---------- a branch that edits shared files fails shared ----------
shared_fails() { # <name> <file> <append-text>
  git -C "$R" checkout -q -b "feature/2026-10-17-$1" main
  mkdir -p "$R/specs/2026-10-17-$1"
  sed -e "s/^feature: .*/feature: 2026-10-17-$1/" -e "s/^g2: .*/g2: $APPROVED/" "$TPL_STATE" > "$R/specs/2026-10-17-$1/state.md"
  printf '%s\n' "$3" >> "$R/$2"
  out="$(cd "$R" && .rx/scripts/rx-check.sh shared 2>&1)"; rc=$?
  assert_eq "1" "$rc" "shared fails when a branch edits $2"
  assert_contains "$out" "$2" "shared names $2"
  git -C "$R" checkout -q -f main; git -C "$R" clean -qfd -e .rx/local
}
shared_fails claude CLAUDE.md "# changed by a feature"
shared_fails arch docs/knowledge/architecture.md "- new layer"
shared_fails oldentry docs/knowledge/decisions/2026-10-01-start.md "Decision: rewritten."

# ---------- control: two branches editing the same shared file DO conflict ----------
R="$(new_repo)"
for b in one two; do
  git -C "$R" checkout -q -b "feature/2026-10-16-$b" main
  printf -- '- entry from %s\n' "$b" >> "$R/CLAUDE.md"
  git -C "$R" add -A >/dev/null 2>&1
  # the pre-commit gate would refuse this on a feature branch; --no-verify stands in for a developer who skips it
  git -C "$R" commit -q --no-verify -m "edit CLAUDE.md on $b" >/dev/null 2>&1 || _rx_fail "control: setup commit on $b failed"
done
git -C "$R" checkout -q main
git -C "$R" merge -q --no-ff -m "merge one" feature/2026-10-16-one >/dev/null 2>&1
assert_eq "0" "$?" "control: first merge is clean"
git -C "$R" merge -q --no-ff -m "merge two" feature/2026-10-16-two >/dev/null 2>&1
assert_eq "1" "$?" "control: both branches editing CLAUDE.md conflict on merge"
git -C "$R" merge --abort >/dev/null 2>&1

echo "test_multidev: ok"
