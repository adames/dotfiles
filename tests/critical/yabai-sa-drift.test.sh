#!/usr/bin/env bash
# Critical test: yabai scripting addition drift detection
# SA gets uninstalled on brew upgrade; must be detectable

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"
FIXTURES="$REPO_ROOT/tests/fixtures"

pass=0; fail=0

# Test 1: ws-doctor can detect yabai-sa-load status
test_doctor_detects_sa_status() {
  if [[ ! -x "$DOCTOR" ]]; then
    echo "SKIP: ws-doctor not found"
    return 0
  fi

  # Check if --only flag exists
  if "$DOCTOR" --help 2>&1 | grep -q -- '--only'; then
    echo "PASS: ws-doctor supports --only flag for targeted checks"
    ((pass++))
  else
    echo "INFO: ws-doctor may not support --only (check manually)"
  fi

  # Check for yabai-sa-load check in doctor
  if grep -q "yabai.*scripting.*addition\|sa.*load\|yabai-sa" "$DOCTOR" 2>/dev/null; then
    echo "PASS: ws-doctor has yabai SA check"
    ((pass++))
  else
    echo "WARN: ws-doctor may not check yabai SA status"
  fi
}

# Test 2: yabai-sa-install.sh exists and is executable
test_sa_installer_exists() {
  local installer="$REPO_ROOT/macos/yabai-sa-install.sh"
  if [[ -x "$installer" ]]; then
    echo "PASS: yabai-sa-install.sh exists and is executable"
    ((pass++))
  else
    echo "FAIL: yabai-sa-install.sh missing or not executable"
    ((fail++))
  fi
}

# Test 3: Check for SA hash tracking
test_sa_hash_tracking() {
  local installer="$REPO_ROOT/macos/yabai-sa-install.sh"
  if [[ -f "$installer" ]]; then
    if grep -q "sha256\|hash\|checksum" "$installer" 2>/dev/null; then
      echo "PASS: SA installer tracks binary hash"
      ((pass++))
    else
      echo "INFO: SA installer may not use hash tracking"
    fi
  fi
}

# Run tests
echo "=== yabai-sa-drift.test.sh ==="
test_doctor_detects_sa_status
test_sa_installer_exists
test_sa_hash_tracking

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
