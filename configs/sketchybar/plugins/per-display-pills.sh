#!/usr/bin/env bash
# Sync sketchybar's per-display items with yabai's space assignment.
# Adds/removes the per-display "you are here" name chips and the
# workspace pills; assigns display=<N> to each so they render only on
# their owning monitor; enforces the visible-pill cap on notched
# displays. Pills + chips are left-anchored — the bar lays them out
# from the left corner toward the center, no centering math needed.
#
# Item families:
#   workspace.name.<D>   — left-most label per display, shows the focused
#                          workspace name on display D (paint-all.sh
#                          updates the label/color text).
#   space.<N>            — workspace pill N (one per yabai space).
#
# Invoked from:
#   • sketchybarrc startup (after items are added)
#   • yabai signals: display_added / display_removed / display_changed
#   • ~/.config/workspace/hooks/post-mutate.sh after add / remove
#
# Steps:
#   1. One-time cleanup: drop legacy nav.prev.* / nav.next.* items
#      (bracketing chevrons from an earlier version). Idempotent.
#   2. Ensure workspace.name.<D> exists for every yabai display.
#   3. Ensure space.<N> exists for every yabai space; remove stale of
#      both families.
#   4. Reorder so each display's items are: chip, then pills in
#      space-index order.
#   5. Set display=<D> on every item; apply the visible-pill cap on
#      notched laptops so pills don't slide under the camera housing.

set -u

PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
WS_LAPTOP_UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"
WS_LAYOUT_ENV="${WS_LAYOUT_ENV:-$HOME/.cache/workspace/layout.env}"
LEGACY_NOTCH_MAX_VISIBLE=10

# Silent bail.
command -v sketchybar >/dev/null 2>&1 || exit 0
pgrep -x sketchybar >/dev/null 2>&1 || exit 0
command -v yabai >/dev/null 2>&1 || exit 0
yabai -m query --spaces >/dev/null 2>&1 || exit 0

