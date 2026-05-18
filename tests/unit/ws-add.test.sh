#!/usr/bin/env bash
# Unit tests for `ws add` — atomicity in the face of yabai SA failures.
#
# Regression: a previous revision wrote spaces.json BEFORE calling
# `yabai -m space --create`, and swallowed any yabai error with
# `|| true`. When the scripting-addition wasn't loaded, the SA error
# was silently dropped and the user ended up with identity entries
# that had no matching yabai space. This test pins the new flow:
#
#   1. yabai -m space --create first; on SA failure, abort and DO NOT
#      touch spaces.json.
#   2. spaces.json write second.
#   3. When yabai is absent (Linux, brew services stop yabai), behave
#      as an identity-only operation (writes spaces.json, no yabai call).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WS="$REPO_ROOT/configs/workspace/cli/ws"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# yabai stub via PATH override.
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

# pgrep stub: cmd_add's yabai-create gate is `have yabai && pgrep -x yabai
# >/dev/null`. On Linux CI there's no actual yabai process running, so the
# gate would skip the branch we're trying to test and the test would
# trivially pass with the yabai-create code never executing. Pretend
# yabai is running (PID 12345) when queried for yabai; fall through to
# the real pgrep for anything else.
cat > "$TMP/pgrep" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    yabai) echo 12345; exit 0 ;;
  esac
done
exec /usr/bin/pgrep "$@" 2>/dev/null
EOF
chmod 755 "$TMP/pgrep"

# Sandbox the ws env so the test never touches the real spaces.json
# or fires real cascade/hook scripts.
export WS_CONFIG="$TMP/spaces.json"
export WS_HANDLER="$TMP/nonexistent"     # _fire_cascade no-ops
export WS_HOOK="$TMP/nonexistent"        # _fire_post no-ops
export WS_THEMES_DIR="$TMP/themes"
export WS_SF_MAP="$TMP/nonexistent"      # forces icon=none path
export YABAI_STUB_CALL_LOG="$TMP/yabai.log"

# Baseline spaces.json with one slot (slot 1 = "home").
_seed_config() {
  cat > "$WS_CONFIG" <<'EOF'
{
  "palette": "catppuccin-mocha",
  "spaces": {
    "1": {
      "name": "home",
      "color": "#cba6f7",
      "stableLogicalLabel": "home",
      "iconSpec": {
        "kind": "none",
        "fallbackSfSymbol": "stop.fill",
        "fallbackText": "HO",
        "userOverridden": false
      }
    }
  }
}
EOF
}

# Snapshot of spaces.json (for assert_untouched comparison).
_snapshot() {
  command cp -- "$WS_CONFIG" "$WS_CONFIG.snap"
}

pass=0; fail=0

_run_add() {
  # Stdin from /dev/null so isatty checks fail → no interactive prompts.
  PATH="$TMP:$PATH" "$WS" add "$@" </dev/null
}

_assert() {
  local label="$1" condition_msg="$2" actual_msg="$3" cond_exit="$4"
  if (( cond_exit == 0 )); then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$label" "$condition_msg" "$actual_msg"
  fi
}

# ── 1. SA missing → ws add aborts, spaces.json is untouched ─────────────
_seed_config
_snapshot
: > "$YABAI_STUB_CALL_LOG"
export YABAI_STUB_FAIL=sa
exit_code=0
out=$(_run_add foo 2>&1) || exit_code=$?

_assert "SA missing → ws add exits 1" \
  "exit 1" "exit $exit_code" \
  $(( exit_code == 1 ? 0 : 1 ))

# spaces.json must be byte-identical to the seed snapshot.
if command cmp -s "$WS_CONFIG" "$WS_CONFIG.snap"; then
  pass=$((pass + 1)); printf 'ok   SA missing → spaces.json untouched\n'
else
  fail=$((fail + 1))
  printf 'FAIL SA missing → spaces.json untouched\n  diff:\n'
  command diff "$WS_CONFIG.snap" "$WS_CONFIG" || true
fi

# Error message must mention the installer.
if command grep -qF -- "yabai-sa-install.sh --force" <<<"$out"; then
  pass=$((pass + 1)); printf 'ok   SA-missing error names the installer\n'
else
  fail=$((fail + 1))
  printf 'FAIL SA-missing error names the installer\n  out:\n%s\n' "$out"
fi

# ── 2. yabai succeeds → ws add writes spaces.json, exits 0 ──────────────
unset YABAI_STUB_FAIL
_seed_config
: > "$YABAI_STUB_CALL_LOG"
exit_code=0
_run_add foo >/dev/null 2>&1 || exit_code=$?

_assert "yabai ok → ws add exits 0" \
  "exit 0" "exit $exit_code" \
  $(( exit_code == 0 ? 0 : 1 ))

# spaces.json must now have slot 2 named "foo".
new_name=$(command jq -r '.spaces["2"].name // empty' "$WS_CONFIG" 2>/dev/null)
if [[ "$new_name" == "foo" ]]; then
  pass=$((pass + 1)); printf 'ok   yabai ok → spaces.json slot 2 = "foo"\n'
else
  fail=$((fail + 1))
  printf 'FAIL yabai ok → spaces.json slot 2 = "foo"\n  got: "%s"\n' "$new_name"
fi

# Yabai received the create call.
if command grep -qF -- "-m space --create" "$YABAI_STUB_CALL_LOG"; then
  pass=$((pass + 1)); printf 'ok   yabai ok → space --create was invoked\n'
else
  fail=$((fail + 1))
  printf 'FAIL yabai ok → space --create was invoked\n  log:\n%s\n' "$(cat "$YABAI_STUB_CALL_LOG")"
fi

# ── 3. yabai absent (WS_GROW_YABAI_ON_ADD=0) → identity-only add ───────
unset YABAI_STUB_FAIL
_seed_config
: > "$YABAI_STUB_CALL_LOG"
exit_code=0
WS_GROW_YABAI_ON_ADD=0 _run_add bar >/dev/null 2>&1 || exit_code=$?

_assert "yabai-disabled → ws add exits 0 (identity-only)" \
  "exit 0" "exit $exit_code" \
  $(( exit_code == 0 ? 0 : 1 ))

new_name=$(command jq -r '.spaces["2"].name // empty' "$WS_CONFIG" 2>/dev/null)
if [[ "$new_name" == "bar" ]]; then
  pass=$((pass + 1)); printf 'ok   identity-only → spaces.json slot 2 = "bar"\n'
else
  fail=$((fail + 1))
  printf 'FAIL identity-only → spaces.json slot 2 = "bar"\n  got: "%s"\n' "$new_name"
fi

# No yabai call should have happened with WS_GROW_YABAI_ON_ADD=0.
if ! command grep -q . "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
  pass=$((pass + 1)); printf 'ok   identity-only → yabai never invoked\n'
else
  fail=$((fail + 1))
  printf 'FAIL identity-only → yabai never invoked\n  log:\n%s\n' "$(cat "$YABAI_STUB_CALL_LOG")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
