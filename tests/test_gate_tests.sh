#!/usr/bin/env bash
# scripts/rx-gate-tests.sh: Stop / SubagentStop hook that keeps the build phase green.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

GATE="$ROOT/scripts/rx-gate-tests.sh"
TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"
NL=$'\n'

SCR="$(cd "$(fixture_tmpdir)" && pwd -P)"
# count.sh <counter-file> <exit>: records one run, prints 30 numbered lines, exits <exit>.
cat > "$SCR/count.sh" <<'EOS'
echo run >> "$1"
i=1
while [ "$i" -le 30 ]; do echo "line $i"; i=$((i + 1)); done
exit "$2"
EOS
# hang.sh <pidfile> : a child that outlives its parent unless the tree is killed.
cat > "$SCR/hang.sh" <<'EOS'
sleep 31 &
echo $! > "$1"
wait
EOS

# run_gate <repo> [payload]: sets OUT, ERR, RC, ELAPSED (cwd=<repo>, payload on stdin).
run_gate() {
  local d="$1" ef t0=$SECONDS
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(cd "$d" && "$GATE" <<<"${2-"{}"}" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
  ELAPSED=$((SECONDS - t0))
}

# new_repo [key=value...]: repo on feature/x, phase build; callers set CNT="${R%/r}/count" (run counter).
new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  local CNT="$d/count"
  fixture_config "$d/r" "test_cmd=sh $SCR/count.sh $CNT 0" "$@"
  mkdir -p "$d/r/src" "$d/r/tests" "$d/r/specs/x"
  printf 'a\n' > "$d/r/src/A.java"
  printf 't\n' > "$d/r/tests/ATest.java"
  printf '.rx/local/\n' > "$d/r/.gitignore"
  git -C "$d/r" add -A
  git -C "$d/r" commit -q -m base
  git -C "$d/r" checkout -q -b feature/x
  sed -e "s/^feature: .*/feature: x/" -e "s/^phase: .*/phase: build/" "$TPL_STATE" > "$d/r/specs/x/state.md"
  printf '%s\n' "$d/r"
}
runs() { if [ -f "$CNT" ]; then wc -l < "$CNT" | tr -d ' '; else echo 0; fi; }
setstate() { sed -i.bak "s/^$2: .*/$2: $3/" "$1/specs/x/state.md"; rm "$1/specs/x/state.md.bak"; }

# ---------- no-op, other phases, no feature ----------
R="$(new_repo)"; CNT="${R%/r}/count"; rm "$R/.rx/config.yml"
run_gate "$R"
assert_eq "0" "$RC" "no config: rc 0"; assert_eq "" "$ERR$OUT" "no config: silent"; assert_eq "0" "$(runs)" "no config: tests not run"
R="$(new_repo)"; CNT="${R%/r}/count"; setstate "$R" phase plan
run_gate "$R"
assert_eq "0" "$RC" "phase plan: rc 0"; assert_eq "0" "$(runs)" "phase plan: tests not run"
R="$(new_repo)"; CNT="${R%/r}/count"; git -C "$R" checkout -q main
run_gate "$R"
assert_eq "0" "$RC" "no active feature: rc 0"; assert_eq "0" "$(runs)" "no active feature: tests not run"
R="$(new_repo)"; CNT="${R%/r}/count"; sed -i.bak 's/^phase: .*/phase: bogus/' "$R/specs/x/state.md"; rm "$R/specs/x/state.md.bak"
run_gate "$R"
assert_eq "0" "$RC" "invalid state: rc 0"; assert_contains "$ERR" "state.md invalid" "invalid state warns"; assert_eq "0" "$(runs)" "invalid state: not run"
R="$(new_repo)"; CNT="${R%/r}/count"; setstate "$R" status blocked
run_gate "$R"
assert_eq "0" "$RC" "status blocked: rc 0 (dev stopped on a blocker)"; assert_eq "0" "$(runs)" "status blocked: not run"

# ---------- green: run, cache, skip, invalidate ----------
R="$(new_repo)"; CNT="${R%/r}/count";
run_gate "$R"
assert_eq "0" "$RC" "green: rc 0"; assert_eq "" "$OUT" "green: stdout stays empty"; assert_eq "1" "$(runs)" "green: ran once"
[ -s "$R/.rx/local/test-hash" ] || _rx_fail "green: hash written"
run_gate "$R"
assert_eq "0" "$RC" "unchanged: rc 0"; assert_eq "1" "$(runs)" "unchanged: skipped"
printf 'b\n' >> "$R/src/A.java"; run_gate "$R"
assert_eq "2" "$(runs)" "source file edited: re-run"
printf 'x\n' > "$R/src/New.java"; run_gate "$R"
assert_eq "3" "$(runs)" "new untracked source file: re-run"
rm "$R/src/New.java"; run_gate "$R"
assert_eq "4" "$(runs)" "source file removed: re-run"
printf 'doc\n' >> "$R/README.md"; run_gate "$R"
assert_eq "4" "$(runs)" "file outside globs: skipped"
fixture_config "$R" "test_cmd=sh $SCR/count.sh $CNT 0" "test_globs=tests/**"
run_gate "$R"
assert_eq "5" "$(runs)" "test_globs added: re-run (config is part of the hash)"
printf 'more\n' >> "$R/tests/ATest.java"; run_gate "$R"
assert_eq "6" "$(runs)" "test file edited: re-run"
fixture_config "$R" "test_cmd=sh $SCR/count.sh $CNT 0 extra" "test_globs=tests/**"
run_gate "$R"
assert_eq "7" "$(runs)" "test_cmd changed: re-run"

