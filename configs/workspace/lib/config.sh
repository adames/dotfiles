#!/usr/bin/env bash
# Workspace system configuration loader
# Sources user configuration from ~/.config/workspace/config.env or uses defaults

# Default configuration - can be overridden by user
: "${WORKSPACE_BUNDLE_PREFIX:=com.user.workspace}"
: "${WORKSPACE_WINDOW_MANAGER:=yabai}"
: "${WORKSPACE_BAR:=ws-statusbar}"

# XDG-compliant paths
if [[ -n "$XDG_CONFIG_HOME" ]]; then
    WORKSPACE_CONFIG_DIR="${XDG_CONFIG_HOME}/workspace"
else
    WORKSPACE_CONFIG_DIR="$HOME/.config/workspace"
fi

if [[ -n "$XDG_CACHE_HOME" ]]; then
    WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME}/workspace"
else
    WORKSPACE_CACHE_DIR="$HOME/.cache/workspace"
fi

WORKSPACE_BIN_DIR="$HOME/.local/bin"

# LaunchAgent paths
WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# File names
WORKSPACE_SPACES_FILE="spaces.json"
WORKSPACE_TOPOLOGY_FILE="topology.json"
WORKSPACE_LAYOUT_ENV="layout.env"
WORKSPACE_CURRENT_ENV="current.env"

# Window manager binary paths
if [[ "$WORKSPACE_WINDOW_MANAGER" == "yabai" ]]; then
    WORKSPACE_WM_BIN="/opt/homebrew/bin/yabai"
elif [[ "$WORKSPACE_WINDOW_MANAGER" == "aerospace" ]]; then
    WORKSPACE_WM_BIN="/opt/homebrew/bin/aerospace"
else
    WORKSPACE_WM_BIN=""
fi

# Derived values
WORKSPACE_LOG_SUBSYSTEM="${WORKSPACE_BUNDLE_PREFIX}.topology"

# LaunchAgent labels
LAUNCHAGENT_TOPOLOGY="${WORKSPACE_BUNDLE_PREFIX}.topologyd"
LAUNCHAGENT_STATUSBAR="${WORKSPACE_BUNDLE_PREFIX}.statusbar"
LAUNCHAGENT_AUTOHIDE="${WORKSPACE_BUNDLE_PREFIX}.autohide"

# Load user overrides if present
if [[ -r "$WORKSPACE_CONFIG_DIR/config.env" ]]; then
    # shellcheck source=/dev/null
    source "$WORKSPACE_CONFIG_DIR/config.env"
fi

# Export all variables for child processes
export WORKSPACE_BUNDLE_PREFIX
export WORKSPACE_WINDOW_MANAGER
export WORKSPACE_BAR
export WORKSPACE_CONFIG_DIR
export WORKSPACE_CACHE_DIR
export WORKSPACE_BIN_DIR
export WORKSPACE_LAUNCH_AGENTS_DIR
export WORKSPACE_SPACES_FILE
export WORKSPACE_TOPOLOGY_FILE
export WORKSPACE_LAYOUT_ENV
export WORKSPACE_CURRENT_ENV
export WORKSPACE_WM_BIN
export WORKSPACE_LOG_SUBSYSTEM
