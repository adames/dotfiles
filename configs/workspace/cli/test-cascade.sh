#!/usr/bin/env bash
# test-cascade.sh — end-to-end verification of the `ws` CLI (formerly
# `workspace`; the old name is kept as a compat symlink).
#
# Snapshot-mutate-assert-restore on the live spaces.json. The trap
# guarantees restoration even on test failure or signal. Runs in <2s.
#
# Invoked by `ws verify`. Exit 0 on success, non-zero on regression.
# Best-effort downstream assertions (current.env, tmux env) are skipped
# silently on absence so the harness works on Ubuntu / in CI.

set -u

WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
WS_THEMES_DIR="${WS_THEMES_DIR:-$HOME/.config/workspace/themes}"
WS_HANDLER="${WS_HANDLER:-$HOME/.config/workspace/on-space-changed.sh}"
WS_HOOK="${WS_HOOK:-$HOME/.config/workspace/hooks/post-mutate.sh}"

# Prefer the deployed CLI; fall back to the in-repo one. `ws` first;
# `workspace` (compat symlink) is the secondary lookup path so older
# installs continue to work until the next bootstrap.
WS_BIN="${WS_BIN:-}"
if [[ -z "$WS_BIN" ]]; then
  if   [[ -x "$HOME/.local/bin/ws" ]];                  then WS_BIN="$HOME/.local/bin/ws"
  elif [[ -x "$HOME/.local/bin/workspace" ]];           then WS_BIN="$HOME/.local/bin/workspace"
  elif [[ -x "${BASH_SOURCE[0]%/*}/ws" ]];              then WS_BIN="${BASH_SOURCE[0]%/*}/ws"
  elif [[ -x "${BASH_SOURCE[0]%/*}/workspace" ]];       then WS_BIN="${BASH_SOURCE[0]%/*}/workspace"
  else
    echo "test-cascade: ws CLI not found" >&2
    exit 1
  fi
fi

# Don't grow yabai during tests — we're only exercising the JSON layer.
# WS_GROW_YABAI_ON_ADD controls whether `ws add` calls
# `yabai -m space --create` to create a real macOS space alongside the
# JSON slot. Tests set 0 to keep the harness side-effect-free.
export WS_GROW_YABAI_ON_ADD=0
# The harness intentionally grows the JSON past yabai's space count to
# give positional tests headroom. WS_SKIP_YABAI_SLOT_CHECK=1 tells the
# `ws` CLI to skip every yabai-derived slot-count check (the validator,
# the doctor's drift check, and the count subcommand) so the JSON-side
# tests can exercise slots that don't correspond to real yabai spaces.
export WS_SKIP_YABAI_SLOT_CHECK=1

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

# USER_SNAP: pristine user config; ONLY used by the trap for final restore.
# SNAP: post-growth test baseline; what tests reset to mid-run.
USER_SNAP=$(mktemp) || { red "mktemp failed"; exit 1; }
SNAP=$(mktemp)      || { red "mktemp failed"; rm -f "$USER_SNAP"; exit 1; }
cp "$WS_CONFIG" "$USER_SNAP"

restore() {
  cp -f "$USER_SNAP" "$WS_CONFIG" 2>/dev/null || true
  [[ -x "$WS_HANDLER" ]] && "$WS_HANDLER" >/dev/null 2>&1 || true
  rm -f "$SNAP" "$USER_SNAP"
}
trap restore EXIT INT TERM

# Grow to a deterministic floor so positional tests (slots 3,5,6,7) have
# headroom regardless of the user's actual slot count. The factory default
# is empty; the harness needs ≥7 to exercise all positional assertions.
MIN_SLOTS=7
while (( $("$WS_BIN" count) < MIN_SLOTS )); do
  next=$(( $("$WS_BIN" count) + 1 ))
  # `ws add [NAME] [ICON]` — no COLOR (theme-driven now). Pass name only.
  "$WS_BIN" add "verify-slot-$next" >/dev/null \
    || { red "harness setup: ws add failed at slot $next"; exit 1; }
done

cp "$WS_CONFIG" "$SNAP"

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

