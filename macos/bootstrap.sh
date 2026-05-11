#!/usr/bin/env bash
# macos/bootstrap.sh — install everything the Hyper-key scheme needs on macOS.
#
# Flow:
#   1. cache sudo (one prompt for the whole run)
#   2. brew + CLI tools + yabai/skhd formulae
#   3. GUI casks (Karabiner-Elements, Hammerspoon, Rectangle)
#   4. deploy configs from ../configs/
#   5. set macOS defaults (spans-displays, iTerm meta)
#   6. hand off to permissions-wizard.sh for the proactive permission flow
#
# Each phase is idempotent and re-running is safe.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"
. "$DOTFILES_DIR/lib/macos-tcc.sh"

mac_install_packages() {
  if ! have brew; then
    log "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  fi

  log "installing CLI tools"
  brew install --quiet \
    git zsh tmux neovim direnv jq starship fzf \
    ripgrep fd git-delta zoxide gh \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null

  log "installing yabai + skhd (formulae)"
  brew install --quiet koekeishiya/formulae/yabai >/dev/null || true
  brew install --quiet koekeishiya/formulae/skhd  >/dev/null || true

  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    log "installing GUI casks (will sudo-prompt for each .pkg)"
    # ghostty   — primary terminal (fast, GPU-accelerated, macOS-native)
    # raycast   — Spotlight replacement (smarter, free for personal use)
    # rectangle — SIP-safe window-snap fallback
    brew install --cask karabiner-elements hammerspoon rectangle ghostty raycast 2>&1 | \
      sed 's/^/    cask: /' || true
  else
    warn "skipping cask installs — run later:"
    warn "  brew install --cask karabiner-elements hammerspoon rectangle ghostty raycast"
  fi

  # Cask sanity: brew records a cask as "installed" once the artifact is
  # staged, but if the .pkg installer was interrupted (e.g. killed mid-sudo)
  # the .app never lands. Detect and re-run if we have a TTY.
  if [[ ! -d /Applications/Karabiner-Elements.app ]]; then
    local pkg
    pkg=$(find "$(brew --prefix 2>/dev/null)/Caskroom/karabiner-elements" -name "*.pkg" 2>/dev/null | head -1)
    if [[ -n "$pkg" ]]; then
      warn "Karabiner cask staged but .app missing — installer never ran"
      if has_tty; then
        log "running staged installer now (will sudo-prompt)"
        sudo installer -pkg "$pkg" -target / || warn "installer failed"
      else
        warn "fix later: sudo installer -pkg \"$pkg\" -target /"
      fi
    fi
  fi
}

mac_deploy_configs() {
  install_file "$CONFIGS_DIR/karabiner.json"              "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/skhdrc"                      "$HOME/.skhdrc"
  install_file "$CONFIGS_DIR/yabairc"                     "$HOME/.yabairc"             755
  install_file "$CONFIGS_DIR/hammerspoon-init.lua"        "$HOME/.hammerspoon/init.lua"
  install_file "$CONFIGS_DIR/hammerspoon-cheatsheet.lua"  "$HOME/.hammerspoon/cheatsheet.lua"
  install_file "$CONFIGS_DIR/tmux.conf"                   "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/ghostty-config"              "$HOME/.config/ghostty/config"

  # Shell + git + ripgrep + sessionizer (added in shell-layer refactor)
  install_file "$CONFIGS_DIR/zshrc"                       "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"                   "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                   "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"            "$HOME/.local/bin/tmux-sessionizer" 755

  # gitconfig is split: structural settings tracked, user info in ~/.gitconfig.local.
  # Create a stub if missing so [include] doesn't fail silently on a fresh box.
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    log "creating ~/.gitconfig.local stub (fill in user.email / user.name)"
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
  fi

  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua" \
               "$HOME/.config/nvim/after/plugin/keymaps.lua"
}

mac_set_defaults() {
  # yabai requires "Displays have separate Spaces" (Mission Control toggle).
  # The underlying preference is com.apple.spaces spans-displays = 0 (false).
  # NB: the change only takes effect after logout/login. We surface that fact
  # in the wizard's finalize step.
  if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]]; then
    log "setting com.apple.spaces spans-displays = false (yabai requirement)"
    defaults write com.apple.spaces spans-displays -bool false
    export HYPER_BOOTSTRAP_NEED_RELOGIN=1
  fi

  if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
    log "configuring iTerm2 (Option = Meta)"
    defaults write com.googlecode.iterm2 "Left Option Key Sends" -string "Esc+"
  else
    warn "iTerm2 prefs not found — skipping (launch iTerm2 once, then re-run)"
  fi

  # Hammerspoon: prevent AppKit from restoring the Console window on every
  # reload. Wipe the saved frame; init.lua's close-console hook handles the
  # current process. defaults read returns 0 if Hammerspoon prefs exist.
  if defaults read org.hammerspoon.Hammerspoon >/dev/null 2>&1; then
    log "wiping saved Hammerspoon Console window frame"
    defaults delete org.hammerspoon.Hammerspoon "NSWindow Frame console" 2>/dev/null || true
  fi
}

mac_cache_sudo() {
  if ! has_tty; then
    warn "no TTY detected — cask installs and Accessibility prompts will be skipped"
    warn "re-run from a real terminal to install GUI apps, or set BOOTSTRAP_SKIP_CASKS=1"
    return 0
  fi
  log "caching sudo credential (one prompt for the whole run)"
  sudo -v
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  local sudo_keepalive_pid=$!
  trap 'kill '"$sudo_keepalive_pid"' 2>/dev/null' EXIT
}

main() {
  log "macOS detected — applying Hyper-key keybinding scheme"
  mac_cache_sudo
  mac_install_packages
  mac_deploy_configs
  mac_set_defaults

  # Hand off to the proactive permission wizard. It probes every TCC gate,
  # registers apps in the list (by launching them), chains the user through
  # System Settings, then finalizes (logout prompt + summary).
  "$DOTFILES_DIR/macos/permissions-wizard.sh"
}

main "$@"
