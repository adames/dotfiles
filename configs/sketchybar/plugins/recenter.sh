#!/usr/bin/env bash
# Recenter the workspace pill strip per display.
#
# Each display gets its own centering math because the constraints differ:
#   • Notched laptop: pills fit between the screen-left corner and a
#     half-notch-width safety buffer to the camera notch. Hard cap at
#     10 visible pills.
#   • Non-notched displays (externals, MBAir / 13" MBP built-in): pills
#     center between the left and right edges, no cap.
#
# Centering is applied to the FIRST pill on each display via
# `--set space.<first> padding_left=<PAD>`; subsequent pills on that
# display get padding_left=0 so they pack flush behind the first.
# Sketchybar's bar-level padding_left is left at a small default.

set -u

PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
WS_LAPTOP_UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"

# Each pill renders at ~36px wide with JetBrainsMono NF Bold 12pt +
# icon padding 8/8 + item padding 0/0. The active pill is ~16px wider
# (background.padding_left/right=8). Average with one active out of ten
# ≈ 38. Tunable.
PILL_AVG_WIDTH=38

# Half-notch buffer applied on the right edge of the notched-laptop
# region: pills stop NOTCH_WIDTH/2 away from the actual notch edge.
NOTCH_WIDTH=400
MIN_PAD=8
NOTCH_MAX_VISIBLE=10

if ! command -v sketchybar >/dev/null 2>&1; then exit 0; fi
if ! pgrep -x sketchybar >/dev/null 2>&1; then exit 0; fi
if ! command -v yabai >/dev/null 2>&1; then exit 0; fi
if ! yabai -m query --displays >/dev/null 2>&1; then exit 0; fi

# Resolve laptop display index. UUID-based first (canonical, set by
# laptop-uuid-init.sh), origin-based fallback (display at frame (0,0)
# is the macOS primary, which is the built-in laptop panel in most
# default arrangements).
laptop_idx=""
if command -v jq >/dev/null 2>&1; then
  if [[ -r "$WS_LAPTOP_UUID_FILE" ]]; then
    laptop_uuid=$(<"$WS_LAPTOP_UUID_FILE")
    laptop_idx=$(yabai -m query --displays 2>/dev/null \
      | jq -r --arg u "$laptop_uuid" '[.[] | select(.uuid == $u) | .index] | first // empty' 2>/dev/null)
  fi
  if [[ -z "$laptop_idx" ]]; then
    laptop_idx=$(yabai -m query --displays 2>/dev/null \
      | jq -r '[.[] | select(.frame.x == 0 and .frame.y == 0) | .index] | first // empty' 2>/dev/null)
  fi
fi
notch_host=$("$PLUGIN_DIR/notch-detect.sh" 2>/dev/null || echo no)

# Walk displays. For each: compute visible-pill count and centering pad.
yabai -m query --displays 2>/dev/null \
  | jq -r '.[] | "\(.index)\t\(.frame.w)\t\(.spaces | map(tostring) | join(","))"' \
  | while IFS=$'\t' read -r display width sid_csv; do
      IFS=',' read -ra sids <<<"$sid_csv"
      total=${#sids[@]}

      # Determine which sids are visible on this display.
      visible_count=$total
      if [[ "$notch_host" == "yes" && -n "$laptop_idx" && "$display" == "$laptop_idx" ]]; then
        (( visible_count > NOTCH_MAX_VISIBLE )) && visible_count=$NOTCH_MAX_VISIBLE
      fi
      (( visible_count < 1 )) && continue

      pills_w=$(( visible_count * PILL_AVG_WIDTH ))

      if [[ "$notch_host" == "yes" && -n "$laptop_idx" && "$display" == "$laptop_idx" ]]; then
        # Notched: usable horizontal region = (screen_w - NOTCH_WIDTH) / 2.
        # That subtracts the notch itself + a half-notch buffer.
        usable=$(( ( ${width%.*} - NOTCH_WIDTH ) / 2 ))
      else
        # Non-notched: full screen width is usable.
        usable=$(( ${width%.*} ))
      fi

      pad=$(( (usable - pills_w) / 2 ))
      (( pad < MIN_PAD )) && pad=$MIN_PAD

      # First pill on this display gets the centering pad; siblings get 0.
      first_sid="${sids[0]}"
      for sid in "${sids[@]}"; do
        if [[ "$sid" == "$first_sid" ]]; then
          sketchybar --set "space.$sid" padding_left="$pad" >/dev/null 2>&1 || true
        else
          sketchybar --set "space.$sid" padding_left=0 >/dev/null 2>&1 || true
        fi
      done
    done

# Reset the bar's global padding_left to a small default; per-display
# centering is now handled by the first pill on each display.
sketchybar --bar padding_left=0 padding_right=0 >/dev/null 2>&1 || true
