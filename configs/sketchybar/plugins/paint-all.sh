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

# MARK: - Optimistic fast path
#
# ws-focus / ws-send-follow fire this trigger with the target SID +
# OLD SID *before* invoking yabai's space --focus. Goal: the pill
# snaps to the target the instant the user commits the chord, well
# before yabai's transition animation + the space_changed cascade
# would otherwise land.
#
# The full repaint below takes ~70ms (two yabai RPCs + multi-stage jq
# + per-pill loop). For "instant feel" that's already too much. The
# fast path here does the bare minimum: one jq into spaces.json to
# decide bare-vs-customized for the old + new slots, then two batched
# `sketchybar --set` calls for the two pills that changed. ~10–15ms
# total. The eventual real cascade fires the full paint redundantly
# and catches anything we missed (the chip label, multi-display state,
# etc.). Render decisions here mirror the main loop exactly, so the
# two paints land on the same state.
if [[ -n "${WS_OPTIMISTIC_SID:-}" && -n "${WS_OPTIMISTIC_OLD_SID:-}" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/sketchybar/colors.sh" 2>/dev/null || true
  : "${INACTIVE_FILL:=0xff45475a}"
  : "${INACTIVE_LABEL:=0xff6c7086}"
  : "${ACTIVE_FG:=0xff1e1e2e}"

  # Per-host overlay (resolves WS_CONFIG to spaces.<hostname>.json when present).
  if [[ -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/workspace/lib/resolve-config.sh"
  fi
  CFG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
  command -v jq >/dev/null 2>&1 || exit 0
  [[ -r "$CFG" ]] || exit 0

  # Single jq call → two rows for OLD and NEW slot indices. Build one
  # batched `sketchybar --set ... --set ...` so the whole update lands
  # as one sketchybar RPC. Also captures the NEW slot's name + colour
  # for the chip update at the bottom.
  args=()
  new_name=""
  new_slot_hex=""
  while IFS=$'\t' read -r slot color codepoint user_overridden stable_label name; do
    [[ -z "$slot" ]] && continue
    slot_hex="0xff${color#\#}"
    is_bare=0
    [[ "$user_overridden" == "false" && "$name" == "$stable_label" && -z "$codepoint" ]] && is_bare=1

    if [[ "$slot" == "$WS_OPTIMISTIC_SID" ]]; then
      # New active pill: filled background, dark icon. Bare slots use
      # INACTIVE_FILL as the muted "focused but no identity" fill.
      new_name="$name"
      new_slot_hex="$slot_hex"
      if (( is_bare )); then
        args+=(--set "space.$slot"
               background.drawing=on background.color="$INACTIVE_FILL"
               icon.color="$ACTIVE_FG")
      else
        args+=(--set "space.$slot"
               background.drawing=on background.color="$slot_hex"
               icon.color="$ACTIVE_FG")
      fi
    else
      # Old active pill: clear background, slot-color icon (or
      # INACTIVE_LABEL for bare).
      if (( is_bare )); then
        args+=(--set "space.$slot"
               background.drawing=off
               icon.color="$INACTIVE_LABEL")
      else
        args+=(--set "space.$slot"
               background.drawing=off
               icon.color="$slot_hex")
      fi
    fi
  done < <(
    jq -r --arg o "$WS_OPTIMISTIC_OLD_SID" --arg n "$WS_OPTIMISTIC_SID" '
      . as $root
      | [$o, $n][]
      | . as $k
      | ($root.spaces[$k] // {}) as $s
      | [$k,
         ($s.color                                 // "#9399b2"),
         ($s.iconSpec.codepoint                    // ""),
         (($s.iconSpec.userOverridden // false) | tostring),
         ($s.stableLogicalLabel                    // ($s.name // "")),
         ($s.name                                  // ("ws" + $k))]
      | @tsv
    ' "$CFG" 2>/dev/null
  )

  # Chip update on the target display — focused-display style: filled
  # slot-color background, dark text. Same shape as the full repaint's
  # chip loop. The eventual cascade redraws the same state.
  if [[ -n "${WS_OPTIMISTIC_DISPLAY:-}" && -n "$new_slot_hex" ]]; then
    [[ -z "$new_name" ]] && new_name="ws$WS_OPTIMISTIC_SID"
    args+=(--set "workspace.name.$WS_OPTIMISTIC_DISPLAY"
           label="$new_name"
           label.color="$ACTIVE_FG"
           background.drawing=on
           background.color="$new_slot_hex"
           background.border_width=2
           background.border_color="$new_slot_hex")
  fi

  (( ${#args[@]} > 0 )) && sketchybar "${args[@]}" >/dev/null 2>&1
  exit 0
fi

ACTIVE_SID=0
ACTIVE_DISPLAY=0
# Optimistic override (no OLD sid): paint-all falls through to the
# full repaint but with ACTIVE_SID forced to the optimistic target.
# Slower than the fast path above (~70ms) but still beats the cascade
# delay; used for the chip-update-on-cross-display case.
if [[ -n "${WS_OPTIMISTIC_SID:-}" ]]; then
  ACTIVE_SID="$WS_OPTIMISTIC_SID"
  ACTIVE_DISPLAY="${WS_OPTIMISTIC_DISPLAY:-1}"
fi
# Authoritative focus from yabai. current.env is updated by
# on-space-changed.sh, which fires on yabai's `space_changed`. Some
# focus changes — particularly cross-display mouse clicks or non-yabai-
# driven transitions — have empirically shipped without that signal,
# leaving the cascade cache stale. paint-all.sh ran with the old cache
# and lit the wrong chip. Querying yabai inside paint-all.sh makes the
# chip self-correcting on every repaint regardless of cascade state.
if [[ "$ACTIVE_SID" == 0 ]] \
   && command -v yabai >/dev/null 2>&1 \
   && yabai -m query --spaces --space >/dev/null 2>&1; then
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
    # Optimistic pre-paint: on the target display, force the chip's
    # visible-space view to the optimistic SID (and pick up that
    # slot's identity from spaces.json) so the chip's label + colour
    # don't lag a frame behind the pill highlight.
    if [[ -n "${WS_OPTIMISTIC_SID:-}" && "$d_idx" == "${WS_OPTIMISTIC_DISPLAY:-}" ]]; then
      s_idx="$WS_OPTIMISTIC_SID"
      read -r s_name s_color < <(
        jq -r --arg k "$s_idx" '
          [ (.spaces[$k].name  // ("ws" + $k)),
            (.spaces[$k].color // "#cdd6f4") ]
          | @tsv
        ' "$CONFIG" 2>/dev/null
      )
    fi
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
