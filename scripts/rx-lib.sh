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

# rx_valid_id <id>: 0 iff id matches ^[A-Za-z0-9][A-Za-z0-9._-]*$ (explicit
# character lists, so the result does not depend on the locale).
rx_valid_id() {
  case "${1-}" in
    ''|[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*) return 1 ;;
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;;
  esac
  return 0
}

# rx_branch_id <branch>: print the feature id that <branch> encodes under
# branch_pattern (default feature/{id}; one `{id}` placeholder, plain string
# stripping, never a regex) and return 0. Print nothing and return 1 if the
# pattern lacks exactly one `{id}`, the branch does not match, or the id is
# not valid per rx_valid_id. The configured base_branch is never a feature branch
# (so `branch_pattern: {id}` does not turn `main` into a feature id).
rx_branch_id() {
  local branch="${1-}" pattern prefix suffix id base
  [ -n "$branch" ] || return 1
  base="$(rx_cfg base_branch)"
  [ "$branch" != "$base" ] || return 1
  pattern="$(rx_cfg branch_pattern 'feature/{id}')"
  case "$pattern" in
    *'{id}'*) ;;
    *) return 1 ;;
  esac
  prefix="${pattern%%'{id}'*}"
  suffix="${pattern#*'{id}'}"
  case "$suffix" in
    *'{id}'*) return 1 ;;
  esac
  case "$branch" in
    "$prefix"*"$suffix") ;;
    *) return 1 ;;
  esac
  id="${branch#"$prefix"}"
  id="${id%"$suffix"}"
  rx_valid_id "$id" || return 1
  printf '%s\n' "$id"
  return 0
}

# rx_id_branch <id>: print the branch name for a feature id under branch_pattern
# (default feature/{id}) and return 0: the inverse of rx_branch_id. Print nothing and
# return 1 if the id is invalid, the pattern lacks exactly one `{id}`, or the result is the
# configured base_branch.
rx_id_branch() {
  local id="${1-}" pattern prefix suffix branch
  rx_valid_id "$id" || return 1
  pattern="$(rx_cfg branch_pattern 'feature/{id}')"
  case "$pattern" in
    *'{id}'*) ;;
    *) return 1 ;;
  esac
  prefix="${pattern%%'{id}'*}"
  suffix="${pattern#*'{id}'}"
  case "$suffix" in
    *'{id}'*) return 1 ;;
  esac
  branch="${prefix}${id}${suffix}"
  [ "$branch" != "$(rx_cfg base_branch)" ] || return 1
  printf '%s\n' "$branch"
  return 0
}

# rx_feature_id: print the active feature id and return 0, else print nothing
# and return 1. Order: (a) current branch via rx_branch_id, (b) first line of
# <root>/.rx/local/active. Ids must be valid per rx_valid_id. Detached HEAD,
# rebase and non-git all fall through to (b).
rx_feature_id() {
  local branch id root line
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || branch=""
  if [ -n "$branch" ]; then
    rx_branch_id "$branch" && return 0
  fi
  root="$(rx_root)"
  if [ -f "$root/.rx/local/active" ]; then
    line=""
    IFS= read -r line < "$root/.rx/local/active" || true
    line="${line%$'\r'}"
    id="$(_rx_trim "$line")"
    if rx_valid_id "$id"; then
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
  rx_valid_id "$id" || return 1
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
  rx_valid_id "$id" || { printf 'state.md invalid: not found\n' >&2; return 1; }
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
        if [ "$k" = feature ] && [ "$v" != "$id" ]; then
          printf "state.md invalid: feature '%s' does not match directory '%s'\n" "$v" "$id" >&2
          return 1
        fi
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

# _rx_glob_re <glob>: print an anchored ERE for one source_globs entry.
#   `**/` zero or more directories, `**` anything (including `/`), `*` anything but `/`,
#   `?` one char but `/`. Everything else is literal (no braces, no [classes]).
_rx_glob_re() {
  local g="${1-}" re="^" c
  while [ -n "$g" ]; do
    case "$g" in
      '**/'*) re="${re}(.*/)?"; g="${g#'**/'}"; continue ;;
      '**'*) re="${re}.*"; g="${g#'**'}"; continue ;;
    esac
    c="${g:0:1}"
    g="${g:1}"
    case "$c" in
      '*') re="${re}[^/]*" ;;
      '?') re="${re}[^/]" ;;
      '^') re="${re}\\^" ;;
      '.'|'+'|'('|')'|'['|'{'|'}'|'|'|'$'|'\') re="${re}[${c}]" ;;
      ']') re="${re}[]]" ;;
      *) re="${re}${c}" ;;
    esac
  done
  printf '%s$\n' "$re"
}

