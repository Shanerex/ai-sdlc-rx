#!/usr/bin/env bash
# scripts/rx-guard.sh: PreToolUse guard (plan-first, architecture.md, rx-owned files, gate lines).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

GUARD="$ROOT/scripts/rx-guard.sh"
TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"

# run_guard <repo> <json>: sets ERR, RC (cwd=<repo>, payload on stdin).
run_guard() {
  local d="$1" ef
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  (cd "$d" && "$GUARD" <<<"$2" >/dev/null 2>"$ef")
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# payload <repo> <tool> <path> [agent_id] [new_string]
payload() {
  jq -nc --arg cwd "$1" --arg tool "$2" --arg p "$3" --arg a "${4-}" --arg ns "${5-}" '
    {hook_event_name: "PreToolUse", cwd: $cwd, tool_name: $tool,
     tool_input: ({file_path: $p} + (if $ns != "" then {new_string: $ns, content: $ns} else {} end))}
    + (if $a != "" then {agent_id: $a} else {} end)'
}

# mkstate <repo> <id> <g2>: state.md from the REAL template, phase build.
mkstate() {
  mkdir -p "$1/specs/$2"
  sed -e "s/^feature: .*/feature: $2/" -e "s/^phase: .*/phase: build/" \
      -e "s/^g2: .*/g2: $3/" "$TPL_STATE" > "$1/specs/$2/state.md"
}

new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  fixture_config "$d/r"
  git -C "$d/r" checkout -q -b feature/x
  printf '%s\n' "$d/r"
}

blocked() { # <name> : last run must be exit 2 with one-line reason
  assert_eq "2" "$RC" "$1: rc 2"
  case "$ERR" in *$'\n'*[!$'\n']*) _rx_fail "$1: reason must be one line: $ERR" ;; esac
  assert_contains "$ERR" "rx-guard:" "$1: reason prefix"
}
allowed() { assert_eq "0" "$RC" "$1: rc 0"; }

APPROVED="approved:rex:2026-10-16"

# ---------- plan-first ----------
R="$(new_repo)"; mkstate "$R" x none
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"
blocked "src edit before G2"
assert_contains "$ERR" "G2" "reason names G2"
run_guard "$R" "$(payload "$R" Write "$R/src/deep/er/A.java")"; blocked "nested src write before G2"
run_guard "$R" "$(payload "$R" MultiEdit "$R/src/A.java")"; blocked "MultiEdit before G2"
run_guard "$R" "$(jq -nc --arg cwd "$R" --arg p "$R/src/N.ipynb" '{cwd:$cwd,tool_name:"NotebookEdit",tool_input:{notebook_path:$p}}')"
blocked "NotebookEdit before G2"
run_guard "$R" "$(payload "$R" Edit "src/A.java")"; blocked "relative path resolved against cwd"
run_guard "$R" "$(payload "$R" Edit "$R/src/../src/A.java")"; blocked "dot-dot path normalised"
run_guard "$R" "$(payload "$R" Edit "$R/src/my file (1).java")"; blocked "path with spaces and parens"
run_guard "$R" "$(payload "$R" Edit "$R/specs/x/plan.md")"; allowed "specs/ before G2"
run_guard "$R" "$(payload "$R" Edit "$R/docs/knowledge/decisions/d.md")"; allowed "docs/ before G2"
run_guard "$R" "$(payload "$R" Edit "$R/.rx/local/test-hash")"; allowed ".rx/local before G2"
run_guard "$R" "$(payload "$R" Edit "$R/README.md")"; allowed "non-source file before G2"
run_guard "$R" "$(payload "$R" Edit "/elsewhere/src/A.java")"; allowed "path outside repo"
run_guard "$R" "$(payload "$R" Bash "$R/src/A.java")"; allowed "non-edit tool ignored"
mkstate "$R" x "$APPROVED"
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "src edit after G2"
fixture_config "$R" "enforce_plan_first=false"; mkstate "$R" x none
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "enforce_plan_first false"
fixture_config "$R" "source_globs=nothing/**"
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "source_globs matching nothing"
fixture_config "$R" "source_globs="
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "empty source_globs"

