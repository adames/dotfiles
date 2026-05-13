#!/usr/bin/env bash
# test-cascade.sh — end-to-end verification of the `workspace` CLI.
#
# Snapshot-mutate-assert-restore on the live spaces.json. The trap
# guarantees restoration even on test failure or signal. Runs in <2s.
#
# Invoked by `workspace verify`. Exit 0 on success, non-zero on
# regression. Best-effort downstream assertions (current.env, tmux env)
# are skipped silently on absence so the harness works on Ubuntu / in CI.

set -u

WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
WS_THEMES_DIR="${WS_THEMES_DIR:-$HOME/.config/workspace/themes}"
WS_HANDLER="${WS_HANDLER:-$HOME/.config/workspace/on-space-changed.sh}"
WS_HOOK="${WS_HOOK:-$HOME/.config/workspace/hooks/post-mutate.sh}"

# Prefer the deployed CLI; fall back to the in-repo one.
WS_BIN="${WS_BIN:-}"
if [[ -z "$WS_BIN" ]]; then
  if [[ -x "$HOME/.local/bin/workspace" ]]; then
    WS_BIN="$HOME/.local/bin/workspace"
  elif [[ -x "${BASH_SOURCE[0]%/*}/workspace" ]]; then
    WS_BIN="${BASH_SOURCE[0]%/*}/workspace"
  else
    echo "test-cascade: workspace CLI not found" >&2
    exit 1
  fi
fi

# Don't grow yabai during tests — we're only exercising the JSON layer.
export WS_ADD_GROW_YABAI=0

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

FAILED=0
fail() { red "✗ $*"; FAILED=1; }
pass() { dim   "✓ $*"; }

# ── snapshot + restore ───────────────────────────────────────────────────

if [[ ! -r "$WS_CONFIG" ]]; then
  red "spaces.json not found at $WS_CONFIG"
  exit 1
fi

SNAP=$(mktemp) || { red "mktemp failed"; exit 1; }
cp "$WS_CONFIG" "$SNAP"

restore() {
  cp -f "$SNAP" "$WS_CONFIG" 2>/dev/null || true
  [[ -x "$WS_HANDLER" ]] && "$WS_HANDLER" >/dev/null 2>&1 || true
  rm -f "$SNAP"
}
trap restore EXIT INT TERM

assert() {
  # assert <msg> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1 (expected: $2, actual: $3)"
  fi
}

assert_true() {
  # assert_true <msg> <cmd...>
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi
}

assert_false() {
  local msg="$1"; shift
  if ! "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi
}

# ── tests ────────────────────────────────────────────────────────────────

orig_count=$("$WS_BIN" count)
dim "── starting tests · orig_count=$orig_count"

# 1 · doctor green on clean state
assert_true "doctor green on baseline" "$WS_BIN" doctor

# 2 · name roundtrip
"$WS_BIN" name 3 "test-name-$$" >/dev/null
assert "name 3" "test-name-$$" "$(jq -r '.spaces["3"].name' "$WS_CONFIG")"

# 3 · color roundtrip
"$WS_BIN" color 5 "#abcdef" >/dev/null
assert "color 5 = #abcdef" "#abcdef" "$(jq -r '.spaces["5"].color' "$WS_CONFIG")"

# 4 · color validation rejects bad input
assert_false "color rejects non-hex" "$WS_BIN" color 5 "not-a-color"

# 5 · icon roundtrip + PUA preservation
if jq -e '.icons[5] | length > 0' "$WS_THEMES_DIR/catppuccin-mocha.json" >/dev/null 2>&1; then
  pua_icon=$(jq -r '.icons[5]' "$WS_THEMES_DIR/catppuccin-mocha.json")
  "$WS_BIN" icon 7 "$pua_icon" >/dev/null
  py_ok=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
ic = d["spaces"]["7"]["icon"]
print("ok" if any(0xE000 <= ord(c) <= 0xF8FF or 0xF0000 <= ord(c) <= 0xFFFFD for c in ic) else "no")
' "$WS_CONFIG")
  assert "icon 7 preserves PUA codepoint" "ok" "$py_ok"
fi

# 6 · add / count / remove involution
"$WS_BIN" add "added-$$" "#112233" "" >/dev/null
assert "add increments count" "$((orig_count + 1))" "$("$WS_BIN" count)"
assert "added slot has expected name" "added-$$" "$(jq -r --arg c "$((orig_count + 1))" '.spaces[$c].name' "$WS_CONFIG")"
"$WS_BIN" remove -y "$((orig_count + 1))" >/dev/null
assert "remove restores count" "$orig_count" "$("$WS_BIN" count)"

# 7 · remove from middle: renumbering
old6=$(jq -c '.spaces["6"]' "$WS_CONFIG")
"$WS_BIN" remove -y 5 >/dev/null
new5=$(jq -c '.spaces["5"]' "$WS_CONFIG")
assert "remove middle: slot 5 = old slot 6" "$old6" "$new5"
assert "count decremented" "$((orig_count - 1))" "$("$WS_BIN" count)"
# Restore from snapshot before next test (re-fire cascade silently)
cp -f "$SNAP" "$WS_CONFIG"

