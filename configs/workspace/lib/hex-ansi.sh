# hex-ansi.sh — parse "#RRGGBB" into decimal RGB components.
#
# Two callers want this:
#   • on-space-changed.sh pre-renders the truecolor workspace chip into
#     MACOS_SPACE_ANSI so prompt-time consumers can `printf $MACOS_SPACE_ANSI`
#     instead of re-parsing the hex on every redraw.
#   • workspace CLI `_swatch` renders a truecolor block for `workspace
#     status`.
#
# Source it: `. "$HOME/.config/workspace/lib/hex-ansi.sh"`
#
# Then: `read -r r g b < <(ws_hex_to_rgb "#RRGGBB")`
#
# Bad input (non-hex chars, wrong length) → silently emits "0 0 0". Callers
# are expected to have already validated the color (workspace CLI gates on
# the regex; on-space-changed.sh trusts the JSON written through that gate).

ws_hex_to_rgb() {
  local hex="${1#\#}"
  local r=$(( 16#${hex:0:2} ))
  local g=$(( 16#${hex:2:2} ))
  local b=$(( 16#${hex:4:2} ))
  printf '%d %d %d\n' "$r" "$g" "$b"
}
