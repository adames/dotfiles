#!/usr/bin/env bash
# Repaint one workspace pill. Invoked by sketchybar on the workspace_changed
# trigger (fired from ~/.config/workspace/on-space-changed.sh) and on item
# init. sketchybar sets $NAME to the item name (space.N); we derive the slot
# index from it because sketchybar's --set only accepts named properties,
# not arbitrary script env vars.

set -u

SID="${NAME##*.}"

CONFIG="$HOME/.config/workspace/spaces.json"
CACHE="$HOME/.cache/workspace/current.env"

# shellcheck source=/dev/null
source "$HOME/.config/sketchybar/colors.sh"

# Active slot from the env cache. The cache is written atomically by
# on-space-changed.sh (mktemp + mv) so a torn read is impossible.
ACTIVE_SID=0
if [[ -r "$CACHE" ]]; then
  # shellcheck source=/dev/null
  source "$CACHE" 2>/dev/null || true
  ACTIVE_SID="${MACOS_SPACE_INDEX:-0}"
fi

# Per-slot metadata from spaces.json. IFS=$'\t' so names with spaces survive.
NAME_TXT="ws$SID"
COLOR="#9399b2"
ICON=""
if [[ -r "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  IFS=$'\t' read -r NAME_TXT COLOR ICON < <(
    jq -r --arg k "$SID" '
      .spaces[$k] // {}
      | [(.name // ("ws"+$k)), (.color // "#9399b2"), (.icon // "")] | @tsv
    ' "$CONFIG" 2>/dev/null
  ) || true
fi

PILL_COLOR="0xff${COLOR#\#}"
PILL_LABEL="$NAME_TXT"
PILL_ICON="$SID $ICON"

if [[ "$SID" == "$ACTIVE_SID" ]]; then
  sketchybar --set "$NAME" \
    background.drawing=on \
    background.color="$PILL_COLOR" \
    icon.color="$ACTIVE_FG" \
    label.color="$ACTIVE_FG" \
    icon="$PILL_ICON" \
    label="$PILL_LABEL"
else
  sketchybar --set "$NAME" \
    background.drawing=off \
    icon.color="$PILL_COLOR" \
    label.color="$INACTIVE_LABEL" \
    icon="$PILL_ICON" \
    label="$PILL_LABEL"
fi
