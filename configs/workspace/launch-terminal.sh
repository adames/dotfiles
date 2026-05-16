#!/usr/bin/env bash
# ws-launch-terminal — focus a yabai-labeled workspace (if given) and
# spawn a new window of the user's preferred terminal.
#
# Usage:
#   ws-launch-terminal              # just open a new terminal here
#   ws-launch-terminal <label>      # focus yabai space <label> first, then open
#
# Terminal app detection order (no hardcoding any one app):
#   1. $WS_TERMINAL_APP env var  — explicit override
#   2. Ghostty, iTerm, Alacritty, kitty, WezTerm  — modern picks first
#   3. Terminal  — always present on macOS, final fallback
#
# Spawning talks directly to the app's AppleScript dictionary
# (`tell application "X" to make new window`) where possible —
# avoids the System-Events keystroke pattern, which needs
# Accessibility permission for osascript (-1719) and silently
# fails when permission isn't granted. Ghostty is the exception:
# its dictionary doesn't expose `make new window` and its macOS
# CLI rejects the `+new-window` action, so the Ghostty branch
# below uses System Events. Grant skhd Accessibility for that
# path to work (System Settings → Privacy & Security →
# Accessibility).

set -u

# Optional space focus. The arg can be any yabai space label (set
# manually via `yabai -m space N --label foo` if you want stable
# IDs across reboots) or just `<index>`.
target="${1:-}"
if [[ -n "$target" ]] && command -v yabai >/dev/null 2>&1; then
  yabai -m space --focus "$target" 2>/dev/null || true
fi

# Detect terminal app.
app="${WS_TERMINAL_APP:-}"
if [[ -z "$app" ]]; then
  for candidate in Ghostty iTerm Alacritty kitty WezTerm Terminal; do
    if [[ -d "/Applications/$candidate.app" \
       || -d "$HOME/Applications/$candidate.app" ]]; then
      app="$candidate"
      break
    fi
  done
fi
if [[ -z "$app" ]]; then
  printf 'ws-launch-terminal: no terminal app found in /Applications/\n' >&2
  exit 1
fi

# Ghostty special-case (1.3.x on macOS).
#   - `open -na Ghostty` spawns a separate .app instance which gets
#     its own Dock entry, then exits via single-instance handoff
#     WITHOUT producing a new window. Result: extra Dock icon, no
#     window. So drop the -n.
#   - `+new-window` CLI action is rejected on macOS
#     ("not supported on this platform").
#   - AppleScript `make new window` returns -2710 (verb not implemented).
# Cold start: `open -a` launches Ghostty (single Dock icon). Warm
# path: activate the running instance and click File > New Window.
#
# Why menu click instead of keystroke "n" using command down:
#   Keystroke injection goes through skhd's CGEvent tap. When Caps is
#   held (e.g. user holds Caps+T), the injected Cmd+N gets OR'd with
#   the live Hyper modifier state, turning it into Hyper+N which skhd
#   intercepts as ws-focus-next. Clicking a menu item is an AX API
#   call — it bypasses skhd entirely regardless of held modifiers.
#   ws-doctor lints for this collision class.
# Requires Accessibility permission for skhd / osascript.
if [[ "$app" == "Ghostty" ]]; then
  if pgrep -ixq ghostty 2>/dev/null; then
    osascript >/dev/null 2>&1 \
      -e 'tell application "Ghostty" to activate' \
      -e 'delay 0.1' \
      -e 'tell application "System Events" to tell process "Ghostty" to click menu item "New Window" of menu "File" of menu bar 1' \
      || true
  else
    open -a "$app" >/dev/null 2>&1 || true
  fi
  exit 0
fi

# Other terminals: keep the activate + make-new-window chain with a
# pgrep gate to avoid the original double-window bug on cold start.
# -i (case-insensitive) so apps whose process name diverges from their
# Finder name still match when running.
if pgrep -ixq "$app" 2>/dev/null; then
  if ! osascript >/dev/null 2>&1 \
         -e "tell application \"$app\" to activate" \
         -e "tell application \"$app\" to make new window"; then
    # Dictionary missing `make new window` — fall back to `open -na`.
    open -na "$app" >/dev/null 2>&1 || true
  fi
else
  open -a "$app" >/dev/null 2>&1 || true
fi
