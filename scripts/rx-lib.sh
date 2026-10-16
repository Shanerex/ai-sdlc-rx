#!/usr/bin/env bash
# rx-lib.sh: shared helpers for the rx toolkit. SOURCE this file; do not execute it.
#
# Sourcing only defines functions. It does not set shell options, change IFS,
# install traps, cd, or print. Public names are rx_*, internal helpers _rx_*.
# Targets macOS bash 3.2 + BSD userland (no associative arrays, no GNU flags).
#
# Config is flat `key: value` yaml in <root>/.rx/config.yml. Feature state lives
# in <root>/specs/<feature-id>/state.md frontmatter (see skills/rx-spec/SKILL.md).

# rx_root: print the git toplevel of the cwd, or $PWD outside a git repo.
rx_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -n "$top" ]; then
    printf '%s\n' "$top"
  else
    printf '%s\n' "$PWD"
  fi
  return 0
}

# rx_enabled: return 0 iff <root>/.rx/config.yml is a regular file.
rx_enabled() {
  local root
  root="$(rx_root)"
  [ -f "$root/.rx/config.yml" ]
}

# rx_noop_unless_enabled: call at the TOP of a script. When rx is not enabled it
# runs `exit 0` in the CALLER's shell, so the whole script ends quietly. (Called
# from a subshell or $(...) it only leaves that subshell.)
rx_noop_unless_enabled() {
  rx_enabled || exit 0
  return 0
}

# rx_die <msg>: print `rx: <msg>` to stderr and `exit 2`. It exits only the
# CURRENT shell: called directly from the sourcing script it ends the script,
# but inside $(...) or a pipeline it ends just that subshell and the script
# keeps running. Capture with `x="$(...)" || exit 2` (see rx_require_cfg).
rx_die() {
  printf 'rx: %s\n' "$*" >&2
  exit 2
}

# _rx_trim <string>: print the string without leading/trailing whitespace.
_rx_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# rx_cfg <key> [default]: print the value of flat `key: value` from the config.
#   - first matching key wins; the key must match exactly and be followed by
#     `:` and then end of line or whitespace
#   - value is trimmed; one pair of surrounding '...' or "..." is stripped (no
#     escapes; the first closing quote ends the value, the rest is ignored)
#   - unquoted: a `#` that follows whitespace starts a comment; `a#b` is kept
#   - empty value, missing key or missing file prints the default (or nothing)
#   - lines that are not `key: value` shaped are ignored. Always returns 0.
rx_cfg() {
  local key="${1-}" def="${2-}" file line rest val q
  local val_found=0
  file="$(rx_root)/.rx/config.yml"
  val=""
  if [ -n "$key" ] && [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      line="${line#"${line%%[![:space:]]*}"}"
      case "$line" in
        "$key":*) ;;
        *) continue ;;
      esac
      rest="${line#"$key":}"
      case "$rest" in
        ''|[[:space:]]*) ;;
        *) continue ;;
      esac
      rest="${rest#"${rest%%[![:space:]]*}"}"
      q="${rest:0:1}"
      if [ "$q" = '"' ] || [ "$q" = "'" ]; then
        val="${rest:1}"
        case "$val" in
          *"$q"*) val="${val%%"$q"*}" ;;
          *) val="$rest"; q="" ;;
        esac
      else
        q=""
        val="$rest"
      fi
      if [ -z "$q" ]; then
        case "$val" in
          '#'*) val="" ;;
          *) val="${val%%[[:space:]]#*}" ;;
        esac
        val="$(_rx_trim "$val")"
      fi
      val_found=1
      break
    done < "$file"
  fi
  [ "$val_found" -eq 1 ] || val=""
  if [ -z "$val" ]; then
    val="$def"
  fi
  if [ -n "$val" ]; then
    printf '%s\n' "$val"
  fi
  return 0
}

# rx_require_cfg <key>: print the value and return 0 if non-empty, else rx_die
# (message on stderr, exit 2 of the CURRENT shell). A bare call at script level,
# e.g. `rx_require_cfg k >/dev/null`, exits the script. Inside command
# substitution only the subshell exits, so the caller MUST write
#   x="$(rx_require_cfg k)" || exit 2
# otherwise it continues with rc=2 and an empty x.
rx_require_cfg() {
  local v
  v="$(rx_cfg "${1-}")"
  if [ -z "$v" ]; then
    rx_die "missing config key: ${1-}"
  fi
  printf '%s\n' "$v"
  return 0
}

# _rx_valid_id <id>: 0 iff id matches ^[A-Za-z0-9][A-Za-z0-9._-]*$ (explicit
# character lists, so the result does not depend on the locale).
_rx_valid_id() {
  case "${1-}" in
    ''|[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*) return 1 ;;
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;;
  esac
  return 0
}

