#!/usr/bin/env bash
# ubuntu/bootstrap.sh — set up the Hyper-key dev environment on Ubuntu.
#
# For minerva (VPS / VM) where the macOS layer (yabai/skhd/Hammerspoon/
# Karabiner) doesn't apply. Installs the same shell + nvim stack so the
# editor and CLI tooling feel identical to the Mac.
#
# Idempotent: re-running is safe.
#
# Override the dotfiles repo URL with DOTFILES_REPO=git@github.com:you/dotfiles.git
#
# Phases:
#   1. system   — apt packages
#   2. dotfiles — chezmoi-managed home tree
#   3. shell    — starship, zsh plugins (git-clone), fzf
#   4. runtimes — mise + Docker + Claude CLI
#   5. configs  — drop in tmux, nvim, ripgreprc, sessionizer
#   6. shell    — set zsh as default

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 1 · system packages ──────────────────────────────────────────────
phase_system() {
  section "Phase 1/6 · system packages"
  step "apt update + upgrade"
  sudo apt update && sudo apt upgrade -y >/dev/null
  ok "system up to date"

  step "installing apt packages"
  sudo apt install -y \
    git curl zsh build-essential direnv tmux htop neovim jq \
    ripgrep fd-find git-delta zoxide >/dev/null
  ok "git zsh tmux neovim direnv jq ripgrep fd zoxide …"

  # fd is named fdfind on Debian/Ubuntu. Symlink so scripts/configs that
  # reference `fd` work uniformly across macOS and Linux. ~/.local/bin is on PATH.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "symlinked fdfind → ~/.local/bin/fd"
  fi

  if ! have gh; then
    step "installing GitHub CLI (gh) from upstream apt repo"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update -qq && sudo apt install -y gh >/dev/null
    ok "gh installed"
  fi
}

# ─── phase 2 · chezmoi-managed dotfiles ─────────────────────────────────────
phase_dotfiles() {
  section "Phase 2/6 · dotfiles (chezmoi)"
  if ! have chezmoi; then
    step "installing chezmoi"
    curl -fsLS https://get.chezmoi.io | bash -s -- -b "$HOME/.local/bin"
    ok "chezmoi installed"
  fi
  if [[ ! -d "$HOME/.local/share/chezmoi" ]]; then
    step "initialising chezmoi from $DOTFILES_REPO"
    chezmoi init "$DOTFILES_REPO"
  fi
  step "applying chezmoi state"
  chezmoi apply --force || warn "chezmoi apply had warnings"
  ok "dotfiles applied"
}

# ─── phase 3 · shell layer ──────────────────────────────────────────────────
phase_shell() {
  section "Phase 3/6 · shell layer"
  if ! have starship; then
    step "installing Starship"
    curl -sS https://starship.rs/install.sh | sh -s -- --yes >/dev/null
    ok "Starship installed"
  fi

  step "installing zsh plugins (git clones into ~/.zsh)"
  [[ -d ~/.zsh/zsh-autosuggestions ]] || \
    git clone -q https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
  [[ -d ~/.zsh/zsh-syntax-highlighting ]] || \
    git clone -q https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
  ok "zsh-autosuggestions + zsh-syntax-highlighting"

  if [[ ! -d ~/.fzf ]]; then
    step "installing fzf shell integration"
    git clone --depth 1 -q https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all --no-bash >/dev/null
    ok "fzf shell integration"
  fi
}

# ─── phase 4 · runtimes ─────────────────────────────────────────────────────
phase_runtimes() {
  section "Phase 4/6 · runtimes"
  if ! have mise && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    step "installing mise"
    curl -fsSL https://mise.run | sh >/dev/null
    ok "mise installed"
  fi
  step "mise install (per ~/.tool-versions / .mise.toml)"
  "$HOME/.local/bin/mise" install || mise install || true

  if ! have docker; then
    step "installing Docker"
    curl -fsSL https://get.docker.com | sh >/dev/null
    sudo usermod -aG docker "$USER"
    ok "Docker installed (re-login for group membership)"
  fi

  if ! have claude; then
    step "installing Claude CLI"
    curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
    bash /tmp/claude-install.sh
    ok "Claude CLI installed"
  fi
}

# ─── phase 5 · configs ──────────────────────────────────────────────────────
phase_configs() {
  section "Phase 5/6 · configs"
  install_file "$CONFIGS_DIR/tmux.conf"           "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/ripgreprc"           "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"    "$HOME/.local/bin/tmux-sessionizer" 755

  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-init.lua"       "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"    "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # zshrc and gitconfig are intentionally NOT installed here — chezmoi
  # already manages them on Linux. To track them via chezmoi, copy
  # configs/zshrc and configs/gitconfig into your chezmoi source dir.
  info "zshrc + gitconfig left to chezmoi (see configs/ for canonical versions)"
}

# ─── phase 6 · default shell ────────────────────────────────────────────────
phase_default_shell() {
  section "Phase 6/6 · default shell"
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    step "setting login shell to zsh"
    sudo chsh -s "$(command -v zsh)" "$USER" || warn "chsh failed; run manually"
    ok "default shell → zsh (effective on next login)"
  else
    ok "zsh already default shell"
  fi
}

# ─── entry ──────────────────────────────────────────────────────────────────
main() {
  banner "Hyper-key dotfiles bootstrap" "Ubuntu · minerva dev env"
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  phase_system
  phase_dotfiles
  phase_shell
  phase_runtimes
  phase_configs
  phase_default_shell

  section "Done"
  ok "bootstrap complete"
  info "log out / log in for the shell change to apply"
}

main "$@"
