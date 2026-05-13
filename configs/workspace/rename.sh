#!/usr/bin/env bash
# Rename flow for the focused workspace slot. Uses an AppleScript dialog
# so it works from skhd's no-tty daemon context.
#
# Thin wrapper: yabai-index lookup + AppleScript prompt → `workspace
# name`. All the atomic-write + cascade machinery lives in the CLI.

set -u

WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
WS_BIN="${WS_BIN:-$HOME/.local/bin/workspace}"

INDEX=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index' 2>/dev/null)
if [[ -z "${INDEX:-}" || "$INDEX" == "null" ]]; then
  osascript -e 'display notification "yabai unavailable" with title "Workspace rename"' >/dev/null 2>&1
  exit 1
fi

CURRENT=$(jq -r --arg k "$INDEX" '.spaces[$k].name // ""' "$WS_CONFIG" 2>/dev/null)

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

if [[ ! -x "$WS_BIN" ]]; then
  osascript -e 'display notification "workspace CLI missing — run ~/dotfiles/bootstrap.sh" with title "Workspace rename"' >/dev/null 2>&1
  exit 1
fi

exec "$WS_BIN" name "$INDEX" "$NEW"
