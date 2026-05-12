#!/usr/bin/env bash
# Sync sketchybar's pill set with yabai's per-display space assignment.
#
# Invoked from:
#   • sketchybarrc startup (after items are added)
#   • yabai signals: display_added / display_removed / display_changed
#   • ~/.config/workspace/hooks/post-mutate.sh after add / remove
#
# For each yabai space:
#   1. Ensure pill `space.<N>` exists (add if missing, with the standard
#      script / click_script / subscription).
#   2. Set associated_display_mask = 1 << (display - 1) so the pill only
#      renders on its owning display.
#   3. If the owning display is the laptop AND the laptop has a notch
#      AND it has >10 spaces, hide the 11th+ via drawing=off so they
#      don't overflow the notch-bounded region.
#
# For each existing sketchybar `space.<N>` whose N is no longer a yabai
# space: remove it.

set -u

PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
WS_LAPTOP_UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"
NOTCH_MAX_VISIBLE=10

# Silent bail if sketchybar isn't running.
if ! command -v sketchybar >/dev/null 2>&1; then exit 0; fi
if ! pgrep -x sketchybar >/dev/null 2>&1; then exit 0; fi
if ! command -v yabai >/dev/null 2>&1; then exit 0; fi
if ! yabai -m query --spaces >/dev/null 2>&1; then exit 0; fi

# Resolve laptop yabai display index. First try the UUID captured by
# laptop-uuid-init.sh (canonical). If that file isn't present (user
# never single-display-bootstrapped), fall back to the display at frame
# origin (0,0) — almost always the macOS primary, which on Mac laptops
# is the built-in panel by default.
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

# Notch presence on the laptop. Per the design ask: pills capped at 10
# only on this display.
notch_host=$("$PLUGIN_DIR/notch-detect.sh" 2>/dev/null || echo no)

# Cache yabai's current state in a single query each.
spaces_json=$(yabai -m query --spaces 2>/dev/null)
[[ -z "$spaces_json" ]] && exit 0

# Set of yabai space indices, plus a per-display ordered list.
current_spaces=$(echo "$spaces_json" | jq -r '.[].index' | sort -n)

# Existing sketchybar pill items (space.N).
existing_pills=$(sketchybar --query bar 2>/dev/null \
  | jq -r '.items[] | select(test("^space\\."))' \
  | sed 's/^space\.//' | sort -n)

# Add pills for new yabai spaces.
for sid in $current_spaces; do
  if ! grep -qx "$sid" <<<"$existing_pills"; then
    sketchybar --add item "space.$sid" left \
               --set "space.$sid" \
                  script="$PLUGIN_DIR/space.sh" \
                  click_script="yabai -m space --focus $sid" \
                  padding_left=0 \
                  padding_right=0 \
               --subscribe "space.$sid" workspace_changed \
               >/dev/null 2>&1 || true
  fi
done

# Remove pills for yabai spaces that no longer exist.
for sid in $existing_pills; do
  if ! grep -qx "$sid" <<<"$current_spaces"; then
    sketchybar --remove "space.$sid" >/dev/null 2>&1 || true
  fi
done

# Apply per-display visibility. Sketchybar's documented setter is
# `display=<index>` (1-based); it computes the bitmask internally.
echo "$spaces_json" \
  | jq -r '. | group_by(.display)[] | "\(.[0].display)\t\([.[].index | tostring] | join(","))"' \
  | while IFS=$'\t' read -r display sid_csv; do
      n=0
      IFS=',' read -ra sids <<<"$sid_csv"
      for sid in "${sids[@]}"; do
        n=$((n + 1))
        # Visible unless on notched laptop past the 10-pill cap.
        drawing=on
        if [[ "$notch_host" == "yes" \
              && -n "$laptop_idx" \
              && "$display" == "$laptop_idx" \
              && "$n" -gt "$NOTCH_MAX_VISIBLE" ]]; then
          drawing=off
        fi
        sketchybar --set "space.$sid" \
          display="$display" \
          drawing="$drawing" \
          >/dev/null 2>&1 || true
      done
    done

# Repaint + recompute centering.
[[ -x "$PLUGIN_DIR/recenter.sh" ]] && "$PLUGIN_DIR/recenter.sh" >/dev/null 2>&1 || true
sketchybar --trigger workspace_changed >/dev/null 2>&1 || true
