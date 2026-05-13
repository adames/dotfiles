#!/usr/bin/env bash
# Unit tests for configs/workspace/lib/hex-ansi.sh.
#
# Runs with no external deps — pure bash. Safe on Ubuntu and on macOS
# without yabai / sketchybar / etc.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../configs/workspace/lib/hex-ansi.sh
. "$REPO_ROOT/configs/workspace/lib/hex-ansi.sh"

pass=0; fail=0

_assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  want: %q\n  got:  %q\n' "$label" "$want" "$got"
  fi
}

_assert_eq "#000000 → 0 0 0"            "0 0 0"        "$(ws_hex_to_rgb '#000000')"
_assert_eq "#ffffff → 255 255 255"      "255 255 255"  "$(ws_hex_to_rgb '#ffffff')"
_assert_eq "#FFFFFF (uppercase)"        "255 255 255"  "$(ws_hex_to_rgb '#FFFFFF')"
_assert_eq "#cdd6f4 (catppuccin text)"  "205 214 244"  "$(ws_hex_to_rgb '#cdd6f4')"
_assert_eq "leading # is optional"      "205 214 244"  "$(ws_hex_to_rgb 'cdd6f4')"
_assert_eq "#ff0000 (pure red)"         "255 0 0"      "$(ws_hex_to_rgb '#ff0000')"
_assert_eq "#00ff00 (pure green)"       "0 255 0"      "$(ws_hex_to_rgb '#00ff00')"
_assert_eq "#0000ff (pure blue)"        "0 0 255"      "$(ws_hex_to_rgb '#0000ff')"

# `read -r r g b < <(...)` is the canonical destructuring pattern — make
# sure the output shape supports it without surprise quoting.
read -r r g b < <(ws_hex_to_rgb '#1e1e2e')
_assert_eq "destructuring: red"   "30"   "$r"
_assert_eq "destructuring: green" "30"   "$g"
_assert_eq "destructuring: blue"  "46"   "$b"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
