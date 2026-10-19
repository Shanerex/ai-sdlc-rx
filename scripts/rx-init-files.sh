#!/usr/bin/env bash
# rx-init-files.sh: the deterministic half of /rx:init. Run it from the rx plugin (it copies itself's
# siblings), inside the target git repository.
#   rx-init-files.sh                     create .rx/local, docs/knowledge/{decisions,learnings} and
#                                        specs/; add .rx/local/ to .gitignore (once); copy scripts/
#                                        and the rx-spec templates into .rx/scripts/ with a version
#                                        stamp (.rx/scripts/.rx-version); install the git pre-commit
#                                        wrapper. Safe to rerun. Prints which of .rx/config.yml,
#                                        CLAUDE.md and docs/knowledge/architecture.md exist.
#   rx-init-files.sh --refresh-scripts   re-copy .rx/scripts (scripts, templates, version stamp) only
#   rx-init-files.sh --install-config <draft>
#   rx-init-files.sh --install-claude-md <draft>
#   rx-init-files.sh --install-architecture <draft>
#                                        validate a model-written draft and copy it into place. Never
#                                        overwrites an existing target (exit 1). The guard blocks
#                                        agents from writing these paths directly, so /rx:init goes
#                                        through here.
#     config:  flat `key: value` lines (blank lines and # comments allowed), test_cmd set, no
#              coverage_cmd / coverage_min (coverage is out of scope for v0.1)
#     CLAUDE.md: at most 60 lines, no `@import` line      architecture.md: at most 80 lines
# Exit codes: 0 ok, 1 refused or invalid draft or foreign pre-commit hook left in place (the rest was
# done), 2 usage or environment error.
# Targets macOS bash 3.2 + BSD userland. Deliberately no `set -e`.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/rx-lib.sh" ] || ! . "$SCRIPT_DIR/rx-lib.sh"; then
  printf 'rx-init: rx-lib.sh not found\n' >&2
  exit 2
fi
rx_locale_c

_in_die() {
  printf 'rx-init: %s\n' "$*" >&2
  exit 2
}
_in_usage() {
  printf 'usage: rx-init-files.sh [--refresh-scripts | --install-config <file> | --install-claude-md <file> | --install-architecture <file>]\n' >&2
  exit 2
}

MODE=init
DRAFT=""
case "$#:${1-}" in
  0:) ;;
  1:--refresh-scripts) MODE=refresh ;;
  2:--install-config) MODE=config; DRAFT="$2" ;;
  2:--install-claude-md) MODE=claude; DRAFT="$2" ;;
  2:--install-architecture) MODE=arch; DRAFT="$2" ;;
  *) _in_usage ;;
esac

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || _in_die "a git repository is required"
cd "$TOP" || _in_die "cannot enter $TOP"

HOOK_MARK="# rx-managed pre-commit"

