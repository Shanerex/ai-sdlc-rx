#!/usr/bin/env bash
# rx-check.sh <specs|shared|done> [feature-id]: deterministic gates for the rx toolkit.
# No LLM, no network. Used by /rx:next, pre-commit and CI.
#   specs [feature-id]  spec-file hygiene: line caps, required headings, frontmatter,
#                       ID uniqueness, task line format, tasks cite existing ACs
#   shared [feature-id] merge-safety: a feature branch (base_branch...HEAD, plus staged,
#                       unstaged and untracked changes) may only touch code, its own
#                       specs/<id>/ and NEW files under docs/knowledge/{decisions,learnings}/
#   done                (not implemented yet)
# Exit codes: 0 clean, 1 violations (one `<path>: <reason>` line each on stdout),
# 2 usage or install error (message on stderr).
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.
# Each subcommand is a function _chk_<name> in this file; add new ones to the
# dispatcher at the bottom.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-check: rx-lib.sh not found\n' >&2
  exit 2
fi
# The checks are byte-oriented: under a UTF-8 locale BSD tr/sed abort at the first
# invalid byte and bash =~ fails on it, which would turn into false passes/fails.
export LC_ALL=C
rx_noop_unless_enabled

_chk_usage() {
  printf 'usage: rx-check.sh <specs|shared|done> [feature-id]\n' >&2
  exit 2
}

_chk_not_implemented() {
  printf "rx-check: '%s' not implemented\n" "$1" >&2
  exit 2
}

# ---------------------------------------------------------------- specs

# Files checked per feature dir, in report order (only those present).
CHK_FILES="state.md requirements.md plan.md tasks.md review.md quick.md review.qa.md review.security.md"

# _chk_cap <file>: print the line cap for a spec file name (mirrors rx-spec SKILL.md).
_chk_cap() {
  case "$1" in
    state.md) echo 30 ;;
    requirements.md) echo 60 ;;
    plan.md) echo 100 ;;
    tasks.md) echo 40 ;;
    review.md) echo 60 ;;
    quick.md) echo 30 ;;
    review.qa.md) echo 30 ;;
    review.security.md) echo 30 ;;
    *) echo 0 ;;
  esac
}

# _chk_tpl_find <file>: set TPL_PATH to the template for spec file <file> and return 0,
# or return 1 when it cannot be found. The template DIRECTORY is the first candidate
# that exists, in order: $RX_TEMPLATES (if set), <script-dir>/../skills/rx-spec/templates,
# <script-dir>/templates (.rx/scripts copy). Only that directory is used: a template
# missing from it is "not found" (no per-file fallback, so a broken override cannot be
# masked). review.qa.md and review.security.md have no template: that is not an error
# (TPL_PATH stays empty, return 0).
TPL_DIR=""
_chk_tpl_find() {
  local dir
  TPL_PATH=""
  case "$1" in
    review.qa.md|review.security.md) return 0 ;;
  esac
  if [ -z "$TPL_DIR" ]; then
    for dir in "${RX_TEMPLATES-}" "$SCRIPT_DIR/../skills/rx-spec/templates" "$SCRIPT_DIR/templates"; do
      [ -n "$dir" ] || continue
      if [ -d "$dir" ]; then
        TPL_DIR="$dir"
        break
      fi
    done
  fi
  [ -n "$TPL_DIR" ] || return 1
  [ -f "$TPL_DIR/$1" ] || return 1
  TPL_PATH="$TPL_DIR/$1"
  return 0
}

# _chk_v <file> <reason>: record a violation line for the current feature.
_chk_v() {
  VIOL="${VIOL}specs/${CUR_ID}/${1}: ${2}"$'\n'
}

# _chk_ids <AC|R> <file>: print the ids (e.g. AC-1) of the `- AC-n:` / `- R-n:` lines.
_chk_ids() {
  local line id
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "- $1-"[0-9]*:*)
        id="${line#- }"
        id="${id%%:*}"
        case "$id" in
          "$1-"*[!0-9]*) ;;
          *) printf '%s\n' "$id" ;;
        esac
        ;;
    esac
  done < "$CUR_DIR/$2"
}

