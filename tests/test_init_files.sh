#!/usr/bin/env bash
# scripts/rx-init-files.sh: the deterministic half of /rx:init (dirs, .gitignore, .rx/scripts copy,
# pre-commit wrapper, --refresh-scripts, and the guarded installers for config / CLAUDE.md /
# architecture.md that the model-written drafts go through).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

INIT="$ROOT/scripts/rx-init-files.sh"
TPL="$ROOT/skills/rx-spec/templates"
VERSION="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"

# run_init <repo> [args...]: sets RC, OUT, ERR (cwd=<repo>, stdin closed).
run_init() {
  local d="$1" of ef
  shift
  of="$(mktemp "$RX_TMP_ROOT/out.XXXXXX")"
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  (cd "$d" && "$INIT" "$@" </dev/null >"$of" 2>"$ef")
  RC=$?
  OUT="$(cat "$of")"
  ERR="$(cat "$ef")"
  rm -f "$of" "$ef"
}

new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  printf '%s\n' "$d/r"
}

# snap <repo>: checksum of everything /rx:init manages, to prove a second run changes nothing.
snap() {
  (cd "$1" && { find .rx docs specs -type f 2>/dev/null; echo .gitignore; echo "$(git rev-parse --git-path hooks/pre-commit)"; } \
    | sort | while IFS= read -r f; do [ -f "$f" ] && shasum -a 256 "$f"; done | shasum -a 256)
}

# ---------- fresh install ----------
R="$(new_repo)"
run_init "$R"
assert_eq "0" "$RC" "fresh: rc 0 ($ERR)"
for d in .rx/local docs/knowledge/decisions docs/knowledge/learnings specs .rx/scripts/templates; do
  assert_exit 0 test -d "$R/$d"
done
assert_eq "1" "$(grep -cx '.rx/local/' "$R/.gitignore")" "fresh: .gitignore has .rx/local/ once"
for s in rx-lib.sh rx-check.sh rx-guard.sh rx-gate-tests.sh rx-new-feature.sh rx-status.sh rx-precommit.sh; do
  assert_exit 0 test -x "$R/.rx/scripts/$s"
  assert_exit 0 cmp -s "$ROOT/scripts/$s" "$R/.rx/scripts/$s"
