#!/usr/bin/env bash
# scripts/rx-lib.sh: root/enabled, flat-yaml config, feature id, state.md read + validation, source hygiene.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/fixture.sh"

LIB="$ROOT/scripts/rx-lib.sh"
TPL_STATE="$ROOT/skills/rx-spec/templates/state.md"

# inrepo <dir> <cmd...>: source the lib in a subshell cwd'd at <dir>, run cmd.
inrepo() {
  local d="$1"
  shift
  ( cd "$d" && . "$LIB" && "$@" )
}

# inrepo_eval <dir> <code>: same, for compound code.
inrepo_eval() {
  ( cd "$1" && . "$LIB" && eval "$2" )
}

# run <dir> <cmd...>: sets OUT (stdout), ERR (stderr), RC (exit code).
run() {
  local d="$1" ef
  shift
  ef="$(mktemp "$RX_TMP_ROOT/err.XXXXXX")"
  OUT="$(inrepo "$d" "$@" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# new_repo: print a fresh fixture git repo path (physical path, branch main).
new_repo() {
  local d
  d="$(cd "$(fixture_tmpdir)" && pwd -P)"
  fixture_repo "$d/r"
  printf '%s\n' "$d/r"
}

# writecfg <repo> <content>: raw .rx/config.yml (printf-escapes allowed).
writecfg() {
  mkdir -p "$1/.rx"
  printf "$2" > "$1/.rx/config.yml"
}

# ---------- rx_root ----------
R="$(new_repo)"
mkdir -p "$R/a/b"
run "$R" rx_root
assert_eq "$R" "$OUT" "rx_root at repo top"
run "$R/a/b" rx_root
assert_eq "$R" "$OUT" "rx_root from subdirectory"
assert_eq "0" "$RC" "rx_root rc in git"

PLAIN="$(cd "$(fixture_tmpdir)" && pwd -P)"
mkdir -p "$PLAIN/plain"
GIT_CEILING_DIRECTORIES="$PLAIN" run "$PLAIN/plain" rx_root
assert_eq "$PLAIN/plain" "$OUT" "rx_root outside git is PWD"
assert_eq "0" "$RC" "rx_root rc outside git"
assert_eq "" "$ERR" "rx_root outside git is quiet"

# ---------- rx_enabled / rx_noop_unless_enabled ----------
R="$(new_repo)"
run "$R" rx_enabled
assert_eq "1" "$RC" "rx_enabled false without config"
mkdir -p "$R/.rx/config.yml"
run "$R" rx_enabled
assert_eq "1" "$RC" "rx_enabled false when config.yml is a directory"
rmdir "$R/.rx/config.yml"
writecfg "$R" 'test_cmd: true\n'
run "$R" rx_enabled
assert_eq "0" "$RC" "rx_enabled true with config"
mkdir -p "$R/sub"
run "$R/sub" rx_enabled
assert_eq "0" "$RC" "rx_enabled true from subdirectory"

D="$(new_repo)"
out="$(inrepo_eval "$D" 'rx_noop_unless_enabled; echo AFTER' 2>&1)"; rc=$?
assert_eq "0" "$rc" "noop_unless_enabled exits 0 when disabled"
assert_eq "" "$out" "noop_unless_enabled stops the caller (no AFTER)"
out="$(inrepo_eval "$R" 'rx_noop_unless_enabled; echo AFTER' 2>&1)"; rc=$?
assert_eq "0" "$rc" "noop_unless_enabled rc when enabled"
assert_eq "AFTER" "$out" "noop_unless_enabled does not exit when enabled"

# ---------- rx_cfg ----------
C="$(new_repo)"
cfg_case() { # <message> <expected> <config-content> <key> [default]
  local msg="$1" want="$2" content="$3"
  shift 3
  writecfg "$C" "$content"
  run "$C" rx_cfg "$@"
  assert_eq "$want" "$OUT" "rx_cfg $msg"
  assert_eq "0" "$RC" "rx_cfg $msg: rc 0"
  assert_eq "" "$ERR" "rx_cfg $msg: quiet"
}
cfg_case "plain"                 "mvn test"        'test_cmd: mvn test\n' test_cmd
cfg_case "no space after colon"  ""                'test_cmd:mvn\n' test_cmd
cfg_case "double quoted"         "mvn -q test"     'test_cmd: "mvn -q test"\n' test_cmd
cfg_case "single quoted"         "mvn -q test"     "test_cmd: 'mvn -q test'\\n" test_cmd
cfg_case "inner other quote"     "bash -c 'x y'"   'test_cmd: "bash -c '"'x y'"'"\n' test_cmd
cfg_case "trailing comment"      "mvn test"        'test_cmd: mvn test # run it\n' test_cmd
cfg_case "tab then comment"      "mvn test"        'test_cmd: mvn test\t# run it\n' test_cmd
cfg_case "comment after quotes"  "a # b"           'k: "a # b"   # real comment\n' k
cfg_case "hash without space"    "a#b"             'k: a#b\n' k
cfg_case "hash in url"           "http://x/#frag"  'k: http://x/#frag\n' k
cfg_case "only a comment"        "dflt"            'k: # nothing\n' k dflt
cfg_case "whitespace trimmed"    "v"               'k:    v   \n' k
cfg_case "crlf line"             "v"               'k: v\r\n' k
cfg_case "empty value"           ""                'k:\n' k
cfg_case "empty value default"   "dflt"            'k:\n' k dflt
cfg_case "empty quoted default"  "dflt"            'k: ""\n' k dflt
cfg_case "empty single quoted"   "dflt"            "k: ''\\n" k dflt
cfg_case "blank spaces default"  "dflt"            'k:    \n' k dflt
cfg_case "missing key"           ""                'a: 1\n' k
cfg_case "missing key default"   "dflt"            'a: 1\n' k dflt
cfg_case "exact key match"       "dflt"            'test_cmd_extra: nope\n' test_cmd dflt
cfg_case "exact key, prefix key" "yes"             'test_cmd_extra: nope\ntest_cmd: yes\n' test_cmd
cfg_case "key is suffix of other" "dflt"           'my_test_cmd: nope\n' test_cmd dflt
cfg_case "value with colon"      "http://x:80/p"   'k: http://x:80/p\n' k
cfg_case "value with spaces"     "mvn -q test -pl a b" 'k: mvn -q test -pl a b\n' k
cfg_case "braces"                "feature/{id}"    'k: feature/{id}\n' k
cfg_case "junk lines ignored"    "ok"              'garbage\n: x\n  \n# k: no\n--- \n=== k\nk: ok\n' k
cfg_case "indented key"          "v"               '   k: v\n' k
cfg_case "commented key"         "dflt"            '# k: v\n' k dflt
cfg_case "first match wins"      "one"             'k: one\nk: two\n' k
cfg_case "first match wins empty" "dflt"           'k:\nk: two\n' k dflt
cfg_case "no trailing newline"   "v"               'k: v' k
cfg_case "unterminated quote"    '"abc'            'k: "abc\n' k

rm -f "$C/.rx/config.yml"
run "$C" rx_cfg k dflt
assert_eq "dflt" "$OUT" "rx_cfg missing config file -> default"
assert_eq "0" "$RC" "rx_cfg missing config file rc 0"
assert_eq "" "$ERR" "rx_cfg missing config file quiet"
run "$C" rx_cfg k
assert_eq "" "$OUT" "rx_cfg missing config file, no default -> nothing"
assert_eq "0" "$RC" "rx_cfg missing config file, no default rc 0"

writecfg "$C" 'k: from-root\n'
mkdir -p "$C/deep/er"
run "$C/deep/er" rx_cfg k
assert_eq "from-root" "$OUT" "rx_cfg reads config from repo root when run in a subdirectory"

# ---------- rx_require_cfg ----------
writecfg "$C" 'base_branch: main\nempty:\nq: ""\n'
run "$C" rx_require_cfg base_branch
assert_eq "main" "$OUT" "rx_require_cfg prints value"
assert_eq "0" "$RC" "rx_require_cfg ok rc"
for k in missing empty q; do
  run "$C" rx_require_cfg "$k"
  assert_eq "2" "$RC" "rx_require_cfg $k dies with 2"
  assert_eq "" "$OUT" "rx_require_cfg $k prints nothing to stdout"
  assert_eq "rx: missing config key: $k" "$ERR" "rx_require_cfg $k message"
done

# ---------- rx_die ----------
run "$C" rx_die "boom now"
assert_eq "2" "$RC" "rx_die exits 2"
assert_eq "rx: boom now" "$ERR" "rx_die message on stderr"
assert_eq "" "$OUT" "rx_die nothing on stdout"
out="$(inrepo_eval "$C" 'rx_die x; echo AFTER' 2>/dev/null)"
assert_eq "" "$out" "rx_die stops the caller"

# rx_die exits only the current shell: inside $(...) the caller must add `|| exit 2`.
out="$(inrepo_eval "$C" 'x="$(rx_require_cfg missing 2>/dev/null)" || exit 2; echo AFTER' 2>&1)"; rc=$?
assert_eq "2" "$rc" "x=\"\$(rx_require_cfg k)\" || exit 2 exits the script with 2"
assert_eq "" "$out" "later command does not run after || exit 2"
out="$(inrepo_eval "$C" 'x="$(rx_require_cfg missing 2>/dev/null)"; rc=$?; echo "AFTER rc=$rc x=[$x]"' 2>&1)"; rc=$?
assert_eq "0" "$rc" "without || exit 2 the caller keeps running"
assert_eq "AFTER rc=2 x=[]" "$out" "without || exit 2 the caller sees rc=2 and empty x (documented caveat)"
out="$(inrepo_eval "$C" 'rx_require_cfg missing >/dev/null 2>&1; echo AFTER' 2>&1)"; rc=$?
assert_eq "2" "$rc" "bare rx_require_cfg call exits the script with 2"
assert_eq "" "$out" "bare rx_require_cfg call stops the script"

# ---------- rx_feature_id ----------
F="$(new_repo)"
fid_case() { # <message> <branch|-> <config-content|-> <expected> <expected-rc>
  local msg="$1" br="$2" content="$3" want="$4" wantrc="$5"
  if [ "$br" != "-" ]; then
    git -C "$F" checkout -q -b "$br"
  fi
  if [ "$content" != "-" ]; then writecfg "$F" "$content"; fi
  run "$F" rx_feature_id
  assert_eq "$want" "$OUT" "feature_id $msg: output"
  assert_eq "$wantrc" "$RC" "feature_id $msg: rc"
  assert_eq "" "$ERR" "feature_id $msg: quiet"
  git -C "$F" checkout -q main
  if [ "$br" != "-" ]; then git -C "$F" branch -q -D "$br"; fi
}
rm -rf "$F/.rx"
git -C "$F" checkout -q -b feature/2026-10-16-login
run "$F" rx_feature_id
assert_eq "2026-10-16-login" "$OUT" "feature_id default pattern, no config"
assert_eq "0" "$RC" "feature_id default pattern rc"
mkdir -p "$F/src/deep"
run "$F/src/deep" rx_feature_id
assert_eq "2026-10-16-login" "$OUT" "feature_id from a subdirectory"
git -C "$F" checkout -q main
git -C "$F" branch -q -D feature/2026-10-16-login

fid_case "feature/{id} pattern"  "feature/abc.1_x-2" 'branch_pattern: feature/{id}\n' "abc.1_x-2" 0
fid_case "wrong prefix"          "hotfix/abc"        'branch_pattern: feature/{id}\n' "" 1
fid_case "{id} pattern: base branch is no feature" "-" 'branch_pattern: {id}\nbase_branch: main\n' "" 1
fid_case "custom pattern"        "wip/abc-x"         'branch_pattern: wip/{id}-x\n' "abc" 0
fid_case "custom suffix mismatch" "wip/abc-y"        'branch_pattern: wip/{id}-x\n' "" 1
fid_case "quoted pattern"        "wip/abc"           'branch_pattern: "wip/{id}"   # c\n' "abc" 0
fid_case "{id} alone"            "2026-q4-sso"       'branch_pattern: {id}\n' "2026-q4-sso" 0
fid_case "pattern without {id}"  "feature/abc"       'branch_pattern: feature/abc\n' "" 1
fid_case "pattern without {id}, literal branch" "feature" 'branch_pattern: feature\n' "" 1
fid_case "two placeholders never match" "a/x/b/x"    'branch_pattern: a/{id}/b/{id}\n' "" 1
fid_case "slash in id rejected"  "feature/foo/bar"   'branch_pattern: feature/{id}\n' "" 1
fid_case "id must start alnum"   "feature/_hidden"   'branch_pattern: feature/{id}\n' "" 1
fid_case "empty id rejected"     "wip/-x"            'branch_pattern: wip/{id}-x\n' "" 1
fid_case "pattern is not a regex" "featureXabc"      'branch_pattern: feature.{id}\n' "" 1
fid_case "regex chars in pattern literal" "a+b/zed" 'branch_pattern: a+b/{id}\n' "zed" 0
fid_case "branch main, no active" "-"                'branch_pattern: feature/{id}\n' "" 1
# with `{id}` alone the base branch is not a feature: fall through to .rx/local/active
writecfg "$F" 'branch_pattern: {id}\nbase_branch: main\n'
mkdir -p "$F/.rx/local"
printf 'from-active\n' > "$F/.rx/local/active"
run "$F" rx_feature_id
assert_eq "from-active" "$OUT" "feature_id: base branch falls through to .rx/local/active"
assert_eq "0" "$RC" "feature_id: base branch falls through, rc 0"
rm -rf "$F/.rx/local"
fid_case "no config at all, main" "-"                '' "" 1

# (b) .rx/local/active fallback
mkdir -p "$F/.rx/local"
act_case() { # <message> <active content printf-fmt> <expected> <expected-rc>
  printf "$2" > "$F/.rx/local/active"
  run "$F" rx_feature_id
  assert_eq "$3" "$OUT" "active $1: output"
  assert_eq "$4" "$RC" "active $1: rc"
  assert_eq "" "$ERR" "active $1: quiet"
}
git -C "$F" checkout -q main
writecfg "$F" 'branch_pattern: feature/{id}\n'
act_case "plain"               'my-feat\n'         "my-feat" 0
act_case "no newline"          'my-feat'           "my-feat" 0
act_case "trailing whitespace" '  my-feat \t \n'   "my-feat" 0
act_case "crlf"                'my-feat\r\n'       "my-feat" 0
act_case "first line only"     'one\ntwo\n'        "one" 0
act_case "empty file"          ''                  "" 1
act_case "blank first line"    '\nsecond\n'        "" 1
act_case "whitespace only"     '   \n'             "" 1
act_case "slash rejected"      'foo/bar\n'         "" 1
act_case "dotdot rejected"     '../x\n'            "" 1
rm -f "$F/.rx/local/active"
run "$F" rx_feature_id
assert_eq "1" "$RC" "no active file, main -> rc 1"
assert_eq "" "$OUT" "no active file, main -> no output"

printf 'from-active\n' > "$F/.rx/local/active"
git -C "$F" checkout -q -b feature/from-branch
run "$F" rx_feature_id
assert_eq "from-branch" "$OUT" "branch wins over active file"
git -C "$F" checkout -q -b feature/a/b
run "$F" rx_feature_id
assert_eq "from-active" "$OUT" "invalid branch id falls through to active file"
assert_eq "" "$ERR" "fall-through is quiet"
git -C "$F" checkout -q --detach
run "$F" rx_feature_id
assert_eq "from-active" "$OUT" "detached HEAD falls back to active file"
assert_eq "0" "$RC" "detached HEAD fallback rc"
assert_eq "" "$ERR" "detached HEAD fallback quiet"
mkdir -p "$F/sub"
run "$F/sub" rx_feature_id
assert_eq "from-active" "$OUT" "active file found from a subdirectory"
rm -f "$F/.rx/local/active"
run "$F" rx_feature_id
assert_eq "1" "$RC" "detached HEAD without active file -> rc 1"
assert_eq "" "$OUT" "detached HEAD without active file -> no output"
assert_eq "" "$ERR" "detached HEAD without active file quiet"

# rebase in progress (detached) falls through quietly
RB="$(new_repo)"
mkdir -p "$RB/.rx/local"
printf 'feature/{id}\n' | sed 's/^/branch_pattern: /' > "$RB/.rx/config.yml"
printf 'rb-feat\n' > "$RB/.rx/local/active"
printf '1\n' > "$RB/f.txt"; git -C "$RB" add f.txt; git -C "$RB" commit -q -m base
git -C "$RB" checkout -q -b feature/side
printf '2\n' > "$RB/f.txt"; git -C "$RB" commit -q -am side
git -C "$RB" checkout -q main
printf '3\n' > "$RB/f.txt"; git -C "$RB" commit -q -am mainchange
git -C "$RB" checkout -q feature/side
git -C "$RB" rebase main >/dev/null 2>&1
[ -d "$RB/.git/rebase-merge" ] || [ -d "$RB/.git/rebase-apply" ] || assert_eq "rebase in progress" "not in progress" "rebase fixture"
run "$RB" rx_feature_id
assert_eq "rb-feat" "$OUT" "rebase in progress falls through to active file"
assert_eq "" "$ERR" "rebase in progress quiet"
git -C "$RB" rebase --abort >/dev/null 2>&1

# non-git directory: only the active file can resolve
NG="$(cd "$(fixture_tmpdir)" && pwd -P)"
mkdir -p "$NG/p/.rx/local"
printf 'branch_pattern: feature/{id}\n' > "$NG/p/.rx/config.yml"
GIT_CEILING_DIRECTORIES="$NG" run "$NG/p" rx_feature_id
assert_eq "1" "$RC" "non-git, no active -> rc 1"
assert_eq "" "$ERR" "non-git, no active -> quiet"
printf 'ng-feat\n' > "$NG/p/.rx/local/active"
GIT_CEILING_DIRECTORIES="$NG" run "$NG/p" rx_feature_id
assert_eq "ng-feat" "$OUT" "non-git resolves from active file"

# ---------- rx_branch_id ----------
BI="$(new_repo)"
bid_case() { # <message> <branch> <config-content> <expected> <expected-rc>
  writecfg "$BI" "$3"
  run "$BI" rx_branch_id "$2"
  assert_eq "$4" "$OUT" "branch_id $1: output"
  assert_eq "$5" "$RC" "branch_id $1: rc"
  assert_eq "" "$ERR" "branch_id $1: quiet"
}
bid_case "default pattern"      "feature/abc.1_x-2" 'test_cmd: true\n' "abc.1_x-2" 0
bid_case "base branch is never an id"  "main"  'branch_pattern: {id}\nbase_branch: main\n' "" 1
bid_case "custom base branch is never an id" "trunk" 'branch_pattern: {id}\nbase_branch: trunk\n' "" 1
bid_case "other branch with {id} alone" "work-1" 'branch_pattern: {id}\nbase_branch: main\n' "work-1" 0
bid_case "base_branch unset, {id} alone" "main" 'branch_pattern: {id}\n' "main" 0
bid_case "prefixed branch named like base" "feature/main" 'branch_pattern: feature/{id}\nbase_branch: main\n' "main" 0
bid_case "explicit pattern"     "feature/abc"       'branch_pattern: feature/{id}\n' "abc" 0
bid_case "wrong prefix"         "release/1"         'branch_pattern: feature/{id}\n' "" 1
bid_case "custom prefix+suffix" "wip/abc-x"         'branch_pattern: wip/{id}-x\n' "abc" 0
bid_case "suffix mismatch"      "wip/abc-y"         'branch_pattern: wip/{id}-x\n' "" 1
bid_case "{id} alone"           "2026-q4-sso"       'branch_pattern: {id}\n' "2026-q4-sso" 0
bid_case "no placeholder"       "feature/abc"       'branch_pattern: feature/abc\n' "" 1
bid_case "two placeholders"     "a/x/b/x"           'branch_pattern: a/{id}/b/{id}\n' "" 1
bid_case "slash in id"          "feature/foo/bar"   'branch_pattern: feature/{id}\n' "" 1
bid_case "id must start alnum"  "feature/_hidden"   'branch_pattern: feature/{id}\n' "" 1
bid_case "empty id"             "wip/-x"            'branch_pattern: wip/{id}-x\n' "" 1
bid_case "empty branch"         ""                  'branch_pattern: feature/{id}\n' "" 1
bid_case "pattern not a regex"  "featureXabc"       'branch_pattern: feature.{id}\n' "" 1
bid_case "regex chars literal"  "a+b/zed"           'branch_pattern: a+b/{id}\n' "zed" 0
bid_case "bare prefix"          "feature/"          'branch_pattern: feature/{id}\n' "" 1
rm -f "$BI/.rx/config.yml"
run "$BI" rx_branch_id feature/nocfg
assert_eq "nocfg" "$OUT" "branch_id works without config (default pattern)"
clobb="$(inrepo_eval "$BI" 'branch=B pattern=P prefix=X suffix=S id=I; rx_branch_id feature/q >/dev/null; echo "$branch$pattern$prefix$suffix$id"' 2>&1)"
assert_eq "BPXSI" "$clobb" "branch_id does not clobber caller variables"

# ---------- rx_state_get ----------
S="$(new_repo)"
mkdir -p "$S/specs/f1" "$S/specs/f2" "$S/specs/f3"
cat > "$S/specs/f1/state.md" <<'EOF'
---
feature: f1
phase: plan
status: awaiting-human
g1: approved:rex:2026-10-16
g2: none
g3: none
bump: none
next:   do: the thing
---
# State: f1

phase: not-frontmatter
EOF
printf '# no frontmatter\nphase: build\n' > "$S/specs/f2/state.md"
printf -- '---\nphase: build\nno closing marker\n' > "$S/specs/f3/state.md"
run "$S" rx_state_get f1 phase
assert_eq "plan" "$OUT" "state_get normal"
assert_eq "0" "$RC" "state_get normal rc"
run "$S" rx_state_get f1 g1
assert_eq "approved:rex:2026-10-16" "$OUT" "state_get value with colons"
run "$S" rx_state_get f1 next
assert_eq "do: the thing" "$OUT" "state_get trims and keeps inner colon"
run "$S" rx_state_get f1 status
assert_eq "awaiting-human" "$OUT" "state_get hyphenated value"
run "$S" rx_state_get f1 nokey
assert_eq "1" "$RC" "state_get missing key rc 1"
assert_eq "" "$OUT$ERR" "state_get missing key silent"
run "$S" rx_state_get nosuch phase
assert_eq "1" "$RC" "state_get missing file rc 1"
assert_eq "" "$OUT$ERR" "state_get missing file silent"
run "$S" rx_state_get f2 phase
assert_eq "1" "$RC" "state_get no frontmatter rc 1"
assert_eq "" "$OUT$ERR" "state_get no frontmatter silent"
run "$S" rx_state_get f3 phase
assert_eq "1" "$RC" "state_get unterminated frontmatter rc 1"
run "$S" rx_state_get ../x phase
assert_eq "1" "$RC" "state_get rejects path-like id"
mkdir -p "$S/sub"
run "$S/sub" rx_state_get f1 phase
assert_eq "plan" "$OUT" "state_get from a subdirectory"

# ---------- rx_valid_id / rx_id_branch ----------
for id in a A1 2026-10-16-add-health PROJ-123 a.b_c; do
  assert_exit 0 inrepo "$ROOT" rx_valid_id "$id"
done
for id in "" -a .a _a "a b" "a/b" "a;b" '$x' "../x" 'a*'; do
  assert_exit 1 inrepo "$ROOT" rx_valid_id "$id"
done
IB="$(new_repo)"
run "$IB" rx_id_branch 2026-10-16-add-health
assert_eq "feature/2026-10-16-add-health" "$OUT" "rx_id_branch: default pattern"; assert_eq "0" "$RC" "rx_id_branch: rc 0"
fixture_config "$IB" "branch_pattern=ft/{id}-wip"
run "$IB" rx_id_branch PROJ-1
assert_eq "ft/PROJ-1-wip" "$OUT" "rx_id_branch: custom pattern"
run "$IB" rx_branch_id "$OUT"
assert_eq "PROJ-1" "$OUT" "rx_id_branch round-trips through rx_branch_id"
run "$IB" rx_id_branch "a b"
assert_eq "1" "$RC" "rx_id_branch: invalid id"; assert_eq "" "$OUT" "rx_id_branch: invalid id prints nothing"
fixture_config "$IB" "branch_pattern=no-placeholder"
run "$IB" rx_id_branch x
assert_eq "1" "$RC" "rx_id_branch: pattern without {id}"
fixture_config "$IB" "branch_pattern={id}/{id}"
run "$IB" rx_id_branch x
assert_eq "1" "$RC" "rx_id_branch: pattern with two {id}"
fixture_config "$IB" "branch_pattern={id}"
run "$IB" rx_id_branch main
assert_eq "1" "$RC" "rx_id_branch: never maps an id onto base_branch"

# ---------- rx_state_valid ----------
V="$(new_repo)"
mkdir -p "$V/specs/real"
sed 's/^feature: .*/feature: real/' "$TPL_STATE" > "$V/specs/real/state.md"
run "$V" rx_state_valid real
assert_eq "0" "$RC" "real templates/state.md passes rx_state_valid"
assert_eq "" "$OUT$ERR" "valid state is silent"

# mkstate <id> <feature> <phase> <status> <g1> <g2> <g3> <bump> <next>
mkstate() {
  mkdir -p "$V/specs/$1"
  printf -- '---\nfeature: %s\nphase: %s\nstatus: %s\ng1: %s\ng2: %s\ng3: %s\nbump: %s\nnext: %s\n---\n# State\n' \
    "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" > "$V/specs/$1/state.md"
}
valid_case() { # <message> <expected-rc> <expected-err-or-empty> <id>
  run "$V" rx_state_valid "$4"
  assert_eq "$2" "$RC" "state_valid $1: rc"
  assert_eq "" "$OUT" "state_valid $1: stdout empty"
  assert_eq "$3" "$ERR" "state_valid $1: stderr"
}
mkstate ok1 ok1 done approved approved:rex:2026-10-16 approved:a.b-c:2026-01-02 none major "ship it"
valid_case "all enum values" 0 "" ok1
for p in intake requirements plan build verify close done; do
  mkstate "$p" "$p" "$p" draft none none none none n
  valid_case "phase $p" 0 "" "$p"
done
for s in draft awaiting-human approved blocked; do
  mkstate s s intake "$s" none none none none n
  valid_case "status $s" 0 "" s
done
for b in none patch minor major; do
  mkstate b b intake draft none none none "$b" n
  valid_case "bump $b" 0 "" b
done

valid_case "not found" 1 "state.md invalid: not found" nosuch
mkdir -p "$V/specs/nofm"; printf '# just a doc\nphase: build\n' > "$V/specs/nofm/state.md"
valid_case "no frontmatter" 1 "state.md invalid: no frontmatter" nofm
mkdir -p "$V/specs/unterm"; printf -- '---\nfeature: u\nphase: build\n' > "$V/specs/unterm/state.md"
valid_case "unterminated frontmatter" 1 "state.md invalid: no frontmatter" unterm
mkdir -p "$V/specs/empty"; : > "$V/specs/empty/state.md"
valid_case "empty file" 1 "state.md invalid: no frontmatter" empty

for k in feature phase status g1 g2 g3 bump next; do
  mkstate m m intake draft none none none none n
  grep -v "^$k:" "$V/specs/m/state.md" > "$V/specs/m/state.tmp" && mv "$V/specs/m/state.tmp" "$V/specs/m/state.md"
  valid_case "missing $k" 1 "state.md invalid: missing key $k" m
done
# keys in a different order still validate
mkdir -p "$V/specs/ord"
printf -- '---\nnext: n\nbump: none\ng3: none\ng2: none\ng1: none\nstatus: draft\nphase: plan\nfeature: ord\n---\n' > "$V/specs/ord/state.md"
valid_case "order not enforced" 0 "" ord
# a key outside the frontmatter does not count
mkdir -p "$V/specs/out"
printf -- '---\nfeature: o\nphase: plan\nstatus: draft\ng1: none\ng2: none\nbump: none\nnext: n\n---\ng3: none\n' > "$V/specs/out/state.md"
valid_case "key outside frontmatter" 1 "state.md invalid: missing key g3" out

mkstate bad bad foo draft none none none none n
valid_case "bad phase" 1 "state.md invalid: unknown phase 'foo'" bad
mkstate bad bad intake Draft none none none none n
valid_case "bad status" 1 "state.md invalid: unknown status 'Draft'" bad
mkstate bad bad intake draft yes none none none n
valid_case "bad g1" 1 "state.md invalid: bad g1 'yes'" bad
mkstate bad bad intake draft none approved:rex none none n
valid_case "gate missing date" 1 "state.md invalid: bad g2 'approved:rex'" bad
mkstate bad bad intake draft none none approved:rex:2026-1-1 none n
valid_case "gate bad date" 1 "state.md invalid: bad g3 'approved:rex:2026-1-1'" bad
mkstate bad bad intake draft approved::2026-10-16 none none none n
valid_case "gate empty approver" 1 "state.md invalid: bad g1 'approved::2026-10-16'" bad
mkstate bad bad intake draft "approved:rex smith:2026-10-16" none none none n
valid_case "gate approver with space" 1 "state.md invalid: bad g1 'approved:rex smith:2026-10-16'" bad
mkstate bad bad intake draft approved:a:b:2026-10-16 none none none n
valid_case "gate approver with colon" 1 "state.md invalid: bad g1 'approved:a:b:2026-10-16'" bad
mkstate bad bad intake draft none none none Major n
valid_case "bad bump" 1 "state.md invalid: unknown bump 'Major'" bad
mkstate bad bad intake draft none none none none ""
valid_case "empty next" 1 "state.md invalid: empty next" bad
mkstate bad "" intake draft none none none none n
valid_case "empty feature" 1 "state.md invalid: empty feature" bad
valid_case "path-like id" 1 "state.md invalid: not found" ../real
mkstate mis other intake draft none none none none n
valid_case "feature differs from the directory id" 1 "state.md invalid: feature 'other' does not match directory 'mis'" mis
# exactly one stderr line
run "$V" rx_state_valid bad
assert_eq "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" "state_valid prints a single line"

# ---------- rx_run_timeout ----------
RT="$(cd "$(fixture_tmpdir)" && pwd -P)"
RTO="$RT/out"
NLX=$'\n'
# rt <seconds> <command-string>: runs rx_run_timeout in $RT; sets RC, ELAPSED; output in $RTO.
rt() {
  local t0=$SECONDS
  ( cd "$RT" && . "$LIB" && rx_run_timeout "$1" "$RTO" "$2"; rc=$?; printf '%s' "$RX_RT_STATE" > "$RT.state"; exit $rc ) 2>"$RT/rt.err"
  RC=$?
  RTSTATE="$(cat "$RT.state" 2>/dev/null)"
  rm -f "$RT.state"
  ELAPSED=$((SECONDS - t0))
}
rt 5 'echo hello; echo oops >&2'
assert_eq "0" "$RC" "rx_run_timeout: success status"
assert_eq "hello${NLX}oops" "$(cat "$RTO")" "rx_run_timeout: stdout and stderr captured"
assert_eq "" "$(cat "$RT/rt.err")" "rx_run_timeout: nothing on the caller's stderr"
rt 5 'echo partial; exit 7'
assert_eq "7" "$RC" "rx_run_timeout: failure status passed through"
assert_eq "partial" "$(cat "$RTO")" "rx_run_timeout: output of a failing command"
rt 5 'kill -9 $$'
assert_eq "137" "$RC" "rx_run_timeout: death by signal is the shell status, not 124"
rt 5 'pwd; cat; echo stdin-closed'
assert_eq "$RT${NLX}stdin-closed" "$(cat "$RTO")" "rx_run_timeout: runs in the current dir with stdin at EOF"
rt 5 'exit 124'
assert_eq "124" "$RC" "rx_run_timeout: command exit status 124 is passed through as is"
printf 'old\n' > "$RTO"
rt 5 'true'
assert_eq "" "$(cat "$RTO")" "rx_run_timeout: outfile is truncated"
rt 5 'printf "a b\n  \$x \"q\" '"'"'s'"'"'\n"'
assert_eq "a b${NLX}  \$x \"q\" 's'" "$(cat "$RTO")" "rx_run_timeout: command string is passed verbatim"
assert_eq "" "$(ls "$RT" | grep -v -E '^(out|rt.err)$')" "rx_run_timeout: no stray files next to the outfile"
assert_eq "ran" "$RTSTATE" "rx_run_timeout: RX_RT_STATE is ran after a normal run"
rt 5 'exit 124'
assert_eq "124" "$RC" "rx_run_timeout: a command's own 124 is passed through"
assert_eq "ran" "$RTSTATE" "rx_run_timeout: a command's own 124 is not a timeout"
rt 5 'exit 2'
assert_eq "ran" "$RTSTATE" "rx_run_timeout: a command's own 2 is not a usage error"
( cd "$RT" && . "$LIB" && rx_run_timeout 5 "$RT/nodir/out" true; rc=$?; printf '%s %s' "$rc" "$RX_RT_STATE" > "$RT.state" ) 2>"$RT/rt.err"
assert_eq "1 error" "$(cat "$RT.state")" "rx_run_timeout: unwritable outfile is state error"
assert_contains "$(cat "$RT/rt.err")" "cannot write" "rx_run_timeout: unwritable outfile message"
rm -f "$RT.state"

# timeout: 124 shortly after the limit, output so far kept, whole tree gone
rm -f "$RT/pid1" "$RT/pid2"
rt 1 'echo before; sh -c "sleep 31 & echo \$! > '"$RT"'/pid1; wait" & sh -c "sh -c \"sleep 32 & echo \\\$! > '"$RT"'/pid2; wait\"" & wait'
assert_eq "124" "$RC" "rx_run_timeout: timeout status"
assert_eq "timeout" "$RTSTATE" "rx_run_timeout: RX_RT_STATE is timeout after a timeout"
[ "$ELAPSED" -le 3 ] || _rx_fail "rx_run_timeout: timeout took ${ELAPSED}s (limit 1s)"
assert_eq "before" "$(cat "$RTO")" "rx_run_timeout: output written before the timeout is kept"
for pf in pid1 pid2; do
  kill -0 "$(cat "$RT/$pf" 2>/dev/null || echo 999999)" 2>/dev/null \
    && _rx_fail "rx_run_timeout: orphan from $pf survived the timeout"
  [ -s "$RT/$pf" ] || _rx_fail "rx_run_timeout: $pf was never written (test setup)"
done
assert_eq "" "$(ls "$RT" | grep -v -E '^(out|rt.err|pid1|pid2|kids)$')" "rx_run_timeout: flag file removed after a timeout"

# no watcher left after a normal run either (the limit is a marker value to find it by)
rt 41 'true'
assert_eq "0" "$RC" "rx_run_timeout: quick command with a long limit"
[ "$ELAPSED" -le 2 ] || _rx_fail "rx_run_timeout: quick command took ${ELAPSED}s"
kids="$(bash -c ". '$LIB'; rx_run_timeout 42 '$RTO' true; pgrep -P \$\$ > '$RT/kids'; wc -l < '$RT/kids'" | tr -d ' ')"
assert_eq "0" "$kids" "rx_run_timeout: no child process left behind (normal run)"
kids="$(bash -c ". '$LIB'; rx_run_timeout 1 '$RTO' 'sleep 30'; pgrep -P \$\$ > '$RT/kids'; wc -l < '$RT/kids'" | tr -d ' ')"
assert_eq "0" "$kids" "rx_run_timeout: no child process left behind (timeout)"

# usage errors
rt 0 true
assert_eq "2" "$RC" "rx_run_timeout: 0 seconds is a usage error"
assert_contains "$(cat "$RT/rt.err")" "positive integer" "rx_run_timeout: usage message"
assert_eq "usage" "$RTSTATE" "rx_run_timeout: RX_RT_STATE is usage on a usage error"
rt abc true
assert_eq "2" "$RC" "rx_run_timeout: non-numeric seconds is a usage error"
rt "" true
assert_eq "2" "$RC" "rx_run_timeout: empty seconds is a usage error"
( cd "$RT" && . "$LIB" && rx_run_timeout 5 "" true ) 2>/dev/null
assert_eq "2" "$?" "rx_run_timeout: empty outfile is a usage error"

# caller state: options, traps, variables, monitor mode
state_probe='
  trap "echo caller-int" INT
  trap "echo caller-term" TERM
  trap "echo caller-hup" HUP
  trap "echo caller-quit" QUIT
  pid=P wpid=W rc=R secs=S out=O cmd=C had_m=H flag=F old_int=I old_term=T
  b_o="$(set +o)"; b_t="$(trap -p)"; b_m="${-//[^m]/}"
  rx_run_timeout 1 "'"$RTO"'" "sleep 30" ; r1=$?
  rx_run_timeout 5 "'"$RTO"'" "exit 3"; r2=$?
  a_o="$(set +o)"; a_t="$(trap -p)"; a_m="${-//[^m]/}"
  [ "$b_o" = "$a_o" ] && echo opts-same || echo opts-DIFF
  [ "$b_t" = "$a_t" ] && echo traps-same || echo traps-DIFF
  [ "$b_m" = "$a_m" ] && echo monitor-same || echo monitor-DIFF
  echo "$r1 $r2 $pid$wpid$rc$secs$out$cmd$had_m$flag$old_int$old_term"
'
got="$(bash -c ". '$LIB'; $state_probe" 2>&1)"
assert_eq "opts-same${NLX}traps-same${NLX}monitor-same${NLX}124 3 PWRSOCHFIT" "$got" "rx_run_timeout leaves options, traps, monitor mode and variables alone"
got="$(bash -c ". '$LIB'; set -m; $state_probe" 2>&1)"
assert_eq "opts-same${NLX}traps-same${NLX}monitor-same${NLX}124 3 PWRSOCHFIT" "$got" "rx_run_timeout with monitor mode already on"
got="$(bash -c ". '$LIB'; set -eu; rx_run_timeout 5 '$RTO' 'exit 4' || echo \"rc=\$?\"; rx_run_timeout 1 '$RTO' 'sleep 30' || echo \"rc=\$?\"" 2>&1)"
assert_eq "rc=4${NLX}rc=124" "$got" "rx_run_timeout under set -eu returns the status (callers guard it)"