# _chk_one_file <file>: caps, headings, frontmatter, then ID rules for that file.
# Uses/updates the per-feature globals: VIOL, SEEN_AC, SEEN_R, SEEN_T, ALL_AC.
_chk_one_file() {
  local f="$1" path="$CUR_DIR/$1" cap n fm st msg heads h line id cites a rest
  local task_re='^- \[[ x]\] T-[0-9]+ \(AC-[0-9]+(, AC-[0-9]+)*\): .+'
  local trig_re='^[[:space:]]*[-*+][[:space:]]+\[[^]]*\][[:space:]]*T-'

  # line cap: CR stripped, an unterminated last line counts (awk NR does both)
  cap="$(_chk_cap "$f")"
  n="$(tr -d '\r' < "$path" | awk 'END { print NR }')"
  if [ "$n" -gt "$cap" ]; then
    _chk_v "$f" "$n lines exceeds cap $cap"
  fi

  # frontmatter
  if [ "$f" = "state.md" ]; then
    msg="$(rx_state_valid "$CUR_ID" 2>&1)" || _chk_v "$f" "${msg#state.md invalid: }"
  else
    if fm="$(_rx_fm "$path")"; then
      st="$(_rx_fm_get "$fm" status)" || st=""
      case "$st" in
        draft|final) ;;
        *) _chk_v "$f" "frontmatter status must be draft|final" ;;
      esac
    else
      _chk_v "$f" "missing frontmatter"
    fi
  fi

  # required headings, derived from the template
  if ! _chk_tpl_find "$f"; then
    printf 'rx-check: rx-spec templates not found\n' >&2
    exit 2
  fi
  if [ -n "$TPL_PATH" ]; then
    heads="$(tr -d '\r' < "$path" | sed 's/[[:space:]]*$//' | grep '^## ')"
    while IFS= read -r h || [ -n "$h" ]; do
      h="${h%$'\r'}"
      h="$(printf '%s' "$h" | sed 's/[[:space:]]*$//')"
      case "$h" in
        '## '*) ;;
        *) continue ;;
      esac
      printf '%s\n' "$heads" | grep -Fxq -- "$h" || _chk_v "$f" "missing heading '$h'"
    done < "$TPL_PATH"
  fi

  # IDs: AC and R lines, task lines
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "- AC-"[0-9]*:*)
        case "$f" in
          requirements.md|quick.md)
            id="${line#- }"
            id="${id%%:*}"
            case "$id" in
              AC-*[!0-9]*) ;;
              *)
                case "$SEEN_AC" in
                  *"|$id|"*) _chk_v "$f" "duplicate $id" ;;
                  *) SEEN_AC="${SEEN_AC}|${id}|" ;;
                esac
                ;;
            esac
            ;;
        esac
        ;;
      "- R-"[0-9]*:*)
        if [ "$f" = "requirements.md" ]; then
          id="${line#- }"
          id="${id%%:*}"
          case "$id" in
            R-*[!0-9]*) ;;
            *)
              case "$SEEN_R" in
                *"|$id|"*) _chk_v "$f" "duplicate $id" ;;
                *) SEEN_R="${SEEN_R}|${id}|" ;;
              esac
              ;;
          esac
        fi
        ;;
    esac
    # task lines (tasks.md, quick.md): the trigger is wide so near misses cannot hide,
    # the format is strict; only well-formed lines take part in the id checks
    case "$f" in
      tasks.md|quick.md)
        if [[ $line =~ $trig_re ]]; then
          if [[ $line =~ $task_re ]]; then
            rest="${line#*T-}"
            id="T-${rest%% *}"
            case "$SEEN_T" in
              *"|$id|"*) _chk_v "$f" "duplicate $id" ;;
              *) SEEN_T="${SEEN_T}|${id}|" ;;
            esac
            cites="${line#*\(}"
            cites="${cites%%\)*}"
            cites="${cites//,/ }"
            for a in $cites; do
              case "$ALL_AC" in
                *"|$a|"*) ;;
                *) _chk_v "$f" "$id cites unknown $a" ;;
              esac
            done
          else
            _chk_v "$f" "malformed task line '${line:0:40}'"
          fi
        fi
        ;;
    esac
  done < "$path"
}

# _chk_feature <id>: check one feature dir, appending to VIOL.
_chk_feature() {
  local f ac
  CUR_ID="$1"
  CUR_DIR="$CHK_ROOT/specs/$1"
  if [ ! -d "$CUR_DIR" ]; then
    VIOL="${VIOL}specs/${CUR_ID}: not found"$'\n'
    return 0
  fi
  if ! _rx_valid_id "$CUR_ID"; then
    VIOL="${VIOL}specs/${CUR_ID}: invalid feature id"$'\n'
    return 0
  fi
  [ -f "$CUR_DIR/state.md" ] || _chk_v "state.md" "not found"
  SEEN_AC=""
  SEEN_R=""
  SEEN_T=""
  ALL_AC=""
  # every AC the feature defines (requirements.md + quick.md), needed before tasks are read
  for f in requirements.md quick.md; do
    [ -f "$CUR_DIR/$f" ] || continue
    while IFS= read -r ac; do
      [ -n "$ac" ] && ALL_AC="${ALL_AC}|${ac}|"
    done <<EOF
$(_chk_ids AC "$f")
EOF
  done
  for f in $CHK_FILES; do
    [ -f "$CUR_DIR/$f" ] || continue
    _chk_one_file "$f"
  done
}

