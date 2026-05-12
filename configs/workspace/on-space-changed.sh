#!/usr/bin/env bash
# Refreshes ~/.cache/workspace/current.env from spaces.json + yabai state,
# pushes vars into tmux global env, asks Hammerspoon to render the overlay.
#
# Called from yabai signals (space_changed, display_changed), the rename
# flow, and skhd Meh+R (manual refresh). Idempotent. Silent on subsystem
# absence — system stays usable even if Hammerspoon or tmux is down.

set -u

WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
WS_CACHE_DIR="${WS_CACHE_DIR:-$HOME/.cache/workspace}"
WS_LOCK="$WS_CACHE_DIR/.lock"
WS_ENV="$WS_CACHE_DIR/current.env"

mkdir -p "$WS_CACHE_DIR"

# Serialize concurrent invocations (signal storm during display_added, or
# rename racing a space switch). Block — handler is fast.
exec 9>"$WS_LOCK"
flock 9

# Resolve current focused space + display from yabai. If yabai is down or
# scripting addition not loaded the query may fail; degrade quietly.
INDEX=0
DISPLAY=1
if command -v yabai >/dev/null 2>&1; then
  read -r INDEX DISPLAY < <(
    yabai -m query --spaces --space 2>/dev/null \
      | jq -r '"\(.index) \(.display)"' 2>/dev/null
  ) || true
fi
: "${INDEX:=0}"
: "${DISPLAY:=1}"

# Look up metadata. Missing entry → ws<N> + neutral text color.
NAME="ws${INDEX}"
COLOR="#cdd6f4"
ICON=""
if [[ -r "$WS_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  read -r NAME COLOR ICON < <(
    jq -r --arg k "$INDEX" '
      .spaces[$k] // {}
      | [
          (.name  // ("ws" + $k)),
          (.color // "#cdd6f4"),
          (.icon  // "")
        ] | @tsv
    ' "$WS_CONFIG" 2>/dev/null
  ) || true
fi

# Atomic env file: write tmp + rename. Readers (zsh precmd) never see a
# half-written file. Single-quote-escape values for safe `source`.
_qq() {
  local s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

tmp=$(mktemp "$WS_CACHE_DIR/.env.XXXXXX") || exit 1
{
  printf 'export MACOS_SPACE_INDEX=%s\n'   "$INDEX"
  printf 'export MACOS_SPACE_NAME=%s\n'    "$(_qq "$NAME")"
  printf 'export MACOS_SPACE_COLOR=%s\n'   "$(_qq "$COLOR")"
  printf 'export MACOS_SPACE_ICON=%s\n'    "$(_qq "$ICON")"
  printf 'export MACOS_SPACE_DISPLAY=%s\n' "$DISPLAY"
} > "$tmp"
mv -f "$tmp" "$WS_ENV"

# tmux global env. Default socket only — multi-socket setups are not in
# scope and the architectural review explicitly flagged it as
# over-engineering. Silent on "no server running".
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux set-environment -g MACOS_SPACE_INDEX   "$INDEX"
  tmux set-environment -g MACOS_SPACE_NAME    "$NAME"
  tmux set-environment -g MACOS_SPACE_COLOR   "$COLOR"
  tmux set-environment -g MACOS_SPACE_ICON    "$ICON"
  tmux set-environment -g MACOS_SPACE_DISPLAY "$DISPLAY"
  tmux refresh-client -S 2>/dev/null || true
fi

# Hammerspoon overlay. Display id is passed so the OSD lands on the screen
# containing the new focused space (not always the main display).
if command -v hs >/dev/null 2>&1; then
  hs -c "Workspace.show($INDEX, $DISPLAY)" >/dev/null 2>&1 || true
fi
