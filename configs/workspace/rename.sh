#!/usr/bin/env bash
# Fallback rename flow for when Hammerspoon is unavailable. Uses an
# AppleScript dialog so it works from skhd's no-tty daemon context.
# Hammerspoon's Workspace.rename() is preferred (skhd tries that first).

set -u

WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine current space index.
INDEX=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index' 2>/dev/null)
if [[ -z "${INDEX:-}" || "$INDEX" == "null" ]]; then
  osascript -e 'display notification "yabai unavailable" with title "Workspace rename"' >/dev/null 2>&1
  exit 1
fi

CURRENT=$(jq -r --arg k "$INDEX" '.spaces[$k].name // ""' "$WS_CONFIG" 2>/dev/null)

# Prompt via osascript (one-shot dialog; brittle AppleScript kept to a
# single line so it can't drift).
NEW=$(osascript <<OSA 2>/dev/null
try
  set answer to text returned of (display dialog "Rename workspace ${INDEX}" default answer "${CURRENT}" with title "Workspace" buttons {"Cancel","OK"} default button "OK")
  return answer
on error
  return ""
end try
OSA
)
[[ -z "$NEW" ]] && exit 0

# Atomic JSON rewrite.
mkdir -p "$(dirname "$WS_CONFIG")"
tmp=$(mktemp) || exit 1
jq --arg k "$INDEX" --arg name "$NEW" '
  .spaces[$k] = ((.spaces[$k] // {}) + {name: $name})
' "$WS_CONFIG" > "$tmp" && mv -f "$tmp" "$WS_CONFIG"

# Fire the standard cascade so tmux, env file, and (if it comes back) hs
# all see the new name immediately.
exec "$SELF_DIR/on-space-changed.sh"