# Pull authoritative display/notch state when available; tolerate absence.
if [[ -r "$WS_LAYOUT_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$WS_LAYOUT_ENV" 2>/dev/null || true
fi

# yabai-index of the laptop display (different domain from CGDirectDisplayID,
# which is what the daemon publishes). UUID-first, origin-(0,0) fallback.
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

spaces_json=$(yabai -m query --spaces 2>/dev/null)
[[ -z "$spaces_json" ]] && exit 0
displays_json=$(yabai -m query --displays 2>/dev/null)
[[ -z "$displays_json" ]] && exit 0

current_spaces=$(echo "$spaces_json" | jq -r '.[].index' | sort -n)
current_displays=$(echo "$displays_json" | jq -r '.[].index' | sort -n)

# Existing items, classified by name pattern.
all_items=$(sketchybar --query bar 2>/dev/null | jq -r '.items[]' || true)
existing_pills=$(echo "$all_items" | sed -n 's/^space\.\([0-9]\+\)$/\1/p' | sort -n)
existing_chips=$(echo "$all_items" | sed -n 's/^workspace\.name\.\([0-9]\+\)$/\1/p' | sort -n)
legacy_nav=$(echo "$all_items" | grep -E '^nav\.(prev|next)\.[0-9]+$' || true)

# 1. One-time cleanup: legacy nav.prev.* / nav.next.* items.
for item in $legacy_nav; do
  sketchybar --remove "$item" >/dev/null 2>&1 || true
done

# 2. Per-display name chip. Always-visible "you are here" label sitting
#    at the leftmost slot of each display's strip. paint-all.sh sets the
#    label text + color from spaces.json + yabai's per-display visible
#    space; this script only handles the item's lifecycle + display
#    assignment.
for d in $current_displays; do
  if ! grep -qx "$d" <<<"$existing_chips"; then
    sketchybar --add item "workspace.name.$d" left \
               --set "workspace.name.$d" \
                  icon.drawing=off \
                  label.drawing=on \
                  label.padding_left=8 \
                  label.padding_right=12 \
                  display="$d" \
                  drawing=on \
               >/dev/null 2>&1 || true
  fi
done
for d in $existing_chips; do
  if ! grep -qx "$d" <<<"$current_displays"; then
    sketchybar --remove "workspace.name.$d" >/dev/null 2>&1 || true
  fi
done

# 3. Pills — add missing, remove stale. Pills carry no per-item script
#    and no event subscription — the centralized workspace.paint
#    sentinel runs plugins/paint-all.sh for the batched per-pill render.
for sid in $current_spaces; do
  if ! grep -qx "$sid" <<<"$existing_pills"; then
    sketchybar --add item "space.$sid" left \
               --set "space.$sid" \
                  click_script="yabai -m space --focus $sid" \
                  padding_left=2 \
                  padding_right=0 \
               >/dev/null 2>&1 || true
  fi
done
for sid in $existing_pills; do
  if ! grep -qx "$sid" <<<"$current_spaces"; then
    sketchybar --remove "space.$sid" >/dev/null 2>&1 || true
  fi
done

# 4. Canonical order: walk displays in index order; each display group
#    is [chip, pill_min, ..., pill_max].
reorder_list=$(
  echo "$spaces_json" \
    | jq -r '. | group_by(.display)[] | [(.[0].display), ([.[].index] | sort | .[])] | @tsv'
)
order_args=()
while IFS=$'\t' read -r d_and_sids; do
  IFS=$'\t' read -r -a parts <<<"$d_and_sids"
  display="${parts[0]}"
  [[ -z "$display" ]] && continue
  order_args+=("workspace.name.$display")
  for sid in "${parts[@]:1}"; do
    order_args+=("space.$sid")
  done
done <<<"$reorder_list"
if (( ${#order_args[@]} > 0 )); then
  sketchybar --reorder "${order_args[@]}" >/dev/null 2>&1 || true
fi

# 5. Per-display: assignment + drawing state + max-visible enforcement
#    for pills. Batched into one sketchybar invocation. The chip's
#    display assignment was set at --add time; only pills need their
#    display + drawing updated here (they may have moved between
#    displays since the last sync).
display_groups=$(
  echo "$spaces_json" \
    | jq -r '. | group_by(.display)[] | "\(.[0].display)\t\([.[].index | tostring] | join(","))"'
)
set_args=()
while IFS=$'\t' read -r display sid_csv; do
  [[ -z "$display" ]] && continue
  IFS=',' read -ra sids <<<"$sid_csv"

  # Visible-pill cap on notched laptops: pills past the cap render
  # drawing=off so they don't get clipped by the camera housing. The
  # ws-topologyd-published WS_MAX_VISIBLE_SLOTS_<id> overrides the
  # legacy 10-pill default when available.
  max_visible=""
  if [[ -n "${WS_LAPTOP_DISPLAY_ID:-}" \
        && -n "$laptop_idx" \
        && "$display" == "$laptop_idx" ]]; then
    var_name="WS_MAX_VISIBLE_SLOTS_${WS_LAPTOP_DISPLAY_ID}"
    max_visible="${!var_name:-}"
  fi
  if [[ -z "$max_visible" \
        && "$notch_host" == "yes" \
        && -n "$laptop_idx" \
        && "$display" == "$laptop_idx" ]]; then
    max_visible=$LEGACY_NOTCH_MAX_VISIBLE
  fi

  n=0
  for sid in "${sids[@]}"; do
    n=$((n + 1))
    drawing=on
    [[ -n "$max_visible" && "$n" -gt "$max_visible" ]] && drawing=off
    set_args+=(--set "space.$sid" "display=$display" "drawing=$drawing")
  done
done <<< "$display_groups"
if (( ${#set_args[@]} > 0 )); then
  sketchybar "${set_args[@]}" >/dev/null 2>&1 || true
fi

# Trigger a repaint so paint-all.sh fills in the chip labels + pill
# colors. Sentinel-subscribed; one batched transaction.
sketchybar --trigger workspace_changed >/dev/null 2>&1 || true
