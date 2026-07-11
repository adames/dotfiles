#!/usr/bin/env bash
# Idempotent Ubuntu bootstrap (VPS / VM). No aerospace/Hyperkey — shell + nvim only.
# Override dotfiles repo with DOTFILES_REPO=...

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 0 · sparse-checkout (idempotent, runs first) ─────────────────────
# Prune the working tree of macOS-only paths (aerospace, sketchybar,
# the Swift workspace package, etc.) so a Linux clone only contains
# files this host actually uses. Manifest at lib/platform-manifest.sh
# is the single source of truth — see ubuntu/sparse-checkout.sh.
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
    sudo apt-get update -qq && sudo apt-get install -y ncurses-bin >/dev/null
  fi
  if [[ -f "$HOME/.terminfo/x/xterm-ghostty" ]]; then
    ok "xterm-ghostty already in ~/.terminfo — skipping"
  else
    step "compiling configs/xterm-ghostty.terminfo → ~/.terminfo"
    if tic -x -o "$HOME/.terminfo" "$CONFIGS_DIR/xterm-ghostty.terminfo" 2>&1 \
         | sed 's/^/    /'; then
      ok "xterm-ghostty installed (reconnect SSH or 'exec zsh' to pick up)"
    else
      warn "tic returned non-zero — entry may still be usable"
    fi
  fi
}

# ─── phase 2 · system packages ──────────────────────────────────────────────
phase_system() {
  section "Phase 2/6 · system packages"
  step "apt update + upgrade"
  sudo apt-get update && sudo apt-get upgrade -y >/dev/null
  ok "system up to date"

  step "installing apt packages"
  sudo apt-get install -y \
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
    sudo apt-get update -qq && sudo apt-get install -y gh >/dev/null
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
    step "installing fzf (binary only)"
    git clone --depth 1 -q https://github.com/junegunn/fzf.git ~/.fzf
    # --bin, not --all: the installer's rc edits get overwritten by
    # phase_configs anyway. The shared zshrc gates on `command -v fzf`,
    # so all we owe it is the binary on PATH.
    ~/.fzf/install --bin >/dev/null
    ok "fzf binary built"
  fi
  # Outside the clone gate so a re-run heals installs from the --all era.
  mkdir -p "$HOME/.local/bin"
  ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
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
  local mise_bin
  mise_bin="$(command -v mise || echo "$HOME/.local/bin/mise")"
  if "$mise_bin" install; then
    ok "mise runtimes installed"
  else
    warn "mise install had failures"
  fi
}

# ─── phase 5 · configs ──────────────────────────────────────────────────────
phase_configs() {
  section "Phase 5/6 · configs"
  install_file "$CONFIGS_DIR/tmux.conf"           "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/ripgreprc"           "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"    "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$CONFIGS_DIR/starship.toml"       "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/zshrc"               "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"           "$HOME/.gitconfig"

  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-init.lua"       "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"    "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # Retired surfaces: the ws CLI was macOS-only all along (sigil), so the
  # old install block here shipped a binary and completions for a command
  # that can't work on Linux. Sweep the orphans off machines bootstrapped
  # from those versions (same convention as macos/bootstrap.sh).
  rm -f "$HOME/.local/bin/ws" "$HOME/.local/bin/workspace"
  rm -f "$HOME/.config/zsh/completions/_ws"
  rm -f "$HOME/.config/bash/completions/ws.bash"
  rm -f "$HOME/.config/workspace/cli/test-cascade.sh"

  ensure_gitconfig_local
}

# ─── phase 6 · default shell ────────────────────────────────────────────────
phase_default_shell() {
  section "Phase 6/6 · default shell"
  # ${VAR:-} guards: minimal environments (containers, cloud-init) run
  # without USER/SHELL exported, and set -u would abort right here.
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    step "setting login shell to zsh"
    sudo chsh -s "$(command -v zsh)" "${USER:-$(id -un)}" || warn "chsh failed; run manually"
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