# a TERM or HUP to the caller kills the command's group too, and the caller dies of the signal
# (INT and QUIT are handled the same way, but background jobs of a non-interactive shell ignore
# them from the start, so they cannot be exercised from here)
for sig in TERM HUP; do
  rm -f "$RT/pidt" "$RT/survived"
  bash -c ". '$LIB'; rx_run_timeout 30 '$RTO' 'sleep 35 & echo \$! > $RT/pidt; wait'; echo survived > '$RT/survived'" </dev/null >/dev/null 2>&1 &
  tp=$!
  n=0
  while [ ! -s "$RT/pidt" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  kill -s "$sig" "$tp"
  wait "$tp" 2>/dev/null
  sleep 0.3
  kill -0 "$(cat "$RT/pidt" 2>/dev/null || echo 999999)" 2>/dev/null \
    && _rx_fail "rx_run_timeout: command survived a $sig to its caller"
  [ -e "$RT/survived" ] && _rx_fail "rx_run_timeout: caller kept running after $sig"
done

# ---------- locale helpers ----------
got="$(LC_ALL=en_US.UTF-8 bash -c ". '$LIB'; rx_locale_c; echo \$LC_ALL; rx_locale_c; rx_locale_user; echo \$LC_ALL; rx_locale_c; echo \$LC_ALL" 2>&1)"
assert_eq "C${NLX}en_US.UTF-8${NLX}C" "$got" "rx_locale_c / rx_locale_user round trip (LC_ALL set), idempotent save"
got="$(env -u LC_ALL bash -c ". '$LIB'; rx_locale_c; echo \$LC_ALL; rx_locale_user; echo \"[\${LC_ALL+set}]\"; rx_locale_c; rx_locale_user; echo \"[\${LC_ALL+set}]\"" 2>&1)"
assert_eq "C${NLX}[]${NLX}[]" "$got" "rx_locale_user unsets LC_ALL when the caller had none"

