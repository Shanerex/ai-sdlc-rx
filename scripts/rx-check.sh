#!/usr/bin/env bash
# rx-check.sh <specs|shared|done> [feature-id]: deterministic gates for the rx toolkit.
# No LLM, no network. Used by /rx:next, pre-commit and CI.
#   specs [feature-id]  spec-file hygiene: line caps, required headings, frontmatter,
#                       ID uniqueness, task line format, tasks cite existing ACs
#   shared              (not implemented yet)
#   done                (not implemented yet)
# Exit codes: 0 clean, 1 violations (one `<path>: <reason>` line each on stdout),
# 2 usage or install error (message on stderr).
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.
# Each subcommand is a function _chk_<name> in this file; add new ones to the
# dispatcher at the bottom.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/rx-lib.sh"
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
# or return 1 when there is none in any location. Lookup order: $RX_TEMPLATES,
# <script-dir>/../skills/rx-spec/templates, <script-dir>/templates (.rx/scripts copy).
# review.qa.md and review.security.md have no template: that is not an error
# (TPL_PATH stays empty, return 0).
_chk_tpl_find() {
  local dir
  TPL_PATH=""
  case "$1" in
    review.qa.md|review.security.md) return 0 ;;
  esac
  for dir in "${RX_TEMPLATES-}" "$SCRIPT_DIR/../skills/rx-spec/templates" "$SCRIPT_DIR/templates"; do
    [ -n "$dir" ] || continue
    if [ -f "$dir/$1" ]; then
      TPL_PATH="$dir/$1"
      return 0
    fi
  done
  return 1
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
      "- [ ] T-"*|"- [x] T-"*)
        case "$f" in
          tasks.md|quick.md)
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
            ;;
        esac
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

_chk_shared() { _chk_not_implemented shared; }
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
