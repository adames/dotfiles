# icon-decode.sh — decode an iconSpec.codepoint escape to its literal glyph.
#
# spaces.json (v2) stores icons as ASCII-escaped codepoints — `\uXXXX` for
# BMP scalars or `\u{XXXXX}` for supplementary-plane scalars — never raw
# PUA bytes. Every consumer (tmux env, starship chip, sketchybar pill)
# renders the same glyph, regardless of how the file is edited or
# synced. This helper centralizes the unescape.
#
# Source it: `. "$HOME/.config/workspace/lib/icon-decode.sh"`
#
# Then: `glyph=$(ws_decode_icon "$ESC")` — prints the literal glyph, or
# empty string when input is empty / malformed.

ws_decode_icon() {
  local esc="${1-}"
  [[ -z "$esc" ]] && return 0
  if [[ "$esc" == "\\u{"* ]]; then
    local hex="${esc#\\u\{}"; hex="${hex%\}}"
    local padded
    padded=$(printf '%08x' "0x$hex" 2>/dev/null) || return 0
    printf "\\U${padded}"
  else
    local hex="${esc#\\u}"
    printf "\\u${hex}"
  fi
}
