#!/usr/bin/env bash
# rx-status.sh [--all]: read-only dashboard for the active rx feature. No LLM, no network.
#   - active block: feature, phase (status), gates, bump, task progress, next
#   - --all: one line per remote feature branch, read from the origin/* remote-tracking
#     refs with `git show` (nothing is checked out, nothing is fetched)
#   - one warning line when .rx/scripts is older than the plugin that shipped it
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/rx-lib.sh"
rx_noop_unless_enabled

ALL=0
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    *)
      printf 'usage: rx-status.sh [--all]\n' >&2
      exit 2
      ;;
  esac
done

ROOT="$(rx_root)"

# _st_counts: read tasks.md text on stdin; print "<done> <total>". Tolerates CRLF
# and a missing final newline.
_st_counts() {
  local text d t
  text="$(tr -d '\r')"
  t="$(printf '%s\n' "$text" | grep -Ec '^- \[[ x]\] T-[0-9]+')"
  d="$(printf '%s\n' "$text" | grep -Ec '^- \[x\] T-[0-9]+')"
  printf '%s %s\n' "${d:-0}" "${t:-0}"
}

# _st_frac <done> <total>: print done/total.
_st_frac() { printf '%s/%s' "$1" "$2"; }

# _st_remote_line <marker> <id> <branch>: one --all line for origin/<branch>.
_st_remote_line() {
  local marker="$1" id="$2" branch="$3" ref fm phase status g1 g2 g3 tasks counts
  ref="refs/remotes/origin/$branch"
  fm="$(git -C "$ROOT" show "$ref:specs/$id/state.md" 2>/dev/null | _rx_fm /dev/stdin)" || fm=""
  phase="$(_rx_fm_get "$fm" phase)" || phase=""
  status="$(_rx_fm_get "$fm" status)" || status=""
  g1="$(_rx_fm_get "$fm" g1)" || g1=""
  g2="$(_rx_fm_get "$fm" g2)" || g2=""
  g3="$(_rx_fm_get "$fm" g3)" || g3=""
  if [ -z "$fm" ] || [ -z "$phase" ] || [ -z "$status" ] || [ -z "$g1" ] || [ -z "$g2" ] || [ -z "$g3" ]; then
    printf '%s %s  (no state.md)\n' "$marker" "$id"
    return 0
  fi
  if tasks="$(git -C "$ROOT" show "$ref:specs/$id/tasks.md" 2>/dev/null)"; then
    counts="$(printf '%s' "$tasks" | _st_counts)"
    tasks="$(_st_frac "${counts% *}" "${counts#* }")"
  else
    tasks="-"
  fi
  printf '%s %s  %s/%s  %s  g1=%s g2=%s g3=%s\n' "$marker" "$id" "$phase" "$status" "$tasks" "$g1" "$g2" "$g3"
}

# _st_all <active-id-or-empty>: the --all section (prints nothing if no matches).
_st_all() {
  local active="$1" ref branch id nl tab pairs sorted marker
  tab="$(printf '\t')"
  nl=$'\n'
  git -C "$ROOT" remote 2>/dev/null | grep -qx origin || return 0
  pairs=""
  while IFS= read -r ref; do
    case "$ref" in
      origin/*) branch="${ref#origin/}" ;;
      *) continue ;;
    esac
    [ "$branch" = "HEAD" ] && continue
    id="$(rx_branch_id "$branch")" || continue
    pairs="${pairs}${id}${tab}${branch}${nl}"
  done <<EOF
$(git -C "$ROOT" for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null)
EOF
  [ -n "$pairs" ] || return 0
  sorted="$(printf '%s' "$pairs" | LC_ALL=C sort -t "$tab" -k1,1)"
  printf '\n'
  while IFS="$tab" read -r id branch; do
    marker=" "
    [ -n "$active" ] && [ "$id" = "$active" ] && marker="*"
    _st_remote_line "$marker" "$id" "$branch"
  done <<EOF
$sorted
EOF
}

# _st_stale: one warning line iff the plugin copy and .rx/scripts/.rx-version differ.
_st_stale() {
  local pj="$SCRIPT_DIR/../.claude-plugin/plugin.json" vf="$ROOT/.rx/scripts/.rx-version"
  local line="" have want
  [ -f "$pj" ] && [ -f "$vf" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  want="$(jq -r .version "$pj" 2>/dev/null)" || return 0
  want="$(_rx_trim "${want%$'\r'}")"
  { [ -n "$want" ] && [ "$want" != "null" ]; } || return 0
  IFS= read -r line < "$vf" || true
  have="$(_rx_trim "${line%$'\r'}")"
  if [ "$have" != "$want" ]; then
    printf 'warning: .rx/scripts is v%s, plugin is v%s; run /rx:init --refresh-scripts\n' "$have" "$want"
  fi
  return 0
}

ACTIVE=""
if ACTIVE="$(rx_feature_id)"; then
  msg="$(rx_state_valid "$ACTIVE" 2>&1)" || {
    printf '%s\n' "$msg"
    exit 1
  }
  tasks_file="$ROOT/specs/$ACTIVE/tasks.md"
  if [ -f "$tasks_file" ]; then
    counts="$(_st_counts < "$tasks_file")"
    tasks="$(_st_frac "${counts% *}" "${counts#* }")"
  else
    tasks="-"
  fi
  printf 'feature: %s\n' "$ACTIVE"
  printf 'phase:   %s (%s)\n' "$(rx_state_get "$ACTIVE" phase)" "$(rx_state_get "$ACTIVE" status)"
  printf 'gates:   g1=%s g2=%s g3=%s\n' "$(rx_state_get "$ACTIVE" g1)" "$(rx_state_get "$ACTIVE" g2)" "$(rx_state_get "$ACTIVE" g3)"
  printf 'bump:    %s\n' "$(rx_state_get "$ACTIVE" bump)"
  printf 'tasks:   %s\n' "$tasks"
  printf 'next:    %s\n' "$(rx_state_get "$ACTIVE" next)"
else
  ACTIVE=""
  printf 'no active feature\n'
fi

[ "$ALL" -eq 1 ] && _st_all "$ACTIVE"
_st_stale
exit 0
