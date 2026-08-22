#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture + migration history: docs/architecture.md.

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 1 · sudo ─────────────────────────────────────────────────────────
phase_sudo() {
  section "Phase 1/4 · sudo"
  if ! has_tty; then
    warn "no TTY — cask installs and Accessibility prompts will be skipped"
    return 0
  fi
  step "caching sudo (one prompt for the run)"
  sudo -v
  # Keepalive — refresh every 50s so long shell-outs don't re-prompt.
  ( while sudo -nv 2>/dev/null; do
      sleep 50
      kill -0 "$$" 2>/dev/null || exit
    done ) &
  # `|| true` so a dead keepalive doesn't overwrite the script's exit
  # status with the kill's 1. (On the success path the trap never fires —
  # phase_wizard exec's away — and the keepalive self-terminates via its
  # kill -0 check.)
  trap 'kill '"$!"' 2>/dev/null || true' EXIT
  ok "sudo cached"
}

# ─── phase 2 · packages ─────────────────────────────────────────────────────
phase_packages() {
  section "Phase 2/4 · packages"

  ensure_xcode_clt

  if ! have brew; then
    step "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    ok "Homebrew installed"
  fi

  local brewfile="$DOTFILES_DIR/macos/Brewfile"
  local brewfile_local="$DOTFILES_DIR/macos/Brewfile.local"

  # Brew Bundle no longer supports type flags (`--formula`, `--cask`) on
  # install. Restore the full Brewfile when interactive; otherwise ask Bundle
  # to skip every declared cask so headless runs don't wedge on sudo prompts.
  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing macos/Brewfile"
    if brew bundle install --file="$brewfile" --no-upgrade 2>&1 | sed 's/^/    /'; then
      ok "Brewfile"
    else
      warn "macos/Brewfile install had failures"
    fi
  else
    local cask_skip
    cask_skip="$(brewfile_casks "$brewfile")"
    step "installing formulae from macos/Brewfile (casks skipped)"
    if HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" \
         brew bundle install --file="$brewfile" --no-upgrade 2>&1 | sed 's/^/    /'; then
      ok "formulae"
    else
      warn "macos/Brewfile formula install had failures"
    fi
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
  fi

  # Per-Mac heavy apps (orbstack on the M3; the Air has no Brewfile.local).
  if [[ -f "$brewfile_local" ]]; then
    step "installing macos/Brewfile.local (this-machine apps)"
    if brew bundle install --file="$brewfile_local" --no-upgrade 2>&1 | sed 's/^/    /'; then
      ok "Brewfile.local"
    else
      warn "macos/Brewfile.local install had failures"
    fi
  fi

  # Strip Gatekeeper quarantine so scripted `open -a` works pre-launch.
  for app in /Applications/Hyperkey.app /Applications/Helium.app; do
    [[ -d "$app" ]] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  done

  seed_hyperkey_defaults

  # Devin is required on every Mac. No cask exists, so brew can't
  # own it — the app self-updates; bootstrap just refuses to stay silent
  # when it's missing.
  if [[ ! -d /Applications/Devin.app ]]; then
    warn "Devin.app missing — install from https://devin.ai (no cask)"
  fi

  # Upgrade pass — brew/mise/softwareupdate. Same logic the user runs
  # standalone as `update-sys`; bootstrap calls it so a fresh re-run
  # leaves the machine fully current, not just package-list-complete.
  # Non-fatal: a flaky upgrade must not abort before configs deploy.
  if bash "$DOTFILES_DIR/bin/update-system"; then
    ok "upgrade pass"
  else
    warn "update-system had failures — continuing to configs"
  fi
}

brewfile_casks() {
  local brewfile="$1"
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*cask[[:space:]]+"/ {
      line = $0
      sub(/^[[:space:]]*cask[[:space:]]+"/, "", line)
      sub(/".*/, "", line)
      print line
    }
  ' "$brewfile" | paste -sd' ' -
}

# Xcode Command Line Tools — brew needs them to install most formulae.
# Without them, the Homebrew installer drops you into a graphical
# "install developer tools" prompt that wedges any non-interactive run.
ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  step "installing Xcode Command Line Tools"
  if has_tty; then
    xcode-select --install 2>/dev/null || true
    err "complete the Xcode CLT prompt, then re-run this bootstrap"
    exit 1
  fi
  err "Xcode CLT missing and no TTY for the install prompt"
  exit 1
}

