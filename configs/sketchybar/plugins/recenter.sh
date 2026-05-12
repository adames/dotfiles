#!/usr/bin/env bash
# Recenter the workspace pill strip in the left-of-notch region.
#
# Called from:
#   • sketchybarrc startup (after items are added)
#   • ~/.config/workspace/hooks/post-mutate.sh on add/remove
#
# Computes `--bar padding_left = (left_of_notch_width - n_pills *
# avg_pill_width) / 2` so pills stay centered between the top-left
# corner and the camera notch as the visible count changes (1..10).

set -u

WS_CONFIG="$HOME/.config/workspace/spaces.json"

# Visible pill count is min(spaces.json count, 10). The cap mirrors the
# loop in sketchybarrc and the cap in the post-mutate hook.
count=10
if [[ -r "$WS_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  count=$(jq '.spaces | keys | length' "$WS_CONFIG" 2>/dev/null || echo 10)
fi
(( count > 10 )) && count=10
(( count < 1 ))  && count=1

# Each pill renders at ~48px wide with JetBrainsMono NF Bold 12pt +
# icon padding 8+8 + item padding 8+8. Tunable if your font changes.
PILL_AVG_WIDTH=48

# Effective notch width used as the right-side exclusion zone. The real
# camera notch is ~184–200px wide depending on model; we double that to
# 400 so pills sit half-a-notch-width away from the actual edge (per
# the design ask: "padded half the size of the camera").
NOTCH_WIDTH=400

# Screen width via osascript — cheap and dependency-free. Falls back to
# 1512 (default MBP 14") if the query fails.
screen_w=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null \
  | awk -F', ' '{print $3}' 2>/dev/null)
[[ -z "$screen_w" || "$screen_w" -lt 100 ]] && screen_w=1512

left_of_notch=$(( (screen_w - NOTCH_WIDTH) / 2 ))
pills_w=$(( count * PILL_AVG_WIDTH ))
pad=$(( (left_of_notch - pills_w) / 2 ))
(( pad < 8 )) && pad=8

sketchybar --bar padding_left="$pad"
