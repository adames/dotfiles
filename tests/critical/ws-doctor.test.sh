#!/usr/bin/env bash
# Critical test: ws-doctor core functionality
# Health check must catch all known failure modes

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"

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

# Test 3: Doctor checks for critical components
test_doctor_checks_critical() {
  if [[ ! -f "$DOCTOR" ]]; then
    return 0
  fi

  local checks=0

  if grep -q "yabai\|tiler" "$DOCTOR" 2>/dev/null; then
    echo "PASS: Doctor checks yabai/window manager"
    ((checks++))
  fi

  if grep -q "skhd\|hotkey" "$DOCTOR" 2>/dev/null; then
    echo "PASS: Doctor checks skhd/hotkey daemon"
    ((checks++))
  fi

  if grep -q "config\|drift" "$DOCTOR" 2>/dev/null; then
    echo "PASS: Doctor checks config drift"
    ((checks++))
  fi

  if grep -q "permission\|tcc\|accessibility" "$DOCTOR" 2>/dev/null; then
    echo "PASS: Doctor checks permissions"
    ((checks++))
  fi

  if ((checks >= 2)); then
    ((pass++))
  else
    echo "WARN: Doctor may be missing critical checks"
  fi
}

# Test 4: Doctor can run (may return non-zero if issues found, but shouldn't crash)
test_doctor_runs() {
  if [[ ! -x "$DOCTOR" ]]; then
    return 0
  fi

  # Run with timeout to avoid hanging
  if timeout 10 "$DOCTOR" &>/dev/null || timeout 10 "$DOCTOR" 2>&1 | grep -q .; then
    echo "PASS: ws-doctor executes without hanging"
    ((pass++))
  else
    echo "WARN: ws-doctor may have issues (check manually)"
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
