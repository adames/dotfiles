#!/usr/bin/env bash
# Walks the three TCC panes the Hyper-key stack needs.
# No probes, no polling — opens a pane, lists toggles, waits for ↵.

set -euo pipefail
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

[[ "$(uname -s)" == "Darwin" ]] || { err "macOS only"; exit 1; }

open_pane() { open "x-apple.systempreferences:com.apple.preference.security?$1"; }

pause_for() {
  printf '\n%s\n\n' "$1"
  has_tty && read -r -p "  ↵  press enter when done... " _ || true
}

# Apps must appear in the TCC list before the user can flip a toggle. Launching
# them once is what registers them — service start for headless, open -ga for GUI.
register() {
  step "registering apps in TCC lists"
  yabai --start-service       >/dev/null 2>&1 || true
  skhd  --start-service       >/dev/null 2>&1 || true
  open -ga Hammerspoon        2>/dev/null    || true
  open -ga Karabiner-Elements 2>/dev/null    || true
  sleep 2
  ok "registered"
}

# Karabiner's daemons need to be re-kicked after a fresh grant. Hammerspoon
# picks up changes via a normal reload.
kick_services() {
  step "kicking services"
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.daemon.karabiner_grabber"             2>/dev/null || true
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server"  2>/dev/null || true
  pgrep -x Hammerspoon >/dev/null && \
    osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null 2>&1
  ok "kicked"
}

# yabai needs a fresh login to pick up spans-displays. Offer to do it now.
maybe_logout() {
  [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" == "0" ]] || return 0
  pgrep -x yabai >/dev/null && return 0   # yabai already up — already logged in since the change
  has_tty || { warn "log out / log in required to apply spans-displays"; return 0; }
  section "Logout for spans-displays"
  printf '  Log out now? [y/N] '; read -r ans
  [[ "$ans" =~ ^[Yy] ]] && osascript -e 'tell application "System Events" to log out' || warn "remember to log out later"
}

main() {
  banner "TCC permission walk-through" "three panes — five minutes total"
  register

  section "1/3 · Accessibility"
  open_pane Privacy_Accessibility
  pause_for "  Toggle ON in Accessibility:
    • yabai
    • skhd
    • Hammerspoon
    • Karabiner-Elements"

  section "2/3 · Input Monitoring"
  open_pane Privacy_ListenEvent
  pause_for "  Toggle ON in Input Monitoring:
    • Karabiner-Elements
    • Karabiner-DriverKit-VirtualHIDDevice"

  section "3/3 · System Extensions"
  open_pane Privacy_SystemServices
  pause_for "  Approve in Privacy & Security (banner near the top):
    • Karabiner-DriverKit-VirtualHIDDevice"

  kick_services
  maybe_logout

  banner "Done" "press Caps + 0 to verify the Hammerspoon overlay"
}

main "$@"
