#!/usr/bin/env bash
# One-shot teardown of everything this repo used to run. Called by
# macos/bootstrap.sh phase_apply; safe to run by hand.
#
# Teardown is migration code, not steady state. Every sweep here used to
# live in phase_apply and cost ~4s of brew forks on every run of a Mac
# that had been clean for months. Now the script stamps its GENERATION in
# ~/.local/state/dotfiles/retired and a machine already at that
# generation exits in milliseconds. Adding a sweep means bumping
# GENERATION, or the stamped Macs never see it.
#
# Every sweep is idempotent — a machine that never had the thing no-ops
# through — so a bump re-runs the whole file, not just the new part.
#
# Generation log (docs/architecture.md has the reasoning):
#   1  2026-09  Karabiner, yabai/skhd, AeroSpace, Raycast, sigil, mise,
#               the 2026-09 app + formula prune, ExpressVPN daemon
#   2  2026-09  Tor Browser — arrived undeclared alongside the Sikarugir
#               experiment; the cask's download URL 404s, which wedged
#               every `brew upgrade` on the machine
#   3  2026-09  Sikarugir + cabextract (the Wine experiment, done), UTM
#               (VMs are OrbStack's job), exercism (never picked up),
#               Reader.app (PDF Expert is the one PDF app), QuickMD
#               (glow is the one markdown viewer)

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

GENERATION=3
STAMP_DIR="$HOME/.local/state/dotfiles"
STAMP="$STAMP_DIR/retired"

stamped_generation() {
  local g
  g="$(cat "$STAMP" 2>/dev/null || true)"
  case "$g" in
    ''|*[!0-9]*) echo 0 ;;
    *)           echo "$g" ;;
  esac
}

if (( $(stamped_generation) >= GENERATION )); then
  exit 0
fi

step "one-shot teardown (generation $(stamped_generation) → $GENERATION)"

# Ask brew once, grep the answers. `brew list --cask` per app is ~250ms
# a probe; a single listing is the same fact for every probe below.
installed_casks="" installed_formulae=""
if have brew; then
  installed_casks="$(brew list --cask 2>/dev/null || true)"
  installed_formulae="$(brew list --formula 2>/dev/null || true)"
fi
has_cask()    { grep -qx "$1" <<<"$installed_casks"; }
has_formula() { grep -qx "$1" <<<"$installed_formulae"; }

# quit + uninstall a retired cask. `--zap` runs the cask's own zap stanza
# (prefs, caches, saved state) — only for apps that hold no documents.
retire_cask() {
  local cask="$1" app="$2" zap="${3:-}"
  if pgrep -x "$app" >/dev/null 2>&1; then
    step "stopping $app (retired)"
    osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
  fi
  has_cask "$cask" || return 0
  step "uninstalling $cask cask"
  # shellcheck disable=SC2086  # $zap is either empty or the one flag
  if brew uninstall --cask $zap "$cask" >/dev/null 2>&1; then
    ok "$cask uninstalled"
  else
    warn "$cask cask uninstall failed"
  fi
}

# ─── generation 1 · window managers, launcher, sigil ────────────────────────

# Stop legacy services BEFORE deleting their configs — otherwise
# Karabiner's grabber can wedge the input system on its way out.
if has_formula yabai || has_formula skhd; then
  brew_services="$(brew services list 2>/dev/null || true)"
  for svc in yabai skhd; do
    if grep -q "^$svc.*started" <<<"$brew_services"; then
      step "stopping legacy service: $svc"
      brew services stop "$svc" >/dev/null 2>&1 || true
    fi
  done
fi
if pgrep -x karabiner_grabber >/dev/null 2>&1 \
     || pgrep -x Karabiner-Elements >/dev/null 2>&1; then
  step "stopping Karabiner-Elements (replaced by Hyperkey)"
  osascript -e 'tell application "Karabiner-Elements" to quit' 2>/dev/null || true
  launchctl unload -w "$HOME/Library/LaunchAgents/org.pqrs."*.plist 2>/dev/null || true
  sleep 1
fi
rm -f  "$HOME/.skhdrc" "$HOME/.yabairc"
rm -rf "$HOME/.config/yabai" "$HOME/.config/skhd" "$HOME/.config/karabiner"

