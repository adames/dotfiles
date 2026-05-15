#!/usr/bin/env bash
# ws-launch-notes — open a quick-capture / notes surface.
#
# The keymap layer (skhdrc Caps+q) doesn't know which note tool the user
# prefers — that decision lives here, matching the launch-terminal.sh /
# launch-browser.sh pattern.
#
# Detection order (no hardcoded one app):
#   1. $WS_NOTES_APP env var — explicit override.
#        - If it contains '://' it's treated as a URL and passed to `open`.
#        - Otherwise it's treated as an app name and `open -a "$WS_NOTES_APP"`.
#   2. Raycast Notes — if /Applications/Raycast.app exists, open the
#      raycast-notes extension deeplink.
#   3. Apple Notes — always present on macOS, final fallback.
#
# Loud failure (osascript display notification) if even Apple Notes is
# unreachable, which would be very unusual.

set -u

app="${WS_NOTES_APP:-}"

if [[ -n "$app" ]]; then
  if [[ "$app" == *"://"* ]]; then
    open "$app" >/dev/null 2>&1 && exit 0
  else
    open -a "$app" >/dev/null 2>&1 && exit 0
  fi
  osascript -e "display notification \"WS_NOTES_APP set but '$app' didn't open\" with title \"ws-launch-notes\"" >/dev/null 2>&1 || true
  exit 1
fi

if [[ -d "/Applications/Raycast.app" || -d "$HOME/Applications/Raycast.app" ]]; then
  open 'raycast://extensions/raycast/raycast-notes/raycast-notes' >/dev/null 2>&1 && exit 0
fi

# Apple Notes ships with macOS. If `open -a` fails here, something is
# very wrong with the machine; surface it as a notification rather than
# silent.
if open -a "Notes" >/dev/null 2>&1; then
  exit 0
fi

osascript -e 'display notification "no notes app reachable (try setting $WS_NOTES_APP)" with title "ws-launch-notes"' >/dev/null 2>&1 || true
exit 1
