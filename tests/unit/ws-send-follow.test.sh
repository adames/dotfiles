#!/usr/bin/env bash
# Unit tests for configs/workspace/cli/ws-send-follow.
#
# Most valuable file in the helper test suite: it pins down the
# next/prev wrap-around index math
#   next: (cur % count) + 1
#   prev: ((cur - 2 + count) % count) + 1
# which has off-by-one and wrap-edge traps a manual test would miss.
#
# Also asserts the helper refuses to act when no window is focused —
# the exact bug from the old Mod+digit chord that motivated the rewrite.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/configs/workspace/cli/ws-send-follow"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

cat > "$TMP/osascript" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 755 "$TMP/osascript"
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

export PATH="$TMP:$PATH"
export YABAI_STUB_CALL_LOG="$TMP/calls.log"

pass=0; fail=0

_run() { : > "$YABAI_STUB_CALL_LOG"; "$@" >/dev/null 2>&1; return $?; }

_assert_exit() {
  local label="$1" want="$2"; shift 2
  local got=0; _run "$@" || got=$?
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL %s (want exit %s, got %s)\n' "$label" "$want" "$got"
  fi
}

_assert_called() {
  local label="$1" needle="$2"
  if grep -qF "$needle" "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  log:\n%s\n' "$label" "$needle" "$(cat "$YABAI_STUB_CALL_LOG")"
  fi
}

_assert_not_called() {
  local label="$1" needle="$2"
  if grep -qF "$needle" "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
    fail=$((fail + 1)); printf 'FAIL %s (should not be called: %s)\n' "$label" "$needle"
  else
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  fi
}

# ── arg validation ──────────────────────────────────────────────────────
_assert_exit "missing arg exits 2" 2 "$HELPER"

# ── no focused window → loud failure, no window --space call ────────────
YABAI_STUB_FOCUSED_WINDOW=null _run "$HELPER" 3
exit_no_win=$?
if [[ "$exit_no_win" == 1 ]]; then
  pass=$((pass + 1)); printf 'ok   no focused window exits 1\n'
else
  fail=$((fail + 1)); printf 'FAIL no focused window expected exit 1, got %s\n' "$exit_no_win"
fi
_assert_not_called "no-window: yabai window --space not called" "window --space"

# ── happy path: send to slot 5 with a window focused ────────────────────
_assert_exit  "send to slot 5 exits 0" 0 "$HELPER" 5
_assert_called "send to 5 calls window --space 5" "window --space 5"
_assert_called "send to 5 also focuses space 5"   "space --focus 5"

# ── out-of-range slot (default 10 spaces) → exit 1, no send ─────────────
_assert_exit       "slot 99 exits 1"                       1 "$HELPER" 99
_assert_not_called "out-of-range: window --space not called" "window --space 99"

# ── next/prev wrap-around math ──────────────────────────────────────────
# Stub default has 10 spaces (index 1..10).

# next: (cur % count) + 1
YABAI_STUB_FOCUSED_SPACE=1 _assert_exit "next from 1 of 10" 0 "$HELPER" next
_assert_called "next from 1 sends to 2" "window --space 2"

YABAI_STUB_FOCUSED_SPACE=10 _assert_exit "next from 10 wraps to 1" 0 "$HELPER" next
_assert_called "next from 10 wraps to slot 1" "window --space 1"

YABAI_STUB_FOCUSED_SPACE=5 _assert_exit "next from 5 → 6" 0 "$HELPER" next
_assert_called "next from 5 sends to 6" "window --space 6"

# prev: ((cur - 2 + count) % count) + 1
YABAI_STUB_FOCUSED_SPACE=2 _assert_exit "prev from 2 → 1" 0 "$HELPER" prev
_assert_called "prev from 2 sends to 1" "window --space 1"

YABAI_STUB_FOCUSED_SPACE=1 _assert_exit "prev from 1 wraps to last" 0 "$HELPER" prev
_assert_called "prev from 1 wraps to slot 10" "window --space 10"

YABAI_STUB_FOCUSED_SPACE=5 _assert_exit "prev from 5 → 4" 0 "$HELPER" prev
_assert_called "prev from 5 sends to 4" "window --space 4"

# ── single-space edge: COUNT=1 → next/prev are no-ops (same slot) ───────
SINGLE_SPACE='[{"index":1,"display":1}]'
YABAI_STUB_SPACES_JSON="$SINGLE_SPACE" YABAI_STUB_FOCUSED_SPACE=1 \
  _assert_exit "next with COUNT=1 → same slot, exits 0" 0 "$HELPER" next
_assert_called "COUNT=1 next still sends (slot 1)" "window --space 1"

# ── COUNT=3 wrap edges ──────────────────────────────────────────────────
THREE_SPACES='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
YABAI_STUB_SPACES_JSON="$THREE_SPACES" YABAI_STUB_FOCUSED_SPACE=3 \
  _assert_exit "COUNT=3 next from 3 wraps to 1" 0 "$HELPER" next
_assert_called "wrap-next sends to 1" "window --space 1"

YABAI_STUB_SPACES_JSON="$THREE_SPACES" YABAI_STUB_FOCUSED_SPACE=1 \
  _assert_exit "COUNT=3 prev from 1 wraps to 3" 0 "$HELPER" prev
_assert_called "wrap-prev sends to 3" "window --space 3"

# ── yabai action failure → loud failure ─────────────────────────────────
YABAI_STUB_FAIL=1 _assert_exit "yabai send failure exits 1" 1 "$HELPER" 5

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
