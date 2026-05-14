#!/usr/bin/env bash
# Sync sketchybar's per-display items with yabai's space assignment.
# Adds/removes the per-display "you are here" name chips and the
# workspace pills; assigns display=<N> to each so they render only on
# their owning monitor. Pills + chips are left-anchored — the bar lays
# them out from the left corner toward the center, no centering math
# and no visibility cap.
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
#   5. Set display=<D> + drawing=on on every pill (no visibility cap —
#      yabai is the source of truth for pill count; if pills overflow
#      the aux region on a notched laptop that's expected behavior,
#      not a bug).

set -u

# Silent bail.
command -v sketchybar >/dev/null 2>&1 || exit 0
pgrep -x sketchybar >/dev/null 2>&1 || exit 0
command -v yabai >/dev/null 2>&1 || exit 0
yabai -m query --spaces >/dev/null 2>&1 || exit 0

spaces_json=$(yabai -m query --spaces 2>/dev/null)
[[ -z "$spaces_json" ]] && exit 0
displays_json=$(yabai -m query --displays 2>/dev/null)
[[ -z "$displays_json" ]] && exit 0

current_spaces=$(echo "$spaces_json" | jq -r '.[].index' | sort -n)
current_displays=$(echo "$displays_json" | jq -r '.[].index' | sort -n)

# Existing items, classified by name pattern.
all_items=$(sketchybar --query bar 2>/dev/null | jq -r '.items[]' || true)
# NOTE: `-E` (ERE) is required so `+` is a quantifier. BSD sed on macOS
# treats `\+` as a literal plus sign — the GNU BRE convention silently
# matches zero items, leaving existing_pills/existing_chips empty.
# That made the remove-stale loops below into no-ops, so orphan
# pills from a now-smaller yabai never got cleaned up.
existing_pills=$(echo "$all_items" | sed -nE 's/^space\.([0-9]+)$/\1/p' | sort -n)
existing_chips=$(echo "$all_items" | sed -nE 's/^workspace\.name\.([0-9]+)$/\1/p' | sort -n)
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
#
#    `width=140` pins the chip's geometry: the pill chain to the right
#    of the chip doesn't shift when the focused-workspace name changes
#    length (home → uplink → ridiculouslylongname). Set at --add time,
#    never updated by paint-all.sh, so focus events stay geometry-stable.
#
#    Centering math: sketchybar's `label.align=center` only centers text
#    WITHIN the label's own rendering box — not within the parent item.
#    With auto-sized label width, the label box hugs the text and the
#    item lays out content left-anchored, leaving a large right-side
#    gap. To actually center the name in the chip we (a) zero the
#    off-icon's padding so the icon block has no width, and (b) force
#    `label.width` to span the chip's visible interior (item width
#    minus the bar's default bg padding). Then `label.align=center`
#    centers the text within that wide label box, which IS the chip.
#    ~140pt fits ~11 chars at 12pt bold; longer names truncate
#    (acceptable trade vs. geometry instability).
chip_width=140
# Chip has no internal bg padding now — bg fills its entire slot, and
# label.width spans the full chip so `align=center` centers the name in
# the visible rectangle. (Earlier we used bg.padding_left/right=8 with
# label.width = chip_width - 16. The 8-on-each-side inset interacted
# awkwardly with the slot-rhythm math below, eating into the chip→pill
# gap by exactly the chip's bg.padding_left. Setting it to 0 simplifies
# both the centering and the layout.)
label_width=$chip_width

# Slot rhythm: the bar reads as alternating visible pills and invisible
# pill-sized chunks of space. Pills measure ~43-44pt at 12pt bold; 44
# is the round target. We achieve the rhythm via item padding_left — in
# sketchybar that aliases background.padding_left, and the visible gap
# from a pill's left edge to the previous item's right edge equals the
# pill's padding_left (for pill→pill). Setting chip.padding_left=0 too
# makes the chip→pill boundary follow the same rule.
SLOT_GAP=44
for d in $current_displays; do
  if ! grep -qx "$d" <<<"$existing_chips"; then
    sketchybar --add item "workspace.name.$d" left >/dev/null 2>&1 || true
  fi
  # Apply the chip's fixed geometric contract unconditionally (not just
  # at --add time) so existing chips from earlier deployments pick up
  # any tweaks — and to defend against property drift if some other
  # plugin ever touches these. paint-all.sh stays the sole writer of
  # label.value and label.color.
  sketchybar --set "workspace.name.$d" \
    icon.drawing=off \
    icon.padding_left=0 \
    icon.padding_right=0 \
    label.drawing=on \
    label.align=center \
    label.padding_left=0 \
    label.padding_right=0 \
    label.width="$label_width" \
    width="$chip_width" \
    padding_left=0 \
    padding_right=0 \
    display="$d" \
    drawing=on \
    >/dev/null 2>&1 || true
done
for d in $existing_chips; do
  if ! grep -qx "$d" <<<"$current_displays"; then
    sketchybar --remove "workspace.name.$d" >/dev/null 2>&1 || true
  fi
done

# 3. Pills — add missing, remove stale. Pills carry no per-item script
#    and no event subscription — the centralized workspace.paint
#    sentinel runs plugins/paint-all.sh for the batched per-pill render.
#    `padding_left=$SLOT_GAP` is the invisible-pill-sized gap that
#    appears before every pill. Re-applied unconditionally in step 5
#    so existing pills from older deploys pick up the current value.
for sid in $current_spaces; do
  if ! grep -qx "$sid" <<<"$existing_pills"; then
    sketchybar --add item "space.$sid" left \
               --set "space.$sid" \
                  click_script="yabai -m space --focus $sid" \
                  padding_left="$SLOT_GAP" \
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

# 5. Per-display: assignment + drawing=on + padding on every pill. No
#    cap. The chip's display assignment was set at --add time; pills
#    need their display updated here (they may have moved between
#    displays since the last sync). Padding is re-asserted unconditionally
#    so an existing pill from an older deploy picks up the current gap
#    without requiring a re-add. Batched into one sketchybar invocation.
display_groups=$(
  echo "$spaces_json" \
    | jq -r '. | group_by(.display)[] | "\(.[0].display)\t\([.[].index | tostring] | join(","))"'
)
set_args=()
while IFS=$'\t' read -r display sid_csv; do
  [[ -z "$display" ]] && continue
  IFS=',' read -ra sids <<<"$sid_csv"
  for sid in "${sids[@]}"; do
    set_args+=(--set "space.$sid" "display=$display" "drawing=on" "padding_left=$SLOT_GAP" "padding_right=0")
  done
done <<< "$display_groups"
if (( ${#set_args[@]} > 0 )); then
  sketchybar "${set_args[@]}" >/dev/null 2>&1 || true
fi

# Trigger a repaint so paint-all.sh fills in the chip labels + pill
# colors. Sentinel-subscribed; one batched transaction.
sketchybar --trigger workspace_changed >/dev/null 2>&1 || true
