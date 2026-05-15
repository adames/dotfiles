#!/usr/bin/env bash
# Unit tests for configs/workspace/topology/Sources/ws-prompt.
#
# Drives the binary in --simulate-keys (headless) mode with a stubbed
# yabai and a fixture spaces.json. Asserts the printed "action=..."
# line and the exit code. The full live overlay (NSEvent / SwiftUI
# window) is covered by the manual test matrix; this file pins the
# state machine + helper-dispatch contract.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"

# Find the built binary. We prefer the release build inside the swift
# build dir (matches what install.sh symlinks), and fall back to the
# debug binary so a `swift build` without -c release also works.
TOPOLOGY="$REPO_ROOT/configs/workspace/topology"
BIN_RELEASE="$TOPOLOGY/.build/release/ws-prompt"
BIN_DEBUG="$TOPOLOGY/.build/debug/ws-prompt"
if [[ -x "$BIN_RELEASE" ]]; then
  BIN="$BIN_RELEASE"
elif [[ -x "$BIN_DEBUG" ]]; then
  BIN="$BIN_DEBUG"
else
  echo "ws-prompt binary not built; run 'swift build -c release' in $TOPOLOGY" >&2
  echo "skipping ws-prompt simulate tests" >&2
  echo "0 passed, 0 failed"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# yabai-stub: same fixture as the other tests use, default 10 spaces.
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"
chmod 755 "$TMP/yabai"
export YABAI_BIN="$TMP/yabai"
export YABAI_STUB_CALL_LOG="$TMP/yabai.calls.log"

# Spaces fixture with three named slots.
export WS_CONFIG="$FIXTURES/ws-prompt-spaces.json"

pass=0; fail=0
_run() {
  local label="$1" expected_exit="$2" expected_substr="$3"; shift 3
  : > "$YABAI_STUB_CALL_LOG"
  local actual_exit=0
  local out
  out=$("$BIN" "$@" 2>/dev/null) || actual_exit=$?
  if [[ "$actual_exit" != "$expected_exit" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected exit: %s\n  actual exit:   %s\n  output: %s\n' \
      "$label" "$expected_exit" "$actual_exit" "$out"
    return
  fi
  if [[ -n "$expected_substr" ]] && ! grep -qF "$expected_substr" <<<"$out"; then
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected output to contain: %s\n  actual output: %s\n' \
      "$label" "$expected_substr" "$out"
    return
  fi
  pass=$((pass + 1))
  printf 'ok   %s\n' "$label"
}

# ── focus mode ──────────────────────────────────────────────────────────
_run "caps+f 1 focuses slot 1"    0 "helper=ws-focus arg=1" \
  focus --simulate-keys "1"
_run "caps+f 0 focuses slot 10"   0 "helper=ws-focus arg=10" \
  focus --simulate-keys "0"
_run "caps+f 5 focuses slot 5"    0 "helper=ws-focus arg=5" \
  focus --simulate-keys "5"

# ── go (send) mode ──────────────────────────────────────────────────────
_run "caps+g 3 sends to slot 3"  0 "helper=ws-send-follow arg=3" \
  send --simulate-keys "3"
_run "caps+g 0 sends to slot 10" 0 "helper=ws-send-follow arg=10" \
  send --simulate-keys "0"

# ── name fuzzy match (Enter commits) ────────────────────────────────────
_run "caps+f home<CR> focuses by name (slot 1)" 0 "helper=ws-focus arg=1" \
  focus --simulate-keys "home<CR>"
_run "caps+g docs<CR> sends by name (slot 3)"  0 "helper=ws-send-follow arg=3" \
  send --simulate-keys "docs<CR>"

# ── all-numeric query via backspace-erasure → slot 11 ───────────────────
_run "caps+f x<BS>11<CR> focuses slot 11" 0 "helper=ws-focus arg=11" \
  focus --simulate-keys "x<BS>11<CR>"

# ── Esc cancels ─────────────────────────────────────────────────────────
_run "caps+f <ESC> cancels" 1 "action=cancel" \
  focus --simulate-keys "<ESC>"
_run "caps+g <ESC> cancels" 1 "action=cancel" \
  send --simulate-keys "<ESC>"

# ── structural: no sticky skhd modes remain (only `default` is allowed) ─
if grep -E '^::' "$REPO_ROOT/configs/skhdrc" | grep -vE '^:: default\b' | grep -q .; then
  fail=$((fail + 1))
  printf 'FAIL skhdrc still declares non-default modes:\n%s\n' \
    "$(grep -E '^::' "$REPO_ROOT/configs/skhdrc")"
else
  pass=$((pass + 1))
  printf 'ok   skhdrc has no sticky workspace modes\n'
fi

# ── manage mode is wired up (chord present, accepted by binary) ─────────
if grep -qE '^cmd \+ alt \+ ctrl - return.*ws-prompt.*manage' "$REPO_ROOT/configs/skhdrc"; then
  pass=$((pass + 1))
  printf 'ok   skhdrc binds Caps+Shift+Return to ws-prompt manage\n'
else
  fail=$((fail + 1))
  printf 'FAIL skhdrc missing Caps+Shift+Return → ws-prompt manage binding\n'
fi
# Manage mode is live-only (multi-stage state machine + Process exec).
# Smoke test: binary accepts the mode as an arg without crashing. Use
# --simulate-keys to exercise the arg-parse path; manage rejects the
# flag explicitly, which is the documented contract.
manage_out=$("$BIN" manage --simulate-keys "a" 2>&1)
manage_exit=$?
if [[ "$manage_exit" == "2" ]] && grep -qF 'not supported in manage mode' <<<"$manage_out"; then
  pass=$((pass + 1))
  printf 'ok   ws-prompt manage mode accepted (simulate-keys rejected as expected)\n'
else
  fail=$((fail + 1))
  printf 'FAIL ws-prompt manage mode arg parse broken\n  exit=%s out=%s\n' "$manage_exit" "$manage_out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