# 3 · color roundtrip + 4 · color validation: RETIRED.
# `ws color N #HEX` was removed when colors became theme-driven only
# (see the `ws color` gravestone comment in configs/workspace/cli/ws).
# The "color stays positional across reorder/move/swap" coverage moved
# to the swap / reorder / move blocks below, which already snapshot
# pre-mutation colors and assert they're unchanged after the op.

# 5 · icon roundtrip writes a v2 iconSpec.codepoint
if jq -e '.icons[5] | length > 0' "$WS_THEMES_DIR/catppuccin-mocha.json" >/dev/null 2>&1; then
  pua_icon=$(jq -r '.icons[5]' "$WS_THEMES_DIR/catppuccin-mocha.json")
  "$WS_BIN" icon 7 "$pua_icon" >/dev/null
  # The codepoint is stored as an ASCII-escape (`\u{F048B}` or `\uXXXX`),
  # not the raw PUA char. Just assert the field is present and looks like
  # a codepoint escape — round-tripping the literal glyph through decode
  # is covered by lib/icon-decode.sh's own tests.
  cp7=$(jq -r '.spaces["7"].iconSpec.codepoint // ""' "$WS_CONFIG")
  kind7=$(jq -r '.spaces["7"].iconSpec.kind // ""' "$WS_CONFIG")
  if [[ "$cp7" =~ ^\\u[0-9a-fA-F{}]+$ ]] && [[ "$kind7" == "nerdFont" ]]; then
    pass "icon 7: iconSpec.codepoint=$cp7, kind=nerdFont"
  else
    fail "icon 7: expected v2 iconSpec.codepoint+kind=nerdFont (got cp='$cp7', kind='$kind7')"
  fi
fi

# 5a · cmd_status renders v2 icons (must DECODE iconSpec.codepoint to a
# glyph — not print the literal \uXXXX escape). Restore the snapshot
# first because prior tests have shuffled slots around, and the icons
# may have moved.
cp -f "$SNAP" "$WS_CONFIG"
status_out=$("$WS_BIN" status 2>/dev/null)
slot1_icon=$(printf '%s\n' "$status_out" | awk 'NR>1 && $1=="1" {print $2}')
if [[ "$slot1_icon" == *'\u'* ]]; then
  fail "status row 1 has literal \\u escape (not decoded): '$slot1_icon'"
elif [[ -z "$slot1_icon" ]]; then
  # Slot 1's iconSpec may legitimately have no codepoint (kind=none).
  # In that case the column shows fallbackText. Empty is only a failure
  # if BOTH codepoint and fallbackText are unset, which is itself a
  # doctor violation — so trust doctor and treat empty as inconclusive.
  dim "skip: status slot 1 icon empty (kind=none seed?)"
else
  pass "status decodes iconSpec.codepoint to a glyph (slot 1: '$slot1_icon')"
fi

# 6 · add / count / remove involution
# Signature is `ws add [NAME] [ICON]` — no COLOR positional (theme-driven).
# Pass name only; the iconSpec assertions below verify the no-icon path
# writes kind=none + fallbackText.
"$WS_BIN" add "added-$$" >/dev/null
assert "add increments count" "$((orig_count + 1))" "$("$WS_BIN" count)"
assert "added slot has expected name" "added-$$" "$(jq -r --arg c "$((orig_count + 1))" '.spaces[$c].name' "$WS_CONFIG")"

# 6a · add writes a v2 iconSpec scaffold (kind: none, fallbackText derived)
new_slot_idx=$((orig_count + 1))
add_kind=$(jq -r --arg c "$new_slot_idx" '.spaces[$c].iconSpec.kind // "MISSING"' "$WS_CONFIG")
assert "add seeds iconSpec.kind=none" "none" "$add_kind"
add_ft=$(jq -r --arg c "$new_slot_idx" '.spaces[$c].iconSpec.fallbackText // ""' "$WS_CONFIG")
assert "add seeds iconSpec.fallbackText" "AD" "$add_ft"

# 6b · icon NEW_SLOT star.fill mutates the just-added slot (was a no-op pre-fix)
"$WS_BIN" icon "$new_slot_idx" star.fill >/dev/null
new_kind=$(jq -r --arg c "$new_slot_idx" '.spaces[$c].iconSpec.kind // ""' "$WS_CONFIG")
new_sf=$(jq -r --arg c "$new_slot_idx" '.spaces[$c].iconSpec.symbolName // ""' "$WS_CONFIG")
assert "icon on new slot sets kind=sfSymbol" "sfSymbol" "$new_kind"
assert "icon on new slot sets symbolName=star.fill" "star.fill" "$new_sf"