# _chk_specs [feature-id]
_chk_specs() {
  local id name
  CHK_ROOT="$(rx_root)"
  VIOL=""
  if [ "$#" -gt 1 ]; then
    _chk_usage
  fi
  if [ "$#" -eq 1 ]; then
    if ! _rx_valid_id "$1"; then
      printf "rx-check: invalid feature id '%s'\n" "$1" >&2
      exit 2
    fi
    id="$1"
  else
    id="$(rx_feature_id)" || id=""
  fi

  if [ -n "$id" ]; then
    _chk_feature "$id"
  elif [ -d "$CHK_ROOT/specs" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      [ -d "$CHK_ROOT/specs/$name" ] || continue
      _chk_feature "$name"
    done <<EOF
$(ls -1 "$CHK_ROOT/specs" 2>/dev/null | LC_ALL=C sort)
EOF
  fi

  if [ -n "$VIOL" ]; then
    printf '%s' "$VIOL"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- shared

# _chk_sv <path> <reason>: record a violation (sorted by path then reason, de-duplicated).
# Kept in a bash array with insertion sort: paths may contain any byte but NUL,
# newlines included, so no line-oriented tool can be used here.
SH_KEYS=()
SH_US=$'\001'
_chk_sv() {
  local key="$1$SH_US$2" i=0 n j
  n=${#SH_KEYS[@]}
  while [ "$i" -lt "$n" ] && [[ "${SH_KEYS[$i]}" < "$key" ]]; do
    i=$((i + 1))
  done
  if [ "$i" -lt "$n" ] && [ "${SH_KEYS[$i]}" = "$key" ]; then
    return 0
  fi
  j=$n
  while [ "$j" -gt "$i" ]; do
    SH_KEYS[$j]="${SH_KEYS[$((j - 1))]}"
    j=$((j - 1))
  done
  SH_KEYS[$i]="$key"
}

# _chk_shared_rule <status> <path> <lowercased-path>: record a violation for one changed
# path, if it breaks a rule. First matching rule wins. Matching of the protected NAMES
# is case-insensitive (a branch must not slip CLAUDE.md past the gate as claude.md); the
# exceptions (.rx/local/, own specs dir, new knowledge entries) need the exact case.
# Uses SH_ID, SH_ROOT, SH_REF and SH_VF (lowercased version_file, may be empty).
_chk_shared_rule() {
  local p="$2" lp="$3" rest name
  case "$lp" in
    claude.md|agents.md|docs/knowledge/architecture.md)
      _chk_sv "$p" "shared file modified"
      return 0
      ;;
    .rx)
      _chk_sv "$p" "shared file modified"
      return 0
      ;;
    .rx/*)
      case "$p" in
        .rx/local/*) ;;
        *) _chk_sv "$p" "shared file modified" ;;
      esac
      return 0
      ;;
  esac
  if [ -n "$SH_VF" ] && [ "$lp" = "$SH_VF" ]; then
    _chk_sv "$p" "shared file modified"
    return 0
  fi
  case "$lp" in
    docs/knowledge|docs/knowledge/*)
      # Allowed: a file docs/knowledge/{decisions,learnings}/<name>.md (single level) that
      # the base does not have. Judged against the base tree, not by the status letter, so
      # a new entry that is edited again before the next commit (A then M) stays new, while
      # an existing entry never passes whatever happened to it.
      case "$p" in
        docs/knowledge/decisions/*.md|docs/knowledge/learnings/*.md)
          name="${p#docs/knowledge/*/}"
          case "$name" in
            */*|.md) ;;
            *)
              if ! git -C "$SH_ROOT" cat-file -e "$SH_REF:$p" 2>/dev/null; then
                return 0
              fi
              ;;
          esac
          ;;
      esac
      _chk_sv "$p" "only new decision/learning files may be added under docs/knowledge/"
      return 0
      ;;
    specs)
      _chk_sv "$p" "shared file modified"
      return 0
      ;;
    specs/*)
      case "$p" in
        specs/*)
          rest="${p#specs/}"
          case "$rest" in
            */*)
              [ "${rest%%/*}" = "$SH_ID" ] || _chk_sv "$p" "another feature's spec modified"
              ;;
            *) _chk_sv "$p" "shared file modified" ;;
          esac
          ;;
        *) _chk_sv "$p" "another feature's spec modified" ;;
      esac
      return 0
      ;;
  esac
  return 0
}

