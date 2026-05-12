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
WS_LOCK_DIR="$WS_CACHE_DIR/.lock.d"
WS_ENV="$WS_CACHE_DIR/current.env"

mkdir -p "$WS_CACHE_DIR"

# Serialize concurrent invocations (signal storm during display_added, or
# rename racing a space switch). mkdir is atomic on POSIX — used here
# because macOS ships no flock(1). Bounded retry: ~1.5s ceiling, then
# proceed unlocked (handler is idempotent — the worst case is a torn
# read of a half-written current.env, which the next signal corrects).
_acquired=0
for _ in $(seq 1 30); do
  if mkdir "$WS_LOCK_DIR" 2>/dev/null; then _acquired=1; break; fi
  sleep 0.05
done
if (( _acquired )); then
  trap 'rmdir "$WS_LOCK_DIR" 2>/dev/null || true' EXIT
fi

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
# IFS=$'\t' so workspace names containing spaces (e.g. "infra prod") stay
# intact — jq emits TSV.
NAME="ws${INDEX}"
COLOR="#cdd6f4"
ICON=""
if [[ -r "$WS_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  IFS=$'\t' read -r NAME COLOR ICON < <(
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
