#!/usr/bin/env bash
# The installed git pre-commit gate (hook wrapper from rx-init-files.sh + scripts/rx-precommit.sh):
# plan-first, merge-safety, the test gate, and the base-branch checks on the gate inputs. Every case
# is a real `git commit` in a fixture repo whose rx files came from rx-init-files.sh, and the plugin
# directory is deleted before any commit, so only .rx/scripts can be doing the work.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"
APPROVED="approved:rex:2026-10-16"

# mkstate <repo> <id> <phase> <g2>
mkstate() {
  mkdir -p "$1/specs/$2"
  sed -e "s/^feature: .*/feature: $2/" -e "s/^phase: .*/phase: $3/" \
      -e "s/^g2: .*/g2: $4/" "$TPL_STATE" > "$1/specs/$2/state.md"
}

# new_repo [config-key=value...]: repo on main with rx installed and committed, plugin copy removed.
new_repo() {
  local d plugin
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  plugin="$d/plugin"
  mkdir -p "$plugin"
  cp -R "$ROOT/scripts" "$ROOT/skills" "$ROOT/.claude-plugin" "$plugin/"
  fixture_repo "$d/r"
  fixture_config "$d/r" "$@"
  printf '# project\n' > "$d/r/CLAUDE.md"
  mkdir -p "$d/r/docs/knowledge" "$d/r/src"
  printf '# arch\n' > "$d/r/docs/knowledge/architecture.md"
  printf 'class Base {}\n' > "$d/r/src/Base.java"
  (cd "$d/r" && "$plugin/scripts/rx-init-files.sh" >/dev/null 2>&1) || _rx_fail "setup: init failed"
  git -C "$d/r" add -A >/dev/null 2>&1
  git -C "$d/r" commit -q -m "rx setup" 2>"$d/setup.err" || _rx_fail "setup commit failed: $(cat "$d/setup.err")"
  rm -rf "$plugin"
  printf '%s\n' "$d/r"
}

# try_commit <repo> [env...]: commit what is staged; sets RC and ERR.
try_commit() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  env "$@" git -C "$d" commit -q -m "test commit" >/dev/null 2>"$ef"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}
stage() { mkdir -p "$1/$(dirname "$2")"; printf 'x\n' >> "$1/$2"; git -C "$1" add -- "$2"; }
refused() { assert_eq "1" "$RC" "$1: commit refused"; }
accepted() { assert_eq "0" "$RC" "$1: commit accepted ($ERR)"; }

# ---------- the setup commit itself, on main ----------
R="$(new_repo)"
assert_eq "2" "$(git -C "$R" rev-list --count HEAD)" "setup: rx files committed on the base branch"

# ---------- plan-first ----------
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan none
git -C "$R" add specs; stage "$R" src/A.java
try_commit "$R"; refused "code before G2"
assert_contains "$ERR" "G2" "code before G2: reason names G2"
git -C "$R" reset -q src/A.java
try_commit "$R"; accepted "specs only before G2"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; stage "$R" src/A.java
try_commit "$R"; accepted "code after G2"

# ---------- merge-safety (shared) ----------
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; stage "$R" CLAUDE.md
try_commit "$R"; refused "CLAUDE.md on a feature branch"
assert_contains "$ERR" "CLAUDE.md" "CLAUDE.md: reason names the file"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; stage "$R" docs/knowledge/architecture.md
try_commit "$R"; refused "architecture.md on a feature branch"

# ---------- test gate ----------
R="$(new_repo test_cmd=false)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x build "$APPROVED"
git -C "$R" add specs; stage "$R" src/A.java
try_commit "$R"; refused "red tests in the build phase"
assert_contains "$ERR" "rx-gate" "red tests: reason from the gate"
R="$(new_repo test_cmd=true)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x build "$APPROVED"
git -C "$R" add specs; stage "$R" src/A.java
try_commit "$R"; accepted "green tests in the build phase"

# ---------- gate inputs come from the base branch ----------
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; git -C "$R" rm -q .rx/config.yml
try_commit "$R"; refused "config deleted (staged)"
assert_contains "$ERR" ".rx/config.yml" "config deleted: reason names the file"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; rm "$R/.rx/config.yml"
try_commit "$R"; refused "config deleted (worktree only)"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; printf '#!/bin/sh\nexit 0\n' > "$R/.rx/scripts/rx-check.sh"; git -C "$R" add -f .rx/scripts/rx-check.sh
try_commit "$R"; refused "gate script rewritten to exit 0"
assert_contains "$ERR" ".rx/scripts" "rewritten script: reason names .rx/scripts"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; printf '#!/bin/sh\nexit 0\n' > "$R/.rx/scripts/rx-extra.sh"
try_commit "$R"; refused "untracked file added to .rx/scripts"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan "$APPROVED"
git -C "$R" add specs; rm "$R/.rx/scripts/rx-precommit.sh"
try_commit "$R"; refused "pre-commit script deleted"

# ---------- branches that are not feature branches ----------
R="$(new_repo)"; git -C "$R" checkout -q -b chore/docs; stage "$R" CLAUDE.md
try_commit "$R"; refused "shared file on a non-feature branch"
assert_contains "$ERR" "RX_SHARED_OK" "non-feature branch: reason names the human override"
git -C "$R" reset -q CLAUDE.md; git -C "$R" checkout -q -- CLAUDE.md; stage "$R" src/B.java
try_commit "$R"; refused "code on a non-feature branch"
git -C "$R" reset -q src/B.java; stage "$R" CLAUDE.md
try_commit "$R" RX_SHARED_OK=0; refused "RX_SHARED_OK=0 is not an override"
try_commit "$R" RX_SHARED_OK=1; accepted "RX_SHARED_OK=1 lands a human-only change"
R="$(new_repo)"; stage "$R" src/B.java
try_commit "$R"; accepted "code committed on the base branch itself"
R="$(new_repo)"; git -C "$R" checkout -q -b feature/x; mkstate "$R" x plan none
git -C "$R" add specs; git -C "$R" checkout -q --detach
stage "$R" src/A.java
try_commit "$R"; accepted "detached HEAD without an active feature (rebase)"

# ---------- not set up ----------
D="$(cd "$(fixture_tmpdir)" && pwd -P)"; fixture_repo "$D/r"
mkdir -p "$D/r/.rx/scripts"; cp "$ROOT/scripts/"*.sh "$D/r/.rx/scripts/"
printf '#!/bin/sh\nexec .rx/scripts/rx-precommit.sh\n' > "$D/r/.git/hooks/pre-commit"; chmod +x "$D/r/.git/hooks/pre-commit"
stage "$D/r" src/A.java
try_commit "$D/r"; accepted "no .rx/config.yml anywhere: no-op"

echo "test_precommit: ok"
