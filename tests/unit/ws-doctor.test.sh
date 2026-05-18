#!/usr/bin/env bash
# Unit tests for bin/ws-doctor — specifically the yabai-sa-load check.
#
# ws-doctor has a --only=NAME flag for running a single check in
# isolation; we exploit it to keep this test focused. yabai is stubbed
# via the shared fixture; YABAI_STUB_FAIL=sa stages a scripting-
# addition error, any other non-empty value exits non-zero without
# that magic string.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"
export PATH="$TMP:$PATH"
export YABAI_STUB_CALL_LOG="$TMP/yabai.log"

# ws-doctor sources lib/common.sh and uses DOTFILES_DIR / CONFIGS_DIR
# in error messages. Inherit the real values so paths resolve.
export DOTFILES_DIR="$REPO_ROOT"
export CONFIGS_DIR="$REPO_ROOT/configs"

pass=0; fail=0

# Use `command grep` to dodge any user-level alias (e.g. ugrep, which
# parses leading `-m` in the pattern as its max-count flag). The `--`
# guards against patterns that start with `-`.
_grep_qF() { command grep -qF -- "$1" "${2:-/dev/null}"; }

# Run ws-doctor with --only=<check> and assert the result line contains
# a needle. Defaults to yabai-sa-load for backward compatibility with
# the existing call sites; pass a third arg to target a different check.
# No --quiet (it suppresses PASS / SKIP).
_assert_contains() {
  local label="$1" needle="$2" check="${3:-yabai-sa-load}"
  : > "$YABAI_STUB_CALL_LOG"
  local out
  out=$("$DOCTOR" "--only=$check" 2>&1 || true)
  if command grep -qF -- "$needle" <<<"$out"; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected output to contain: %s\n  actual output:\n%s\n' \
      "$label" "$needle" "$out"
  fi
}

# ── PASS: stub returns success for `space --create` + `--destroy` ───────
unset YABAI_STUB_FAIL
_assert_contains "SA loaded → PASS line"          "SA loaded"

# ── FAIL: stub emits the canonical scripting-addition error ─────────────
export YABAI_STUB_FAIL=sa
_assert_contains "SA missing → FAIL line"         "SA not loaded"
_assert_contains "FAIL message points at the installer" "yabai-sa-install.sh --force"

# ── WARN: stub exits 1 without the SA-specific stderr ──────────────────
export YABAI_STUB_FAIL=1
_assert_contains "non-SA failure → WARN line"     "non-SA reason"

# ── Probe restores focus to the originally-focused space ────────────────
# Stage focus on space index 3, then confirm the call log shows a
# `space --focus 3` after the create/destroy pair.
unset YABAI_STUB_FAIL
export YABAI_STUB_FOCUSED_SPACE=3
: > "$YABAI_STUB_CALL_LOG"
"$DOCTOR" --only=yabai-sa-load >/dev/null 2>&1 || true
if _grep_qF '-m space --focus 3' "$YABAI_STUB_CALL_LOG"; then
  pass=$((pass + 1))
  printf 'ok   probe restores focus to original space\n'
else
  fail=$((fail + 1))
  printf 'FAIL probe restores focus to original space\n  yabai log:\n%s\n' \
    "$(cat "$YABAI_STUB_CALL_LOG")"
fi

# ── slot-drift check ───────────────────────────────────────────────────
# WS_CONFIG-driven; seed a spaces.json with K slots, point yabai stub
# at K' spaces, assert the check picks the right verdict.
unset YABAI_STUB_FAIL
unset YABAI_STUB_FOCUSED_SPACE
export WS_CONFIG="$TMP/spaces.json"
_seed_spaces() {
  local n="$1" entries=""
  for (( i = 1; i <= n; i++ )); do
    [[ -n "$entries" ]] && entries+=","
    entries+="\"$i\":{\"name\":\"slot$i\",\"color\":\"#cba6f7\",\"stableLogicalLabel\":\"slot$i\",\"iconSpec\":{\"kind\":\"none\",\"fallbackSfSymbol\":\"stop.fill\",\"fallbackText\":\"S$i\",\"userOverridden\":false}}"
  done
  printf '{"palette":"catppuccin-mocha","spaces":{%s}}\n' "$entries" > "$WS_CONFIG"
}

_seed_spaces 3
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
_assert_contains "drift matched (yabai=3, json=3) → PASS" "agree on 3" slot-drift

_seed_spaces 2
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1},{"index":4,"display":1}]'
_assert_contains "drift: yabai>json → FAIL names missing count" "missing identity entry" slot-drift

_seed_spaces 5
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
_assert_contains "drift: json>yabai → FAIL describes phantom slots" "phantom slot" slot-drift

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