# Seed Hyperkey (Caps→Hyper, tap-for-Esc). v1.56 reads from the bundle-id
# domain `com.knollsoft.Hyperkey` with the keys below; an older build (the
# one f17cf62 patched against) read from the plain `Hyperkey` domain with
# enableHyperKey/tapForEscape — those don't exist in v1.56, so the prior
# seeding was a no-op and every caps chord died until the user opened
# Hyperkey and re-toggled the switches by hand. Hyperkey rewrites its
# prefs on quit, so the write order matters: quit → write → relaunch.
# Idempotent.
seed_hyperkey_defaults() {
  [[ -d /Applications/Hyperkey.app ]] || return 0
  local domain="com.knollsoft.Hyperkey" ver
  ver=$(defaults read /Applications/Hyperkey.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo '?')
  step "seeding Hyperkey ($domain · v$ver)"

  osascript -e 'tell application "Hyperkey" to quit' 2>/dev/null || true
  # Quit is async — wait for the process to actually exit so its on-quit
  # prefs rewrite can't clobber ours (a fixed sleep lost the race on slow
  # machines). ~5s cap, then proceed regardless.
  local waited=0
  while pgrep -x Hyperkey >/dev/null 2>&1 && (( waited < 50 )); do
    sleep 0.1
    waited=$((waited + 1))
  done

  # Caps→Hyper (capsLockRemapped=2, keyRemap=1), Hyper = ⌃⌥⌘⇧
  # (hyperFlags=1966080), tap-for-Esc on (executeQuickHyperKey=1) with
  # keycode 53 (kVK_Escape).
  defaults write "$domain" capsLockRemapped     -int  2
  defaults write "$domain" keyRemap             -int  1
  defaults write "$domain" hyperFlags           -int  1966080
  defaults write "$domain" quickHyperKeycode    -int  53
  defaults write "$domain" executeQuickHyperKey -int  1
  defaults write "$domain" launchOnLogin        -int  1

  # Relaunch in the background so the daemon picks up the seeded prefs
  # without stealing focus.
  open -ga Hyperkey 2>/dev/null || true
  ok "Hyperkey seeded (caps→hyper, tap-for-esc)"
}