# ---------- no active feature ----------
R="$(new_repo)"; mkstate "$R" x none
git -C "$R" checkout -q main
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "on main, no active feature"
git -C "$R" checkout -q -b hotfix-1
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "branch outside branch_pattern"
git -C "$R" checkout -q --detach
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "detached HEAD, no active file"
mkdir -p "$R/.rx/local"; printf 'x\n' > "$R/.rx/local/active"
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; blocked ".rx/local/active fallback"
# the architecture rule needs no feature
run_guard "$R" "$(payload "$R" Edit "$R/docs/knowledge/architecture.md")"; blocked "architecture.md on detached HEAD"

# ---------- invalid state ----------
R="$(new_repo)"; mkstate "$R" x none
sed -i.bak 's/^phase: .*/phase: bogus/' "$R/specs/x/state.md"; rm "$R/specs/x/state.md.bak"
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"
allowed "invalid state does not block"
assert_contains "$ERR" "state.md invalid" "invalid state warns"
rm "$R/specs/x/state.md"
run_guard "$R" "$(payload "$R" Edit "$R/src/A.java")"; allowed "missing state.md does not block"
assert_contains "$ERR" "state.md invalid" "missing state.md warns"

# ---------- rx-owned files ----------
R="$(new_repo)"; mkstate "$R" x "$APPROVED"
for p in docs/knowledge/architecture.md docs/knowledge/../knowledge/architecture.md .rx/config.yml .rx/scripts/rx-check.sh .rx/scripts/templates/plan.md; do
  run_guard "$R" "$(payload "$R" Write "$R/$p")"; blocked "$p after G2"
done
run_guard "$R" "$(payload "$R" Edit "docs/knowledge/architecture.md")"; blocked "relative architecture.md"
run_guard "$R" "$(payload "$R" Edit "$R/docs/knowledge/architecture.md.bak")"; allowed "similar name"
run_guard "$R" "$(payload "$R" Edit "$R/sub/docs/knowledge/architecture.md")"; allowed "architecture.md deeper in tree"

# ---------- gate lines in state.md ----------
S="$R/specs/x/state.md"
run_guard "$R" "$(payload "$R" Edit "$S" sub-1 'g3: approved:ai:2026-10-16')"; blocked "subagent sets g3"
run_guard "$R" "$(payload "$R" Edit "$S" sub-1 $'g2: none')"; blocked "subagent resets g2"
run_guard "$R" "$(payload "$R" Edit "$S" '' 'g3: approved:rex:2026-10-16')"; allowed "main thread (orchestrator) sets g3"
run_guard "$R" "$(payload "$R" Edit "$S" sub-1 $'status: blocked\nnext: ask human')"; allowed "subagent status/next"
run_guard "$R" "$(payload "$R" Edit "$S" sub-1 "g2: $APPROVED")"; allowed "subagent writes the g2 value already there"
run_guard "$R" "$(payload "$R" Write "$S" sub-1 "$(cat "$S")")"; allowed "subagent rewrites state.md unchanged"
run_guard "$R" "$(payload "$R" Write "$R/specs/y/state.md" sub-1 'g1: approved:ai:2026-10-16')"; blocked "subagent creates state with g1 approved"
run_guard "$R" "$(payload "$R" Write "$R/specs/y/state.md" sub-1 'g1: none')"; allowed "subagent creates state with g1 none"
run_guard "$R" "$(payload "$R" Edit "$R/specs/x/plan.md" sub-1 'g3: approved:ai:2026-10-16')"; allowed "g-line in another spec file"

# ---------- no-op ----------
R="$(new_repo)"; rm "$R/.rx/config.yml"
run_guard "$R" "$(payload "$R" Edit "$R/docs/knowledge/architecture.md")"; allowed "no config: no-op"
assert_eq "" "$ERR" "no config: silent"

# ---------- bad input ----------
R="$(new_repo)"; mkstate "$R" x none
run_guard "$R" 'not json'; allowed "malformed payload does not block"
assert_contains "$ERR" "rx-guard:" "malformed payload warns"
run_guard "$R" '{}'; allowed "empty payload"
run_guard "$R" ''; allowed "no stdin payload"
echo "test_guard: ok"