# 8 · swap (positional colors: name+icon swap, color stays at slot)
color1_orig=$(jq -r '.spaces["1"].color' "$SNAP")
color2_orig=$(jq -r '.spaces["2"].color' "$SNAP")
name1_orig=$(jq -r '.spaces["1"].name'  "$SNAP")
name2_orig=$(jq -r '.spaces["2"].name'  "$SNAP")
"$WS_BIN" swap 1 2 >/dev/null
assert "swap: slot 1 name = old slot 2 name" "$name2_orig" "$(jq -r '.spaces["1"].name' "$WS_CONFIG")"
assert "swap: slot 2 name = old slot 1 name" "$name1_orig" "$(jq -r '.spaces["2"].name' "$WS_CONFIG")"
assert "swap (positional): slot 1 color UNCHANGED" "$color1_orig" "$(jq -r '.spaces["1"].color' "$WS_CONFIG")"
assert "swap (positional): slot 2 color UNCHANGED" "$color2_orig" "$(jq -r '.spaces["2"].color' "$WS_CONFIG")"
"$WS_BIN" swap 1 2 >/dev/null
assert "swap involution: slot 1 name restored" "$name1_orig" "$(jq -r '.spaces["1"].name' "$WS_CONFIG")"

# 8b · slot-name resolver: commands accept names not just indices
"$WS_BIN" name "$name1_orig" "renamed-by-name-$$" >/dev/null
assert "name resolver: slot 1 renamed via its old name" "renamed-by-name-$$" "$(jq -r '.spaces["1"].name' "$WS_CONFIG")"
# Restore original name so subsequent positional tests work
"$WS_BIN" name 1 "$name1_orig" >/dev/null

# 9 · reorder: rotate left then right (positional colors → only name+icon move)
n=$("$WS_BIN" count)
left=$(seq 2 "$n"; echo 1)
right=$(echo "$n"; seq 1 $((n - 1)))
# shellcheck disable=SC2086
"$WS_BIN" reorder $left >/dev/null
assert "reorder rotate-left: slot $n name = old slot 1 name" \
  "$(jq -r '.spaces["1"].name' "$SNAP")" \
  "$(jq -r --arg c "$n" '.spaces[$c].name' "$WS_CONFIG")"
assert "reorder (positional): slot $n color UNCHANGED" \
  "$(jq -r --arg c "$n" '.spaces[$c].color' "$SNAP")" \
  "$(jq -r --arg c "$n" '.spaces[$c].color' "$WS_CONFIG")"
# shellcheck disable=SC2086
"$WS_BIN" reorder $right >/dev/null
assert "reorder rotate-right restores" \
  "$(jq -Sc '.spaces' "$SNAP")" \
  "$(jq -Sc '.spaces' "$WS_CONFIG")"

# 10 · reorder validates: duplicates rejected
seq_ok=$(seq 1 "$n" | tr '\n' ' ')
dup_args="1 1 $(seq 3 "$n" | tr '\n' ' ')"
# shellcheck disable=SC2086
assert_false "reorder rejects duplicates" "$WS_BIN" reorder $dup_args

# 11 · reorder validates: out-of-range rejected
oor_args="$(seq 2 "$n" | tr '\n' ' ') $((n + 1))"
# shellcheck disable=SC2086
assert_false "reorder rejects out-of-range" "$WS_BIN" reorder $oor_args

# 12 · reorder validates: wrong arity rejected
assert_false "reorder rejects wrong arity" "$WS_BIN" reorder 1 2 3
unset seq_ok

# 12a · move <SRC> <DEST> numeric
cp -f "$SNAP" "$WS_CONFIG"
"$WS_BIN" move 1 3 >/dev/null
assert "move 1→3: slot 3 name = old slot 1 name" "$name1_orig" "$(jq -r '.spaces["3"].name' "$WS_CONFIG")"
assert "move 1→3: slot 1 color UNCHANGED (positional)" "$color1_orig" "$(jq -r '.spaces["1"].color' "$WS_CONFIG")"

# 12b · move <SRC> before|after <REF>
cp -f "$SNAP" "$WS_CONFIG"
name3_orig=$(jq -r '.spaces["3"].name' "$SNAP")
"$WS_BIN" move "$name1_orig" after "$name3_orig" >/dev/null
assert "move A after C: slot 3 name = A" "$name1_orig" "$(jq -r '.spaces["3"].name' "$WS_CONFIG")"

cp -f "$SNAP" "$WS_CONFIG"
"$WS_BIN" move "$name3_orig" before "$name1_orig" >/dev/null
assert "move C before A: slot 1 name = C" "$name3_orig" "$(jq -r '.spaces["1"].name' "$WS_CONFIG")"

# 12c · rotate is well-defined (involution at rotate $n)
# Comparisons use jq -Sc so intra-slot key order doesn't matter — only
# semantic equivalence of (name, color, icon) per slot.
cp -f "$SNAP" "$WS_CONFIG"
n=$("$WS_BIN" count)
"$WS_BIN" rotate "$n" >/dev/null
assert "rotate by N is identity" \
  "$(jq -Sc '.spaces' "$SNAP")" "$(jq -Sc '.spaces' "$WS_CONFIG")"
