#!/usr/bin/env bash
# tests/run-all.sh — discover and run every tests/critical/*.test.sh.
# Sequential: each test is <100ms, parallelism complicates output for
# no real win. Exits 0 only if every file exits 0.
#
# Tests focus on historically troublesome traps:
# - bootstrap idempotency
# - yabai scripting addition drift
# - config source/deploy drift
# - ws-doctor core functionality
#
# Output convention: each test prints its own `N passed, M failed`
# line on exit; this runner aggregates pass/fail counts across files
# and prints a single summary at the end.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
shopt -s nullglob

files=( "$SCRIPT_DIR"/critical/*.test.sh )
if (( ${#files[@]} == 0 )); then
  printf 'no test files found in %s/critical/\n' "$SCRIPT_DIR" >&2
  exit 1
fi

total_files=${#files[@]}
failed_files=0

for f in "${files[@]}"; do
  name="${f##*/}"
  printf '── %s ──\n' "$name"
  if "$f"; then
    :
  else
    failed_files=$((failed_files + 1))
  fi
  printf '\n'
done

printf '==== %d test file(s); %d failed ====\n' "$total_files" "$failed_files"
(( failed_files == 0 ))
