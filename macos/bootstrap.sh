#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture + migration history: docs/architecture.md.

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
  # Keepalive — refresh every 50s so long shell-outs don't re-prompt.
  ( while sudo -nv 2>/dev/null; do
      sleep 50
      kill -0 "$$" 2>/dev/null || exit
    done ) &
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
    git zsh tmux neovim direnv starship fzf \
    ripgrep fd git-delta zoxide gh lazygit \
    pyright ruff \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null
  ok "shell + dev tools (rg, fd, delta, zoxide, gh, lazygit, pyright, ruff …)"

  step "installing aerospace (window manager)"
  brew install --quiet --cask nikitabobko/tap/aerospace >/dev/null || true
  ok "aerospace"

  step "workspace status bar (ws-statusbar) — built from Swift"
  ok "ws-statusbar (topology build)"

  # JetBrains Mono Nerd Font supplies the pill-strip PUA glyphs.
  step "installing JetBrains Mono Nerd Font (cask)"
  brew install --quiet --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 || true
  ok "font-jetbrains-mono-nerd-font"

  local casks="hyperkey ghostty raycast orbstack"
  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing GUI casks: $casks"
    # shellcheck disable=SC2086
    brew install --cask $casks 2>&1 | sed "s/^/    /" || true
    ok "casks installed (or already present)"
  else
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
    step "later: brew install --cask $casks"
  fi

  # Strip Gatekeeper quarantine so scripted `open -a` works pre-launch.
  for app in /Applications/AeroSpace.app /Applications/Hyperkey.app; do
    [[ -d "$app" ]] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  done

  # Seed Hyperkey defaults (Caps→Hyper, tap-for-Esc). Idempotent.
  if [[ -d /Applications/Hyperkey.app ]]; then
    defaults write Hyperkey enableHyperKey -bool true 2>/dev/null || true
    defaults write Hyperkey tapForEscape   -bool true 2>/dev/null || true
  fi
}

# ─── phase 3 · apply configs + macOS defaults ───────────────────────────────
phase_apply() {
  section "Phase 3/4 · deploy configs & defaults"

  : > "$HOME/.hushlogin"

  install_file "$CONFIGS_DIR/aerospace.toml"             "$HOME/.config/aerospace/aerospace.toml"

  # Stop legacy services BEFORE deleting their configs — otherwise
  # Karabiner's grabber can wedge the input system on its way out.
  for svc in yabai skhd; do
    if brew services list 2>/dev/null | grep -q "^$svc.*started"; then
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

  # Cheatsheet HUD content is hand-maintained in the sigil repo. Install
  # it straight from there; if the sigil checkout isn't present we skip
  # rather than synthesize stale content.
  if [[ -f "$HOME/code/sigil/cheatsheet.json" ]]; then
    install_file "$HOME/code/sigil/cheatsheet.json" "$HOME/.config/workspace/cheatsheet.json"
  else
    warn "sigil checkout not found; leaving $HOME/.config/workspace/cheatsheet.json untouched"
  fi

  # Retired surfaces: sketchybar / yabai-era workspace scripts / borders.
  rm -rf "$HOME/.config/sketchybar"
  rm -f "$HOME/.config/workspace/rename.sh"
  rm -f "$HOME/.local/bin/ws-info"
  rm -f "$HOME/.local/bin/ws-destroy-current"
  rm -f "$HOME/.config/workspace/borders-refresh.sh"
  rm -f "$HOME/.config/workspace/lib/colors.sh"
  rm -f "$HOME/.config/workspace/reconcile-displays.sh"
  rm -f "$HOME/.config/workspace/laptop-uuid-init.sh"
  rm -f "$HOME/.config/workspace/laptop.uuid"
  rm -f "$HOME/.config/workspace/sketchybar-tuning.env"
  rm -rf "$HOME/.config/borders"

  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/starship.toml"              "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$CONFIGS_DIR/completions/_ws"            "$HOME/.config/zsh/completions/_ws"
  install_file "$CONFIGS_DIR/completions/ws.bash"        "$HOME/.config/bash/completions/ws.bash"

  # Sigil (workspace identity layer + ws-* binaries) clones to
  # ~/.config/workspace/. Its install.sh builds + symlinks into
  # ~/.local/bin/ and registers LaunchAgents.
  if [[ ! -d "$HOME/.config/workspace/.git" ]]; then
    step "installing workspace from https://github.com/adames/sigil"
    if command -v git >/dev/null 2>&1; then
      git clone --depth 1 https://github.com/adames/sigil.git "$HOME/.config/workspace"
      ok "workspace cloned"
    else
      warn "git not found — skipping workspace install"
      export BOOTSTRAP_TOPOLOGY_FAILED=1
    fi
  else
    step "workspace already installed at ~/.config/workspace/"
  fi

  if [[ -f "$HOME/.config/workspace/install.sh" ]]; then
    if command -v swift >/dev/null 2>&1; then
      step "building workspace (Swift toolchain found)"
      if ! bash "$HOME/.config/workspace/install.sh"; then
        warn "workspace install.sh failed (binaries may be stale or missing)"
        export BOOTSTRAP_TOPOLOGY_FAILED=1
      fi
    else
      warn "swift toolchain not found — workspace binaries will not be built;"
      warn "  install via 'xcode-select --install', then re-run this bootstrap"
      export BOOTSTRAP_TOPOLOGY_FAILED=1
    fi
  fi

  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"           "$HOME/.config/nvim/after/plugin/keymaps.lua"

  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
    ok "created ~/.gitconfig.local stub — edit user.email / user.name"
  fi

  # Second pass heals transient launchctl EIO from the first install.sh.
  # On success, clear the failure flag the wizard reads.
  step "configuring workspace runtime"
  if [[ -f "$HOME/.config/workspace/install.sh" ]]; then
    if bash "$HOME/.config/workspace/install.sh"; then
      unset BOOTSTRAP_TOPOLOGY_FAILED
    else
      warn "workspace runtime config had issues"
    fi
  fi

  # Populate the sigil-fenced workspace blocks in aerospace.toml from
  # spaces.json. Without this, Caps+1..0 silently do nothing.
  if command -v "$HOME/.local/bin/ws-topology" >/dev/null 2>&1; then
    step "emitting workspace digit bindings (ws-topology emit-aerospace)"
    "$HOME/.local/bin/ws-topology" emit-aerospace --write --validate --reload \
      || warn "emit-aerospace failed — Caps+1..0 chords may be unbound until you re-run it"
  fi
}

# ─── phase 4 · permission wizard ────────────────────────────────────────────
phase_wizard() {
  section "Phase 4/4 · permission wizard"
  step "handing off to permissions-wizard.sh"
  exec "$DOTFILES_DIR/macos/permissions-wizard.sh"
}

main() {
  section "Hyper-key dotfiles bootstrap (macOS)"
  phase_sudo
  phase_packages
  phase_apply
  phase_wizard
}

main "$@"