# AeroSpace: mouse + single screen won; tiling never earned its keep.
retire_cask aerospace AeroSpace
rm -rf "$HOME/.config/aerospace"

# Raycast: native Tahoe Spotlight is the launcher.
retire_cask raycast Raycast
rm -rf "$HOME/Library/Application Support/com.raycast.macos" \
       "$HOME/Library/Caches/com.raycast.macos" \
       "$HOME/Library/Application Support/com.raycast.shared"
defaults delete com.raycast.macos >/dev/null 2>&1 || true

# Sigil (the Swift workspace package) went with AeroSpace — its last
# survivor, the ws-cheatsheet HUD, was only reachable via a chord that
# lived in aerospace.toml. Sweep the clone, its symlinked binaries, and
# the rune generator that fed it. ws-doctor is this repo's own and stays.
rm -rf "$HOME/.config/workspace"
for bin in "$HOME/.local/bin/ws-"*; do
  [[ -e "$bin" || -L "$bin" ]] || continue
  [[ "${bin##*/}" == "ws-doctor" ]] || rm -f "$bin"
done
# The glob above never matched sigil's two plainest names.
rm -f "$HOME/.local/bin/ws" "$HOME/.local/bin/workspace"
python3 -m pip uninstall --quiet --yes rune 2>/dev/null || true

# Earlier eras: sketchybar / borders.
rm -rf "$HOME/.config/sketchybar" "$HOME/.config/borders"

# ─── generation 1 · the 2026-09 app prune ───────────────────────────────────
# Hand-installed bundles, not casks, so rm the .app. ~/Library is left
# alone for these on purpose: Firefox bookmarks and VS Code settings are
# yours to delete, not bootstrap's.
for app in Firefox "Visual Studio Code" ExpressVPN \
           Keynote "Pages Creator Studio" "MD Viewer" "Elmedia Player" \
           HandBrake; do
  [[ -d "/Applications/$app.app" ]] || continue
  step "removing /Applications/$app.app (retired)"
  osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
  if rm -rf "/Applications/$app.app" 2>/dev/null; then
    ok "$app removed"
  # A pkg-installed .app can be root-owned; retry under the sudo phase 1
  # cached. -n so a run without it warns instead of blocking on a prompt.
  elif sudo -n rm -rf "/Applications/$app.app" 2>/dev/null; then
    ok "$app removed (sudo)"
  else
    warn "$app.app could not be removed — delete it by hand"
  fi
done

# ExpressVPN ships a privileged daemon that outlives the app. Nothing
# else here installs a LaunchDaemon, so this stays a named special case.
daemon=/Library/LaunchDaemons/com.expressvpn.expressvpnd.plist
if [[ -f "$daemon" ]]; then
  step "unloading ExpressVPN privileged daemon"
  if sudo -n launchctl bootout system "$daemon" 2>/dev/null \
       && sudo -n rm -f "$daemon" 2>/dev/null; then
    ok "expressvpnd unloaded and removed"
  else
    warn "expressvpnd still installed — needs sudo: launchctl bootout system $daemon"
  fi
fi
# A VPN client holds no documents; its prefs, caches, logs and root-owned
# socket dir all outlive both the app and the daemon. Swept.
shopt -s nullglob
expressvpn_paths=(
  "$HOME/Library/Application Support/com.expressvpn.ExpressVPN"
  "$HOME/Library/Preferences/com.expressvpn.ExpressVPN.plist"
  "$HOME/Library/Caches/com.expressvpn.ExpressVPN"
  "$HOME/Library/HTTPStorages/com.expressvpn.ExpressVPN"
  "$HOME/Library/Logs/ExpressVPN"
  "$HOME/Library/Application Support/CrashReporter/ExpressVPN_"*.plist
)
shopt -u nullglob
for p in "${expressvpn_paths[@]}"; do
  [[ -e "$p" ]] || continue
  rm -rf "$p" 2>/dev/null || warn "could not remove $p"
done
sys="/Library/Application Support/com.expressvpn.ExpressVPN"
if [[ -d "$sys" ]] && ! sudo -n rm -rf "$sys" 2>/dev/null; then
  warn "ExpressVPN system dir remains — needs sudo: rm -rf \"$sys\""
