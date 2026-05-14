#!/usr/bin/env bash
# Stages every newly-created window on the user's currently focused
# space and gives it keyboard focus. Centers the window if (and only if)
# yabai/app rules already have it floating. Tile-vs-float is the app's
# decision, not this script's. Called from the yabai window_created
# signal (registered in ~/.yabairc as ws_stage_window).
#
# Three behaviours, each independently gated:
#   1. cross-space migration  — if born elsewhere, move to focused space.
#                               Always applied (tiled or floating).
#   2. center @ 50%           — only if window is already floating
#                               (yabairc app rules / subrole rules).
#                               Tiled windows take their natural BSP slot.
#   3. focus                  — always.
#
# Skips:
#   - non-AXWindow roles
#   - AXDialog / AXSystemDialog / AXSystemFloatingWindow / AXSheet
#     subroles (modal sheets, system overlays — leave attached/in-place).
#
# Silent on failure: a window may already be gone by the time we query
# (apps that flash a window for <100ms). Exit cleanly so the signal
# queue keeps draining.
#
# Non-goals:
#   - No burst guard: if an app restores N windows on launch, they all
#     migrate + focus in sequence. Cheap to add later if it bites.
#   - We do not toggle float ourselves. caps+shift+f is the user's
#     unfloat-to-commit chord on a staged floating window.

set -u

WID="${1:-${YABAI_WINDOW_ID:-}}"
[[ -z "$WID" ]] && exit 0

command -v yabai >/dev/null 2>&1 || exit 0
command -v jq    >/dev/null 2>&1 || exit 0

# Query the window. If it's already gone (quick-flash), exit silently.
info=$(yabai -m query --windows --window "$WID" 2>/dev/null) || exit 0
[[ -z "$info" ]] && exit 0

# Skip non-standard windows. AXWindow is the role for top-level NSWindows
# that count as "real" windows to the user. The subrole skips cover
# modal sheets and system overlays that shouldn't be relocated.
role=$(jq -r '.role     // empty' <<<"$info")
subrole=$(jq -r '.subrole // empty' <<<"$info")
[[ "$role" != "AXWindow" ]] && exit 0
case "$subrole" in
  AXDialog|AXSystemDialog|AXSystemFloatingWindow|AXSheet) exit 0 ;;
esac

is_floating=$(jq -r '."is-floating"' <<<"$info")
src_space=$(jq -r '.space' <<<"$info")

# Resolve the user's currently focused space. Done at signal time, not
# registration time, so we always pull to wherever the user is *now*.
dst_space=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
[[ -z "$dst_space" ]] && exit 0

# 1. Migrate to focused space if the window was born elsewhere.
if [[ "$src_space" != "$dst_space" ]]; then
  yabai -m window "$WID" --space "$dst_space" 2>/dev/null || exit 0
fi

# 2. Center only when the app/yabai rules have it floating. Tiled
#    windows are left to yabai's BSP placement.
if [[ "$is_floating" == "true" ]]; then
  yabai -m window "$WID" --grid 4:4:1:1:2:2 2>/dev/null || true
fi

# 3. Focus (also raises in yabai).
yabai -m window "$WID" --focus 2>/dev/null || true
