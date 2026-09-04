#!/usr/bin/env bash
# macos/macos-defaults.sh — curated macOS preferences for cross-Mac parity.
#
# Called from phase_apply. Idempotent: writes are compare-first (dw below),
# and the Dock/Finder restart only fires when a value actually changed.
# Safe to re-run unconditionally.
#
# Encoded values are the **live M3 baseline**. Three settings differed
# from an earlier recollection — live wins:
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

# ── Spotlight ───────────────────────────────────────────────────────────────
# Cmd+Space got switched off when Raycast took over as launcher; retiring
# Raycast left it off, so Spotlight had no hotkey at all. 64 = Spotlight
# search (Cmd+Space), 65 = Finder search window (Cmd+Opt+Space). These live
# in a nested dict, so dw() can't touch them — compare-first by hand.
step "spotlight hotkeys"
SHK_CHANGED=0
shk() {  # shk <id> <modifier-mask> — enable a Space-key symbolic hotkey
  local id="$1" mask="$2" cur
  cur="$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:$id:enabled" \
         "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null || true)"
  [[ "$cur" == "true" ]] && return 0
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" "
    <dict><key>enabled</key><true/><key>value</key><dict>
    <key>type</key><string>standard</string>
    <key>parameters</key><array>
      <integer>65535</integer><integer>49</integer><integer>$mask</integer>
    </array></dict></dict>"
  SHK_CHANGED=1
}
shk 64 1048576   # Cmd+Space       — Spotlight search
shk 65 1572864   # Cmd+Opt+Space   — Finder search window
if (( SHK_CHANGED )); then
  # Without this the new binding only takes effect at next login.
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u \
    2>/dev/null || true
  ok "Cmd+Space -> Spotlight, Cmd+Opt+Space -> Finder search"
else
  ok "Spotlight hotkeys already bound"
fi

# Tahoe's Spotlight pane splits results into (a) apps/files/folders and the
# calculator, which are always on and NOT listed here, and (b) this opt-in
# list of app-content sources. We want a launcher, not a second Mail search
# box: keep only on-device related content and Dictionary lookups. Notably
# dropped — System.menuItems (frontmost app's menu commands) and
# System.iphoneApps (iPhone Mirroring), both "search inside an app".
# Hidden File Types stays empty so nothing on disk is suppressed.
step "spotlight search results"
SPOT_RULES=(Custom.relatedContents com.apple.Dictionary)
cur_rules="$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null | \
             tr -d ' \n"(),' || true)"
want_rules="$(printf '%s' "${SPOT_RULES[*]}" | tr -d ' ')"
if [[ "$cur_rules" != "$want_rules" ]]; then
  defaults write com.apple.Spotlight EnabledPreferenceRules -array "${SPOT_RULES[@]}"
  defaults write com.apple.Spotlight DisabledUTTypes -array
  killall Spotlight 2>/dev/null || true
  ok "app-content sources trimmed to related content + Dictionary"
else
  ok "Spotlight search results already current"
fi

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