# ---------------------------------------------------------------- scripts copy
_in_find_tpl() {
  local d
  for d in "$SCRIPT_DIR/../skills/rx-spec/templates" "$SCRIPT_DIR/templates"; do
    if [ -f "$d/state.md" ] && [ -f "$d/quick.md" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 1
}

_in_version() {
  local pj="$SCRIPT_DIR/../.claude-plugin/plugin.json" v
  [ -f "$pj" ] || return 1
  v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" | head -n 1)"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

_in_copy_scripts() {
  local tpl ver tmp f
  tpl="$(_in_find_tpl)" || _in_die "rx-spec templates not found; run this from the rx plugin, not from .rx/scripts"
  ver="$(_in_version)" || _in_die "plugin version not found; run this from the rx plugin, not from .rx/scripts"
  tmp="$TOP/.rx/scripts.new.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/templates" || _in_die "cannot create $tmp"
  for f in "$SCRIPT_DIR"/*.sh; do
    [ "$(basename "$f")" = "rx-init-files.sh" ] && continue
    cp "$f" "$tmp/" && chmod +x "$tmp/$(basename "$f")" || { rm -rf "$tmp"; _in_die "cannot copy $f"; }
  done
  cp "$tpl"/*.md "$tmp/templates/" || { rm -rf "$tmp"; _in_die "cannot copy templates"; }
  printf '%s\n' "$ver" > "$tmp/.rx-version"
  rm -rf "$TOP/.rx/scripts"
  mv "$tmp" "$TOP/.rx/scripts" || { rm -rf "$tmp"; _in_die "cannot install .rx/scripts"; }
}

# ---------------------------------------------------------------- pre-commit wrapper
# _in_hook_text <base-branch>: the wrapper. It is POSIX sh and lives outside the tracked tree, so a
# branch cannot edit it. Before handing over to .rx/scripts it checks, against base_branch, that
# the branch has not deleted the config or rewritten the gate scripts it is about to run.
_in_hook_text() {
  cat <<HOOK
#!/bin/sh
$HOOK_MARK (written by rx-init-files.sh; rerun /rx:init to rewrite it)
BASE='$1'
root=\$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "\$root" || exit 1
cur=\$(git symbolic-ref --short -q HEAD 2>/dev/null)
if [ "\$cur" != "\$BASE" ] && git cat-file -e "\$BASE:.rx/config.yml" 2>/dev/null; then
  if [ ! -f .rx/config.yml ]; then
    echo "rx pre-commit: .rx/config.yml exists on \$BASE but is missing here (git checkout \$BASE -- .rx/config.yml)" >&2
    exit 1
  fi
  if ! git diff --quiet "\$BASE" -- .rx/scripts || [ -n "\$(git ls-files --others --exclude-standard .rx/scripts)" ]; then
    echo "rx pre-commit: .rx/scripts differs from \$BASE; the gate scripts change on \$BASE only (git checkout \$BASE -- .rx/scripts)" >&2
    exit 1
  fi
fi
if [ ! -x .rx/scripts/rx-precommit.sh ]; then
  [ -f .rx/config.yml ] || exit 0
  echo "rx pre-commit: .rx/scripts/rx-precommit.sh is missing; run /rx:init --refresh-scripts" >&2
  exit 1
fi
exec .rx/scripts/rx-precommit.sh "\$@"
HOOK
}

# _in_branch_ok <name>: a plain branch name only. The name is written into the hook wrapper, so
# anything the shell would interpret (quotes, spaces, $, ;) must never get there.
_in_branch_ok() {
  [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]]
}

# _in_base_branch: base_branch from the repo's config, else main. Returns 1 for an unsafe name.
_in_base_branch() {
  local b=""
  [ -f "$TOP/.rx/config.yml" ] && b="$(rx_cfg base_branch)"
  b="${b:-main}"
  _in_branch_ok "$b" || return 1
  printf '%s\n' "$b"
}

# _in_install_hook [only-if-managed]: write the wrapper. A hook that is not ours is left alone and
# the function returns 1; with an argument, an absent or foreign hook is skipped silently.
_in_install_hook() {
  local hp base
  hp="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null)" || return 0
  case "$hp" in /*) ;; *) hp="$TOP/$hp" ;; esac
  if [ -e "$hp" ] || [ -L "$hp" ]; then
    if ! grep -qF "$HOOK_MARK" "$hp" 2>/dev/null; then
      [ -n "${1-}" ] && return 0
      printf 'rx-init: a pre-commit hook that is not rx-managed already exists at %s; left untouched. Call .rx/scripts/rx-precommit.sh from it to enable the rx pre-commit gates.\n' "$hp" >&2
      return 1
    fi
  elif [ -n "${1-}" ]; then
    return 0
  fi
  base="$(_in_base_branch)" || {
    printf 'rx-init: base_branch in .rx/config.yml must be a plain branch name (letters, digits, . _ / -); pre-commit hook not installed\n' >&2
    return 1
  }
  mkdir -p "$(dirname "$hp")" || return 0
  _in_hook_text "$base" > "$hp.tmp.$$" && chmod +x "$hp.tmp.$$" && mv "$hp.tmp.$$" "$hp"
  return 0
}

# ---------------------------------------------------------------- guarded installers
# _in_lines <file>: line count, CRLF and a missing final newline counted like rx-check does.
_in_lines() {
  tr -d '\r' < "$1" | awk 'END { print NR }'
}

# _in_install_draft <draft> <dest> <max-lines> <what>: copy a validated draft to a NEW file.
_in_install_draft() {
  local src="$1" dest="$2" max="$3" what="$4" n
  [ -n "$src" ] || _in_usage
  [ -f "$src" ] || _in_die "cannot read draft $src"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    printf 'rx-init: %s already exists; not overwriting it\n' "$what" >&2
    return 1
  fi
  n="$(_in_lines "$src")"
  if [ "$n" -gt "$max" ]; then
    printf 'rx-init: %s draft has %s lines (cap %s); shorten it\n' "$what" "$n" "$max" >&2
    return 1
  fi
  return 0
}

_in_config_ok() {
  local f="$1" line key val have_test=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ $line =~ ^[[:space:]]*$ ]] || [[ $line =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if ! [[ $line =~ ^([a-z_][a-z0-9_]*):([[:space:]].*)?$ ]]; then
      printf 'rx-init: config line is not a flat `key: value`: %s\n' "$line" >&2
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    val="$(_rx_trim "${BASH_REMATCH[2]}")"
    case "$key" in
      coverage_cmd|coverage_min)
        printf 'rx-init: %s is not supported in v0.1 (coverage checking is out of scope); remove it\n' "$key" >&2
        return 1
        ;;
      test_cmd) [ -n "$val" ] && have_test=1 ;;
      base_branch)
        val="${val%%[[:space:]]#*}"
        val="$(_rx_trim "$val")"
        case "$val" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        if ! _in_branch_ok "$val"; then
          printf 'rx-init: base_branch must be a plain branch name (letters, digits, . _ / -)\n' >&2
          return 1
        fi
        ;;
    esac
  done < "$f"
  if [ "$have_test" -ne 1 ]; then
    printf 'rx-init: config needs a non-empty test_cmd\n' >&2
    return 1
  fi
  return 0
}

_in_claude_ok() {
  if tr -d '\r' < "$1" | grep -Eq '^[[:space:]]*@'; then
    printf 'rx-init: CLAUDE.md must not use @import lines (static project context only)\n' >&2
    return 1
  fi
  return 0
}

_in_put() { # <draft> <dest>
  mkdir -p "$(dirname "$2")" && cp "$1" "$2" || _in_die "cannot write $2"
  printf 'installed %s\n' "$2"
}

case "$MODE" in
  refresh)
    mkdir -p .rx
    _in_copy_scripts
    printf 'refreshed .rx/scripts to v%s\n' "$(cat .rx/scripts/.rx-version)"
    exit 0
    ;;
  config)
    _in_install_draft "$DRAFT" .rx/config.yml 1000 ".rx/config.yml" || exit 1
    _in_config_ok "$DRAFT" || exit 1
    _in_put "$DRAFT" .rx/config.yml
    _in_install_hook only-if-managed
    exit 0
    ;;
  claude)
    _in_install_draft "$DRAFT" CLAUDE.md 60 "CLAUDE.md" || exit 1
    _in_claude_ok "$DRAFT" || exit 1
    _in_put "$DRAFT" CLAUDE.md
    exit 0
    ;;
  arch)
    _in_install_draft "$DRAFT" docs/knowledge/architecture.md 80 "docs/knowledge/architecture.md" || exit 1
    _in_put "$DRAFT" docs/knowledge/architecture.md
    exit 0
    ;;
esac

# ---------------------------------------------------------------- init
mkdir -p .rx/local docs/knowledge/decisions docs/knowledge/learnings specs || _in_die "cannot create directories"

have=0
if [ -f .gitignore ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "${line%$'\r'}" in
      .rx/local/|/.rx/local/|.rx/local|/.rx/local) have=1 ;;
    esac
  done < .gitignore
fi
if [ "$have" -eq 0 ]; then
  if [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  printf '.rx/local/\n' >> .gitignore
fi

_in_copy_scripts
rc=0
_in_install_hook || rc=1

for p in ".rx/config.yml:config" "CLAUDE.md:claude_md" "docs/knowledge/architecture.md:architecture"; do
  if [ -e "${p%%:*}" ]; then
    printf '%s: present\n' "${p#*:}"
  else
    printf '%s: missing\n' "${p#*:}"
  fi
done
printf 'scripts: v%s in .rx/scripts\n' "$(cat .rx/scripts/.rx-version)"
exit "$rc"
