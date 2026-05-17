#!/usr/bin/env bash
# Unit tests for bin/ws-dir.
#
# ws-dir is the float-vs-tile dispatcher behind Caps+h/j/k/l. Floating
# focused window → ws-snap <region>. Tiled (or no focused window) →
# yabai window --focus <direction>. We stub both:
#
#   - yabai: shared tests/fixtures/yabai-stub (PATH-prepended). Env-driven
#     YABAI_STUB_FOCUSED_WINDOW lets us stage the is-floating value.
#   - ws-snap: a tiny per-test stub at $HOME/.local/bin/ws-snap (the
#     absolute path ws-dir uses), with HOME pointed at the test tmpdir.
#
# Assertions read the yabai stub's call log and the ws-snap stub's
# call log to confirm which branch fired with which arg.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/bin/ws-dir"
FIXTURES="$REPO_ROOT/tests/fixtures"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# Shared yabai-stub. Symlinked into PATH so ws-dir's `yabai -m query ...`
# resolves here. The stub understands `window --focus <dir>` (added
# alongside this test) so the tiled branch's exec succeeds without a
# wrapper script — earlier attempts wrote a wrapper into $TMP/yabai
# which, while the path was a symlink to the fixture, clobbered the
# shared fixture. Lesson learned: do not `cat >` to a symlink.
ln -sf "$FIXTURES/yabai-stub" "$TMP/yabai"

# ws-snap stub at the absolute path ws-dir expects.
mkdir -p "$TMP/.local/bin"
cat > "$TMP/.local/bin/ws-snap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${WS_SNAP_CALL_LOG:-/dev/null}"
exit 0
EOF
chmod 755 "$TMP/.local/bin/ws-snap"

export PATH="$TMP:$PATH"
export HOME="$TMP"
export YABAI_STUB_CALL_LOG="$TMP/yabai.log"
export WS_SNAP_CALL_LOG="$TMP/ws-snap.log"

pass=0; fail=0

# Run ws-dir <dir> with a staged is-floating value, then assert which
# command the dispatcher exec'd and with what argument.
_dispatch() {
  local label="$1" floating="$2" dir="$3" expect_helper="$4" expect_arg="$5"
  : > "$YABAI_STUB_CALL_LOG"
  : > "$WS_SNAP_CALL_LOG"
  case "$floating" in
    true)  export YABAI_STUB_FOCUSED_WINDOW='{"id":42,"is-floating":true}'  ;;
    false) export YABAI_STUB_FOCUSED_WINDOW='{"id":42,"is-floating":false}' ;;
    none)  export YABAI_STUB_FOCUSED_WINDOW='null'                          ;;
  esac

  local actual_exit=0
  "$HELPER" "$dir" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" != "0" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s\n  ws-dir exit %s (expected 0)\n  yabai log:\n%s\n  ws-snap log:\n%s\n' \
      "$label" "$actual_exit" "$(cat "$YABAI_STUB_CALL_LOG")" "$(cat "$WS_SNAP_CALL_LOG")"
    return
  fi

  if [[ "$expect_helper" == "ws-snap" ]]; then
    if grep -qxF "$expect_arg" "$WS_SNAP_CALL_LOG" 2>/dev/null; then
      pass=$((pass + 1)); printf 'ok   %s\n' "$label"
    else
      fail=$((fail + 1))
      printf 'FAIL %s\n  expected ws-snap %s\n  ws-snap log:\n%s\n  yabai log:\n%s\n' \
        "$label" "$expect_arg" "$(cat "$WS_SNAP_CALL_LOG")" "$(cat "$YABAI_STUB_CALL_LOG")"
    fi
  else
    # The fixture's call log captures the full argv each invocation.
    if grep -qF "window --focus $expect_arg" "$YABAI_STUB_CALL_LOG" 2>/dev/null; then
      pass=$((pass + 1)); printf 'ok   %s\n' "$label"
    else
      fail=$((fail + 1))
      printf 'FAIL %s\n  expected `yabai -m window --focus %s`\n  yabai log:\n%s\n  ws-snap log:\n%s\n' \
        "$label" "$expect_arg" "$(cat "$YABAI_STUB_CALL_LOG")" "$(cat "$WS_SNAP_CALL_LOG")"
    fi
  fi
}

# ── floating → ws-snap <region> ─────────────────────────────────────────
_dispatch "floating h → ws-snap left"   true h ws-snap left
_dispatch "floating l → ws-snap right"  true l ws-snap right
_dispatch "floating j → ws-snap center" true j ws-snap center
_dispatch "floating k → ws-snap max"    true k ws-snap max

# ── tiled → yabai --window --focus <direction> ──────────────────────────
_dispatch "tiled h → focus west"  false h yabai west
_dispatch "tiled l → focus east"  false l yabai east
_dispatch "tiled j → focus south" false j yabai south
_dispatch "tiled k → focus north" false k yabai north

# ── no focused window → tiled branch (defensive default) ────────────────
_dispatch "no focused window → tiled branch (focus west)" none h yabai west

# ── arg validation: missing / bad direction exits 2 ─────────────────────
_run_exit() {
  local label="$1" expected="$2"; shift 2
  local actual=0
  "$HELPER" "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected exit %s, got %s\n' "$label" "$expected" "$actual"
  fi
}

_run_exit "missing arg exits 2" 2
_run_exit "bad arg 'x' exits 2" 2 x

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
