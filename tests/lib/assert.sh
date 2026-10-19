#!/usr/bin/env bash
# Minimal assertion library (bash 3.2 compatible).
#
# Every assert_* prints a diagnostic to stderr and returns 1 on failure. It also
# records the failure, so that a test file which sources this library exits
# non-zero at the end even if the caller ignored the return value and the
# script would otherwise have exited 0. Assertions run inside a subshell
# (e.g. `( assert_eq a b )`) simply exit 1 with the same diagnostic.

RX_FAILS=${RX_FAILS:-0}
RX_EXIT_HOOKS=${RX_EXIT_HOOKS:-}

# rx_add_exit_hook <function>: run <function> at shell exit (before the final
# status is decided). Libraries share one EXIT trap this way.
rx_add_exit_hook() {
  RX_EXIT_HOOKS="$RX_EXIT_HOOKS $1"
}

_rx_on_exit() {
  local rc=$? hook
  for hook in $RX_EXIT_HOOKS; do
    "$hook" || true
  done
  if [ "$rc" -eq 0 ] && [ "$RX_FAILS" -gt 0 ]; then
    echo "FAILED: $RX_FAILS assertion(s) failed" >&2
    exit 1
  fi
}
trap '_rx_on_exit' EXIT

_rx_fail() {
  RX_FAILS=$((RX_FAILS + 1))
  echo "ASSERT FAIL: $*" >&2
  return 1
}

# assert_eq <expected> <actual> [message]
assert_eq() {
  if [ "$1" = "$2" ]; then
    return 0
  fi
  _rx_fail "${3:-assert_eq}"$'\n'"  expected: $1"$'\n'"  actual:   $2"
}

# assert_exit <code> <cmd...>: run cmd (output discarded), compare its exit code.
assert_exit() {
  local want="$1" got=0
  shift
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    return 0
  fi
  _rx_fail "assert_exit: '$*'"$'\n'"  expected exit: $want"$'\n'"  actual exit:   $got"
}

# assert_contains <haystack> <needle> [message]: literal substring match.
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  _rx_fail "${3:-assert_contains}"$'\n'"  needle:   $2"$'\n'"  haystack: $1"
}
