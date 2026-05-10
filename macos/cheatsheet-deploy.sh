#!/usr/bin/env bash
# macos/cheatsheet-deploy.sh — refresh ~/Desktop/Hyper-Keys.html on demand.
#
# Hammerspoon's init.lua already calls cheatsheet.dump_to_desktop() on every
# reload, so this script is mainly for re-rendering without restarting HS
# (e.g. after editing the sections table on a remote machine via git pull).

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "macOS-only"
  exit 1
fi

if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
  err "Hammerspoon is not running — launch it first (the desktop file is regenerated on every load)"
  exit 1
fi

log "regenerating ~/Desktop/Hyper-Keys.html via Hammerspoon"
osascript -e 'tell application "Hammerspoon" to execute lua code "require(\"cheatsheet\").dump_to_desktop(); return \"ok\""' \
  >/dev/null 2>&1
ls -la "$HOME/Desktop/Hyper-Keys.html"