# ---------- source hygiene ----------
H="$(new_repo)"
out="$(inrepo_eval "$H" 'echo x' 2>&1)"
assert_eq "x" "$out" "sourcing prints nothing"
before="$(bash -c 'set +o' 2>/dev/null)"
after="$(bash -c ". '$LIB'; set +o" 2>&1)"
assert_eq "$before" "$after" "sourcing leaves set -o options unchanged"
after_i="$(bash -c 'IFS=:; cd /; p=$PWD; . "'"$LIB"'"; [ "$IFS" = ":" ] && [ "$PWD" = "$p" ] && echo same' 2>&1)"
assert_eq "same" "$after_i" "sourcing leaves IFS and cwd alone"
trap_out="$(bash -c 'trap "echo T" INT; trap "echo E" EXIT; . "'"$LIB"'"; trap -p' 2>&1)"
assert_contains "$trap_out" "echo T" "sourcing keeps caller INT trap"
assert_contains "$trap_out" "echo E" "sourcing keeps caller EXIT trap"
names="$(bash -c '
  compgen -A function | sort > "'"$H"'/pre_f"; compgen -v | sort > "'"$H"'/pre_v"
  . "'"$LIB"'"
  compgen -A function | sort > "'"$H"'/post_f"; compgen -v | sort > "'"$H"'/post_v"
