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
# Spawning talks directly to the app's AppleScript dictionary
# (`tell application "X" to make new window`). This avoids the
# System-Events menu-click pattern, which requires Accessibility
# permission for osascript (`-1719: not allowed assistive access`)
# and silently fails when permission isn't granted. Fallback to
# `open -na` if the app doesn't expose `make new window` (rare for
# terminals; common dictionaries cover it).

set -u

# Optional space focus. The arg can be any yabai space label (set
# manually via `yabai -m space N --label foo` if you want stable
# IDs across reboots) or just `<index>`.
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

# Ghostty special-case. Ghostty's AppleScript dictionary doesn't
# support `make new window` (returns -2710 / "Can't make class window")
# AND `tell application "Ghostty" to activate` creates a default window
# if none is currently visible — so the activate-then-make-window-then-
# fallback chain we use for iTerm/Terminal/Chrome would land you with
# TWO windows on Hyper+T when Ghostty has no visible window. Ghostty's
# architecture is one-window-per-process, so each `open -na` invocation
# reliably produces exactly one new window regardless of whether the
# app is already running. Use it directly.
if [[ "$app" == "Ghostty" ]]; then
  open -na "$app" >/dev/null 2>&1 || true
  exit 0
fi

# Other terminals: keep the activate + make-new-window chain with a
# pgrep gate to avoid the original double-window bug on cold start.
# -i (case-insensitive) so apps whose process name diverges from their
# Finder name still match when running.
if pgrep -ixq "$app" 2>/dev/null; then
  if ! osascript >/dev/null 2>&1 \
         -e "tell application \"$app\" to activate" \
         -e "tell application \"$app\" to make new window"; then
    # Dictionary missing `make new window` — fall back to `open -na`.
    open -na "$app" >/dev/null 2>&1 || true
  fi
else
  open -a "$app" >/dev/null 2>&1 || true
fi
