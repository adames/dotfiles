#!/usr/bin/env bash
# Idempotent Ubuntu bootstrap (VPS / VM). No yabai/Karabiner — shell + nvim only.
# Override dotfiles repo with DOTFILES_REPO=...

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 0 · sparse-checkout (idempotent, runs first) ─────────────────────
# Prune the working tree of macOS-only paths (Karabiner, yabai, skhd,
# sketchybar, the Swift topology package, etc.) so a Linux clone only
# contains files this host actually uses. Manifest at lib/platform-
# manifest.sh is the single source of truth — see ubuntu/sparse-checkout.sh.
# Safe to run every bootstrap; no-ops when patterns are already current.
phase_sparse_checkout() {
  section "Phase 0/6 · sparse-checkout (prune macOS-only paths)"
  if [[ -x "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" ]]; then
    "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" || warn "sparse-checkout failed; continuing with full tree"
  else
    warn "ubuntu/sparse-checkout.sh missing or not executable — skipping prune"
  fi
}

# ─── phase 1 · terminfo (idempotent, runs first) ────────────────────────────
# When SSH'ing in from Ghostty, TERM=xterm-ghostty is forwarded. Ubuntu's
# default terminfo database doesn't ship that entry, so zsh's line editor
# falls back to a stub — typing duplicates characters, backspace inserts
# spaces, the REPL is unusable. Compile the bundled source to ~/.terminfo
# so any user-level shell finds it. Runs first so the heavier apt/git work
# below isn't done through a broken REPL on the first-ever bootstrap from
# a Ghostty SSH session.
phase_terminfo() {
  section "Phase 1/6 · terminfo (xterm-ghostty)"
  if ! have tic; then
    step "installing ncurses-bin (provides tic)"
    sudo apt update -qq && sudo apt install -y ncurses-bin >/dev/null
  fi
  if [[ -f "$HOME/.terminfo/x/xterm-ghostty" ]]; then
    ok "xterm-ghostty already in ~/.terminfo — skipping"
  else
    step "compiling configs/xterm-ghostty.terminfo → ~/.terminfo"
    tic -x -o "$HOME/.terminfo" "$CONFIGS_DIR/xterm-ghostty.terminfo" 2>&1 \
      | sed 's/^/    /' || warn "tic returned non-zero — entry may still be usable"
    ok "xterm-ghostty installed (reconnect SSH or 'exec zsh' to pick up)"
  fi
}

# ─── phase 1 · system packages ──────────────────────────────────────────────
phase_system() {
  section "Phase 2/6 · system packages"
  step "apt update + upgrade"
  sudo apt update && sudo apt upgrade -y >/dev/null
  ok "system up to date"

  step "installing apt packages"
  sudo apt install -y \
    git curl zsh build-essential direnv tmux htop neovim jq \
    ripgrep fd-find git-delta zoxide >/dev/null
  ok "git zsh tmux neovim direnv jq ripgrep fd zoxide …"

  # Debian/Ubuntu calls fd "fdfind"; symlink for cross-OS parity.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "symlinked fdfind → ~/.local/bin/fd"
  fi

  if ! have gh; then
    step "adding GitHub CLI apt repo"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update -qq && sudo apt install -y gh >/dev/null
    ok "gh installed"
  fi
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
# Docker intentionally NOT installed: on macOS, OrbStack covers containers.
# On Ubuntu (this script) containers aren't a typical workload for the VPS /
# VM use cases — develop locally with OrbStack, ship from there. If you ever
# need a container runtime on the server: `curl -fsSL https://get.docker.com | sh`.
phase_runtimes() {
  section "Phase 4/6 · runtimes"
  if ! have mise && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    step "installing mise"
    curl -fsSL https://mise.run | sh >/dev/null
    ok "mise installed"
  fi
  step "mise install (per ~/.tool-versions / .mise.toml)"
  "$HOME/.local/bin/mise" install || mise install || true
}

# ─── phase 5 · configs ──────────────────────────────────────────────────────
phase_configs() {
  section "Phase 5/6 · configs"
  install_file "$CONFIGS_DIR/tmux.conf"           "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/ripgreprc"           "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"    "$HOME/.local/bin/tmux-sessionizer" 755

  # Workspace CLI: cross-platform mutation tool for spaces.json. macOS-
  # specific consumers (sketchybar, yabai) are silent-on-absence here,
  # but the CLI itself works for editing JSON state from Linux.
  # `ws` is the canonical name; `workspace` is kept as a compat symlink.
  install_file "$CONFIGS_DIR/workspace/cli/ws"              "$HOME/.local/bin/ws"                              755
  ln -sf "ws" "$HOME/.local/bin/workspace"
  install_file "$CONFIGS_DIR/workspace/cli/test-cascade.sh" "$HOME/.config/workspace/cli/test-cascade.sh"      755
  install_file "$CONFIGS_DIR/completions/_ws"               "$HOME/.config/zsh/completions/_ws"
  install_file "$CONFIGS_DIR/completions/ws.bash"           "$HOME/.config/bash/completions/ws.bash"
  install_file "$CONFIGS_DIR/zshrc"               "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"           "$HOME/.gitconfig"

  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-init.lua"       "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"    "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # User info lives in ~/.gitconfig.local (not tracked, [include]'d by gitconfig).
  # Same pattern as macos/bootstrap.sh — keeps the two paths symmetric.
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
    ok "created ~/.gitconfig.local stub — edit user.email / user.name"
  fi
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
  section "Hyper-key dotfiles bootstrap (Ubuntu · minerva dev env)"
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  phase_sparse_checkout
  phase_terminfo
  phase_system
  phase_shell
  phase_runtimes
  phase_configs
  phase_default_shell

  section "Done"
  ok "bootstrap complete"
  step "log out / log in for the shell change to apply"
}

main "$@"
