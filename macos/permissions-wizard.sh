#!/usr/bin/env bash
# Walks the three TCC panes the Hyper-key stack needs.
#
# Probe-gated: lib/macos-tcc.sh asks each tool whether its TCC bit is on
# (via launchctl, systemextensionsctl, hs.accessibilityState, Karabiner-Core-
# Service-rev2 liveness — no Full Disk Access required). Panes whose toggles
# are all already on are skipped silently; panes with missing toggles list
# ONLY the missing items, not the full set.
#
# On the re-bootstrap case (everything already granted) the wizard never
# opens System Settings.
#
# Flags:
#   --force   ignore probes, open every pane with the full default list
#             (debugging / manual re-verification)

set -euo pipefail
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"
. "$DOTFILES_DIR/lib/macos-tcc.sh"

[[ "$(uname -s)" == "Darwin" ]] || { err "macOS only"; exit 1; }

FORCE=
[[ "${1:-}" == "--force" ]] && FORCE=1

open_pane() { open "x-apple.systempreferences:com.apple.preference.security?$1"; }

pause_for() {
  printf '\n%s\n\n' "$1"
  has_tty && read -r -p "  ↵  press enter when done... " _ || true
}

# Apps must appear in the TCC list before the user can flip a toggle.
# Launching them once is what registers them.
register() {
  step "registering apps in TCC lists"
  yabai --start-service       >/dev/null 2>&1 || true
  skhd  --start-service       >/dev/null 2>&1 || true
  open -ga Hammerspoon        2>/dev/null    || true
  open -ga Karabiner-Elements 2>/dev/null    || true
  sleep 2
  ok "registered"
}

# After a fresh grant, services need a re-kick before the toggle "takes".
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
  pgrep -x yabai >/dev/null && return 0
  has_tty || { warn "log out / log in required to apply spans-displays"; return 0; }
  section "Logout for spans-displays"
  printf '  Log out now? [y/N] '; read -r ans
  [[ "$ans" =~ ^[Yy] ]] && osascript -e 'tell application "System Events" to log out' || warn "remember to log out later"
}

# Per-pane missing-items reports. Each function echoes "    • Tool" lines
# for items still missing in that pane; empty output = all toggles already on.
missing_accessibility() {
  mac_yabai_status                  || echo "    • yabai"
  mac_skhd_status                   || echo "    • skhd"
  mac_hammerspoon_accessibility_ok  || echo "    • Hammerspoon"
  mac_karabiner_accessibility_ok    || echo "    • Karabiner-Elements"
}
missing_input_monitoring() {
  mac_karabiner_input_monitoring_ok \
    || printf '    • %s\n    • %s\n' "Karabiner-Elements" "Karabiner-DriverKit-VirtualHIDDevice"
}
missing_system_extensions() {
  mac_driverkit_activated_ok || echo "    • Karabiner-DriverKit-VirtualHIDDevice"
}

main() {
  banner "TCC permission walk-through" "probes first — only opens panes that need attention"

  # First-pass probe. Some probes (Hammerspoon AppleScript bridge, Karabiner
  # core service) need the app to be running. On re-bootstrap it usually is;
  # on first install it isn't. Probe → if anything missing, register → re-probe.
  local acc im se
  acc=$(missing_accessibility)
  im=$(missing_input_monitoring)
  se=$(missing_system_extensions)

  if [[ -n "$acc$im$se" || -n "$FORCE" ]]; then
    register
    # Re-probe now that everything's been kicked. A freshly-installed app
    # might pass on the second try where it failed on the first.
    acc=$(missing_accessibility)
    im=$(missing_input_monitoring)
    se=$(missing_system_extensions)
  fi

  local need_kick=

  if [[ -z "$acc" && -z "$FORCE" ]]; then
    ok "1/3 Accessibility — already granted"
  else
    section "1/3 · Accessibility"
    open_pane Privacy_Accessibility
    pause_for "  Toggle ON in Accessibility:
${acc:-    • yabai
    • skhd
    • Hammerspoon
    • Karabiner-Elements}"
    need_kick=1
  fi

  if [[ -z "$im" && -z "$FORCE" ]]; then
    ok "2/3 Input Monitoring — already granted"
  else
    section "2/3 · Input Monitoring"
    open_pane Privacy_ListenEvent
    pause_for "  Toggle ON in Input Monitoring:
${im:-    • Karabiner-Elements
    • Karabiner-DriverKit-VirtualHIDDevice}"
    need_kick=1
  fi

  if [[ -z "$se" && -z "$FORCE" ]]; then
    ok "3/3 System Extensions — already activated"
  else
    section "3/3 · System Extensions"
    open_pane Privacy_SystemServices
    pause_for "  Approve in Privacy & Security (banner near the top):
${se:-    • Karabiner-DriverKit-VirtualHIDDevice}"
    need_kick=1
  fi

  if [[ -n "$need_kick" ]]; then
    kick_services
  fi
  maybe_logout

  if [[ -z "$need_kick" ]]; then
    banner "All permissions already in place" "no panes opened — re-run with --force to re-verify"
  else
    banner "Done" "press Caps + 0 to verify the Hammerspoon overlay"
  fi
}

main "$@"
