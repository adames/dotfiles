#!/usr/bin/env bash
# Critical test: ws-doctor core functionality
# Health check must catch all known failure modes

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"
# The check bodies live in lib/ws-doctor-checks.sh (sourced by ws-doctor);
# the keyword greps below scan both so a moved check still counts.
CHECKS_LIB="$REPO_ROOT/lib/ws-doctor-checks.sh"
DOCTOR_SRC=("$DOCTOR" "$CHECKS_LIB")

pass=0; fail=0

# Test 1: ws-doctor exists and is executable
test_doctor_exists() {
  if [[ -x "$DOCTOR" ]]; then
    echo "PASS: ws-doctor exists and is executable"
    ((pass++))
  else
    echo "FAIL: ws-doctor missing or not executable"
    ((fail++))
  fi
}

# Test 2: Doctor has --help
test_doctor_help() {
  if "$DOCTOR" --help &>/dev/null || "$DOCTOR" -h &>/dev/null; then
    echo "PASS: ws-doctor supports --help"
    ((pass++))
  else
    echo "INFO: ws-doctor may not have --help (not critical)"
  fi
}

# Test 3: Doctor registers its critical checks.
# Assert against the dispatcher's actual check names (via `--list`), not
# free-text words like "config"/"permission" that survive in any comment
# and pass even when the named check doesn't exist.
test_doctor_checks_critical() {
  [[ -x "$DOCTOR" ]] || { echo "FAIL: ws-doctor not executable"; ((fail++)); return; }

  local listing
  listing="$("$DOCTOR" --list 2>/dev/null)"
  local required=(aerospace-freshness keystroke-collision source-deploy-drift)
  local c
  for c in "${required[@]}"; do
    if grep -q "$c" <<<"$listing"; then
      echo "PASS: ws-doctor registers $c"
      ((pass++))
    else
      echo "FAIL: ws-doctor no longer registers check: $c"
      ((fail++))
    fi
  done
}

# Test 4: Doctor runs to completion without hanging.
# ws-doctor exits with the number of FAILed checks, so a non-zero exit is a
# legitimate result, not a crash. macOS ships no `timeout`, so detect a real
# wrapper and run bare if none exists — never let a "command not found" error
# masquerade as ws-doctor output (the old `| grep -q .` bug).
test_doctor_runs() {
  [[ -x "$DOCTOR" ]] || return 0

  local runner=
  if   command -v timeout  >/dev/null 2>&1; then runner="timeout 20"
  elif command -v gtimeout >/dev/null 2>&1; then runner="gtimeout 20"
  fi

  local rc
  $runner "$DOCTOR" >/dev/null 2>&1
  rc=$?
  if (( rc == 124 || rc == 126 || rc == 127 )); then
    echo "FAIL: ws-doctor did not run cleanly (rc=$rc — timeout or exec failure)"
    ((fail++))
  else
    echo "PASS: ws-doctor ran to completion (exit $rc = FAILed checks, not a crash)"
    ((pass++))
  fi
}

# Run tests
echo "=== ws-doctor.test.sh ==="
test_doctor_exists
test_doctor_help
test_doctor_checks_critical
test_doctor_runs

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
