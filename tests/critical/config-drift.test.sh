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

  if grep -q "source-deploy-drift" "$DOCTOR" 2>/dev/null; then
    echo "PASS: ws-doctor has source-deploy-drift check"
    ((pass++))
  else
    echo "FAIL: ws-doctor no longer registers the source-deploy-drift check"
    ((fail++))
  fi
}

# Test 2: Key configs exist in configs/
test_configs_exist() {
  local configs=("tmux.conf" "zshrc" "gitconfig" "aerospace.toml")
  local found=0
  for cfg in "${configs[@]}"; do
    if [[ -f "$REPO_ROOT/configs/$cfg" ]]; then
      ((found++))
    else
      echo "FAIL: configs/$cfg missing"
      ((fail++))
    fi
  done
  if (( found == ${#configs[@]} )); then
    echo "PASS: all ${#configs[@]} critical configs present"
    ((pass++))
  else
    echo "FAIL: only $found/${#configs[@]} critical configs present"
    ((fail++))
  fi
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

# Test 4: Bootstrap deploys configs idempotently.
# Bootstrap references configs via $CONFIGS_DIR (set in lib/common.sh),
# not a literal "configs" path — the old grep for "install_file.*configs"
# never matched and silently fell through to WARN. Match the real call
# shape and assert hard so a refactor that stops deploying configs fails.
test_bootstrap_deploys_configs() {
  local bs="$REPO_ROOT/macos/bootstrap.sh"
  if grep -Eq 'install_file[[:space:]]+"\$CONFIGS_DIR' "$bs" 2>/dev/null; then
    echo "PASS: Bootstrap deploys configs/ via \$CONFIGS_DIR"
    ((pass++))
  else
    echo "FAIL: macOS bootstrap no longer deploys configs via install_file \"\$CONFIGS_DIR/...\""
    ((fail++))
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
