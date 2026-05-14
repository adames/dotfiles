#!/usr/bin/env bash
# Unit tests for configs/workspace/cli/ws-focus.
#
# Stubs yabai + osascript via PATH override. The helper writes
# notifications via osascript; we silence them with a no-op stub so
# tests don't pop UI on macOS dev machines. Linux CI never has
# osascript on PATH and the stub fills that gap.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/configs/workspace/cli/ws-focus"
FIXTURES="$REPO_ROOT/tests/fixtures"

# Per-test sandbox: prepended PATH (stub yabai + osascript), HOME
# pointing at a tmpdir so the helper never touches real state.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# Tiny osascript no-op stub: every call exits 0, prints nothing. The
# helper only invokes osascript for notifications (fire-and-forget).
cat > "$TMP/osascript" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 755 "$TMP/osascript"

# yabai-stub lives in tests/fixtures/. Symlink it to a PATH-visible
# name so the helper's `yabai -m ...` resolves correctly.
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

export PATH="$TMP:$PATH"
export YABAI_STUB_CALL_LOG="$TMP/calls.log"

pass=0; fail=0
_assert() {
  local label="$1" expected_exit="$2"; shift 2
  : > "$YABAI_STUB_CALL_LOG"
  local actual_exit=0
  "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" ]]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected exit: %s\n  actual exit:   %s\n' "$label" "$expected_exit" "$actual_exit"
  fi
}

_assert_called() {
  local label="$1" needle="$2"
  if grep -qF "$needle" "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected call containing: %s\n  actual log:\n%s\n' "$label" "$needle" "$(cat "$YABAI_STUB_CALL_LOG" 2>/dev/null)"
  fi
}

# ── missing arg → loud failure, exit 2 (per helper's own contract) ──
_assert "missing slot arg exits 2" 2 "$HELPER"

# ── valid slot in range (default stub: 10 spaces) → exits 0, calls focus ──
_assert        "valid slot 3 exits 0"             0 "$HELPER" 3
_assert_called "valid slot 3 invokes yabai focus" "space --focus 3"

# ── out-of-range slot → exit 1, no focus call ──
_assert "slot 99 exits 1 (out of range)" 1 "$HELPER" 99
if grep -q "space --focus 99" "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
  fail=$((fail + 1)); printf 'FAIL out-of-range slot should not invoke focus\n'
else
  pass=$((pass + 1)); printf 'ok   out-of-range slot does not invoke focus\n'
fi

# ── boundary: slot 10 with 10 spaces is valid; slot 11 is not ──
_assert "slot 10 (last) exits 0" 0 "$HELPER" 10
_assert "slot 11 exits 1"        1 "$HELPER" 11

# ── slot 0 (out of 1..N range) → exit 1 ──
_assert "slot 0 exits 1" 1 "$HELPER" 0

# ── yabai unavailable (non-JSON response) → exit 1 ──
# The stub falls back to the default 10-space list when SPACES_JSON is
# unset, so we force a non-JSON response to provoke jq parsing failure
# and exercise the helper's "yabai unavailable" branch.
YABAI_STUB_SPACES_JSON='not json' _assert "yabai unavailable exits 1" 1 "$HELPER" 3

# ── non-numeric target (literal junk) shouldn't crash ──
# ws-focus accepts numeric slots OR `next`/`prev` (handled below). A
# random string falls through to yabai, which either accepts or
# rejects; either outcome is fine as long as the helper doesn't crash.
_assert "non-numeric target does not crash" 0 "$HELPER" foo

# ── next/prev wrap with the default 10-space stub ──
# Focused space defaults to 1. `next` resolves to 2; `prev` wraps to 10.
_assert        "next from 1 → 2 exits 0"     0 "$HELPER" next
_assert_called "next from 1 sends to slot 2" "space --focus 2"

YABAI_STUB_FOCUSED_SPACE=10 _assert        "next from 10 wraps to 1"     0 "$HELPER" next
YABAI_STUB_FOCUSED_SPACE=10 _assert_called "next from 10 sends to slot 1" "space --focus 1"

YABAI_STUB_FOCUSED_SPACE=1 _assert        "prev from 1 wraps to last"    0 "$HELPER" prev
YABAI_STUB_FOCUSED_SPACE=1 _assert_called "prev from 1 sends to slot 10" "space --focus 10"

YABAI_STUB_FOCUSED_SPACE=5 _assert        "prev from 5 → 4"              0 "$HELPER" prev
YABAI_STUB_FOCUSED_SPACE=5 _assert_called "prev from 5 sends to slot 4"  "space --focus 4"

# ── next/prev on a one-space configuration → wraps to itself, exits 0 ──
SINGLE_SPACE='[{"index":1,"display":1,"has-focus":true}]'
YABAI_STUB_SPACES_JSON="$SINGLE_SPACE" YABAI_STUB_FOCUSED_SPACE=1 \
  _assert "next with count=1 wraps to self" 0 "$HELPER" next
YABAI_STUB_SPACES_JSON="$SINGLE_SPACE" YABAI_STUB_FOCUSED_SPACE=1 \
  _assert_called "wrap-1 next still sends to slot 1" "space --focus 1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