# 6c · duplicate name rejected
assert_false "add rejects duplicate name" "$WS_BIN" add "added-$$"

# 6d · rename to existing name rejected
existing_name=$(jq -r '.spaces["1"].name' "$WS_CONFIG")
assert_false "name rejects collision with another slot" "$WS_BIN" name 2 "$existing_name"
# Self-rename to current name is allowed (no-op)
assert_true "name self-rename allowed" "$WS_BIN" name 1 "$existing_name"

"$WS_BIN" remove -y "$new_slot_idx" >/dev/null
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

# 15a · doctor catches v2 iconSpec issues
# Each mutation overwrites the iconSpec wholesale so the test result
# doesn't depend on what fields a user-customized $SNAP carries.
baseline_spec='{"fallbackSfSymbol":"circle.fill","fallbackText":"CO","userOverridden":false}'
# Missing iconSpec is implicit kind=none (per cmd_doctor) — should stay green.
jq '.spaces["1"] |= del(.iconSpec)' "$SNAP" > "$WS_CONFIG"
assert_true "doctor green on missing iconSpec (implicit kind=none)" "$WS_BIN" doctor
jq --argjson b "$baseline_spec" '.spaces["1"].iconSpec = ($b + {kind: "nerdFont"})' "$SNAP" > "$WS_CONFIG"
assert_false "doctor red on kind=nerdFont without codepoint" "$WS_BIN" doctor
jq --argjson b "$baseline_spec" '.spaces["1"].iconSpec = ($b + {kind: "sfSymbol"})' "$SNAP" > "$WS_CONFIG"
assert_false "doctor red on kind=sfSymbol without symbolName" "$WS_BIN" doctor
jq --argjson b "$baseline_spec" '.spaces["1"].iconSpec = ($b + {kind: "bogusKind"})' "$SNAP" > "$WS_CONFIG"
assert_false "doctor red on iconSpec.kind=bogusKind" "$WS_BIN" doctor
cp -f "$SNAP" "$WS_CONFIG"
assert_true "doctor green on seed (v2 iconSpec OK)" "$WS_BIN" doctor

# 15a · layout save/load/list/delete roundtrip
layout_name="harness-test-$$"
"$WS_BIN" layout save "$layout_name" >/dev/null
"$WS_BIN" layout list | grep -q "^$layout_name$" && pass "layout list shows saved layout" || fail "layout list missing $layout_name"

# Trim the saved layout to min(json_count, yabai_count) so `layout load`'s
# reconciliation step is a no-op. Without this, the harness's 7-slot JSON
# floor (line 77) forces `yabai -m space --create` calls during load, which
# fail on machines where yabai's scripting-addition isn't loaded — even
# though the property under test (identity restore) is independent of
# yabai's space count. Slot 1 is preserved because we trim from the tail.
layouts_dir="${WS_LAYOUTS_DIR:-$HOME/.config/workspace/layouts}"
layout_file="$layouts_dir/$layout_name.json"
if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
  yabai_n=$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
  json_n=$(jq '.spaces | length' "$layout_file" 2>/dev/null || echo 0)
  if [[ "$yabai_n" =~ ^[0-9]+$ && "$yabai_n" -ge 1 && "$yabai_n" -lt "$json_n" ]]; then
    tmp=$(mktemp) || { red "mktemp failed"; exit 1; }
    jq --argjson n "$yabai_n" \
       '.spaces |= (to_entries | sort_by(.key | tonumber) | .[:$n] | from_entries)' \
       "$layout_file" > "$tmp" && mv -f "$tmp" "$layout_file"
  fi
fi

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
#      PATH so sketchybar/tmux/yabai are absent. The handler must
#      still exit 0 and refresh current.env (silent-on-absence contract).
if [[ -x "$WS_HANDLER" ]]; then
  cache_env="$HOME/.cache/workspace/current.env"
  if PATH="/usr/bin:/bin" WS_CONFIG="$WS_CONFIG" "$WS_HANDLER" >/dev/null 2>&1; then
    pass "cascade exits 0 with stripped PATH (no sketchybar/tmux/yabai)"
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