"$WS_BIN" rotate 1 >/dev/null
"$WS_BIN" rotate -1 >/dev/null
assert "rotate 1 then -1 restores" \
  "$(jq -Sc '.spaces' "$SNAP")" "$(jq -Sc '.spaces' "$WS_CONFIG")"

# 12d · reverse is an involution
"$WS_BIN" reverse >/dev/null
"$WS_BIN" reverse >/dev/null
assert "reverse twice = identity" \
  "$(jq -Sc '.spaces' "$SNAP")" "$(jq -Sc '.spaces' "$WS_CONFIG")"

# 13 · theme application
"$WS_BIN" theme gruvbox-dark >/dev/null
gruv_first=$(jq -r '.colors[0]' "$WS_THEMES_DIR/gruvbox-dark.json")
assert "theme gruvbox-dark applied to slot 1" "$gruv_first" "$(jq -r '.spaces["1"].color' "$WS_CONFIG")"

# 14 · theme --with-icons restores PUA
"$WS_BIN" theme catppuccin-mocha --with-icons >/dev/null
mocha1=$(jq -r '.colors[0]' "$WS_THEMES_DIR/catppuccin-mocha.json")
assert "theme catppuccin-mocha restored slot 1 color" "$mocha1" "$(jq -r '.spaces["1"].color' "$WS_CONFIG")"

# 15 · doctor red on corrupted state
echo 'not json' > "$WS_CONFIG"
assert_false "doctor red on broken JSON" "$WS_BIN" doctor
cp -f "$SNAP" "$WS_CONFIG"

# 15a · layout save/load/list/delete roundtrip
layout_name="harness-test-$$"
"$WS_BIN" layout save "$layout_name" >/dev/null
"$WS_BIN" layout list | grep -q "^$layout_name$" && pass "layout list shows saved layout" || fail "layout list missing $layout_name"
# Mutate then reload
"$WS_BIN" name 1 "layout-test-mutated-$$" >/dev/null
"$WS_BIN" layout load "$layout_name" -y >/dev/null
assert "layout load restores name" "$(jq -r '.spaces["1"].name' "$SNAP")" "$(jq -r '.spaces["1"].name' "$WS_CONFIG")"
"$WS_BIN" layout delete -y "$layout_name" >/dev/null
"$WS_BIN" layout list | grep -q "^$layout_name$" \
  && fail "layout still listed after delete" \
  || pass "layout delete removed entry"

# 16 · best-effort downstream signals (skip on absence — don't fail)
env_file="$HOME/.cache/workspace/current.env"
if [[ -r "$env_file" ]]; then
  if grep -q '^export MACOS_SPACE_' "$env_file"; then
    pass "current.env carries MACOS_SPACE_* exports"
  else
    fail "current.env missing MACOS_SPACE_* exports"
  fi
else
  dim "skip: current.env not present"
fi

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  if tmux show-environment -g MACOS_SPACE_NAME >/dev/null 2>&1; then
    pass "tmux global env has MACOS_SPACE_NAME"
  else
    dim "skip: tmux running but no MACOS_SPACE_NAME (cascade may not have fired yet)"
  fi
else
  dim "skip: tmux not running"
fi

# 17 · idempotent refresh: running the cascade twice produces no JSON diff
#      and a populated current.env. Mutations land via _write(), cascades
#      via on-space-changed.sh — neither should rewrite spaces.json.
cp -f "$SNAP" "$WS_CONFIG"
before_hash=$(shasum -a 256 "$WS_CONFIG" | awk '{print $1}')
if [[ -x "$WS_HANDLER" ]]; then
  "$WS_HANDLER" >/dev/null 2>&1 || true
  "$WS_HANDLER" >/dev/null 2>&1 || true
  after_hash=$(shasum -a 256 "$WS_CONFIG" | awk '{print $1}')
  assert "cascade re-run does not mutate spaces.json" "$before_hash" "$after_hash"
else
  dim "skip: WS_HANDLER not executable"
fi

# 18 · optional-subsystem absence: run on-space-changed.sh with a stripped
#      PATH so sketchybar/borders/tmux/yabai are absent. The handler must
#      still exit 0 and refresh current.env (silent-on-absence contract).
if [[ -x "$WS_HANDLER" ]]; then
  cache_env="$HOME/.cache/workspace/current.env"
  if PATH="/usr/bin:/bin" WS_CONFIG="$WS_CONFIG" "$WS_HANDLER" >/dev/null 2>&1; then
    pass "cascade exits 0 with stripped PATH (no sketchybar/borders/tmux/yabai)"
  else
    fail "cascade failed with stripped PATH"
  fi
  if [[ -r "$cache_env" ]] && grep -q '^export MACOS_SPACE_' "$cache_env"; then
    pass "cascade refreshes current.env without optional subsystems"
  else
    fail "cascade left current.env unwritten under stripped PATH"
  fi
fi

if (( FAILED )); then
  red "✗ verify FAILED"
  exit 1
fi
green "✓ verify: all green"
