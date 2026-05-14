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
#   bare    + active     icon=<ident>          (ACTIVE_FG icon over
#                        INACTIVE_FILL muted-gray bg — subtle focus cue
#                        for a slot with no assigned colour)
#   custom  + inactive   icon=<ident> <glyph>  (slot-color text, no bg)
#   custom  + active     icon=<ident> <glyph>  (ACTIVE_FG over slot-color
#                        bg fill — the headline focus cue)
#
# The focused pill AND the workspace.name.<D> chip both light up. The
# pill says "this slot has keyboard focus"; the chip says "this is the
# slot's name". Earlier iterations made pills static and let the chip
# carry focus alone — but the highlighted pill is what makes the bar
# scannable at a glance, so it's back. Each pill is still pinned to its
# monitor by per-display-pills.sh and to its slot color by spaces.json.
#
# Pills carry no labels. Each display's leftmost item is a
# workspace.name.<D> chip showing the workspace that's currently
# *visible* on display D (per yabai). Chip styling is an inversion:
#   focused display    → slot-color fill, dark text
#   unfocused display  → empty fill, slot-color text
# In both states the chip carries a thin slot-color border (flush
# against the fill — no inset). On the focused chip the border blends
# into the fill; on the unfocused chip the border IS the chip's
# silhouette. The chip items themselves are created by per-display-
# pills.sh with a fixed `width=140`, so chip text length never shifts
# the pill chain.
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
ACTIVE_DISPLAY=0
# Authoritative focus from yabai. current.env is updated by
# on-space-changed.sh, which fires on yabai's `space_changed`. Some
# focus changes — particularly cross-display mouse clicks or non-yabai-
# driven transitions — have empirically shipped without that signal,
# leaving the cascade cache stale. paint-all.sh ran with the old cache
# and lit the wrong chip. Querying yabai inside paint-all.sh makes the
# chip self-correcting on every repaint regardless of cascade state.
if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces --space >/dev/null 2>&1; then
  read -r ACTIVE_SID ACTIVE_DISPLAY < <(
    yabai -m query --spaces --space 2>/dev/null \
      | jq -r '"\(.index) \(.display)"' 2>/dev/null
  ) || true
fi
# Fallback for headless / pre-yabai / Ubuntu: use the cascade cache.
if [[ "${ACTIVE_SID:-0}" == 0 ]] && [[ -r "$CACHE" ]]; then
  # shellcheck source=/dev/null
  source "$CACHE" 2>/dev/null || true
  ACTIVE_SID="${MACOS_SPACE_INDEX:-0}"
  ACTIVE_DISPLAY="${MACOS_SPACE_DISPLAY:-0}"
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

  # Focused pill (active): fill the background and switch icon to
  # ACTIVE_FG (catppuccin base). Customized slots use their assigned
  # colour for the fill; bare slots use INACTIVE_FILL (surface1) as a
  # muted "in-focus but no identity" highlight.
  # Unfocused pill (inactive): no background; icon coloured by slot
  # identity (slot colour for customized, INACTIVE_LABEL gray for bare).
  if [[ "$idx" == "$ACTIVE_SID" ]]; then
    if (( is_bare )); then
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
done < <(
  # Drive the pill loop from yabai's spaces (source of truth for
  # existence), join with spaces.json metadata for optional identity.
  # If spaces.json has no entry for a yabai-reported space, the // ""
  # fallbacks make it render as a bare pill (gray digit, no glyph).
  # This is the "yabai owns existence, spaces.json owns identity"
  # contract — paint reflects whatever Apple/yabai actually has.
  if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
    yabai -m query --spaces 2>/dev/null \
      | jq -r --slurpfile cfg "$CONFIG" --arg sep "$SEP" '
          . | sort_by(.index) | .[]
          | . as $s
          | ($s.index | tostring) as $k
          | ($cfg[0].spaces[$k] // {}) as $meta
          | (("ws" + $k)) as $default_name
          | [
              $k,
              ($meta.name // $default_name),
              ($meta.color // "#9399b2"),
              ($meta.iconSpec.codepoint // ""),
              (($meta.iconSpec.userOverridden // false) | tostring),
              ($meta.stableLogicalLabel // ($meta.name // $default_name))
            ]
          | join($sep)
        ' 2>/dev/null
  else
    # Fallback for headless / pre-yabai: emit rows for whatever
    # spaces.json has (better than no pills at all).
    jq -r --arg sep "$SEP" '
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
    ' "$CONFIG" 2>/dev/null
  fi
)

# Per-display workspace name chip update. For each yabai display, find
# the currently visible space and set workspace.name.<display>'s label
# to that space's name. The chip items are created by per-display-
# pills.sh (with a fixed `width=140` so this update can never shift
# the pill chain geometry); this loop only rewrites text + colors.
#
# Highlight rule:
#   d_idx == $ACTIVE_DISPLAY  → focused display, full-color chip
#                              (workspace-color background fill, dark fg)
#   otherwise                  → unfocused display, muted gray text,
#                              no background. Single chip is "lit" at
#                              any time, regardless of how many monitors
#                              are attached — fast "where is keyboard
#                              focus" cue across the whole multi-monitor
#                              setup.
# Silently no-ops on machines without yabai (chips stay blank).
if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
  while IFS="$SEP" read -r d_idx s_idx s_name s_color; do
    [[ -z "$d_idx" || -z "$s_idx" ]] && continue
    [[ -z "$s_name" ]] && s_name="ws$s_idx"
    [[ -z "$s_color" ]] && s_color="#cdd6f4"
    slot_hex="0xff${s_color#\#}"
    if [[ "$d_idx" == "$ACTIVE_DISPLAY" ]]; then
      # Focused: slot-color fill, dark text. Border = slot color too;
      # blends with the fill into a solid colored chip.
      args+=(
        --set "workspace.name.$d_idx"
        label="$s_name"
        label.color="$ACTIVE_FG"
        background.drawing=on
        background.color="$slot_hex"
        background.border_width=2
        background.border_color="$slot_hex"
      )
    else
      # Unfocused: empty fill, slot-color text. Border = slot color and
      # IS the visible silhouette of the chip. bg.drawing stays on so
      # the border draws (sketchybar's bg.drawing=off would skip the
      # border too); fill is rendered transparent.
      args+=(
        --set "workspace.name.$d_idx"
        label="$s_name"
        label.color="$slot_hex"
        background.drawing=on
        background.color=0x00000000
        background.border_width=2
        background.border_color="$slot_hex"
      )
    fi
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