# rx_glob_match <repo-relative-path>: return 0 iff the path matches any entry of the
# `source_globs` config key, else 1 (also when the key is empty or missing, so an
# unconfigured repo blocks nothing). Format: comma-separated entries, each trimmed;
# a leading `./` is ignored on both sides. `**/` = any directories (or none), `**` = any
# characters including `/`, `*` and `?` never cross `/`; nothing else is special. bash 3.2
# has no globstar, so entries are translated to EREs by _rx_glob_re.
rx_glob_match() {
  rx_glob_match_key source_globs "${1-}"
}

# rx_glob_match_key <config-key> <repo-relative-path>: same, for any config key holding a
# glob list in the format above (e.g. test_globs).
rx_glob_match_key() {
  local path="${2-}" globs entry re rest
  path="${path#./}"
  globs="$(rx_cfg "${1-}")"
  [ -n "$globs" ] || return 1
  rest="$globs"
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) entry="${rest%%,*}"; rest="${rest#*,}" ;;
      *) entry="$rest"; rest="" ;;
    esac
    entry="$(_rx_trim "$entry")"
    entry="${entry#./}"
    [ -n "$entry" ] || continue
    re="$(_rx_glob_re "$entry")"
    if [[ $path =~ $re ]]; then
      return 0
    fi
  done
  return 1
}

# rx_glob_filter <config-key>...: batch form of rx_glob_match_key for long file lists (a
# per-file call re-reads the config and forks, about 25 ms a file). Reads NUL-separated
# repo-relative paths on stdin and prints, one per line and in input order, those that match
# an entry of ANY named key and are existing regular files (relative to the cwd). The globs
# are translated once. A path containing a newline is skipped. RX_GLOB_NOSTAT=1 skips the file test
# (staged paths may no longer exist on disk).
rx_glob_filter() {
  local key globs rest entry res="" re path
  local -a res_list=()
  for key in "$@"; do
    globs="$(rx_cfg "$key")"
    rest="$globs"
    while [ -n "$rest" ]; do
      case "$rest" in
        *,*) entry="${rest%%,*}"; rest="${rest#*,}" ;;
        *) entry="$rest"; rest="" ;;
      esac
      entry="$(_rx_trim "$entry")"
      entry="${entry#./}"
      [ -n "$entry" ] || continue
      res_list[${#res_list[@]}]="$(_rx_glob_re "$entry")"
    done
  done
  [ "${#res_list[@]}" -gt 0 ] || { cat >/dev/null; return 0; }
  while IFS= read -r -d '' path; do
    path="${path#./}"
    case "$path" in *$'\n'*) continue ;; esac
    [ -n "${RX_GLOB_NOSTAT-}" ] || [ -f "$path" ] || continue
    for re in "${res_list[@]}"; do
      if [[ $path =~ $re ]]; then
        printf '%s\n' "$path"
        break
      fi
    done
  done
  return 0
}

# rx_locale_c / rx_locale_user: the rx checks are byte-oriented (under a UTF-8 locale BSD
# tr/sed abort at the first invalid byte and bash =~ fails on it), so a script calls
# rx_locale_c once after sourcing this file. Commands that belong to the user (test_cmd,
# lint_cmd) must see the caller's own locale: wrap them in rx_locale_user ... rx_locale_c.
# The caller's original LC_ALL (set or unset) is saved by the first rx_locale_c only.
rx_locale_c() {
  if [ "${RX_LC_SAVED-0}" != 1 ]; then
    if [ "${LC_ALL+set}" = set ]; then
      RX_LC_ORIG="$LC_ALL"
      RX_LC_ORIG_SET=1
    else
      RX_LC_ORIG=""
      RX_LC_ORIG_SET=0
    fi
    RX_LC_SAVED=1
  fi
  export LC_ALL=C
  return 0
}

rx_locale_user() {
  [ "${RX_LC_SAVED-0}" = 1 ] || return 0
  if [ "$RX_LC_ORIG_SET" -eq 1 ]; then
    export LC_ALL="$RX_LC_ORIG"
  else
    unset LC_ALL
  fi
  return 0
}

