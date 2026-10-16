#!/usr/bin/env bash
# rx-check.sh <specs|shared|done> [feature-id]: deterministic gates for the rx toolkit.
# No LLM, no network. Used by /rx:next, pre-commit and CI.
#   specs [feature-id]  spec-file hygiene: line caps, required headings, frontmatter,
#                       ID uniqueness, task line format (every checkbox line in tasks.md /
#                       quick.md must be a well-formed task line), tasks cite existing ACs
#   shared [feature-id] merge-safety: a feature branch (net change since the merge base
#                       with base_branch, working tree and untracked files included) may
#                       only touch code, its own specs/<id>/ and NEW files under
#                       docs/knowledge/{decisions,learnings}/ (regular files, at most 6 / 5
#                       lines, first line `tags: [..]`). version_bump: feature (default
#                       release) lifts the version_file protection.
#   done [feature-id]   close-out gate: runs specs and shared for the id, then requires the
#                       lane's files (full: state, requirements, plan, tasks, review; quick:
#                       state + quick.md; never mixed), `status: final` on every spec file
#                       but state.md, no leftover review.qa/security files, gates approved
#                       (full: g1 g2 g3; quick: g2), every task in tasks.md/quick.md ticked,
#                       and test_cmd and lint_cmd (if set) exiting 0 within test_timeout
#                       seconds (default 600; a timed-out command's process tree is
#                       killed). All checks always run and all violations are reported.
#                       bump only has to be a valid value (none is an explicit choice);
#                       coverage is not checked.
# Exit codes: 0 clean, 1 violations (one `<path>: <reason>` line each on stdout, a failing
# command's output tail follows its line, each line prefixed `  | `), 2 usage or install
# error (message on stderr).
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.
# Each subcommand is a function _chk_<name> in this file; add new ones to the
# dispatcher at the bottom.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-check: rx-lib.sh not found\n' >&2
  exit 2
fi
# The checks are byte-oriented: under a UTF-8 locale BSD tr/sed abort at the first
# invalid byte and bash =~ fails on it, which would turn into false passes/fails.
# `done` runs the user's own commands, which must see the user's locale: keep the original.
if [ "${LC_ALL+set}" = set ]; then
  CHK_ORIG_LC_ALL="$LC_ALL"
  CHK_ORIG_LC_ALL_SET=1
else
  CHK_ORIG_LC_ALL=""
  CHK_ORIG_LC_ALL_SET=0
fi
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

# Task lines (tasks.md, quick.md). ONE definition, used by specs (format) and done (ticks).
# A "checkbox line" is any list item that opens with [..]: bullets - * +, numbered 1. 2).
# Every checkbox line must be a well-formed task line, so an unfinished item cannot hide
# behind a malformed or id-less line.
CHK_CB_RE='^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+\[[^]]*\]'
CHK_TASK_RE='^- \[([ x])\] T-([0-9]+) \(AC-[0-9]+(, AC-[0-9]+)*\): .+'

# _chk_task_kind <line>: set TK_KIND to none (not a checkbox line), malformed, open or
# done, and TK_N to the task number for open/done.
TK_KIND=""
TK_N=""
_chk_task_kind() {
  TK_KIND=none
  TK_N=""
  [[ $1 =~ $CHK_CB_RE ]] || return 0
  if [[ $1 =~ $CHK_TASK_RE ]]; then
    TK_N="${BASH_REMATCH[2]}"
    if [ "${BASH_REMATCH[1]}" = "x" ]; then
      TK_KIND=done
    else
      TK_KIND=open
    fi
  else
    TK_KIND=malformed
  fi
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
  local f="$1" path="$CUR_DIR/$1" cap n fm st msg heads h line id cites a

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
    # task lines (tasks.md, quick.md): see _chk_task_kind; only well-formed lines take
    # part in the id checks
    case "$f" in
      tasks.md|quick.md)
        _chk_task_kind "$line"
        if [ "$TK_KIND" = "malformed" ]; then
          _chk_v "$f" "malformed task line '${line:0:40}'"
        elif [ "$TK_KIND" != "none" ]; then
          id="T-$TK_N"
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

# _chk_vbump: validate version_bump (release|feature, default release) into SH_VB; exit 2 on
# anything else. `feature` means the version file is bumped per feature, so it is not shared.
SH_VB=""
_chk_vbump() {
  SH_VB="$(rx_cfg version_bump release)"
  case "$SH_VB" in
    release|feature) ;;
    *)
      printf "rx-check: invalid version_bump '%s' (release|feature)\n" "$SH_VB" >&2
      exit 2
      ;;
  esac
}

