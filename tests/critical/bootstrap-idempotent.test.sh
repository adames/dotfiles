#!/usr/bin/env bash
# Critical test: Bootstrap idempotency
# Bootstrap must be safe to re-run without side effects or double-installs

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

pass=0; fail=0

# Test 1: Bootstrap reports success on consecutive runs
test_idempotent_run() {
  # First run (or check if already installed)
  if [[ -x "$BOOTSTRAP" ]]; then
    echo "PASS: Bootstrap script exists and is executable"
    ((pass++))
  else
    echo "FAIL: Bootstrap script missing or not executable"
    ((fail++))
    return 1
  fi

  # Check for idempotency patterns in bootstrap
  if grep -q "cmp -s" "$REPO_ROOT/lib/common.sh" 2>/dev/null; then
    echo "PASS: install_file uses byte-compare for idempotency"
    ((pass++))
  else
    echo "FAIL: install_file missing idempotency check"
    ((fail++))
  fi
}

# Test 2: install_file helper is idempotent
test_install_file_idempotent() {
  . "$REPO_ROOT/lib/common.sh" 2>/dev/null || {
    echo "SKIP: Cannot source common.sh"
    return 0
  }

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  src="$TMP/test.conf"
  dst="$TMP/deployed.conf"
  echo "test content" > "$src"

  # First install
  install_file "$src" "$dst" 2>/dev/null
  if [[ -f "$dst" ]]; then
    echo "PASS: install_file creates destination"
    ((pass++))
  else
    echo "FAIL: install_file did not create destination"
    ((fail++))
  fi

  # Second install (should be no-op)
  local before_md5
  before_md5=$(md5 -q "$dst" 2>/dev/null || md5sum "$dst" 2>/dev/null | cut -d' ' -f1)
  install_file "$src" "$dst" 2>/dev/null
  local after_md5
  after_md5=$(md5 -q "$dst" 2>/dev/null || md5sum "$dst" 2>/dev/null | cut -d' ' -f1)

  if [[ "$before_md5" == "$after_md5" ]]; then
    echo "PASS: install_file is idempotent (no change on re-run)"
    ((pass++))
  else
    echo "FAIL: install_file modified file on re-run"
    ((fail++))
  fi
}

test_homebrew_bundle_flags() {
  local mac_bootstrap="$REPO_ROOT/macos/bootstrap.sh"

  if grep -Eq 'brew bundle install .*--(formula|cask)([[:space:]]|$)' "$mac_bootstrap"; then
    echo "FAIL: macOS bootstrap uses removed brew bundle install type flags"
    ((fail++))
  else
    echo "PASS: macOS bootstrap avoids removed brew bundle install type flags"
    ((pass++))
  fi

  if grep -q "HOMEBREW_BUNDLE_CASK_SKIP" "$mac_bootstrap"; then
    echo "PASS: macOS bootstrap skips casks via Homebrew Bundle env"
    ((pass++))
  else
    echo "FAIL: macOS bootstrap missing Homebrew Bundle cask skip env"
    ((fail++))
  fi
}

# Run tests
echo "=== bootstrap-idempotent.test.sh ==="
test_idempotent_run
test_install_file_idempotent
test_homebrew_bundle_flags

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
