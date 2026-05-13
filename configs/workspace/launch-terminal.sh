#!/usr/bin/env bash
# ws-launch-terminal — focus a yabai-labeled workspace (if given) and
# spawn a new window of the user's preferred terminal.
#
# Usage:
#   ws-launch-terminal              # just open a new terminal here
#   ws-launch-terminal <label>      # focus yabai space <label> first, then open
#
# Terminal app detection order (no hardcoding any one app):
#   1. $WS_TERMINAL_APP env var  — explicit override
#   2. Ghostty, iTerm, Alacritty, kitty, WezTerm  — modern picks first
#   3. Terminal  — always present on macOS, final fallback
#
# Spawning uses AppleScript "click File→New Window" rather than
# `open -na`, because some terminals (kitty, Alacritty) interpret -n
# as "spawn a second app instance" rather than "open a new window" of
# the existing one. The menu-click pattern works uniformly.

set -u

# Optional space focus. yabai labels are stable identifiers
# ("home", "code") set by yabai-ensure-spaces.sh.
target="${1:-}"
if [[ -n "$target" ]] && command -v yabai >/dev/null 2>&1; then
  yabai -m space --focus "$target" 2>/dev/null || true
fi

# Detect terminal app.
app="${WS_TERMINAL_APP:-}"
if [[ -z "$app" ]]; then
  for candidate in Ghostty iTerm Alacritty kitty WezTerm Terminal; do
    if [[ -d "/Applications/$candidate.app" \
       || -d "$HOME/Applications/$candidate.app" ]]; then
      app="$candidate"
      break
    fi
  done
fi
if [[ -z "$app" ]]; then
  printf 'ws-launch-terminal: no terminal app found in /Applications/\n' >&2
  exit 1
fi

osascript >/dev/null 2>&1 \
  -e "tell application \"$app\" to activate" \
  -e "tell application \"System Events\" to tell process \"$app\" to click menu item \"New Window\" of menu \"File\" of menu bar 1" \
  || true
