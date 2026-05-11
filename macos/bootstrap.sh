#!/usr/bin/env bash
# macos/bootstrap.sh — set up the Hyper-key dev environment on macOS.
#
# Idempotent: re-running is safe and only does work where state has drifted.
#
# Phases:
#   1. sudo       — cache once for the whole run
#   2. packages   — Homebrew formulae (CLI + yabai/skhd) and GUI casks
#   3. configs    — copy from configs/ to their canonical locations
#   4. defaults   — system tweaks (spans-displays, iTerm Option-as-Meta)
#   5. wizard     — hand off to the proactive TCC permission flow
#
# Env knobs:
#   BOOTSTRAP_SKIP_CASKS=1   skip GUI cask installs (headless / no-TTY runs)
#   NO_COLOR=1               plain output (no ANSI)

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"
. "$DOTFILES_DIR/lib/macos-tcc.sh"

# ─── phase 1 · sudo ─────────────────────────────────────────────────────────
phase_sudo() {
  section "Phase 1/5 · sudo"
  if ! has_tty; then
    warn "no TTY — cask installs and Accessibility prompts will be skipped"
    info "re-run from a real terminal, or set BOOTSTRAP_SKIP_CASKS=1"
    return 0
  fi
  step "caching sudo credential (one prompt for the whole run)"
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
    ripgrep fd git-delta zoxide gh \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null
  ok "shell + dev tools (rg, fd, delta, zoxide, gh, …)"

  step "installing yabai + skhd (koekeishiya tap)"
  brew install --quiet koekeishiya/formulae/yabai >/dev/null || true
  brew install --quiet koekeishiya/formulae/skhd  >/dev/null || true
  ok "yabai + skhd"

  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing GUI casks (will sudo-prompt for each .pkg)"
    info "karabiner-elements · hammerspoon · rectangle · ghostty · raycast"
    brew install --cask karabiner-elements hammerspoon rectangle ghostty raycast 2>&1 \
      | sed "s/^/    /" || true
    ok "casks installed (or already present)"
  else
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
    info "later: brew install --cask karabiner-elements hammerspoon rectangle ghostty raycast"
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
        step "running staged Karabiner installer (will sudo-prompt)"
        sudo installer -pkg "$pkg" -target / && ok "Karabiner installed" \
          || warn "installer failed"
      else
        info "fix later: sudo installer -pkg \"$pkg\" -target /"
      fi
    fi
  fi
}

# ─── phase 3 · configs ──────────────────────────────────────────────────────
phase_configs() {
  section "Phase 3/5 · deploy configs"

  # Window/keyboard layer (Karabiner contract → skhd → yabai → Hammerspoon)
  install_file "$CONFIGS_DIR/karabiner.json"             "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/skhdrc"                     "$HOME/.skhdrc"
  install_file "$CONFIGS_DIR/yabairc"                    "$HOME/.yabairc"             755
  install_file "$CONFIGS_DIR/hammerspoon-init.lua"       "$HOME/.hammerspoon/init.lua"
  install_file "$CONFIGS_DIR/hammerspoon-cheatsheet.lua" "$HOME/.hammerspoon/cheatsheet.lua"

  # Terminal + shell layer
  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755

  # Editor layer (init.lua + lazy lock; lazy.nvim self-installs on first launch)
  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"           "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # gitconfig is split: structural settings tracked, user info in
  # ~/.gitconfig.local (not tracked) via [include]. Stub it so [include]
  # doesn't fail silently on a fresh box.
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
    ok "created ~/.gitconfig.local stub"
    info "edit it: $EDITOR ~/.gitconfig.local"
  fi
}

# ─── phase 4 · macOS defaults ───────────────────────────────────────────────
phase_defaults() {
  section "Phase 4/5 · macOS defaults"

  # yabai requires "Displays have separate Spaces" (Mission Control toggle).
  # The underlying preference is com.apple.spaces spans-displays = 0 (false).
  # The change only takes effect after logout/login — surfaced in the wizard.
  if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]]; then
    step "spans-displays → false (yabai requirement)"
    defaults write com.apple.spaces spans-displays -bool false
    export HYPER_BOOTSTRAP_NEED_RELOGIN=1
    info "logout required for this to take effect"
  else
    ok "spans-displays already false"
  fi

  if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
    step "iTerm2 → Option = Meta"
    defaults write com.googlecode.iterm2 "Left Option Key Sends" -string "Esc+"
    ok "iTerm2 configured"
  else
    info "iTerm2 prefs not found — skipping (launch iTerm2 once, then re-run)"
  fi

  # Hammerspoon: prevent AppKit from restoring the Console window on every
  # reload. Wipe the saved frame; init.lua's close-console hook handles the
  # current process.
  if defaults read org.hammerspoon.Hammerspoon >/dev/null 2>&1; then
    defaults delete org.hammerspoon.Hammerspoon "NSWindow Frame console" 2>/dev/null || true
    ok "Hammerspoon Console window frame cleared"
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
  phase_wizard   # exec-replaces; nothing runs after this
}

main "$@"