' 2>&1)"
assert_eq "" "$names" "name-listing probe is quiet"
newf="$(comm -13 "$H/pre_f" "$H/post_f")"
newv="$(comm -13 "$H/pre_v" "$H/post_v")"
assert_eq "" "$(printf '%s\n' "$newf" | grep -v -E '^(rx_|_rx_)[A-Za-z0-9_]*$' | grep -v '^$')" "lib defines only rx_/_rx_ functions"
assert_eq "" "$(printf '%s\n' "$newv" | grep -v -E '^RX_[A-Za-z0-9_]*$' | grep -v '^$')" "lib defines only RX_ variables"
assert_contains "$newf" "rx_feature_id" "probe saw the lib's functions"

# strict-mode callers: no unbound-variable or errexit surprises
strict="$(inrepo_eval "$R" 'set -eu; rx_cfg nokey >/dev/null; rx_cfg test_cmd dflt >/dev/null; rx_enabled; rx_root >/dev/null; rx_feature_id || true; rx_state_get nosuch phase || true; rx_state_valid nosuch 2>/dev/null || true; echo done' 2>&1)"
assert_eq "done" "$strict" "functions behave under set -eu"

# functions do not clobber caller variables
clob="$(inrepo_eval "$F" 'key=K def=D file=F line=L v=V d=DD id=I branch=B pattern=P; rx_cfg branch_pattern x >/dev/null; rx_feature_id >/dev/null; rx_state_get f1 phase >/dev/null; rx_state_valid f1 2>/dev/null; echo "$key$def$file$line$v$d$id$branch$pattern"' 2>&1)"
assert_eq "KDFLVDDIBP" "$clob" "functions do not clobber caller variables"

[ "$RX_FAILS" -eq 0 ] && echo "test_lib: ok"
exit 0
