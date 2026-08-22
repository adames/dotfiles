#!/usr/bin/env bash
# Walks the one TCC pane the Hyper-key stack needs.
#
# Post-Phase-6 surface (after the Karabiner → Hyperkey cut and the
# AeroSpace retirement): the only TCC bit that matters is Accessibility,
# for Hyperkey and Raycast (its global hotkey). No more Input
# Monitoring (Karabiner's
# kext-driven HID stream is gone), no more System Extensions pane (no
# DriverKit dependency). Probe-gated: lib/macos-tcc.sh asks each tool
# whether its grant is in place; an already-clean machine never opens
# System Settings.
#
# Flags:
#   --force   ignore probes, open the pane with the full default list
#             (debugging / manual re-verification)

set -euo pipefail
# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
  open -ga Hyperkey   2>/dev/null || true
  open -ga Raycast    2>/dev/null || true
  sleep 2
  ok "registered"
}

# Per-pane missing-items report. Echoes "    • Tool" lines for items still
# missing in Accessibility; empty output = everything's already granted.
# Both probe the actual TCC grant (auth_value == 2) — liveness is a
# false proxy: register() launches exactly these apps before the re-probe
# (running ≠ granted), and Raycast runs fine WITHOUT Accessibility anyway
# (it just loses its global hotkey). Client ids verified against the live
# system TCC.db. If neither TCC.db is readable (terminal lacks Full Disk
# Access), mac_tcc_granted returns non-zero and we err toward prompting,
# as the header promises.
missing_accessibility() {
  mac_tcc_granted kTCCServiceAccessibility 'com.knollsoft.Hyperkey' || echo "    • Hyperkey"
  mac_tcc_granted kTCCServiceAccessibility 'com.raycast.macos'    || echo "    • Raycast"
}

main() {
  section "TCC permission walk-through (probes first)"

  # First-pass probe. Accessibility is the only pane post-Karabiner.
  # Probe → if anything missing, register → re-probe.
  local acc
  acc=$(missing_accessibility)

  if [[ -n "$acc" || -n "$FORCE" ]]; then
    register
    # Re-probe now that registration has run — launching is what creates
    # the TCC rows, so an app whose grant survived a reinstall can pass
    # here where the first probe found no row at all.
    acc=$(missing_accessibility)
  fi

  # Post-Karabiner there's nothing to restart after a grant — Hyperkey is
  # a regular GUI app (no daemon split). The flag only records whether we
  # opened a pane.
  local opened_pane=

  if [[ -z "$acc" && -z "$FORCE" ]]; then
    ok "Accessibility — already granted"
  else
    section "Accessibility"
    open_pane Privacy_Accessibility
    pause_for "  Toggle ON in Accessibility:
${acc:-    • Hyperkey
    • Raycast}"
    opened_pane=1
  fi

  if [[ -z "$opened_pane" ]]; then
    ok "All permissions already in place"
    step "no panes opened — re-run with --force to re-verify"
  else
    ok "Done"
    step "tap Caps to verify it registers as Esc"
  fi
}

main "$@"
