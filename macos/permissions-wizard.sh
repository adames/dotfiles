#!/usr/bin/env bash
# Walks the one TCC pane the Hyper-key + tiling stack needs.
#
# Post-Phase-6 surface (after the Karabiner → Hyperkey + yabai →
# AeroSpace cuts): the only TCC bit that matters is Accessibility, for
# Hyperkey + AeroSpace + ws-snap. No more Input Monitoring (Karabiner's
# kext-driven HID stream is gone), no more System Extensions pane (no
# DriverKit dependency). Probe-gated: lib/macos-tcc.sh asks each tool
# whether its grant is in place; an already-clean machine never opens
# System Settings.
#
# Flags:
#   --force   ignore probes, open the pane with the full default list
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
  open -ga AeroSpace  2>/dev/null || true
  open -ga Hyperkey   2>/dev/null || true
  # ws-snap moves floating windows via AX, so it needs Accessibility. A
  # no-op invocation forces TCC to enumerate it in the Accessibility list
  # so the user can flip the toggle. The "no focused window" error path
  # is harmless here.
  "$HOME/.local/bin/ws-snap" left >/dev/null 2>&1 || true
  sleep 2
  ok "registered"
}

# Post-Karabiner, no launchctl kickstart is needed — Hyperkey runs as a
# regular GUI app (no daemon split), and AeroSpace + ws-snap don't have
# launchctl labels to refresh. Kept as a no-op stub so the wizard's
# need_kick flag still has somewhere to land if a future tool needs it.
kick_services() {
  :
}

# Per-pane missing-items report. Echoes "    • Tool" lines for items still
# missing in Accessibility; empty output = everything's already granted.
missing_accessibility() {
  pgrep -x AeroSpace >/dev/null || echo "    • AeroSpace"
  pgrep -x Hyperkey  >/dev/null || echo "    • Hyperkey"
  # ws-snap doesn't have a fast launchctl probe; just always remind on
  # first-pass installs (the line is suppressed silently once all
  # other items pass, since TCC grants survive across reboots). When
  # bootstrap.sh already saw the topology build fail, swap the hint to
  # point at the follow-up block — the toggle is useless without the
  # binary, so "build the topology package first" would be misleading.
  if [[ ! -x "$HOME/.local/bin/ws-snap" ]]; then
    if [[ -n "${BOOTSTRAP_TOPOLOGY_FAILED:-}" ]]; then
      echo "    • ws-snap (topology build failed — see follow-up below)"
    else
      echo "    • ws-snap (build the topology package first)"
    fi
  fi
}

main() {
  section "TCC permission walk-through (probes first)"

  # First-pass probe. Accessibility is the only pane post-Karabiner.
  # Probe → if anything missing, register → re-probe.
  local acc
  acc=$(missing_accessibility)

  if [[ -n "$acc" || -n "$FORCE" ]]; then
    register
    # Re-probe now that registration has run. A freshly-installed app
    # might pass on the second try where it failed on the first.
    acc=$(missing_accessibility)
  fi

  local need_kick=

  if [[ -z "$acc" && -z "$FORCE" ]]; then
    ok "Accessibility — already granted"
  else
    section "Accessibility"
    open_pane Privacy_Accessibility
    pause_for "  Toggle ON in Accessibility:
${acc:-    • AeroSpace
    • Hyperkey
    • ws-snap}"
    need_kick=1
  fi

  if [[ -n "$need_kick" ]]; then
    kick_services
  fi

  # Surface anything bootstrap.sh deferred. Today only the topology build
  # uses this channel; if other phases ever need to bubble up follow-ups,
  # extend this block rather than scattering print logic across phases.
  #
  # Belt-and-braces with the flag: bootstrap.sh has been seen setting
  # the flag on a transient first-pass `launchctl bootstrap` EIO, then
  # the second-pass install.sh succeeds and binaries land. The flag
  # *should* be cleared by bootstrap's second pass on success, but we
  # also verify by checking the deployed binary. If ws-snap is present
  # and executable, the build clearly worked — suppress the error.
  if [[ -n "${BOOTSTRAP_TOPOLOGY_FAILED:-}" && ! -x "$HOME/.local/bin/ws-snap" ]]; then
    section "Follow-up required"
    err "topology Swift package did not build — ws-snap and the workspace daemons are missing"
    printf '\n  Most common cause: Command Line Tools went version-skewed\n'
    printf '  (PackageDescription was built against an older swift major).\n\n'
    printf '  Fix one of these, then re-run ./bootstrap.sh:\n\n'
    printf '    A. Reinstall CLT (fast; recommended):\n'
    printf '         sudo rm -rf /Library/Developer/CommandLineTools\n'
    printf '         xcode-select --install\n\n'
    printf '    B. Install full Xcode (larger; only needed if you build other Swift apps):\n'
    printf '         https://apps.apple.com/app/xcode/id497799835\n\n'
  fi

  if [[ -z "$need_kick" ]]; then
    ok "All permissions already in place"
    step "no panes opened — re-run with --force to re-verify"
  else
    ok "Done"
    step "press Caps + ; to verify the ws-cheatsheet HUD"
  fi
}

main "$@"
