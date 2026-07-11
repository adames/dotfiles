#!/usr/bin/env bash
# macos/macos-defaults.sh — curated macOS preferences for cross-Mac parity.
#
# Called from phase_apply. Idempotent: writes are compare-first (dw below),
# and the Dock/Finder restart only fires when a value actually changed.
# Safe to re-run unconditionally.
#
# Encoded values are the **live M3 baseline**, reconciled against the
# one-shot cross-Mac mirror prompt (completed and removed; see git
# history). Three settings differed from the doc's recollection — live
# wins:
#   - ApplePressAndHoldEnabled: live=false (vim posture), doc said true
#   - dock tilesize:            live=44,    doc said 42
#   - Finder view style:        live=Nlsv,  doc said clmv
# M1/Air reconciliation deferred until the Air can be live-read. Until
# then this gives the Air the same posture as the M3.
#
# Hard limits live in docs/macos-defaults.md.

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

section "macOS defaults"

# dw <domain> <key> <type> <value> — defaults write, but only when the
# value actually differs. Feeds CHANGED so the killall at the bottom only
# fires on a real change: an unconditional Dock/Finder restart flashes
# the desktop on every idempotent re-run. `defaults read` prints bools as
# 1/0, hence the normalization.
CHANGED=0
dw() {
  local domain="$1" key="$2" type="$3" value="$4" want cur
  case "$type" in
    -bool) [[ "$value" == "true" || "$value" == "1" ]] && want=1 || want=0 ;;
    *)     want="$value" ;;
  esac
  cur="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  [[ "$cur" == "$want" ]] && return 0
  defaults write "$domain" "$key" "$type" "$value"
  CHANGED=1
}

# ── Appearance ──────────────────────────────────────────────────────────────
step "appearance"
dw -g AppleInterfaceStyle -string Dark
dw -g AppleAccentColor -int -1     # graphite
# Force Dark live — `defaults write` alone takes full effect at next login.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' \
  2>/dev/null || true
ok "Dark mode + graphite accent"

# ── Keyboard ────────────────────────────────────────────────────────────────
step "keyboard"
dw -g KeyRepeat -int 2
dw -g InitialKeyRepeat -int 15
dw -g ApplePressAndHoldEnabled -bool false
dw -g AppleShowAllExtensions -bool true
ok "fast repeat (2/15), press-and-hold off, show all extensions"

# ── Dock ────────────────────────────────────────────────────────────────────
step "dock"
dw com.apple.dock autohide -bool true
dw com.apple.dock tilesize -int 44
dw com.apple.dock show-recents -bool false
dw com.apple.dock mru-spaces -bool false
dw com.apple.dock orientation -string bottom
ok "autohide, tilesize 44, no recents, no MRU spaces, bottom"

# ── Finder ──────────────────────────────────────────────────────────────────
step "finder"
dw com.apple.finder FXPreferredViewStyle -string Nlsv   # list view
dw com.apple.finder FXDefaultSearchScope -string SCcf   # current folder
ok "list view, search current folder"

# ── Trackpad ────────────────────────────────────────────────────────────────
step "trackpad"
dw com.apple.AppleMultitouchTrackpad Clicking -bool false
dw com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool false
dw -g com.apple.mouse.tapBehavior -int 0
ok "tap-to-click disabled (built-in + bluetooth + global)"

# Restart UI processes so changes show without logout. Killing Dock
# also reloads its prefs; same for Finder. Skipped when nothing moved —
# see the dw() note above.
if (( CHANGED )); then
  step "restarting Dock / Finder / SystemUIServer"
  killall Dock Finder SystemUIServer 2>/dev/null || true
  ok "macOS defaults applied"
else
  ok "macOS defaults already current — UI restart skipped"
fi