# rx_feature_id: print the active feature id and return 0, else print nothing
# and return 1. Order: (a) current branch matched against branch_pattern
# (default feature/{id}; one `{id}` placeholder, plain string stripping, never a
# regex), (b) first line of <root>/.rx/local/active. Ids must be valid per
# _rx_valid_id. Detached HEAD, rebase and non-git all fall through to (b).
rx_feature_id() {
  local pattern branch prefix suffix id root line
  pattern="$(rx_cfg branch_pattern 'feature/{id}')"
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || branch=""
  case "$pattern" in
    *'{id}'*)
      prefix="${pattern%%'{id}'*}"
      suffix="${pattern#*'{id}'}"
      case "$suffix" in
        *'{id}'*) branch="" ;;
      esac
      if [ -n "$branch" ]; then
        case "$branch" in
          "$prefix"*"$suffix")
            id="${branch#"$prefix"}"
            id="${id%"$suffix"}"
            if _rx_valid_id "$id"; then
              printf '%s\n' "$id"
              return 0
            fi
            ;;
        esac
      fi
      ;;
  esac
  root="$(rx_root)"
  if [ -f "$root/.rx/local/active" ]; then
    line=""
    IFS= read -r line < "$root/.rx/local/active" || true
    line="${line%$'\r'}"
    id="$(_rx_trim "$line")"
    if _rx_valid_id "$id"; then
      printf '%s\n' "$id"
      return 0
    fi
  fi
  return 1
}

# _rx_fm <state-file>: print the frontmatter lines (between the first line `---`
# and the next `---`). Return 1 if the file lacks an opening or closing marker.
_rx_fm() {
  local line first=1 out=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$first" -eq 1 ]; then
      first=0
      [ "$line" = "---" ] || return 1
      continue
    fi
    if [ "$line" = "---" ]; then
      printf '%s' "$out"
      return 0
    fi
    out="${out}${line}"$'\n'
  done < "$1"
  return 1
}

# _rx_fm_get <frontmatter-text> <key>: print the trimmed value of the first
# `key:` line (split on the first colon only); return 1 if the key is absent.
_rx_fm_get() {
  local line v
  while IFS= read -r line; do
    case "$line" in
      "$2":*)
        v="${line#"$2":}"
        _rx_trim "$v"
        printf '\n'
        return 0
        ;;
    esac
  done <<EOF
$1
EOF
  return 1
}

# rx_state_get <feature-id> <key>: print a state.md frontmatter value, or return
# 1 with no output if the id, file, frontmatter or key is missing/invalid.
rx_state_get() {
  local id="${1-}" key="${2-}" file fm
  _rx_valid_id "$id" || return 1
  [ -n "$key" ] || return 1
  file="$(rx_root)/specs/$id/state.md"
  [ -f "$file" ] || return 1
  fm="$(_rx_fm "$file")" || return 1
  _rx_fm_get "$fm" "$key"
}

# rx_state_valid <feature-id>: return 0 if specs/<id>/state.md has well-formed
# frontmatter with all eight keys and allowed values (mirrors rx-spec SKILL.md).
# Otherwise print ONE line `state.md invalid: <reason>` to stderr and return 1.
rx_state_valid() {
  local id="${1-}" file fm k v rest approver date
  _rx_valid_id "$id" || { printf 'state.md invalid: not found\n' >&2; return 1; }
  file="$(rx_root)/specs/$id/state.md"
  [ -f "$file" ] || { printf 'state.md invalid: not found\n' >&2; return 1; }
  fm="$(_rx_fm "$file")" || { printf 'state.md invalid: no frontmatter\n' >&2; return 1; }
  for k in feature phase status g1 g2 g3 bump next; do
    _rx_fm_get "$fm" "$k" >/dev/null || { printf 'state.md invalid: missing key %s\n' "$k" >&2; return 1; }
  done
  for k in feature phase status g1 g2 g3 bump next; do
    v="$(_rx_fm_get "$fm" "$k")"
    case "$k" in
      feature|next)
        [ -n "$v" ] || { printf 'state.md invalid: empty %s\n' "$k" >&2; return 1; }
        ;;
      phase)
        case "$v" in
          intake|requirements|plan|build|verify|close|done) ;;
          *) printf "state.md invalid: unknown phase '%s'\n" "$v" >&2; return 1 ;;
        esac
        ;;
      status)
        case "$v" in
          draft|awaiting-human|approved|blocked) ;;
          *) printf "state.md invalid: unknown status '%s'\n" "$v" >&2; return 1 ;;
        esac
        ;;
      bump)
        case "$v" in
          none|patch|minor|major) ;;
          *) printf "state.md invalid: unknown bump '%s'\n" "$v" >&2; return 1 ;;
        esac
        ;;
      g1|g2|g3)
        if [ "$v" != "none" ]; then
          rest=""
          case "$v" in
            approved:*:*) rest="${v#approved:}" ;;
          esac
          approver="${rest%:*}"
          date="${rest##*:}"
          case "$date" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
            *) rest="" ;;
          esac
          case "$approver" in
            ''|*[[:space:]:]*) rest="" ;;
          esac
          if [ -z "$rest" ]; then
            printf "state.md invalid: bad %s '%s'\n" "$k" "$v" >&2
            return 1
          fi
        fi
        ;;
    esac
  done
  return 0
}