# _chk_know_entry <path>: content rules for a NEW decision/learning entry: a regular file,
# at most 6 (decision) / 5 (learning) lines counted like specs (CR stripped, a missing final
# newline counts), first line `tags: [..]`. Read from the index when the path is staged,
# else from the working tree. Needs SH_ROOT and SH_TMP.
_chk_know_entry() {
  local p="$1" kind cap rec mode="" staged=0 n first
  local tags_re='^tags: \[.*\]$'
  case "$p" in
    docs/knowledge/decisions/*) kind=decision; cap=6 ;;
    *) kind=learning; cap=5 ;;
  esac
  rec="$(git -C "$SH_ROOT" ls-files -s -z -- ":(literal)$p" 2>/dev/null | tr '\0' '\n' | head -n 1)"
  if [ -n "$rec" ]; then
    staged=1
    mode="${rec%% *}"
  fi
  if { [ "$staged" -eq 1 ] && [ "$mode" != "100644" ] && [ "$mode" != "100755" ]; } || [ -L "$SH_ROOT/$p" ]; then
    _chk_sv "$p" "knowledge entry must be a regular file"
    return 0
  fi
  if [ "$staged" -eq 1 ]; then
    git -C "$SH_ROOT" cat-file blob ":$p" > "$SH_TMP/entry" 2>/dev/null
  else
    cat "$SH_ROOT/$p" > "$SH_TMP/entry" 2>/dev/null
  fi || {
    printf 'rx-check: cannot read %s\n' "$p" >&2
    exit 2
  }
  n="$(tr -d '\r' < "$SH_TMP/entry" | awk 'END { print NR }')"
  if [ "$n" -gt "$cap" ]; then
    _chk_sv "$p" "$kind exceeds $cap lines ($n)"
  fi
  first=""
  IFS= read -r first < "$SH_TMP/entry" || true
  first="${first%$'\r'}"
  [[ $first =~ $tags_re ]] || _chk_sv "$p" "first line must be 'tags: [..]'"
}

# _chk_shared_rule <status> <path> <lowercased-path>: record a violation for one changed
# path, if it breaks a rule. First matching rule wins. Matching of the protected NAMES
# is case-insensitive (a branch must not slip CLAUDE.md past the gate as claude.md); the
# exceptions (.rx/local/, own specs dir, new knowledge entries) need the exact case.
# Uses SH_ID and SH_VF (lowercased version_file, may be empty).
_chk_shared_rule() {
  local st="$1" p="$2" lp="$3" rest name
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
      # Allowed: a NEW file (status A against the merge base) docs/knowledge/
      # {decisions,learnings}/<name>.md, single level.
      case "$p" in
        docs/knowledge/decisions/*.md|docs/knowledge/learnings/*.md)
          name="${p#docs/knowledge/*/}"
          case "$name" in
            */*|.md) ;;
            *)
              if [ "$st" = "A" ]; then
                _chk_know_entry "$p"
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
  local id base ref cur mb st p lp i n key vf tmp
  if [ "$#" -gt 1 ]; then
    _chk_usage
  fi
  SH_ROOT="$(rx_root)"
  if ! git -C "$SH_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'rx-check: not a git repository\n' >&2
    exit 2
  fi
  base="$(rx_require_cfg base_branch)" || exit 2
  _chk_vbump
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

  # base ref: the local branch and/or origin/<base>. When both exist, origin/<base> wins
  # only if the local branch is an ancestor of it (a stale local base); otherwise the
  # local branch is used. Never diff against nothing.
  local lref="refs/heads/$base" oref="refs/remotes/origin/$base" have_l=0 have_o=0
  git -C "$SH_ROOT" rev-parse --verify -q "$lref^{commit}" >/dev/null 2>&1 && have_l=1
  git -C "$SH_ROOT" rev-parse --verify -q "$oref^{commit}" >/dev/null 2>&1 && have_o=1
  if [ "$have_l" -eq 1 ] && [ "$have_o" -eq 1 ]; then
    if git -C "$SH_ROOT" merge-base --is-ancestor "$lref" "$oref" 2>/dev/null; then
      ref="$oref"
    else
      ref="$lref"
    fi
  elif [ "$have_l" -eq 1 ]; then
    ref="$lref"
  elif [ "$have_o" -eq 1 ]; then
    ref="$oref"
  else
    printf "rx-check: base branch '%s' not found\n" "$base" >&2
    exit 2
  fi

  vf="$(rx_cfg version_file)"
  vf="${vf#./}"
  [ "$SH_VB" = "feature" ] && vf=""
  SH_VF="$(printf '%s' "$vf" | tr 'A-Z' 'a-z')"

  # change set: NUL-delimited <status> <path> records, the union of the NET change since
  # the merge base seen from (i) the index (what a commit would record), (ii) the working
  # tree, and (iii) untracked non-ignored files as additions. A violation that was
  # reverted in both the index and the working tree is net-zero and passes; one that is
  # staged but then fixed or removed on disk is still reported.
  # SH_TMP is global: the EXIT trap runs after this function has returned.
  SH_TMP="$(mktemp -d "${TMPDIR:-/tmp}/rx-shared.XXXXXX")" || {
    printf 'rx-check: cannot create a temp dir\n' >&2
    exit 2
  }
  tmp="$SH_TMP"
  trap 'rm -rf "$SH_TMP"' EXIT
  if ! mb="$(git -C "$SH_ROOT" merge-base "$ref" HEAD 2>/dev/null)" || [ -z "$mb" ]; then
    printf "rx-check: cannot diff against base branch '%s': no merge base with HEAD\n" "$base" >&2
    exit 2
  fi
  if ! git -C "$SH_ROOT" diff -z --name-status --no-renames --ignore-submodules=none \
    --cached "$mb" -- > "$tmp/all" 2>"$tmp/err"; then
    printf "rx-check: cannot diff against base branch '%s': %s\n" "$base" "$(cat "$tmp/err")" >&2
    exit 2
  fi
  if ! git -C "$SH_ROOT" diff -z --name-status --no-renames --ignore-submodules=none \
    "$mb" -- >> "$tmp/all" 2>"$tmp/err"; then
    printf "rx-check: cannot diff against base branch '%s': %s\n" "$base" "$(cat "$tmp/err")" >&2
    exit 2
  fi
  if ! git -C "$SH_ROOT" ls-files -z --others --exclude-standard > "$tmp/untracked" 2>"$tmp/err"; then
    printf 'rx-check: cannot list untracked files: %s\n' "$(cat "$tmp/err")" >&2
    exit 2
  fi
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

# ---------------------------------------------------------------- done

# _chk_dv <path-and-reason>: record a violation line of `done` (already formatted).
DN_V=""
_chk_dv() {
  DN_V="${DN_V}${1}"$'\n'
}

# _chk_done_lanes <id>: lane files. quick.md present means the quick lane (state.md +
# quick.md, review.md optional), otherwise the full lane (state, requirements, plan, tasks,
# review). The lanes are exclusive; every present file but state.md must be `status: final`;
# leftover qa/security files must have been merged. Sets DN_LANE (quick|full).
DN_LANE=full
_chk_done_lanes() {
  local id="$1" d="$CHK_ROOT/specs/$1" f fm st required
  if [ -f "$d/quick.md" ]; then
    DN_LANE=quick
    required="state.md quick.md"
    for f in requirements.md plan.md tasks.md; do
      if [ -e "$d/$f" ]; then
        _chk_dv "specs/${id}: quick and full lane files cannot be mixed"
        break
      fi
    done
  else
    DN_LANE=full
    required="state.md requirements.md plan.md tasks.md review.md"
  fi
  for f in $required; do
    [ -e "$d/$f" ] || _chk_dv "specs/${id}/${f}: required for ${DN_LANE} lane"
  done
  for f in requirements.md plan.md tasks.md review.md quick.md; do
    [ -f "$d/$f" ] || continue
    st=""
    if fm="$(_rx_fm "$d/$f")"; then
      st="$(_rx_fm_get "$fm" status)" || st=""
    fi
    [ "$st" = "final" ] || _chk_dv "specs/${id}/${f}: status must be final"
  done
  for f in review.qa.md review.security.md; do
    [ -e "$d/$f" ] && _chk_dv "specs/${id}/${f}: merge into review.md and delete"
  done
  return 0
}

# _chk_done_tasks <id>: every task line of tasks.md / quick.md must be ticked, and there
# must be at least one task in each present file. Checkbox lines that are not well-formed
# task lines are reported by `specs` (same definition: _chk_task_kind).
_chk_done_tasks() {
  local id="$1" d="$CHK_ROOT/specs/$1" f line count
  for f in tasks.md quick.md; do
    [ -f "$d/$f" ] || continue
    count=0
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      _chk_task_kind "$line"
      case "$TK_KIND" in
        open)
          count=$((count + 1))
          _chk_dv "specs/${id}/${f}: T-${TK_N} not done"
          ;;
        done) count=$((count + 1)) ;;
      esac
    done < "$d/$f"
    if [ "$count" -eq 0 ]; then
      _chk_dv "specs/${id}/${f}: no tasks found"
    fi
  done
}

# _chk_done_cmd <label> <key> <command>: run a user command from the repo root with the
# user's original locale, limited to DN_TIMEOUT seconds; record a violation on failure.
# DN_TMP (global: the EXIT trap uses it) holds the combined output.
_chk_done_cmd() {
  local label="$1" key="$2" cmd="$3" rc tail
  if [ "$CHK_ORIG_LC_ALL_SET" -eq 1 ]; then
    LC_ALL="$CHK_ORIG_LC_ALL"
  else
    unset LC_ALL
  fi
  rx_run_timeout "$DN_TIMEOUT" "$DN_TMP/out" "$cmd"
  rc=$?
  export LC_ALL=C
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  if [ "$rc" -eq 124 ]; then
    _chk_dv "${label}: ${key} timed out after ${DN_TIMEOUT}s"
    return 0
  fi
  _chk_dv "${label}: ${key} failed (exit ${rc})"
  tail="$(tr -d '\r' < "$DN_TMP/out" | tail -n 15 | sed 's/^/  | /')"
  if [ -n "$tail" ]; then
    _chk_dv "$tail"
  fi
}

# _chk_done_sub <name> <rc> <output>: take the result of a reused check. 0 is clean, 1 must
# come with violation lines, 2 already printed its message; anything else (a crash, a
# signal, a violation status without a report) must not pass: fail closed.
_chk_done_sub() {
  case "$2" in
    0) ;;
    1)
      if [ -z "$3" ]; then
        printf 'rx-check: unexpected status 1 from %s\n' "$1" >&2
        exit 2
      fi
      ;;
    2) exit 2 ;;
    *)
      printf 'rx-check: unexpected status %s from %s\n' "$2" "$1" >&2
      exit 2
      ;;
  esac
  [ -z "$3" ] || _chk_dv "$3"
}

# _chk_done [feature-id]
_chk_done() {
  local id out rc g v test_cmd lint_cmd gates
  if [ "$#" -gt 1 ]; then
    _chk_usage
  fi
  CHK_ROOT="$(rx_root)"
  if [ "$#" -eq 1 ]; then
    if ! _rx_valid_id "$1"; then
      printf "rx-check: invalid feature id '%s'\n" "$1" >&2
      exit 2
    fi
    id="$1"
  else
    id="$(rx_feature_id)" || id=""
    if [ -z "$id" ]; then
      printf 'rx-check: done needs a feature id (none resolved); pass one explicitly\n' >&2
      exit 2
    fi
  fi

  # configuration first, so that an environment error costs nothing
  _chk_vbump
  test_cmd="$(rx_require_cfg test_cmd)" || exit 2
  lint_cmd="$(rx_cfg lint_cmd)"
  DN_TIMEOUT="$(rx_cfg test_timeout 600)"
  case "$DN_TIMEOUT" in
    ''|*[!0123456789]*|0*|??????????*)
      printf "rx-check: invalid test_timeout '%s' (expected a positive integer number of seconds)\n" "$DN_TIMEOUT" >&2
      exit 2
      ;;
  esac
  # DN_TMP is global: the EXIT trap runs after this function has returned.
  DN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/rx-done.XXXXXX")" || {
    printf 'rx-check: cannot create a temp dir\n' >&2
    exit 2
  }
  trap 'rm -rf "$DN_TMP"' EXIT
  DN_TMP="$(cd "$DN_TMP" && pwd -P)" || exit 2

  # a. specs and b. shared, in subshells: their violation lines are captured verbatim and
  # their exit 2 (message already on stderr) aborts `done` the same way.
  out="$(_chk_specs "$id")"
  _chk_done_sub specs $? "$out"
  out="$(_chk_shared "$id")"
  _chk_done_sub shared $? "$out"

  # c. lanes, then gates: the full lane needs g1-g3, the quick lane only g2 (its single
  # pre-build authorization). state.md validity itself is part of the specs output.
  _chk_done_lanes "$id"
  gates="g1 g2 g3"
  [ "$DN_LANE" = "quick" ] && gates="g2"
  for g in $gates; do
    v="$(rx_state_get "$id" "$g")" || v=""
    case "$v" in
      approved:*) ;;
      *) _chk_dv "specs/${id}/state.md: ${g} not approved" ;;
    esac
  done

  # d. tasks
  _chk_done_tasks "$id"

  # e. tests and f. lint, from the repo root
  cd "$CHK_ROOT" || {
    printf 'rx-check: cannot enter %s\n' "$CHK_ROOT" >&2
    exit 2
  }
  _chk_done_cmd tests test_cmd "$test_cmd"
  if [ -n "$lint_cmd" ]; then
    _chk_done_cmd lint lint_cmd "$lint_cmd"
  fi

  if [ -n "$DN_V" ]; then
    printf '%s' "$DN_V"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- dispatcher

SUB="${1-}"
case "$SUB" in
  specs) shift; _chk_specs "$@" ;;
  shared) shift; _chk_shared "$@" ;;
  done) shift; _chk_done "$@" ;;
  *) _chk_usage ;;
esac
exit "$?"
