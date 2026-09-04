#!/usr/bin/env bash
# Idempotent Ubuntu bootstrap (VPS / VM). No Hyperkey — shell + nvim only.
# Override dotfiles repo with DOTFILES_REPO=...

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 0 · sparse-checkout (idempotent, runs first) ─────────────────────
# Prune the working tree of macOS-only paths (ghostty, the macos/
# scripts, etc.) so a Linux clone only contains
# files this host actually uses. Manifest at lib/platform-manifest.sh
# is the single source of truth — see ubuntu/sparse-checkout.sh.
# Safe to run every bootstrap; no-ops when patterns are already current.
phase_sparse_checkout() {
  phase "sparse-checkout (prune macOS-only paths)"
  if [[ -x "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" ]]; then
    "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" 2>&1 | sed 's/^/    /' \
      || warn "sparse-checkout failed; continuing with full tree"
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
  phase "terminfo (xterm-ghostty)"
  if ! have tic; then
    step "installing ncurses-bin (provides tic)"
    sudo apt-get update -qq && sudo apt-get install -y ncurses-bin >/dev/null
  fi
  if [[ -f "$HOME/.terminfo/x/xterm-ghostty" ]]; then
    ok "xterm-ghostty already in ~/.terminfo — skipping"
  else
    step "compiling configs/xterm-ghostty.terminfo → ~/.terminfo"
    # run_quiet: tic emits an "older tic versions may treat the description
    # field as an alias" advisory on every single run. It's noise when the
    # compile succeeds and the whole story when it doesn't.
    if run_quiet "tic" tic -x -o "$HOME/.terminfo" "$CONFIGS_DIR/xterm-ghostty.terminfo"; then
      ok "xterm-ghostty installed (reconnect SSH or 'exec zsh' to pick up)"
    else
      warn "tic returned non-zero — entry may still be usable"
    fi
  fi
}

# ─── phase 2 · system packages ──────────────────────────────────────────────
phase_system() {
  phase "system packages"
  # `sudo apt-get update && sudo apt-get upgrade -y >/dev/null` bound the
  # redirect to `upgrade` only, so every run dumped ~19 raw "Get:" lines from
  # `update` and then hid the one line worth reading — how many packages
  # actually moved. Both now go through apt_quiet, which does the reverse.
  local upgrade_out held
  step "apt update + upgrade"
  sudo apt-get update 2>&1 | apt_quiet
  upgrade_out="$(sudo apt-get upgrade -y 2>&1)"
  printf '%s\n' "$upgrade_out" | apt_quiet
  ok "system packages upgraded"

  # "and N not upgraded" means apt held packages back (phased rollouts, or a
  # dependency it won't resolve automatically). That's a true, useful,
  # not-a-failure fact — exactly what note() is for. Zero maintenance: the
  # number comes from apt's own summary line.
  held="$(sed -nE 's/.*and ([0-9]+) not upgraded.*/\1/p' <<<"$upgrade_out" | head -1)"
  if [[ -n "${held:-}" ]] && (( held > 0 )); then
    note "$held package(s) held back by apt (see: apt list --upgradable)"
  fi

  step "installing apt packages"
  sudo apt-get install -y \
    git curl zsh build-essential direnv tmux htop neovim jq \
    ripgrep fd-find git-delta zoxide 2>&1 | apt_quiet
  ok "git zsh tmux neovim direnv jq ripgrep fd zoxide …"

  # Debian/Ubuntu calls fd "fdfind"; symlink for cross-OS parity.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "symlinked fdfind → ~/.local/bin/fd"
  fi

  if ! have gh; then
    step "adding GitHub CLI apt repo"
    curl --proto '=https' --tlsv1.2 -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq 2>&1 | apt_quiet
    sudo apt-get install -y gh 2>&1 | apt_quiet
    ok "gh installed"
  fi
}

# ─── phase 3 · shell layer ──────────────────────────────────────────────────
phase_shell() {
  phase "shell layer"
  if ! have starship; then
    step "installing Starship"
    # --proto '=https' --tlsv1.2: refuse any non-HTTPS redirect and any TLS
    # below 1.2. This is still pipe-to-shell — we trust starship.rs — but it
    # closes the downgrade path, and costs nothing to keep.
    run_quiet "starship installer" bash -c \
      "curl --proto '=https' --tlsv1.2 -sSf https://starship.rs/install.sh | sh -s -- --yes"
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
    # The installer downloads a release tarball with curl, whose progress
    # meter goes to stderr — `>/dev/null` never caught it.
    run_quiet "fzf installer" "$HOME/.fzf/install" --bin
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
  phase "runtimes"
  if ! have mise && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    step "installing mise"
    # Same story as fzf: mise.run's installer draws a progress bar on stderr.
    run_quiet "mise installer" bash -c \
      "curl --proto '=https' --tlsv1.2 -fsSL https://mise.run | sh"
    ok "mise installed"
  fi
  step "mise install (per ~/.tool-versions / .mise.toml)"
  local mise_bin
  mise_bin="$(command -v mise || echo "$HOME/.local/bin/mise")"
  if "$mise_bin" install 2>&1 | sed 's/^/    /'; then
    ok "mise runtimes installed"
  else
    warn "mise install had failures"
  fi
}

# ─── phase 5 · configs ──────────────────────────────────────────────────────
phase_configs() {
  phase "configs"
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
  phase "default shell"
  # ${VAR:-} guards: minimal environments (containers, cloud-init) run
  # without USER/SHELL exported, and set -u would abort right here.
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    step "setting login shell to zsh"
    sudo chsh -s "$(command -v zsh)" "${USER:-$(id -un)}" || warn "chsh failed; run manually"
    ok "default shell → zsh"
    note "log out / log in for the zsh shell change to apply"
  else
    ok "zsh already default shell"
  fi
}

# ─── entry ──────────────────────────────────────────────────────────────────
main() {
  section "Hyper-key dotfiles bootstrap (Ubuntu · minerva dev env)"
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  # Without this, tzdata's postinst opens an interactive "select your
  # geographic area" menu mid-install. In a container it auto-answered and
  # merely printed the menu; on a real VPS an unattended run can sit there
  # waiting for input forever. noninteractive takes the package defaults.
  export DEBIAN_FRONTEND=noninteractive

  # The list is the source of truth for both order and count — phase() reads
  # PHASE_TOTAL from it, so adding or reordering a phase needs no edits
  # anywhere else.
  local phases=(
    phase_sparse_checkout
    phase_terminfo
    phase_system
    phase_shell
    phase_runtimes
    phase_configs
    phase_default_shell
  )
  PHASE_TOTAL=${#phases[@]}
  local p
  for p in "${phases[@]}"; do "$p"; done

  # Ubuntu drops this file when a kernel or libc upgrade needs a restart to
  # take effect. On a VPS that's the difference between "patched" and
  # "patched after you reboot", and nothing else in the run would tell you.
  if [[ -f /var/run/reboot-required ]]; then
    note "reboot required to finish applying updates$(
      [[ -f /var/run/reboot-required.pkgs ]] &&
        printf ' (%s)' "$(tr '\n' ' ' < /var/run/reboot-required.pkgs | sed 's/ $//')"
    )"
  fi
  run_summary
}

main "$@"
