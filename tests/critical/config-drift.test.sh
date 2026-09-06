#!/usr/bin/env bash
# Critical test: Config source vs deployed drift detection
# configs/ and deployed files must stay in sync

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"
CHECKS_LIB="$REPO_ROOT/lib/ws-doctor-checks.sh"

pass=0; fail=0

# Test 1: ws-doctor has source-deploy-drift check
# Grepping "drift" against the whole doctor script matched the word in
# any stray comment — tighten to the actual check: the function body
# must exist in lib/ws-doctor-checks.sh AND be wired into bin/ws-doctor's
# CHECKS dispatcher, or the check simply doesn't run.
test_doctor_has_drift_check() {
  if [[ ! -x "$DOCTOR" ]]; then
    echo "SKIP: ws-doctor not found"
    return 0
  fi

  if grep -q 'check_source_deploy_drift()' "$CHECKS_LIB" 2>/dev/null \
     && grep -q 'source-deploy-drift:check_source_deploy_drift' "$DOCTOR" 2>/dev/null; then
    echo "PASS: ws-doctor defines and registers source-deploy-drift check"
    ((pass++))
  else
    echo "FAIL: source-deploy-drift check missing or not registered in CHECKS"
    ((fail++))
  fi
}

# Test 2: Key configs exist in configs/
test_configs_exist() {
  local configs=("tmux.conf" "zshrc" "gitconfig")
  # ghostty-config is macOS-only and pruned from sparse Linux clones
  # (lib/platform-manifest.sh). Only exempt it when sparse-checkout is
  # actually active — a full clone missing it must still fail.
  if [[ -f "$REPO_ROOT/configs/ghostty-config" ]] \
     || [[ "$(git -C "$REPO_ROOT" config --type=bool core.sparsecheckout 2>/dev/null)" != "true" ]]; then
    configs+=("ghostty-config")
  fi
  local found=0
  for cfg in "${configs[@]}"; do
    if [[ -f "$REPO_ROOT/configs/$cfg" ]]; then
      ((found++))
    else
      echo "FAIL: configs/$cfg missing"
      ((fail++))
    fi
  done
  # Only count the summary as a pass when every config was actually
  # found — printing PASS unconditionally masked the per-config FAILs
  # above.
  if (( found == ${#configs[@]} )); then
    echo "PASS: $found/${#configs[@]} critical configs present"
    ((pass++))
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
  # Same invariant on both platforms — assert against the bootstrap this
  # clone actually carries (sparse Linux clones prune macos/).
  local bs="$REPO_ROOT/macos/bootstrap.sh" name="macos"
  [[ -f "$bs" ]] || { bs="$REPO_ROOT/ubuntu/bootstrap.sh"; name="ubuntu"; }
  if grep -Eq 'install_file[[:space:]]+"\$CONFIGS_DIR' "$bs" 2>/dev/null; then
    echo "PASS: $name bootstrap deploys configs/ via \$CONFIGS_DIR"
    ((pass++))
  else
    echo "FAIL: $name bootstrap no longer deploys configs via install_file \"\$CONFIGS_DIR/...\""
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
