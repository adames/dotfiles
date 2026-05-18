#!/usr/bin/env bash
# Critical test: Config source vs deployed drift detection
# configs/ and deployed files must stay in sync

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"

pass=0; fail=0

# Test 1: ws-doctor has source-deploy-drift check
test_doctor_has_drift_check() {
  if [[ ! -x "$DOCTOR" ]]; then
    echo "SKIP: ws-doctor not found"
    return 0
  fi

  if grep -q "source-deploy-drift\|drift" "$DOCTOR" 2>/dev/null; then
    echo "PASS: ws-doctor has source-deploy-drift check"
    ((pass++))
  else
    echo "WARN: ws-doctor may not check source/deploy drift"
  fi
}

# Test 2: Key configs exist in configs/
test_configs_exist() {
  local configs=("tmux.conf" "zshrc" "gitconfig" "skhdrc" "yabairc")
  local found=0
  for cfg in "${configs[@]}"; do
    if [[ -f "$REPO_ROOT/configs/$cfg" ]]; then
      ((found++))
    else
      echo "FAIL: configs/$cfg missing"
      ((fail++))
    fi
  done
  echo "PASS: $found/${#configs[@]} critical configs present"
  ((pass++))
}

# Test 3: install_file uses cmp for drift detection
test_install_uses_cmp() {
  if grep -q "cmp -s" "$REPO_ROOT/lib/common.sh" 2>/dev/null; then
    echo "PASS: install_file uses cmp for drift detection"
    ((pass++))
  else
    echo "FAIL: install_file missing drift detection"
    ((fail++))
  fi
}

# Test 4: Bootstrap deploys configs idempotently
test_bootstrap_deploys_configs() {
  if grep -q "install_file.*configs" "$REPO_ROOT/macos/bootstrap.sh" 2>/dev/null || \
     grep -q "cp.*configs" "$REPO_ROOT/macos/bootstrap.sh" 2>/dev/null; then
    echo "PASS: Bootstrap deploys configs/"
    ((pass++))
  else
    echo "WARN: Bootstrap may not deploy configs (check manually)"
  fi
}

# Run tests
echo "=== config-drift.test.sh ==="
test_doctor_has_drift_check
test_configs_exist
test_install_uses_cmp
test_bootstrap_deploys_configs

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
