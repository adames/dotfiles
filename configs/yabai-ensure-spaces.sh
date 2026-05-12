#!/usr/bin/env bash
# Ensure every connected display has at least N (default 5) BSP spaces.
# Called by ~/.yabairc at startup AND by the `display_added` signal, so
# attaching a monitor mid-session also gets its space count topped up to N
# without re-login.
#
# Requires the yabai scripting addition. If SA is not loaded, `--create`
# prints "cannot create space due to an error with the scripting-addition"
# and we break the inner loop — no infinite spin, just a no-op until the
# user runs macos/yabai-sa-install.sh.

set -e

N="${1:-5}"

# Save original focused display; the loop moves focus per-display because
# `yabai -m space --create` operates on the currently focused display.
ORIG="$(yabai -m query --displays --display 2>/dev/null | jq '.index // 1')"

yabai -m query --displays | jq -r '.[].index' | while read -r disp; do
  yabai -m display --focus "$disp" 2>/dev/null || continue
  while [ "$(yabai -m query --spaces --display | jq 'length')" -lt "$N" ]; do
    if ! yabai -m space --create 2>/dev/null; then
      break
    fi
  done
done

yabai -m display --focus "$ORIG" 2>/dev/null || true
