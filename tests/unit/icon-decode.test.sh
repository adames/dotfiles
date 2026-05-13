#!/usr/bin/env bash
# Unit tests for configs/workspace/lib/icon-decode.sh.
#
# Runs with no external deps — pure bash. Safe on Ubuntu and on macOS
# without yabai / sketchybar / etc.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../configs/workspace/lib/icon-decode.sh
. "$REPO_ROOT/configs/workspace/lib/icon-decode.sh"

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

# Inputs are ASCII-escaped codepoints exactly as spaces.json stores them.
# Each input is built via printf so the test file stays pure ASCII — no
# editor or copy-paste accident can replace the escape with the rendered
# glyph (which is what an earlier draft did, silently breaking these tests).
BMP_F120=$(printf '\\u%s' 'f120')           # 
BMP_F120_UC=$(printf '\\u%s' 'F120')        # 
BMP_F45E=$(printf '\\u%s' 'f45e')           # 
SMP_1F600=$(printf '\\u{%s}' '1F600')       # \u{1F600}
SMP_1f600=$(printf '\\u{%s}' '1f600')       # \u{1f600}

# Expected outputs are the actual scalars, rendered via printf.
expected_bmp=$(printf '')
expected_class=$(printf '')
expected_smp=$(printf '\U0001f600')

_assert_eq "BMP escape U+F120 (lowercase)"      "$expected_bmp"   "$(ws_decode_icon "$BMP_F120")"
_assert_eq "BMP escape U+F120 (uppercase hex)"  "$expected_bmp"   "$(ws_decode_icon "$BMP_F120_UC")"
_assert_eq "BMP escape U+F45E"                  "$expected_class" "$(ws_decode_icon "$BMP_F45E")"
_assert_eq "supplementary-plane U+1F600 (UC)"   "$expected_smp"   "$(ws_decode_icon "$SMP_1F600")"
_assert_eq "supplementary-plane U+1F600 (lc)"   "$expected_smp"   "$(ws_decode_icon "$SMP_1f600")"
_assert_eq "empty input → empty output"         ""                "$(ws_decode_icon '')"
_assert_eq "no argument → empty output"         ""                "$(ws_decode_icon)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