done
assert_exit 1 test -e "$R/.rx/scripts/rx-init-files.sh"
for t in "$TPL"/*.md; do
  assert_exit 0 cmp -s "$t" "$R/.rx/scripts/templates/$(basename "$t")"
done
assert_eq "$VERSION" "$(cat "$R/.rx/scripts/.rx-version")" "fresh: version stamp"
HOOK="$R/.git/hooks/pre-commit"
assert_exit 0 test -x "$HOOK"
assert_contains "$(cat "$HOOK")" "rx-managed pre-commit" "fresh: hook carries the rx marker"
assert_exit 1 test -e "$R/.rx/config.yml"
assert_exit 1 test -e "$R/CLAUDE.md"

# ---------- idempotent ----------
BEFORE="$(snap "$R")"
run_init "$R"
assert_eq "0" "$RC" "second run: rc 0"
assert_eq "$BEFORE" "$(snap "$R")" "second run changes nothing"
assert_eq "1" "$(grep -cx '.rx/local/' "$R/.gitignore")" "second run: .gitignore not duplicated"

# ---------- .gitignore handling ----------
R="$(new_repo)"; printf 'node_modules/\n*.log' > "$R/.gitignore"
run_init "$R"
assert_eq $'node_modules/\n*.log\n.rx/local/' "$(cat "$R/.gitignore")" "gitignore: no trailing newline is repaired, content kept"
R="$(new_repo)"; printf '/.rx/local/\n' > "$R/.gitignore"
run_init "$R"
assert_eq "/.rx/local/" "$(cat "$R/.gitignore")" "gitignore: an equivalent existing entry is kept as is"

# ---------- --refresh-scripts ----------
R="$(new_repo)"; run_init "$R"
printf 'test_cmd: true\n' > "$R/.rx/config.yml"
printf '# mine\n' > "$R/CLAUDE.md"
printf 'old\n' > "$R/.rx/scripts/.rx-version"
printf '# stale\n' >> "$R/.rx/scripts/rx-lib.sh"
printf 'x\n' > "$R/.rx/scripts/stray.sh"
printf '# stale\n' >> "$R/.rx/scripts/templates/state.md"
printf '#!/bin/sh\n# rx-managed pre-commit (edited)\n' > "$R/.git/hooks/pre-commit"
printf 'keep\n' >> "$R/.gitignore"
KEEP="$(cd "$R" && shasum -a 256 .rx/config.yml CLAUDE.md .gitignore .git/hooks/pre-commit)"
run_init "$R" --refresh-scripts
assert_eq "0" "$RC" "refresh: rc 0 ($ERR)"
assert_exit 0 cmp -s "$ROOT/scripts/rx-lib.sh" "$R/.rx/scripts/rx-lib.sh"
assert_exit 0 cmp -s "$TPL/state.md" "$R/.rx/scripts/templates/state.md"
assert_eq "$VERSION" "$(cat "$R/.rx/scripts/.rx-version")" "refresh: version stamp updated"
assert_exit 1 test -e "$R/.rx/scripts/stray.sh"
assert_exit 0 test -x "$R/.rx/scripts/rx-check.sh"
assert_eq "$KEEP" "$(cd "$R" && shasum -a 256 .rx/config.yml CLAUDE.md .gitignore .git/hooks/pre-commit)" "refresh touches nothing but .rx/scripts"
assert_eq "" "$(ls -d "$R"/.rx/scripts.* 2>/dev/null)" "refresh leaves no temp dir behind"
assert_eq "" "$(find "$R/docs" "$R/specs" -type f)" "refresh: docs/specs untouched"

# ---------- environment errors ----------
D="$(cd "$(fixture_tmpdir)" && pwd -P)"
run_init "$D"; assert_eq "2" "$RC" "no git repo: rc 2"; assert_contains "$ERR" "git repository" "no git repo: message"
R="$(new_repo)"; run_init "$R" --bogus; assert_eq "2" "$RC" "unknown flag: rc 2"; assert_contains "$ERR" "usage" "unknown flag: usage"

# ---------- pre-commit hook placement ----------
R="$(new_repo)"; printf '#!/bin/sh\necho mine\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
run_init "$R"
assert_eq "1" "$RC" "foreign hook: rc 1 (not silently skipped)"
assert_contains "$ERR" "pre-commit" "foreign hook: says why"
assert_eq $'#!/bin/sh\necho mine' "$(cat "$R/.git/hooks/pre-commit")" "foreign hook: left untouched"
assert_exit 0 test -x "$R/.rx/scripts/rx-check.sh"
R="$(new_repo)"; HP="$(fixture_tmpdir)/hooks"; git -C "$R" config core.hooksPath "$HP"
run_init "$R"
assert_eq "0" "$RC" "hooksPath: rc 0"
assert_exit 0 test -x "$HP/pre-commit"
assert_exit 1 test -e "$R/.git/hooks/pre-commit"
# a linked worktree shares the hooks of the main repo; init from it must not fail
R="$(new_repo)"; git -C "$R" worktree add -q "$R-wt" -b wt >/dev/null 2>&1
run_init "$R-wt"
assert_eq "0" "$RC" "linked worktree: rc 0 ($ERR)"
assert_exit 0 test -x "$R/.git/hooks/pre-commit"

# ---------- guarded installers (drafts written by the model, never overwriting) ----------
R="$(new_repo)"; run_init "$R"
DRAFT="$(fixture_tmpdir)/draft"
printf '# rx config\ntest_cmd: npm test\nsource_globs: src/**\nbranch_pattern: feature/{id}\nbase_branch: main\n' > "$DRAFT"
run_init "$R" --install-config "$DRAFT"
assert_eq "0" "$RC" "config: rc 0 ($ERR)"
assert_exit 0 cmp -s "$DRAFT" "$R/.rx/config.yml"
printf 'test_cmd: other\n' > "$DRAFT"
run_init "$R" --install-config "$DRAFT"
assert_eq "1" "$RC" "config: existing is never overwritten"
assert_contains "$ERR" "already exists" "config: says so"
assert_contains "$(cat "$R/.rx/config.yml")" "npm test" "config: original kept"

R="$(new_repo)"; run_init "$R"
bad_config() { # <name> <content>
  printf '%s\n' "$2" > "$DRAFT"
  run_init "$R" --install-config "$DRAFT"
  assert_eq "1" "$RC" "config rejected: $1"
  assert_exit 1 test -e "$R/.rx/config.yml"
}
bad_config "no test_cmd" "source_globs: src/**"
bad_config "coverage_cmd (out of scope for v0.1)" $'test_cmd: t\ncoverage_cmd: c'
bad_config "coverage_min" $'test_cmd: t\ncoverage_min: 80'
bad_config "nested yaml" $'test_cmd: t\nbranches:\n  - a'
bad_config "empty test_cmd" "test_cmd:"
run_init "$R" --install-config "$(fixture_tmpdir)/missing"; assert_eq "2" "$RC" "config: missing draft file is a usage error"
run_init "$R" --install-config; assert_eq "2" "$RC" "config: no draft argument is a usage error"

# base_branch is embedded in the hook wrapper: only plain branch names may get there
bad_config "base_branch with a quote" $'test_cmd: t\nbase_branch: x\'; touch /tmp/rx-pwned; echo \''
bad_config "base_branch with a space" $'test_cmd: t\nbase_branch: my branch'
bad_config "base_branch starting with a dash" $'test_cmd: t\nbase_branch: -x'
bad_config "base_branch with a dollar" $'test_cmd: t\nbase_branch: $HOME'
printf 'test_cmd: t\nbase_branch: release/1.x_y-z\n' > "$DRAFT"
run_init "$R" --install-config "$DRAFT"; assert_eq "0" "$RC" "config: a plain branch name with / . _ - is fine ($ERR)"
assert_contains "$(cat "$R/.git/hooks/pre-commit")" "BASE='release/1.x_y-z'" "config install re-stamps the managed hook with the base branch"
R="$(new_repo)"; mkdir -p "$R/.rx"
printf "test_cmd: t\nbase_branch: x'; touch %s/PWNED; echo '\n" "$(dirname "$R")" > "$R/.rx/config.yml"
run_init "$R"
assert_eq "1" "$RC" "init with an unsafe base_branch already in the config: rc 1"
assert_contains "$ERR" "base_branch" "unsafe base_branch: says which key"
assert_exit 1 test -e "$R/.git/hooks/pre-commit"
assert_exit 1 test -e "$(dirname "$R")/PWNED"
assert_exit 0 test -x "$R/.rx/scripts/rx-check.sh"

# CLAUDE.md
R="$(new_repo)"; run_init "$R"
{ for i in $(seq 1 60); do echo "line $i"; done; } > "$DRAFT"
run_init "$R" --install-claude-md "$DRAFT"
assert_eq "0" "$RC" "claude.md: 60 lines ok ($ERR)"
assert_exit 0 cmp -s "$DRAFT" "$R/CLAUDE.md"
printf 'other\n' > "$DRAFT"
run_init "$R" --install-claude-md "$DRAFT"
assert_eq "1" "$RC" "claude.md: existing is never overwritten"
assert_eq "60" "$(wc -l < "$R/CLAUDE.md" | tr -d ' ')" "claude.md: original kept"
R="$(new_repo)"; run_init "$R"
{ for i in $(seq 1 61); do echo "line $i"; done; } > "$DRAFT"
run_init "$R" --install-claude-md "$DRAFT"; assert_eq "1" "$RC" "claude.md: 61 lines rejected"; assert_exit 1 test -e "$R/CLAUDE.md"
printf '# t\n@docs/other.md\n' > "$DRAFT"
run_init "$R" --install-claude-md "$DRAFT"; assert_eq "1" "$RC" "claude.md: @import rejected"; assert_exit 1 test -e "$R/CLAUDE.md"
printf '# t\n  @docs/other.md\n' > "$DRAFT"
run_init "$R" --install-claude-md "$DRAFT"; assert_eq "1" "$RC" "claude.md: indented @import rejected"

# architecture.md (brownfield seed; the guard keeps agents from writing it directly)
R="$(new_repo)"; run_init "$R"
{ for i in $(seq 1 80); do echo "line $i"; done; } > "$DRAFT"
run_init "$R" --install-architecture "$DRAFT"
assert_eq "0" "$RC" "architecture: 80 lines ok ($ERR)"
assert_exit 0 cmp -s "$DRAFT" "$R/docs/knowledge/architecture.md"
run_init "$R" --install-architecture "$DRAFT"; assert_eq "1" "$RC" "architecture: existing is never overwritten"
R="$(new_repo)"; run_init "$R"
{ for i in $(seq 1 81); do echo "line $i"; done; } > "$DRAFT"
run_init "$R" --install-architecture "$DRAFT"; assert_eq "1" "$RC" "architecture: 81 lines rejected"
assert_exit 1 test -e "$R/docs/knowledge/architecture.md"
# CRLF drafts count lines the same way
printf 'a\r\nb\r\n' > "$DRAFT"
run_init "$R" --install-architecture "$DRAFT"; assert_eq "0" "$RC" "architecture: CRLF draft ok"

echo "test_init_files: ok"
