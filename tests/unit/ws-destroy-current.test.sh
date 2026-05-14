#!/usr/bin/env bash
# Unit tests for configs/workspace/cli/ws-destroy-current.
#
# Stubs:
#   - yabai (canned focused-space query)
#   - osascript (heredoc dialog; returns "Cancel" or "Destroy" via env)
#   - ws (logs its args; never actually mutates anything)
#
# Asserts:
#   - "Cancel" path → exits 0, does NOT invoke `ws remove`
#   - "Destroy" path → invokes `ws remove <index> -y`
#   - missing $HOME/.config/workspace/spaces.json is tolerated

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/configs/workspace/cli/ws-destroy-current"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# osascript shim: prints whatever's in $OSASCRIPT_STUB_RETURN. Real
# osascript writes the dialog's button label to stdout; "display
# notification" calls also go through here and produce no output —
# the helper ignores their return value, so a single shim covers both.
cat > "$TMP/osascript" <<'EOF'
#!/usr/bin/env bash
# Notifications (any arg list containing "display notification") return
# silently. Dialog calls (heredoc on stdin) return the canned button.
if [[ "$*" == *"display notification"* ]]; then
  exit 0
fi
# Otherwise it's the heredoc-driven display dialog → echo the canned
# button name.
printf '%s\n' "${OSASCRIPT_STUB_RETURN:-Cancel}"
exit 0
EOF
chmod 755 "$TMP/osascript"

ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

# ws stub: logs every invocation to a file the test inspects. Must
# print nothing on stdout so the helper's exec doesn't propagate
# unexpected output. Returns 0 unless $WS_STUB_FAIL is set.
WS_STUB_LOG="$TMP/ws-calls.log"
cat > "$TMP/ws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WS_STUB_LOG"
[[ -n "\${WS_STUB_FAIL:-}" ]] && exit 1
exit 0
EOF
chmod 755 "$TMP/ws"
export WS_BIN="$TMP/ws"

# Minimal spaces.json so the jq lookup for slot name doesn't error.
export HOME="$TMP"
mkdir -p "$HOME/.config/workspace"
cat > "$HOME/.config/workspace/spaces.json" <<'EOF'
{"palette":"catppuccin-mocha","spaces":{"1":{"name":"work"},"3":{"name":"docs"}}}
EOF

export PATH="$TMP:$PATH"
export YABAI_STUB_FOCUSED_SPACE=3

pass=0; fail=0

_run_cancel() {
  : > "$WS_STUB_LOG"
  OSASCRIPT_STUB_RETURN=Cancel "$HELPER" >/dev/null 2>&1
}

_run_destroy() {
  : > "$WS_STUB_LOG"
  OSASCRIPT_STUB_RETURN=Destroy "$HELPER" >/dev/null 2>&1
}

# ── Cancel path: exit 0, ws never called ────────────────────────────────
_run_cancel
if [[ $? -eq 0 ]]; then
  pass=$((pass + 1)); printf 'ok   Cancel exits 0\n'
else
  fail=$((fail + 1)); printf 'FAIL Cancel should exit 0\n'
fi

if [[ -s "$WS_STUB_LOG" ]]; then
  fail=$((fail + 1)); printf 'FAIL Cancel should not invoke ws (log:\n%s)\n' "$(cat "$WS_STUB_LOG")"
else
  pass=$((pass + 1)); printf 'ok   Cancel does not invoke ws\n'
fi

# ── Destroy path: ws called with `remove <index> -y` ────────────────────
_run_destroy
if [[ $? -eq 0 ]]; then
  pass=$((pass + 1)); printf 'ok   Destroy exits 0\n'
else
  fail=$((fail + 1)); printf 'FAIL Destroy should exit 0\n'
fi

if grep -qF "remove 3 -y" "$WS_STUB_LOG"; then
  pass=$((pass + 1)); printf 'ok   Destroy invokes "ws remove 3 -y"\n'
else
  fail=$((fail + 1)); printf 'FAIL ws-call log missing expected "remove 3 -y":\n%s\n' "$(cat "$WS_STUB_LOG")"
fi

# ── Missing spaces.json: helper tolerates it (jq returns "null", name
#    becomes "(unnamed)"). Verify nothing crashes. ────────────────────────
rm -f "$HOME/.config/workspace/spaces.json"
_run_cancel
if [[ $? -eq 0 ]]; then
  pass=$((pass + 1)); printf 'ok   missing spaces.json tolerated\n'
else
  fail=$((fail + 1)); printf 'FAIL missing spaces.json broke the helper\n'
fi

# ── Missing ws binary: helper exits 1 with a notification ───────────────
WS_BIN_BACKUP="$WS_BIN"
export WS_BIN="$TMP/nonexistent"
_run_cancel
[[ $? -eq 1 ]] && { pass=$((pass + 1)); printf 'ok   missing ws binary exits 1\n'; } \
  || { fail=$((fail + 1)); printf 'FAIL missing ws should exit 1\n'; }
export WS_BIN="$WS_BIN_BACKUP"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
