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

  if [[ -n "$ICON_ESCAPED" ]]; then
    if [[ "$ICON_ESCAPED" == "\\u{"* ]]; then
      hex="${ICON_ESCAPED#\\u\{}"; hex="${hex%\}}"
      padded=$(printf '%08x' "0x$hex")
      ICON=$(printf "\\U${padded}")
    else
      hex="${ICON_ESCAPED#\\u}"
      ICON=$(printf "\\u${hex}")
    fi
  else
    # v1 fallback: matches on-space-changed.sh. Read raw .icon glyph
    # when iconSpec is missing (post-rollback or hand-edited configs).
    ICON_LEGACY=$(_jq '.spaces[$k].icon // ""')
    [[ -n "$ICON_LEGACY" ]] && ICON="$ICON_LEGACY"
  fi
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
