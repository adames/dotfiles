#!/usr/bin/env bash
# resolve-config.sh — source me to export WS_CONFIG to the effective
# per-host spaces.json. Falls through to the shared file if no host
# override exists. An explicit WS_CONFIG in the parent environment
# always wins.
#
# Resolution order:
#   1. WS_CONFIG already set (caller override)
#   2. ~/.config/workspace/spaces.<short-hostname>.json
#   3. ~/.config/workspace/spaces.json (shared default)
#
# Use case: the 2-Mac topology. Both machines symlink/sync
# ~/.config/workspace/spaces.json as the shared default. Either machine
# can opt into a divergent layout by creating spaces.<hostname>.json
# (via `workspace host init`). All cascade consumers — the workspace
# CLI, on-space-changed.sh, paint-all.sh — pick up the override
# automatically because they all source this file.

set -u

if [[ -z "${WS_CONFIG:-}" ]]; then
  _ws_host=$(hostname -s 2>/dev/null || echo unknown)
  _ws_hostfile="$HOME/.config/workspace/spaces.${_ws_host}.json"
  if [[ -r "$_ws_hostfile" ]]; then
    export WS_CONFIG="$_ws_hostfile"
    export WS_HOST_OVERLAY="$_ws_host"
  else
    export WS_CONFIG="$HOME/.config/workspace/spaces.json"
    export WS_HOST_OVERLAY=""
  fi
  unset _ws_host _ws_hostfile
fi