# _chk_shared [feature-id]
_chk_shared() {
  local id base ref cur tmp st p lp i n key vf
  if [ "$#" -gt 1 ]; then
    _chk_usage
  fi
  SH_ROOT="$(rx_root)"
  if ! git -C "$SH_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'rx-check: not a git repository\n' >&2
    exit 2
  fi
  base="$(rx_require_cfg base_branch)" || exit 2
  if [ "$#" -eq 1 ]; then
    if ! _rx_valid_id "$1"; then
      printf "rx-check: invalid feature id '%s'\n" "$1" >&2
      exit 2
    fi
    id="$1"
  else
    id="$(rx_feature_id)" || id=""
    if [ -z "$id" ]; then
      cur="$(git -C "$SH_ROOT" symbolic-ref --short -q HEAD 2>/dev/null)" || cur=""
      if [ "$cur" = "$base" ]; then
        return 0
      fi
      printf 'rx-check: shared needs a feature id (none resolved); pass one explicitly\n' >&2
      exit 2
    fi
  fi
  SH_ID="$id"

  # base ref: the local branch, else origin/<base>; never diff against nothing
  if git -C "$SH_ROOT" rev-parse --verify -q "refs/heads/$base^{commit}" >/dev/null 2>&1; then
    ref="refs/heads/$base"
  elif git -C "$SH_ROOT" rev-parse --verify -q "refs/remotes/origin/$base^{commit}" >/dev/null 2>&1; then
    ref="refs/remotes/origin/$base"
  else
    printf "rx-check: base branch '%s' not found\n" "$base" >&2
    exit 2
  fi
  SH_REF="$ref"

  vf="$(rx_cfg version_file)"
  vf="${vf#./}"
  SH_VF="$(printf '%s' "$vf" | tr 'A-Z' 'a-z')"

  # change set: NUL-delimited <status> <path> records from three sources
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/rx-shared.XXXXXX")" || {
    printf 'rx-check: cannot create a temp dir\n' >&2
    exit 2
  }
  trap 'rm -rf "$tmp"' EXIT
  if ! git -C "$SH_ROOT" diff -z --name-status --no-renames --ignore-submodules=none \
    "$ref...HEAD" -- > "$tmp/committed" 2>"$tmp/err"; then
    printf 'rx-check: cannot diff against base branch '"'"'%s'"'"': %s\n' "$base" "$(cat "$tmp/err")" >&2
    exit 2
  fi
  if ! git -C "$SH_ROOT" diff -z --name-status --no-renames --ignore-submodules=none \
    HEAD -- > "$tmp/worktree" 2>"$tmp/err"; then
    printf 'rx-check: cannot diff the working tree: %s\n' "$(cat "$tmp/err")" >&2
    exit 2
  fi
  if ! git -C "$SH_ROOT" ls-files -z --others --exclude-standard > "$tmp/untracked" 2>"$tmp/err"; then
    printf 'rx-check: cannot list untracked files: %s\n' "$(cat "$tmp/err")" >&2
    exit 2
  fi
  cat "$tmp/committed" "$tmp/worktree" > "$tmp/all"
  while IFS= read -r -d '' p; do
    printf 'A\0%s\0' "$p" >> "$tmp/all"
  done < "$tmp/untracked"
  # lowercased copy, record for record, for the case-insensitive name matching
  tr 'A-Z' 'a-z' < "$tmp/all" > "$tmp/lower"

  exec 3< "$tmp/all" 4< "$tmp/lower"
  while IFS= read -r -d '' -u 3 st && IFS= read -r -d '' -u 3 p; do
    IFS= read -r -d '' -u 4 lp || true
    IFS= read -r -d '' -u 4 lp || true
    _chk_shared_rule "$st" "$p" "$lp"
  done
  exec 3<&- 4<&-

  n=${#SH_KEYS[@]}
  if [ "$n" -eq 0 ]; then
    return 0
  fi
  i=0
  while [ "$i" -lt "$n" ]; do
    key="${SH_KEYS[$i]}"
    printf '%s: %s\n' "${key%"$SH_US"*}" "${key##*"$SH_US"}"
    i=$((i + 1))
  done
  return 1
}

_chk_done() { _chk_not_implemented done; }

# ---------------------------------------------------------------- dispatcher

SUB="${1-}"
case "$SUB" in
  specs) shift; _chk_specs "$@" ;;
  shared) shift; _chk_shared "$@" ;;
  done) shift; _chk_done "$@" ;;
  *) _chk_usage ;;
esac
exit "$?"
