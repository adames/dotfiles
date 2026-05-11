#!/usr/bin/env bash
# ubuntu/bootstrap.sh — minerva dev-env bootstrap for Ubuntu hosts (VPS or VM).
#
# Installs system packages + zsh setup + mise + Docker + Claude CLI, applies
# the chezmoi-managed dotfiles tree from $DOTFILES_REPO, and drops in the
# tmux + nvim configs from this repo's configs/.
#
# Override DOTFILES_REPO if you want to bootstrap from a fork:
#   DOTFILES_REPO=git@github.com:you/dotfiles.git ./ubuntu/bootstrap.sh

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

main() {
  log "Ubuntu detected — bootstrapping minerva dev env"
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  log "installing system packages"
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y \
    git curl zsh build-essential direnv tmux htop neovim jq \
    ripgrep fd-find git-delta zoxide

  # fd is named fdfind on Debian/Ubuntu. Symlink so scripts/configs that say
  # `fd` work uniformly across macOS and Linux. ~/.local/bin is on PATH.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi

  # gh — GitHub's CLI repo (skip if already configured)
  if ! have gh; then
    log "adding GitHub CLI apt repo"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update && sudo apt install -y gh
  fi

  log "installing chezmoi + applying dotfiles ($DOTFILES_REPO)"
  if ! have chezmoi; then
    curl -fsLS https://get.chezmoi.io | bash -s -- -b "$HOME/.local/bin"
  fi
  if [[ ! -d "$HOME/.local/share/chezmoi" ]]; then
    chezmoi init "$DOTFILES_REPO"
  fi
  chezmoi apply --force || warn "chezmoi apply had warnings"

  log "installing Starship"
  have starship || curl -sS https://starship.rs/install.sh | sh -s -- --yes

  log "installing zsh plugins"
  [[ -d ~/.zsh/zsh-autosuggestions ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
  [[ -d ~/.zsh/zsh-syntax-highlighting ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
  if [[ ! -d ~/.fzf ]]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
  fi

  log "installing mise + runtimes"
  if ! have mise && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    curl https://mise.run | sh
  fi
  "$HOME/.local/bin/mise" install || mise install || true

  log "installing Docker"
  if ! have docker; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
  fi

  log "installing Claude CLI"
  if ! have claude; then
    curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
    bash /tmp/claude-install.sh
  fi

  # Drop tmux + nvim keymaps from this repo's configs/.
  install_file "$CONFIGS_DIR/tmux.conf"        "$HOME/.tmux.conf"
  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua" "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # Shell-layer additions: ripgrep config + tmux sessionizer.
  # zshrc and gitconfig are intentionally NOT installed here — chezmoi already
  # manages those on Linux. Sync configs/zshrc and configs/gitconfig into your
  # chezmoi source dir manually if you want them tracked there.
  install_file "$CONFIGS_DIR/ripgreprc"        "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer" "$HOME/.local/bin/tmux-sessionizer" 755

  log "setting default shell to zsh"
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    sudo chsh -s "$(command -v zsh)" "$USER" || warn "chsh failed; run manually"
  fi

  log "bootstrap complete — log out and back in for shell change to apply"
}

main "$@"
