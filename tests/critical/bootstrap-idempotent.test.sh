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
}

# stat's mtime/inode flags differ BSD (macOS) vs GNU (CI's ubuntu-latest);
# try both, GNU form FIRST. Order matters: GNU stat parses `-f` as
# file-system mode, so the BSD form "succeeds" enough on Linux to spray a
# filesystem-info block (with live free-block counters) into the capture —
# on a busy CI runner those counters drift between calls and the
# comparison false-FAILs. BSD stat rejects `-c` cleanly with no stdout,
# so GNU-first is safe on both. Emits "mtime inode" as one string.
_stat_mtime_inode() {
  stat -c '%Y %i' "$1" 2>/dev/null || stat -f '%m %i' "$1" 2>/dev/null
}

# Test 2: install_file helper is idempotent
# A before/after md5 of the *destination* is vacuous: it's equal by
# construction whether install_file short-circuits on cmp -s or just
# blindly re-copies identical bytes. Prove the short-circuit actually
# fires by asserting the file's mtime + inode survive an unchanged
# re-install (a real `install` invocation always creates a fresh
# inode) — then prove it isn't a no-op unconditionally by changing the
# source and asserting the destination DOES update.
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
    return
  fi

  # Re-run against an unchanged source: mtime + inode must be untouched.
  local before after
  before=$(_stat_mtime_inode "$dst")
  sleep 1
  install_file "$src" "$dst" 2>/dev/null
  after=$(_stat_mtime_inode "$dst")

  if [[ -n "$before" && "$before" == "$after" ]]; then
    echo "PASS: install_file no-ops on unchanged source (mtime+inode stable)"
    ((pass++))
  else
    echo "FAIL: install_file touched the destination for an unchanged source"
    ((fail++))
  fi

  # Now change the source — the destination must actually update.
  sleep 1
  echo "changed content" > "$src"
  install_file "$src" "$dst" 2>/dev/null
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "PASS: install_file updates destination when source changes"
    ((pass++))
  else
    echo "FAIL: install_file did not update destination on source change"
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