# rx_run_timeout <seconds> <outfile> <command-string>: run <command-string> with
# `bash -c` from the CURRENT directory, stdin from /dev/null, stdout+stderr combined
# into <outfile> (truncated first). Returns the command's exit status, or 124 when it
# was still running after <seconds> (a positive integer; anything else, or an empty
# <outfile>, is a usage error: message on stderr, return 2; an unwritable <outfile>
# returns 1). The returned status alone is ambiguous (a command can exit 2 or 124 by
# itself), so it also sets the global RX_RT_STATE: ran | timeout | usage | error. Callers
# that must tell a timeout from a command's own 124 test RX_RT_STATE, not the status.
#   - Call it from the top-level shell of a script, not inside `$(...)`: a signal to the
#     caller is re-raised on `$$`, which is the top-level shell even from a subshell.
#   - On timeout the command's whole process group is sent TERM, then KILL 0.2s later,
#     so children it backgrounded die with it (a descendant that moves itself into
#     another session or process group escapes). Output written before the kill stays
#     in <outfile>.
#   - The command runs as a job under monitor mode (`set -m`), which is how it gets its
#     own process group on bash 3.2 (no `timeout`/`setsid` on macOS); a watcher job
#     enforces the limit. Both are reaped before returning: no stray processes are left
#     behind except what the command itself leaves running after a normal exit.
#   - A flag file `<outfile>.timeout` exists only while a timeout is being handled.
#   - Caller state is restored: monitor mode, and the INT/TERM/HUP/QUIT traps (they are replaced
#     while it runs so that a signal to the caller also kills the command's group, then
#     the signal is re-raised once the caller's traps are back). Never sets -e/-u or
#     IFS; RX_RT_STATE is its only global; all other variables are local. Safe under `set -e`/-u
#     (it only returns the status; the caller decides what to do with it).
# Usage: rx_run_timeout 600 "$tmp" "$cmd"; rc=$?
rx_run_timeout() {
  local secs="${1-}" out="${2-}" cmd="${3-}" had_m=0 pid wpid rc=0 flag old_int old_term old_hup old_quit
  case "$secs" in
    ''|*[!0123456789]*|0|00*)
      printf 'rx: rx_run_timeout: seconds must be a positive integer\n' >&2
      RX_RT_STATE=usage
      return 2
      ;;
  esac
  if [ -z "$out" ]; then
    printf 'rx: rx_run_timeout: missing output file\n' >&2
    RX_RT_STATE=usage
    return 2
  fi
  if ! : > "$out" 2>/dev/null; then
    printf 'rx: rx_run_timeout: cannot write %s\n' "$out" >&2
    RX_RT_STATE=error
    return 1
  fi
  flag="$out.timeout"
  rm -f "$flag"
  case "$-" in *m*) had_m=1 ;; esac
  old_int="$(trap -p INT)"
  old_term="$(trap -p TERM)"
  old_hup="$(trap -p HUP)"
  old_quit="$(trap -p QUIT)"
  set -m
  bash -c "$cmd" </dev/null >"$out" 2>&1 &
  pid=$!
  (
    sleep "$secs"
    : > "$flag"
    kill -TERM -- "-$pid" 2>/dev/null
    sleep 0.2
    kill -KILL -- "-$pid" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  wpid=$!
  trap "_rx_rt_abort INT $pid $wpid" INT
  trap "_rx_rt_abort TERM $pid $wpid" TERM
  trap "_rx_rt_abort HUP $pid $wpid" HUP
  trap "_rx_rt_abort QUIT $pid $wpid" QUIT
  { wait "$pid"; } 2>/dev/null && rc=0 || rc=$?
  if [ -e "$flag" ]; then
    { wait "$wpid"; } 2>/dev/null || true
    rc=124
    RX_RT_STATE=timeout
  else
    kill -KILL -- "-$wpid" 2>/dev/null || true
    { wait "$wpid"; } 2>/dev/null || true
    RX_RT_STATE=ran
  fi
  trap - INT TERM HUP QUIT
  [ -z "$old_int" ] || eval "$old_int"
  [ -z "$old_term" ] || eval "$old_term"
  [ -z "$old_hup" ] || eval "$old_hup"
  [ -z "$old_quit" ] || eval "$old_quit"
  [ "$had_m" -eq 1 ] || set +m
  # Monitor mode is back to the caller's setting, so this rm cannot take the terminal
  # as a foreground job. The watcher is reaped, so nobody can create the flag after this.
  rm -f "$flag"
  return "$rc"
}

# _rx_rt_abort <signal> <pid> <watcher-pid>: INT/TERM/HUP/QUIT handler of rx_run_timeout. Kills
# both process groups, puts the caller's traps back (it reads old_int, old_term, old_hup and
# old_quit from the running rx_run_timeout frame) and re-raises the signal on the shell.
_rx_rt_abort() {
  kill -KILL -- "-$2" "-$3" 2>/dev/null
  rm -f "$flag"
  trap - INT TERM HUP QUIT
  [ -z "$old_int" ] || eval "$old_int"
  [ -z "$old_term" ] || eval "$old_term"
  [ -z "$old_hup" ] || eval "$old_hup"
  [ -z "$old_quit" ] || eval "$old_quit"
  kill -s "$1" $$
}
