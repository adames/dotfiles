#!/usr/bin/env bash
# Window Manager abstraction layer
# Provides unified interface for yabai, aerospace, and other window managers
# Sources config.sh for WORKSPACE_WINDOW_MANAGER and WORKSPACE_WM_BIN

# Ensure config is loaded
if [[ -z "${WORKSPACE_WINDOW_MANAGER:-}" ]]; then
    if [[ -r "$HOME/.config/workspace/lib/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.config/workspace/lib/config.sh"
    else
        WORKSPACE_WINDOW_MANAGER="${WORKSPACE_WINDOW_MANAGER:-yabai}"
        WORKSPACE_WM_BIN="${WORKSPACE_WM_BIN:-/opt/homebrew/bin/yabai}"
    fi
fi

# Check if window manager binary exists
_wm_available() {
    [[ -x "$WORKSPACE_WM_BIN" ]]
}

# Run window manager command with error handling
_wm_run() {
    if ! _wm_available; then
        printf 'window-manager: %s not available at %s\n' "$WORKSPACE_WINDOW_MANAGER" "$WORKSPACE_WM_BIN" >&2
        return 1
    fi
    "$WORKSPACE_WM_BIN" "$@"
}

# Get the focused space index (1-based)
# Returns: space index or empty string on error
wm_focused_space() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m query --spaces --space 2>/dev/null | jq -r '.index // empty'
            ;;
        aerospace)
            # TODO: Implement aerospace support
            printf 'aerospace support not yet implemented\n' >&2
            return 1
            ;;
        *)
            printf 'unknown window manager: %s\n' "$WORKSPACE_WINDOW_MANAGER" >&2
            return 1
            ;;
    esac
}

# Get total number of spaces
# Returns: count or 0 on error
wm_space_count() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m query --spaces 2>/dev/null | jq 'length'
            ;;
        aerospace)
            # TODO: Implement aerospace support
            printf '0'
            ;;
        *)
            printf '0'
            ;;
    esac
}

# Focus a space by index
# Args: $1 = space index (1-based)
wm_focus_space() {
    local index="$1"
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m space --focus "$index" 2>/dev/null
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Send focused window to a space
# Args: $1 = space index (1-based), $2 = follow ("true" to follow window)
wm_send_window() {
    local index="$1"
    local follow="${2:-false}"
    local window_id
    
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            if [[ "$follow" == "true" ]]; then
                window_id=$(wm_focused_window)
            fi
            _wm_run -m window --space "$index" 2>/dev/null
            if [[ "$follow" == "true" && -n "$window_id" ]]; then
                wm_focus_window "$window_id"
            fi
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Create a new space
# Returns: new space index or empty on error
wm_create_space() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m space --create 2>/dev/null
            wm_space_count
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Destroy a space by index
# Args: $1 = space index (1-based)
wm_destroy_space() {
    local index="$1"
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m space "$index" --destroy 2>/dev/null
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the focused window ID
# Returns: window ID or empty string
wm_focused_window() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m query --windows --window 2>/dev/null | jq -r '.id // empty'
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Focus a window by ID
# Args: $1 = window ID
wm_focus_window() {
    local id="$1"
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m window --focus "$id" 2>/dev/null
            ;;
        aerospace)
            # TODO: Implement aerospace support
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get display information (for topology)
# Returns: JSON array of displays
wm_query_displays() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m query --displays 2>/dev/null
            ;;
        aerospace)
            # TODO: Implement aerospace support
            printf '[]\n'
            ;;
        *)
            printf '[]\n'
            ;;
    esac
}

# Get space information (for topology)
# Returns: JSON array of spaces
wm_query_spaces() {
    case "$WORKSPACE_WINDOW_MANAGER" in
        yabai)
            _wm_run -m query --spaces 2>/dev/null
            ;;
        aerospace)
            # TODO: Implement aerospace support
            printf '[]\n'
            ;;
        *)
            printf '[]\n'
            ;;
    esac
}

# Export functions for use by other scripts
export -f _wm_available
export -f _wm_run
export -f wm_focused_space
export -f wm_space_count
export -f wm_focus_space
export -f wm_send_window
export -f wm_create_space
export -f wm_destroy_space
export -f wm_focused_window
export -f wm_focus_window
export -f wm_query_displays
export -f wm_query_spaces
