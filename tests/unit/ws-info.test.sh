#!/usr/bin/env bash
# Unit tests for configs/workspace/cli/ws-info.
#
# The helper is mostly a "compose a notification string from yabai +
# spaces.json" operation. We capture the osascript call to assert the
# composed text contains the right slot index, name, color, and icon.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/configs/workspace/cli/ws-info"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# osascript shim: appends every invocation's full arg list to a log
# file, so the test can grep for the composed notification text.
OSA_LOG="$TMP/osa.log"
cat > "$TMP/osascript" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$OSA_LOG"
exit 0
EOF
chmod 755 "$TMP/osascript"

ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

export PATH="$TMP:$PATH"
export HOME="$TMP"
mkdir -p "$HOME/.config/workspace"
cat > "$HOME/.config/workspace/spaces.json" <<'EOF'
{"palette":"catppuccin-mocha","spaces":{"2":{"name":"home","color":"#f9e2af","iconSpec":{"codepoint":"\\uf121"}}}}
EOF

pass=0; fail=0

_assert_log_contains() {
  local label="$1" needle="$2"
  if grep -qF "$needle" "$OSA_LOG" 2>/dev/null; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n  expected substring: %s\n  log:\n%s\n' "$label" "$needle" "$(cat "$OSA_LOG" 2>/dev/null)"
  fi
}

# ── Slot with full identity (name, color, icon) ─────────────────────────
: > "$OSA_LOG"
YABAI_STUB_FOCUSED_SPACE=2 "$HELPER" >/dev/null 2>&1
exit_ok=$?
[[ $exit_ok -eq 0 ]] && { pass=$((pass + 1)); printf 'ok   exits 0 on full identity slot\n'; } \
  || { fail=$((fail + 1)); printf 'FAIL expected exit 0, got %s\n' "$exit_ok"; }

_assert_log_contains "notification includes slot index"  "slot 2"
_assert_log_contains "notification includes slot name"   "home"
_assert_log_contains "notification includes hex color"   "#f9e2af"

# ── Slot with no entry in spaces.json → falls back to "(unnamed)" ───────
: > "$OSA_LOG"
YABAI_STUB_FOCUSED_SPACE=5 "$HELPER" >/dev/null 2>&1
_assert_log_contains "unknown slot falls back to '(unnamed)'" "(unnamed)"
_assert_log_contains "unknown slot still reports index"       "slot 5"

# ── yabai unavailable → exit 1, "yabai unavailable" notification ────────
# Replace the stub with a script that exits 1 + emits empty output, so
# the helper's `yabai -m query --spaces --space | jq -r '.index'`
# pipeline yields null. We can't just `rm` the symlink because that
# falls back to a real yabai on the host's PATH (macOS dev machines).
rm "$TMP/yabai"
cat > "$TMP/yabai" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 755 "$TMP/yabai"

: > "$OSA_LOG"
"$HELPER" >/dev/null 2>&1
exit_down=$?
[[ $exit_down -eq 1 ]] && { pass=$((pass + 1)); printf 'ok   yabai unavailable exits 1\n'; } \
  || { fail=$((fail + 1)); printf 'FAIL expected exit 1 when yabai missing, got %s\n' "$exit_down"; }
_assert_log_contains "yabai-down notification fired" "yabai unavailable"
# Restore the stub for any later test additions.
rm "$TMP/yabai"
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
