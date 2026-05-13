#!/usr/bin/env bash
# ws-launch-browser — open a new browser window in whatever browser
# is available. Companion to ws-launch-terminal; same shape, no
# hardcoded app name.
#
# Usage:
#   ws-launch-browser              # open a new browser window
#
# Browser app detection order (no hardcoding any one app):
#   1. $WS_BROWSER_APP env var  — explicit override
#   2. Brave Browser → Arc → Vivaldi → Chrome → Edge → Firefox
#   3. Safari  — always present on macOS, final fallback
#
# Same two-window-on-cold-start gotcha as launch-terminal.sh: when the
# app isn't running, `tell app to activate` launches it (one default
# window) and a subsequent `make new window` would add a second. The
# pgrep gate below splits the two cases so a press always opens
# exactly one window.

set -u

app="${WS_BROWSER_APP:-}"
if [[ -z "$app" ]]; then
  for candidate in "Brave Browser" "Arc" "Vivaldi" "Google Chrome" "Microsoft Edge" "Firefox" "Safari"; do
    if [[ -d "/Applications/$candidate.app" \
       || -d "$HOME/Applications/$candidate.app" ]]; then
      app="$candidate"
      break
    fi
  done
fi
if [[ -z "$app" ]]; then
  printf 'ws-launch-browser: no browser app found in /Applications/\n' >&2
  exit 1
fi

if pgrep -xq "$app" 2>/dev/null; then
  if ! osascript >/dev/null 2>&1 \
         -e "tell application \"$app\" to activate" \
         -e "tell application \"$app\" to make new window"; then
    # Dictionary missing `make new window` — fall back to `open -na`.
    open -na "$app" >/dev/null 2>&1 || true
  fi
else
  open -a "$app" >/dev/null 2>&1 || true
fi