fi

# ─── generation 1 · formulae that fell off the Brewfile ─────────────────────
# python@3.14 was pipx's orphan; direnv and ruff went with the authoring
# workflow; the rest were one-offs. Anything still depended on is kept
# and named, so the Brewfile gets a chance to adopt it instead.
for f in resvg pipx watchman ruby git-filter-repo python@3.14 direnv ruff; do
  has_formula "$f" || continue
  users="$(brew uses --installed "$f" 2>/dev/null | tr '\n' ' ')"
  if [[ -n "${users// /}" ]]; then
    note "keeping $f — still used by: ${users% }"
    continue
  fi
  step "uninstalling undeclared formula: $f"
  if brew uninstall --formula "$f" >/dev/null 2>&1; then
    ok "$f uninstalled"
  else
    warn "$f uninstall failed"
  fi
done

# mise: runtimes are brew's now (see the Brewfile). The install tree
# survives a brew uninstall — ~350 MB of runtimes plus the shims.
if has_formula mise; then
  step "uninstalling mise (macOS runtimes are brew's now)"
  if brew uninstall --formula mise >/dev/null 2>&1; then
    ok "mise uninstalled"
  else
    warn "mise uninstall failed"
  fi
fi
rm -rf "$HOME/.local/share/mise" "$HOME/.cache/mise" "$HOME/.config/mise"

# ─── generation 2 · Tor Browser ─────────────────────────────────────────────
# Never declared, never deliberately chosen: it showed up the same day as
# the Sikarugir experiment. The cask tracks upstream's release cadence
# and the dmg it pointed at 404'd, which took every `brew upgrade` down
# with it. Zapped: Tor Browser is amnesic by design and holds nothing
# worth keeping.
retire_cask tor-browser "Tor Browser" --zap

# ─── generation 3 · the Wine experiment, VMs, and a second PDF app ──────────
# Sikarugir wraps Windows apps in Wine; it was tried for a couple of weeks
# and never became a habit. Its 533 MB of engines and prefixes under
# ~/Library/Application Support is build cache, not documents — zapped.
# cabextract came in for it and nothing else depends on it.
retire_cask sikarugir "Sikarugir Creator" --zap

# UTM: OrbStack runs the Linux VMs now, and nothing else was ever booted
# in it. NOT zapped: ~/Library/Containers/com.utmapp.UTM holds the VM
# disk images (11 GB on m3). Those are yours to delete, not bootstrap's.
retire_cask utm UTM

# Formulae that fell off. Same keep-if-depended-on rule as generation 1.
for f in cabextract exercism; do
  has_formula "$f" || continue
  users="$(brew uses --installed "$f" 2>/dev/null | tr '\n' ' ')"
  if [[ -n "${users// /}" ]]; then
    note "keeping $f — still used by: ${users% }"
    continue
  fi
  step "uninstalling undeclared formula: $f"
  if brew uninstall --formula "$f" >/dev/null 2>&1; then
    ok "$f uninstalled"
  else
    warn "$f uninstall failed"
  fi
done
rm -rf "$HOME/.config/exercism"

# App Store tier. Reader (Liquid): a second PDF app next to PDF Expert.
# QuickMD: a second markdown viewer next to glow, never opened. Same
# rm-the-bundle shape as generation 1; purchases stay on the Apple ID.
# App Store bundles are root-owned, so this needs phase 1's cached sudo
# — run by hand, it warns and leaves the bundle for you.
for app in Reader QuickMD; do
  [[ -d "/Applications/$app.app" ]] || continue
  step "removing /Applications/$app.app (retired)"
  osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
  if rm -rf "/Applications/$app.app" 2>/dev/null \
       || sudo -n rm -rf "/Applications/$app.app" 2>/dev/null; then
    ok "$app removed"
  else
    warn "$app.app could not be removed — needs sudo: rm -rf \"/Applications/$app.app\""
  fi
done

# ─── stamp ──────────────────────────────────────────────────────────────────
mkdir -p "$STAMP_DIR"
printf '%s\n' "$GENERATION" > "$STAMP"
ok "teardown at generation $GENERATION"
