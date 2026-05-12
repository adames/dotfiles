#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 1 · sudo ─────────────────────────────────────────────────────────
phase_sudo() {
  section "Phase 1/5 · sudo"
  if ! has_tty; then
    warn "no TTY — cask installs and Accessibility prompts will be skipped"
    return 0
  fi
  step "caching sudo (one prompt for the run)"
  sudo -v
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  trap 'kill '"$!"' 2>/dev/null' EXIT
  ok "sudo cached"
}

# ─── phase 2 · packages ─────────────────────────────────────────────────────
phase_packages() {
  section "Phase 2/5 · packages"

  if ! have brew; then
    step "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    ok "Homebrew installed"
  fi

  step "installing CLI formulae"
  brew install --quiet \
    git zsh tmux neovim direnv jq starship fzf \
    ripgrep fd git-delta zoxide gh lazygit \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null
  ok "shell + dev tools (rg, fd, delta, zoxide, gh, lazygit, …)"

  step "installing yabai + skhd (koekeishiya tap)"
  brew install --quiet koekeishiya/formulae/yabai >/dev/null || true
  brew install --quiet koekeishiya/formulae/skhd  >/dev/null || true
  ok "yabai + skhd"

  # orbstack replaces docker-desktop — leaner, native Apple Silicon, faster
  # cold start. If docker-desktop is installed, see the migration note in
  # README.md → "Switching from Docker Desktop".
  local casks="karabiner-elements hammerspoon ghostty raycast orbstack"
  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing GUI casks"
    info "$casks"
    # shellcheck disable=SC2086
    brew install --cask $casks 2>&1 | sed "s/^/    /" || true
    ok "casks installed (or already present)"
  else
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
    info "later: brew install --cask $casks"
  fi

  # brew can mark a cask installed but skip the .pkg if interrupted mid-sudo.
  if [[ ! -d /Applications/Karabiner-Elements.app ]]; then
    local pkg
    pkg=$(find "$(brew --prefix 2>/dev/null)/Caskroom/karabiner-elements" -name "*.pkg" 2>/dev/null | head -1)
    if [[ -n "$pkg" && "$(has_tty && echo y)" ]]; then
      step "running staged Karabiner installer"
      sudo installer -pkg "$pkg" -target / && ok "Karabiner installed" || warn "installer failed"
    elif [[ -n "$pkg" ]]; then
      warn "Karabiner staged but not installed — run: sudo installer -pkg \"$pkg\" -target /"
    fi
  fi
}

# ─── phase 3 · configs ──────────────────────────────────────────────────────
phase_configs() {
  section "Phase 3/5 · deploy configs"

  # Window/keyboard
  install_file "$CONFIGS_DIR/karabiner.json"             "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/skhdrc"                     "$HOME/.skhdrc"
  install_file "$CONFIGS_DIR/yabairc"                    "$HOME/.yabairc"             755
  install_file "$CONFIGS_DIR/yabai-ensure-spaces.sh"     "$HOME/.config/yabai/ensure-spaces.sh" 755
  install_file "$CONFIGS_DIR/hammerspoon-init.lua"       "$HOME/.hammerspoon/init.lua"
  install_file "$CONFIGS_DIR/hammerspoon-cheatsheet.lua" "$HOME/.hammerspoon/cheatsheet.lua"

  # Terminal + shell
  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755

  # Editor — lazy.nvim self-installs on first nvim launch
  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"           "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # User info lives in ~/.gitconfig.local (not tracked, [include]'d by gitconfig).
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
    ok "created ~/.gitconfig.local stub — edit user.email / user.name"
  fi
}

# ─── phase 4 · macOS defaults ───────────────────────────────────────────────
phase_defaults() {
  section "Phase 4/5 · macOS defaults"

  # yabai needs "Displays have separate Spaces" (re-read on fresh login only).
  if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]]; then
    step "spans-displays → false"
    defaults write com.apple.spaces spans-displays -bool false
    info "logout required to take effect"
  else
    ok "spans-displays already false"
  fi

  # Stop Hammerspoon Console from auto-restoring on reload.
  if defaults read org.hammerspoon.Hammerspoon >/dev/null 2>&1; then
    defaults delete org.hammerspoon.Hammerspoon "NSWindow Frame console" 2>/dev/null || true
    ok "Hammerspoon console frame cleared"
  fi
}

# ─── phase 5 · permission wizard ────────────────────────────────────────────
phase_wizard() {
  section "Phase 5/5 · permission wizard"
  step "handing off to permissions-wizard.sh"
  exec "$DOTFILES_DIR/macos/permissions-wizard.sh"
}

# ─── entry ──────────────────────────────────────────────────────────────────
main() {
  banner "Hyper-key dotfiles bootstrap" "macOS · Apple Silicon"
  phase_sudo
  phase_packages
  phase_configs
  phase_defaults
  phase_wizard   # exec-replaces
}

main "$@"
