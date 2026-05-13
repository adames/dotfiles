#!/usr/bin/env bash
# Refreshes ~/.cache/workspace/current.env from spaces.json + yabai state,
# pushes vars into tmux global env, repaints the JankyBorders active
# colour, and triggers the SketchyBar workspace-pill repaint.
#
# Called from yabai signals (space_changed, display_changed), the rename
# flow, and skhd manual-refresh. Idempotent. Silent on subsystem absence
# — system stays usable even if tmux or borders is down.

set -u

# Per-host overlay: source resolves WS_CONFIG to spaces.<hostname>.json
# when present, else falls back to the shared spaces.json. Caller's
# pre-set WS_CONFIG always wins.
if [[ -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/resolve-config.sh"
fi

# Shared codepoint-unescape + hex-to-RGB helpers. The fallback stubs let
# this script keep working when the lib/ shipment hasn't landed yet (very
# early in a fresh bootstrap, before workspace/install.sh runs).
if [[ -r "$HOME/.config/workspace/lib/icon-decode.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/icon-decode.sh"
else
  ws_decode_icon() { :; }
fi
if [[ -r "$HOME/.config/workspace/lib/hex-ansi.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/hex-ansi.sh"
else
  ws_hex_to_rgb() { printf '0 0 0\n'; }
fi

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

# Look up metadata from spaces.json (v2). Missing entry → ws<N> + neutral
# text color.
#
# Why one jq call per field: jq's @tsv format escapes backslashes for
# safe TSV transport (so `` arrives as `\\uf120` in shell), which
# breaks our `${ICON_ESCAPED#\\u}` strip + printf unescape sequence.
# Per-field jq calls cost ~3ms total — invisible at space-switch time —
# and side-step the @tsv escape entirely.
#
# v2 stores the icon as a typed iconSpec.codepoint (ASCII-escaped:
# "\uXXXX" for BMP, "\u{XXXXX}" for supplementary planes) — never raw
# PUA bytes in JSON. We unescape to a literal glyph here so downstream
# consumers (tmux / starship / sketchybar) read the same UTF-8 sequence
# regardless of how the icon is persisted.
NAME="ws${INDEX}"
COLOR="#cdd6f4"
ICON=""
if [[ -r "$WS_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  _jq() { jq -r --arg k "$INDEX" "$1" "$WS_CONFIG" 2>/dev/null; }
  NAME=$(_jq '.spaces[$k].name // ("ws" + $k)')
  COLOR=$(_jq '.spaces[$k].color // "#cdd6f4"')
  ICON_ESCAPED=$(_jq '.spaces[$k].iconSpec.codepoint // ""')

  ICON=$(ws_decode_icon "${ICON_ESCAPED:-}")
fi

# Atomic env file: write tmp + rename. Readers (zsh precmd) never see a
# half-written file. Single-quote-escape values for safe `source`.
_qq() {
  local s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

# Pre-render the workspace chip's truecolor ANSI here, so prompt-time
# consumers (starship custom.workspace) just `printf $MACOS_SPACE_ANSI`
# instead of re-parsing the hex on every prompt. Hex parse is cheap
# (~1ms) but multiplied by every prompt redraw it adds up; computing it
# once per space switch keeps the prompt path purely a printf.
read -r r g b < <(ws_hex_to_rgb "$COLOR")
ANSI=$(printf '\033[1;38;2;24;24;37;48;2;%d;%d;%dm %s  %s \033[0;38;2;%d;%d;%dm\033[0m' \
  "$r" "$g" "$b" "$ICON" "$NAME" "$r" "$g" "$b")

tmp=$(mktemp "$WS_CACHE_DIR/.env.XXXXXX") || exit 1
{
  printf 'export MACOS_SPACE_INDEX=%s\n'   "$INDEX"
  printf 'export MACOS_SPACE_NAME=%s\n'    "$(_qq "$NAME")"
  printf 'export MACOS_SPACE_COLOR=%s\n'   "$(_qq "$COLOR")"
  printf 'export MACOS_SPACE_ICON=%s\n'    "$(_qq "$ICON")"
  printf 'export MACOS_SPACE_DISPLAY=%s\n' "$DISPLAY"
  printf 'export MACOS_SPACE_ANSI=%s\n'    "$(_qq "$ANSI")"
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

# Note: the yabai space LABEL is intentionally NOT updated here. Labels
# are the stable slot *identity* (core / forge / codex / …) set once by
# yabai-ensure-spaces.sh; the JSON NAME is the mutable display string.
# Mirroring rename → label would break reconcile-displays.sh, which uses
# the default labels to address slots. Renames live in tmux/starship/
# borders only.

# JankyBorders: paint the active-window border in the slot's colour.
# Borders takes 0xAARRGGBB; strip the leading '#' from COLOR. Daemon
# may not be running yet (e.g., fresh boot before yabairc launched it)
# — silent on absence.
if command -v borders >/dev/null 2>&1 && pgrep -x borders >/dev/null 2>&1; then
  borders active_color="0xff${COLOR#\#}" 2>/dev/null || true
fi

# SketchyBar workspace pills. Fired AFTER current.env + tmux env + borders
# are committed so every pill plugin reads the same state. The trigger is
# a custom event registered in configs/sketchybar/sketchybarrc; a single
# hidden `workspace.paint` sentinel item subscribes to it and runs
# plugins/paint-all.sh, which emits one batched --set transaction for
# every pill (no per-pill repaint stagger). Silent on subsystem absence
# (e.g., fresh boot before brew services kicks in).
if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --trigger workspace_changed >/dev/null 2>&1 || true
fi
