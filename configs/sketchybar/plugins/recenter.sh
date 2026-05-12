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

# Empirically, each pill renders at ~55px wide with the default
# JetBrainsMono NF Bold 14pt + icon padding 10+10 + item padding 8+8.
# The active pill is ~16px wider due to background.padding; we ignore
# that since exactly one pill is active at any time (averaging out
# gives ~57). Tunable if your font changes.
PILL_AVG_WIDTH=55

# Half-width of the camera notch. The notch is ~184px on a 14" MBP and
# ~200px on a 16". Pads on both sides; a slightly generous 220 keeps
# pills safely clear of the notch edge.
NOTCH_WIDTH=220

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
