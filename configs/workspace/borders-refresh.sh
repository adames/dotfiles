#!/usr/bin/env bash
# Re-assert JankyBorders' active_color from the cached current.env.
#
# Wired to yabai's window_focused signal (see ~/dotfiles/configs/yabairc)
# so the per-space identity color survives:
#   • new windows appearing in the focused space
#   • borders daemon restarts (state resets to its bordersrc bootstrap default)
#   • any other path that briefly drops state between space_changed events
#
# Identical write semantics as on-space-changed.sh:146-148 — call
# `borders active_color="0xff${COLOR#\#}"` with the workspace's #RRGGBB.
# Idempotent + silent: no-op if either the cache or the daemon is missing.

set -u

CACHE="${WS_CACHE_DIR:-$HOME/.cache/workspace}/current.env"
[[ -r "$CACHE" ]] || exit 0

command -v borders >/dev/null 2>&1 || exit 0
pgrep -x borders >/dev/null 2>&1 || exit 0

# shellcheck source=/dev/null
source "$CACHE" 2>/dev/null || exit 0
[[ -n "${MACOS_SPACE_COLOR:-}" ]] || exit 0

borders active_color="0xff${MACOS_SPACE_COLOR#\#}" >/dev/null 2>&1 || true
