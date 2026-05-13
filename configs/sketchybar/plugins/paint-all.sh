#!/usr/bin/env bash
# Single batched paint of every workspace pill. Subscribed to the
# workspace_changed event via a hidden sentinel item — fires once per
# focus / cascade event regardless of pill count. Replaces the per-pill
# space.sh subscriptions that produced staggered repaints (the visible
# flicker on space switches).
#
# Rendering matrix (slot_state × focus_state):
#
#   bare    + inactive   icon=<ident>          (gray, no bg, label off)
#   bare    + active     icon=<ident> label=name (gray, no bg fill — only
#                        cue is label-on; bare slots stay visually neutral
#                        even when focused, per owner policy)
#   custom  + inactive   icon=<ident> <glyph>  (assigned color, no bg)
#   custom  + active     icon=<ident> <glyph> label=name (active fg over
#                        colored bg fill)
#
# `<ident>` is the slot's digit for slot index ≤ 10 (hotkey-reachable via
# Hyper+1..0), or U+2022 BULLET for higher indices that have no hotkey.
#
# `<bare>` = seed-identity slot (name == stableLogicalLabel) AND no icon
# codepoint AND iconSpec.userOverridden == false. Anything else =
# customized, which earns its assigned color.

set -u

CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
CACHE="$HOME/.cache/workspace/current.env"

# Per-host overlay (resolves WS_CONFIG to spaces.<hostname>.json when present).
if [[ -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/resolve-config.sh"
fi
# Shared codepoint→glyph helper. Stub if not yet shipped.
if [[ -r "$HOME/.config/workspace/lib/icon-decode.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/icon-decode.sh"
else
  ws_decode_icon() { :; }
fi
# shellcheck source=/dev/null
source "$HOME/.config/sketchybar/colors.sh"

command -v jq >/dev/null 2>&1 || exit 0
command -v sketchybar >/dev/null 2>&1 || exit 0
[[ -r "$CONFIG" ]] || exit 0

ACTIVE_SID=0
if [[ -r "$CACHE" ]]; then
  # shellcheck source=/dev/null
  source "$CACHE" 2>/dev/null || true
  ACTIVE_SID="${MACOS_SPACE_INDEX:-0}"
fi

DOT_GLYPH=$'\xe2\x80\xa2'   # U+2022 BULLET (UTF-8 bytes). Used for slot > 10.

# Single jq invocation: emit one TSV row per slot with the fields needed
# to decide bare/customized + render the icon. join("\t") avoids @tsv's
# backslash-doubling, preserving codepoint escapes (`\u{F048B}`) as-is.
args=()
while IFS=$'\t' read -r idx name color codepoint user_overridden stable_label; do
  [[ -z "$idx" ]] && continue

  glyph=""
  [[ -n "$codepoint" ]] && glyph=$(ws_decode_icon "$codepoint")

  if (( idx <= 10 )); then
    ident="$idx"
  else
    ident="$DOT_GLYPH"
  fi

  is_bare=0
  if [[ "$user_overridden" == "false" && "$name" == "$stable_label" && -z "$codepoint" ]]; then
    is_bare=1
  fi

  if [[ -n "$glyph" ]]; then
    icon_text="$ident $glyph"
  else
    icon_text="$ident"
  fi

  pill_color="0xff${color#\#}"

  if [[ "$idx" == "$ACTIVE_SID" ]]; then
    if (( is_bare )); then
      args+=(
        --set "space.$idx"
        background.drawing=off
        icon.color="$INACTIVE_LABEL"
        label.color="$INACTIVE_LABEL"
        label.drawing=on
        icon="$icon_text"
        label="$name"
      )
    else
      args+=(
        --set "space.$idx"
        background.drawing=on
        background.color="$pill_color"
        icon.color="$ACTIVE_FG"
        label.color="$ACTIVE_FG"
        label.drawing=on
        icon="$icon_text"
        label="$name"
      )
    fi
  else
    if (( is_bare )); then
      args+=(
        --set "space.$idx"
        background.drawing=off
        icon.color="$INACTIVE_LABEL"
        label.drawing=off
        icon="$icon_text"
      )
    else
      args+=(
        --set "space.$idx"
        background.drawing=off
        icon.color="$pill_color"
        label.drawing=off
        icon="$icon_text"
      )
    fi
  fi
done < <(jq -r '
  .spaces | to_entries
  | sort_by(.key | tonumber)
  | .[]
  | [
      .key,
      (.value.name // ("ws" + .key)),
      (.value.color // "#9399b2"),
      (.value.iconSpec.codepoint // ""),
      ((.value.iconSpec.userOverridden // false) | tostring),
      (.value.stableLogicalLabel // (.value.name // ""))
    ]
  | join("\t")
' "$CONFIG" 2>/dev/null)

# One sketchybar invocation = one redraw transaction. Tolerant of items
# not yet existing (init race during boot).
if (( ${#args[@]} > 0 )); then
  sketchybar "${args[@]}" >/dev/null 2>&1 || true
fi
