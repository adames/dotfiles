#!/usr/bin/env bash
# Repaint one workspace pill. Invoked by sketchybar on the workspace_changed
# trigger (fired from ~/.config/workspace/on-space-changed.sh) and on item
# init. sketchybar sets $NAME to the item name (space.N); we derive the slot
# index from it because sketchybar's --set only accepts named properties,
# not arbitrary script env vars.

set -u

SID="${NAME##*.}"

# Per-host overlay: resolve to spaces.<hostname>.json when present.
if [[ -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/resolve-config.sh"
fi
# Shared codepoint-unescape helper. Stub if the lib hasn't shipped yet.
if [[ -r "$HOME/.config/workspace/lib/icon-decode.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/icon-decode.sh"
else
  ws_decode_icon() { :; }
fi

CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
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

# Per-slot metadata from spaces.json (v2). One jq call per field — see
# on-space-changed.sh for why @tsv would corrupt the escaped codepoint.
NAME_TXT="ws$SID"
COLOR="#9399b2"
ICON=""
if [[ -r "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  _jq() { jq -r --arg k "$SID" "$1" "$CONFIG" 2>/dev/null; }
  NAME_TXT=$(_jq '.spaces[$k].name // ("ws" + $k)')
  COLOR=$(_jq '.spaces[$k].color // "#9399b2"')
  ICON_ESCAPED=$(_jq '.spaces[$k].iconSpec.codepoint // ""')

  ICON=$(ws_decode_icon "${ICON_ESCAPED:-}")
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
