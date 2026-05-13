#!/usr/bin/env bash
# Sync sketchybar's pill set with yabai's per-display space assignment.
#
# Item family:
#   space.<N>     — workspace pill N (one per yabai space)
#
# Invoked from:
#   • sketchybarrc startup (after items are added)
#   • yabai signals: display_added / display_removed / display_changed
#   • ~/.config/workspace/hooks/post-mutate.sh after add / remove
#
# Steps:
#   1. One-time cleanup: drop legacy nav.prev.* / nav.next.* items (the
#      bracketing chevrons we shipped previously). Idempotent — no-op
#      once they're gone.
#   2. Ensure space.<N> exists for every yabai space; remove stale.
#   3. Reorder space items by (display, space-index) so display 1's
#      pills come before display 2's, in numeric order within each group.
#   4. Set display=<D> + drawing state per item; apply per-display
#      max-visible cap from layout.env (or legacy 10-cap fallback).
#   5. Hand off to recenter.sh for density + anchor math.

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

current_spaces=$(echo "$spaces_json" | jq -r '.[].index' | sort -n)

# Existing items, classified by name pattern.
all_items=$(sketchybar --query bar 2>/dev/null | jq -r '.items[]' || true)
existing_pills=$(echo "$all_items" | sed -n 's/^space\.\([0-9]\+\)$/\1/p' | sort -n)
legacy_nav=$(echo "$all_items" | grep -E '^nav\.(prev|next)\.[0-9]+$' || true)

# 1. One-time cleanup: remove legacy nav.prev.* / nav.next.* items.
#    This makes the upgrade from the previous (with-chevrons) version
#    quiet — first run after the rewrite tidies up, subsequent runs no-op.
for item in $legacy_nav; do
  sketchybar --remove "$item" >/dev/null 2>&1 || true
done

# 2. Pills — add missing, remove stale.
# Pills carry no per-item script and no event subscription — the
# centralized workspace.paint sentinel (added in sketchybarrc) is the
# sole subscriber to workspace_changed and runs plugins/paint-all.sh
# for the batched per-pill render.
for sid in $current_spaces; do
  if ! grep -qx "$sid" <<<"$existing_pills"; then
    sketchybar --add item "space.$sid" left \
               --set "space.$sid" \
                  click_script="yabai -m space --focus $sid" \
                  padding_left=0 \
                  padding_right=0 \
               >/dev/null 2>&1 || true
  fi
done
for sid in $existing_pills; do
  if ! grep -qx "$sid" <<<"$current_spaces"; then
    sketchybar --remove "space.$sid" >/dev/null 2>&1 || true
  fi
done

# 3. Canonical order: walk displays in index order; emit each display's
#    pills in space-index order.
reorder_list=$(
  echo "$spaces_json" \
    | jq -r '. | group_by(.display)[] | [(.[0].display), ([.[].index] | sort | .[])] | @tsv'
)
order_args=()
while IFS=$'\t' read -r d_and_sids; do
  IFS=$'\t' read -r -a parts <<<"$d_and_sids"
  for sid in "${parts[@]:1}"; do
    order_args+=("space.$sid")
  done
done <<<"$reorder_list"
if (( ${#order_args[@]} > 0 )); then
  sketchybar --reorder "${order_args[@]}" >/dev/null 2>&1 || true
fi

# 4. Per-display: assignment + drawing state + max-visible enforcement.
# Batched into one sketchybar invocation to avoid per-pill render pulses.
display_groups=$(
  echo "$spaces_json" \
    | jq -r '. | group_by(.display)[] | "\(.[0].display)\t\([.[].index | tostring] | join(","))"'
)
set_args=()
while IFS=$'\t' read -r display sid_csv; do
  [[ -z "$display" ]] && continue
  IFS=',' read -ra sids <<<"$sid_csv"

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

# 5. Density + anchor math.
[[ -x "$PLUGIN_DIR/recenter.sh" ]] && "$PLUGIN_DIR/recenter.sh" >/dev/null 2>&1 || true

sketchybar --trigger workspace_changed >/dev/null 2>&1 || true
