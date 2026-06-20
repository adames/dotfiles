#!/usr/bin/env bash
# macos/macos-defaults.sh — curated macOS preferences for cross-Mac parity.
#
# Called from phase_apply. Idempotent: `defaults write` is set-not-toggle.
# Safe to re-run unconditionally.
#
# Encoded values are the **live M3 baseline** reconciled against
# POLISH_PROMPT.md (Goal D). Three settings differed from the doc's
# recollection — live wins:
#   - ApplePressAndHoldEnabled: live=false (vim posture), doc said true
#   - dock tilesize:            live=44,    doc said 42
#   - Finder view style:        live=Nlsv,  doc said clmv
# M1/Air reconciliation deferred until the Air can be live-read. Until
# then this gives the Air the same posture as the M3.
#
# Hard limits live in docs/macos-defaults.md.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

section "macOS defaults"

# ── Appearance ──────────────────────────────────────────────────────────────
step "appearance"
defaults write -g AppleInterfaceStyle Dark
defaults write -g AppleAccentColor -int -1     # graphite
# Force Dark live — `defaults write` alone takes full effect at next login.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' \
  2>/dev/null || true
ok "Dark mode + graphite accent"

# ── Keyboard ────────────────────────────────────────────────────────────────
step "keyboard"
defaults write -g KeyRepeat -int 2
defaults write -g InitialKeyRepeat -int 15
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write -g AppleShowAllExtensions -bool true
ok "fast repeat (2/15), press-and-hold off, show all extensions"

# ── Dock ────────────────────────────────────────────────────────────────────
step "dock"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 44
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock orientation -string bottom
ok "autohide, tilesize 44, no recents, no MRU spaces, bottom"

# ── Finder ──────────────────────────────────────────────────────────────────
step "finder"
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv   # list view
defaults write com.apple.finder FXDefaultSearchScope -string SCcf   # current folder
ok "list view, search current folder"

# ── Trackpad ────────────────────────────────────────────────────────────────
step "trackpad"
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool false
defaults write -g com.apple.mouse.tapBehavior -int 0
ok "tap-to-click disabled (built-in + bluetooth + global)"

# Restart UI processes so changes show without logout. Killing Dock
# also reloads its prefs; same for Finder.
step "restarting Dock / Finder / SystemUIServer"
killall Dock Finder SystemUIServer 2>/dev/null || true
ok "macOS defaults applied"