# ---------- red ----------
R="$(new_repo)"; CNT="${R%/r}/count";
fixture_config "$R" "test_cmd=sh $SCR/count.sh $CNT 3"
run_gate "$R"
assert_eq "2" "$RC" "red: rc 2"
assert_contains "$ERR" "tests failed (exit 3)" "red: header"
assert_contains "$ERR" "line 30" "red: last line shown"
assert_contains "$ERR" "line 16" "red: 15th line from the end shown"
case "$ERR" in *"line 15"$'\n'*|*"line 15") _rx_fail "red: only the last 15 lines" ;; esac
assert_eq "" "$OUT" "red: stdout empty"
[ -e "$R/.rx/local/test-hash" ] && _rx_fail "red: no hash written"
run_gate "$R"
assert_eq "2" "$RC" "red again: still blocks"; assert_eq "2" "$(runs)" "red again: ran again"
run_gate "$R" '{"stop_hook_active": true}'
assert_eq "0" "$RC" "stop_hook_active: rc 0 even though red"; assert_eq "2" "$(runs)" "stop_hook_active: tests not run"
run_gate "$R" '{"stop_hook_active": false}'
assert_eq "2" "$RC" "stop_hook_active false: blocks"
run_gate "$R" 'garbage'
assert_eq "2" "$RC" "unreadable payload: gate still runs"

# green -> red -> green again with identical content skips
R="$(new_repo)"; CNT="${R%/r}/count";
run_gate "$R"; assert_eq "1" "$(runs)" "cycle: first green"
cp "$R/src/A.java" "$SCR/A.keep"
printf 'broken\n' >> "$R/src/A.java"
fixture_config "$R" "test_cmd=sh $SCR/count.sh $CNT 1"; run_gate "$R"
assert_eq "2" "$RC" "cycle: red after an edit"
fixture_config "$R" "test_cmd=sh $SCR/count.sh $CNT 0"; cp "$SCR/A.keep" "$R/src/A.java"; run_gate "$R"
assert_eq "0" "$RC" "cycle: green again"; assert_eq "2" "$(runs)" "cycle: content identical to the last green run is skipped"

# ---------- timeout ----------
R="$(new_repo "test_timeout=1")"; CNT="${R%/r}/count";
fixture_config "$R" "test_cmd=sh $SCR/hang.sh $SCR/hangpid" "test_timeout=1"
rm -f "$SCR/hangpid"
run_gate "$R"
assert_eq "2" "$RC" "timeout: rc 2"
assert_contains "$ERR" "timed out after 1s" "timeout: message"
[ "$ELAPSED" -le 4 ] || _rx_fail "timeout: took ${ELAPSED}s"
kill -0 "$(cat "$SCR/hangpid" 2>/dev/null || echo 999999)" 2>/dev/null && _rx_fail "timeout: orphan survived"
[ -s "$SCR/hangpid" ] || _rx_fail "timeout: pidfile never written (setup)"
[ -e "$R/.rx/local/test-hash" ] && _rx_fail "timeout: no hash written"
R="$(new_repo "test_timeout=abc")"; CNT="${R%/r}/count";
run_gate "$R"
assert_eq "0" "$RC" "bad test_timeout falls back to the default"; assert_eq "1" "$(runs)" "bad test_timeout: ran"

# ---------- missing test_cmd ----------
R="$(new_repo)"; CNT="${R%/r}/count"; sed -i.bak '/^test_cmd:/d' "$R/.rx/config.yml"; rm "$R/.rx/config.yml.bak"
run_gate "$R"
assert_eq "2" "$RC" "missing test_cmd: rc 2"; assert_contains "$ERR" "test_cmd" "missing test_cmd: reported"
run_gate "$R" '{"stop_hook_active": true}'
assert_eq "0" "$RC" "missing test_cmd: released by stop_hook_active"

# ---------- run from a subdirectory ----------
R="$(new_repo)"; CNT="${R%/r}/count"; mkdir "$R/sub"
OUT="$(cd "$R/sub" && "$GATE" <<<"{\"cwd\": \"$R/sub\"}" 2>/dev/null)"; RC=$?
assert_eq "0" "$RC" "subdirectory: rc 0"; assert_eq "1" "$(runs)" "subdirectory: ran once from the repo root"

# ---------- no git: no caching, still runs ----------
D="$(cd "$(fixture_tmpdir)" && pwd -P)"; CNT="$D/count"
mkdir -p "$D/n/src" "$D/n/specs/x" "$D/n/.rx/local"
fixture_config "$D/n" "test_cmd=sh $SCR/count.sh $CNT 0"
sed -e "s/^feature: .*/feature: x/" -e "s/^phase: .*/phase: build/" "$TPL_STATE" > "$D/n/specs/x/state.md"
printf 'x\n' > "$D/n/.rx/local/active"
run_gate "$D/n"; run_gate "$D/n"
assert_eq "0" "$RC" "no git: rc 0"; assert_eq "2" "$(runs)" "no git: runs every time (no cache)"
echo "test_gate_tests: ok"
