#!/usr/bin/env bash
# Unit tests for configs/workspace/on-space-created.sh.
#
# The handler fires on yabai's space_created signal and grows
# spaces.json so its slot count matches yabai's current count. Tests
# stub yabai via the shared fixture and point WS_BIN at the real
# `ws` CLI with a sandboxed WS_CONFIG. The handler delegates to
# `ws add --no-prompt` (with WS_GROW_YABAI_ON_ADD=0 to avoid
# re-calling yabai), so we're really testing the orchestration:
# count comparison, the missing-loop, and idempotency.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HANDLER="$REPO_ROOT/configs/workspace/on-space-created.sh"
WS="$REPO_ROOT/configs/workspace/cli/ws"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

export WS_CONFIG="$TMP/spaces.json"
export WS_BIN="$WS"
export WS_HANDLER="$TMP/nonexistent"
export WS_HOOK="$TMP/nonexistent"
export WS_THEMES_DIR="$TMP/themes"
export WS_SF_MAP="$TMP/nonexistent"
export YABAI_STUB_CALL_LOG="$TMP/yabai.log"

# Seed spaces.json with N slots (defaults to 2). Each slot is the
# minimal v2 shape the cascade is happy with.
_seed() {
  local n="${1:-2}"
  local entries=""
  for (( i = 1; i <= n; i++ )); do
    [[ -n "$entries" ]] && entries+=","
    entries+="\"$i\":{\"name\":\"slot$i\",\"color\":\"#cba6f7\",\"stableLogicalLabel\":\"slot$i\",\"iconSpec\":{\"kind\":\"none\",\"fallbackSfSymbol\":\"stop.fill\",\"fallbackText\":\"S$i\",\"userOverridden\":false}}"
  done
  printf '{"palette":"catppuccin-mocha","spaces":{%s}}\n' "$entries" > "$WS_CONFIG"
}

pass=0; fail=0

_assert_count() {
  local label="$1" expected="$2"
  local actual
  actual=$(command jq '.spaces | length' "$WS_CONFIG" 2>/dev/null || echo 0)
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected slot count: %s\n  actual:              %s\n  spaces.json:\n%s\n' \
      "$label" "$expected" "$actual" "$(cat "$WS_CONFIG")"
  fi
}

# ── 1. yabai grew by 1; handler appends one identity ────────────────────
_seed 2
# Default stub returns 10 spaces; trim to 3 so we test a real gap.
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
PATH="$TMP:$PATH" bash "$HANDLER"
_assert_count "yabai:3 / json:2 → grows to 3" 3

# ── 2. yabai grew by 3; handler appends three identities ────────────────
_seed 1
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1},{"index":4,"display":1}]'
PATH="$TMP:$PATH" bash "$HANDLER"
_assert_count "yabai:4 / json:1 → grows to 4" 4

# ── 3. counts already match → no-op ─────────────────────────────────────
_seed 3
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
PATH="$TMP:$PATH" bash "$HANDLER"
_assert_count "yabai:3 / json:3 → no change" 3

# ── 4. json HAS MORE than yabai → handler does NOT touch it ────────────
# (That's on-space-destroyed.sh's job, not ours.)
_seed 5
export YABAI_STUB_SPACES_JSON='[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1}]'
PATH="$TMP:$PATH" bash "$HANDLER"
_assert_count "yabai:3 / json:5 → unchanged (prune is destroyed handler's job)" 5

# ── 5. WS_CONFIG missing → exits 0 quietly ──────────────────────────────
rm -f "$WS_CONFIG"
PATH="$TMP:$PATH" bash "$HANDLER"
exit_code=$?
if (( exit_code == 0 )); then
  pass=$((pass + 1)); printf 'ok   missing WS_CONFIG → exits 0\n'
else
  fail=$((fail + 1)); printf 'FAIL missing WS_CONFIG → exits 0 (got %s)\n' "$exit_code"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