# ─── phase 3 · apply configs + macOS defaults ───────────────────────────────
phase_apply() {
  section "Phase 3/4 · deploy configs & defaults"

  : > "$HOME/.hushlogin"

  # Apply curated macOS defaults (Dark mode, Dock/Finder/Trackpad posture)
  # — see docs/macos-defaults.md for the table and hard limits.
  bash "$DOTFILES_DIR/macos/macos-defaults.sh"

  # Stop legacy services BEFORE deleting their configs — otherwise
  # Karabiner's grabber can wedge the input system on its way out.
  # `brew services list` costs ~1s, so capture it once, not per service.
  local brew_services
  brew_services="$(brew services list 2>/dev/null || true)"
  for svc in yabai skhd; do
    if grep -q "^$svc.*started" <<<"$brew_services"; then
      step "stopping legacy service: $svc"
      brew services stop "$svc" >/dev/null 2>&1 || true
    fi
  done
  if pgrep -x karabiner_grabber >/dev/null 2>&1 \
       || pgrep -x Karabiner-Elements >/dev/null 2>&1; then
    step "stopping Karabiner-Elements (replaced by Hyperkey)"
    osascript -e 'tell application "Karabiner-Elements" to quit' 2>/dev/null || true
    launchctl unload -w "$HOME/Library/LaunchAgents/org.pqrs."*.plist 2>/dev/null || true
    sleep 1
  fi
  rm -f  "$HOME/.skhdrc" "$HOME/.yabairc"
  rm -rf "$HOME/.config/yabai" "$HOME/.config/skhd" "$HOME/.config/karabiner"

  # AeroSpace retired (mouse + single screen won; tiling never earned its
  # keep). Quit the app, drop the cask, sweep its config. Idempotent — a
  # machine that never had it just no-ops through.
  if pgrep -x AeroSpace >/dev/null 2>&1; then
    step "stopping AeroSpace (retired)"
    osascript -e 'tell application "AeroSpace" to quit' 2>/dev/null || true
  fi
  if brew list --cask aerospace >/dev/null 2>&1; then
    step "uninstalling aerospace cask"
    brew uninstall --cask aerospace >/dev/null 2>&1 || warn "aerospace cask uninstall failed"
  fi
  rm -rf "$HOME/.config/aerospace"

  # Raycast retired too (native Tahoe Spotlight is the launcher). Same
  # idempotent teardown shape: quit, drop the cask, sweep local state.
  if pgrep -x Raycast >/dev/null 2>&1; then
    step "stopping Raycast (retired)"
    osascript -e 'tell application "Raycast" to quit' 2>/dev/null || true
  fi
  if brew list --cask raycast >/dev/null 2>&1; then
    step "uninstalling raycast cask"
    brew uninstall --cask raycast >/dev/null 2>&1 || warn "raycast cask uninstall failed"
  fi
  rm -rf "$HOME/Library/Application Support/com.raycast.macos" \
         "$HOME/Library/Caches/com.raycast.macos" \
         "$HOME/Library/Application Support/com.raycast.shared"
  defaults delete com.raycast.macos >/dev/null 2>&1 || true

  # Sigil (the Swift workspace package) is fully retired with AeroSpace —
  # its last survivor, the ws-cheatsheet HUD, was only reachable via the
  # Caps+/ chord that lived in aerospace.toml. Sweep the clone, its
  # symlinked binaries, and the rune generator that fed it.
  rm -rf "$HOME/.config/workspace"
  for bin in "$HOME/.local/bin/ws-"*; do
    [[ -e "$bin" || -L "$bin" ]] || continue
    [[ "${bin##*/}" == "ws-doctor" ]] || rm -f "$bin"
  done
  python3 -m pip uninstall --quiet --yes rune 2>/dev/null || true

  # Retired surfaces from earlier eras: sketchybar / borders. (The ws-*
  # launchers and ~/.config/workspace scripts are covered by the sigil
  # sweep above.)
  rm -rf "$HOME/.config/sketchybar"
  rm -rf "$HOME/.config/borders"

  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/starship.toml"              "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/CLAUDE.md"                  "$HOME/.claude/CLAUDE.md"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$DOTFILES_DIR/bin/ws-doctor"             "$HOME/.local/bin/ws-doctor" 755
  install_file "$DOTFILES_DIR/bin/update-system"         "$HOME/.local/bin/update-system" 755
  rm -f "$HOME/.config/zsh/completions/_ws"

  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"           "$HOME/.config/nvim/after/plugin/keymaps.lua"

  ensure_gitconfig_local
}

# ─── phase 4 · permission wizard ────────────────────────────────────────────
phase_wizard() {
  section "Phase 4/4 · permission wizard"
  step "handing off to permissions-wizard.sh"
  exec "$DOTFILES_DIR/macos/permissions-wizard.sh"
}

main() {
  section "Hyper-key dotfiles bootstrap (macOS)"
  # pip --user console scripts land in the Python user-base bin
  # (~/Library/Python/3.x/bin) — off PATH on a fresh Mac. ~/.local/bin
  # matches the Ubuntu bootstrap's PATH posture. The xcode-select gate
  # keeps the python3 CLT shim from popping the GUI installer prompt
  # before ensure_xcode_clt handles it deliberately.
  local pyuser=
  if xcode-select -p >/dev/null 2>&1; then
    pyuser="$(python3 -m site --user-base 2>/dev/null || true)"
  fi
  export PATH="$HOME/.local/bin${pyuser:+:$pyuser/bin}:$PATH"
  phase_sudo
  phase_packages
  phase_apply
  phase_wizard
}

main "$@"
