#!/usr/bin/env bash
# Run every tests/test_*.sh, each in its own bash process.
# Usage: tests/run.sh [tests-dir]   (default: the directory containing this script)
# Prints a PASS/FAIL line per file and a summary; exits 1 if any file failed.

dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
pass=0
fail=0
failed_files=""

total=0
for f in "$dir"/test_*.sh; do
  [ -e "$f" ] || continue
  total=$((total + 1))
  name="$(basename "$f")"
  if bash "$f"; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name"
    fail=$((fail + 1))
    failed_files="$failed_files $name"
  fi
done

if [ "$total" -eq 0 ]; then
  echo "run.sh: no test files found in $dir" >&2
  exit 1
fi
echo "----"
echo "$pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "failed:$failed_files"
  exit 1
fi
