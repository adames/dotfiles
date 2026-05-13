#!/usr/bin/env bash
# Single batched paint of every workspace pill + the per-display
# workspace-name chip. Subscribed to the workspace_changed event via a
# hidden sentinel item — fires once per focus / cascade event regardless
# of pill or display count. Replaces the per-pill space.sh subscriptions
# that produced staggered repaints (visible flicker on space switches).
#
# Pill rendering matrix (slot_state × focus_state):
#
#   bare    + inactive   icon=<ident>          (gray, no bg)
#   bare    + active     icon=<ident>          (gray icon over muted gray
#                        bg — subtle focus cue)
#   custom  + inactive   icon=<ident> <glyph>  (assigned color, no bg)
#   custom  + active     icon=<ident> <glyph>  (active fg over colored
#                        bg fill)
#
# Pills carry no labels. Each display's leftmost item is a
# workspace.name.<D> chip showing the workspace that's currently
# *visible* on display D (per yabai), painted in that space's color.
# The chip items themselves are created by per-display-pills.sh; this
# script only updates their text + color.
#
# `<ident>` is the slot's digit for slot index ≤ 10 (hotkey-reachable
# via Hyper+1..0), or U+2022 BULLET for higher indices.
#
# `<bare>` = seed-identity slot (name == stableLogicalLabel) AND no
# icon codepoint AND iconSpec.userOverridden == false. Anything else =
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
# Defensive defaults: INACTIVE_FILL was added with the workspace-name
# chip change. On a deployed machine that hasn't re-run bootstrap.sh
# yet, ~/.config/sketchybar/colors.sh predates the variable — set -u
# below would otherwise crash on the bare-active branch.
: "${INACTIVE_FILL:=0xff45475a}"   # catppuccin surface1
: "${INACTIVE_LABEL:=0xff6c7086}"  # overlay0
: "${ACTIVE_FG:=0xff1e1e2e}"       # base

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

# Single jq invocation: emit one row per slot with the fields needed to
# decide bare/customized + render the icon. Fields are separated by
# U+001F (Unit Separator) — not \t — so an empty codepoint field
# doesn't collapse against the next \t and slide fallbackText into
# the wrong shell variable. Separator is injected via `--arg sep` so
# this source file doesn't need to carry the raw control byte (Write
# tooling tends to strip it on save).
SEP=$'\x1f'
args=()
while IFS="$SEP" read -r idx name color codepoint user_overridden stable_label; do
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
      # Bare-active: muted gray bg as a subtle focus cue. Icon stays
      # gray. The workspace.name chip carries the explicit identity.
      args+=(
        --set "space.$idx"
        background.drawing=on
        background.color="$INACTIVE_FILL"
        icon.color="$ACTIVE_FG"
        label.drawing=off
        icon="$icon_text"
      )
    else
      args+=(
        --set "space.$idx"
        background.drawing=on
        background.color="$pill_color"
        icon.color="$ACTIVE_FG"
        label.drawing=off
        icon="$icon_text"
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
done < <(jq -r --arg sep "$SEP" '
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
  | join($sep)
' "$CONFIG" 2>/dev/null)

# Per-display workspace name chip update. For each yabai display, find
# the currently visible space and set workspace.name.<display>'s label
# to that space's name + color from spaces.json. The chip items are
# created by per-display-pills.sh; this loop just rewrites their text.
# Silently no-ops on machines without yabai (the chips simply stay
# blank — non-fatal).
if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
  while IFS="$SEP" read -r d_idx s_idx s_name s_color; do
    [[ -z "$d_idx" || -z "$s_idx" ]] && continue
    [[ -z "$s_name" ]] && s_name="ws$s_idx"
    [[ -z "$s_color" ]] && s_color="#cdd6f4"
    args+=(
      --set "workspace.name.$d_idx"
      label="$s_name"
      label.color="0xff${s_color#\#}"
    )
  done < <(
    # Visible-per-display from yabai → join with spaces.json metadata.
    # One jq pipeline: ingests the two JSON sources via $cfg, emits
    # one row per visible space with [display, index, name, color].
    yabai -m query --spaces 2>/dev/null \
      | jq -r --slurpfile cfg "$CONFIG" --arg sep "$SEP" '
          .[]
          | select(."is-visible")
          | . as $s
          | $cfg[0].spaces[($s.index | tostring)] as $meta
          | [
              ($s.display | tostring),
              ($s.index | tostring),
              ($meta.name // ("ws" + ($s.index | tostring))),
              ($meta.color // "#cdd6f4")
            ]
          | join($sep)
        ' 2>/dev/null
  )
fi

# One sketchybar invocation = one redraw transaction. Tolerant of items
# not yet existing (init race during boot).
if (( ${#args[@]} > 0 )); then
  sketchybar "${args[@]}" >/dev/null 2>&1 || true
fi
