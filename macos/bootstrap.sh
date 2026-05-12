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

  step "installing JankyBorders (FelixKratz tap) — neon window borders"
  brew install --quiet FelixKratz/formulae/borders >/dev/null || true
  ok "borders"

  step "installing SketchyBar (FelixKratz tap) — workspace pill strip"
  brew install --quiet FelixKratz/formulae/sketchybar >/dev/null || true
  ok "sketchybar"

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
  install_file "$CONFIGS_DIR/hammerspoon-init.lua"             "$HOME/.hammerspoon/init.lua"
  install_file "$CONFIGS_DIR/hammerspoon-cheatsheet.lua"       "$HOME/.hammerspoon/cheatsheet.lua"
  install_file "$CONFIGS_DIR/hammerspoon-sketchybar-autohide.lua" "$HOME/.hammerspoon/sketchybar-autohide.lua"

  # SketchyBar workspace-pill strip. Replaced the Hammerspoon OSD that
  # used to flash on every space switch — pills are persistent and always
  # visible. Items, colours and the per-pill repaint plugin live under
  # configs/sketchybar/. brew service is started by workspace/install.sh.
  install_file "$CONFIGS_DIR/sketchybar/sketchybarrc"               "$HOME/.config/sketchybar/sketchybarrc"               755
  install_file "$CONFIGS_DIR/sketchybar/colors.sh"                  "$HOME/.config/sketchybar/colors.sh"
  install_file "$CONFIGS_DIR/sketchybar/plugins/space.sh"           "$HOME/.config/sketchybar/plugins/space.sh"           755
  install_file "$CONFIGS_DIR/sketchybar/plugins/recenter.sh"        "$HOME/.config/sketchybar/plugins/recenter.sh"        755
  install_file "$CONFIGS_DIR/sketchybar/plugins/per-display-pills.sh" "$HOME/.config/sketchybar/plugins/per-display-pills.sh" 755
  install_file "$CONFIGS_DIR/sketchybar/plugins/notch-detect.sh"    "$HOME/.config/sketchybar/plugins/notch-detect.sh"    755
  install_file "$CONFIGS_DIR/sketchybar/bootstrap.sh"               "$HOME/.config/sketchybar/bootstrap.sh"               755

  # Workspace-awareness layer: yabai signal handler + rename flow.
  # spaces.json is NOT install_file'd because that would clobber the
  # user's renames; workspace/install.sh below seeds it only when missing.
  install_file "$CONFIGS_DIR/workspace/on-space-changed.sh" "$HOME/.config/workspace/on-space-changed.sh" 755
  install_file "$CONFIGS_DIR/workspace/rename.sh"           "$HOME/.config/workspace/rename.sh"           755
  install_file "$CONFIGS_DIR/workspace/install.sh"          "$HOME/.config/workspace/install.sh"          755
  install_file "$CONFIGS_DIR/workspace/spaces.default.json" "$HOME/.config/workspace/spaces.default.json"

  # Terminal + shell
  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/starship.toml"              "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/starship.toml"              "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755

  # Workspace CLI: per-machine mutation tool for spaces.json. Slot-count
  # agnostic; works on Ubuntu too (cascade is silent-on-absence).
  install_file "$CONFIGS_DIR/workspace/cli/workspace"       "$HOME/.local/bin/workspace"                       755
  install_file "$CONFIGS_DIR/workspace/cli/test-cascade.sh" "$HOME/.config/workspace/cli/test-cascade.sh"      755

  # Workspace identity layer (10-slot system; details in configs/workspace/)
  install_file "$DOTFILES_DIR/lib/colors.sh"              "$HOME/.config/workspace/lib/colors.sh"
  install_file "$CONFIGS_DIR/workspace/spaces.default.json" "$HOME/.config/workspace/spaces.default.json"
  install_file "$CONFIGS_DIR/workspace/on-space-changed.sh" "$HOME/.config/workspace/on-space-changed.sh" 755
  install_file "$CONFIGS_DIR/workspace/reconcile-displays.sh" "$HOME/.config/workspace/reconcile-displays.sh" 755
  install_file "$CONFIGS_DIR/workspace/laptop-uuid-init.sh" "$HOME/.config/workspace/laptop-uuid-init.sh" 755
  install_file "$CONFIGS_DIR/workspace/rename.sh"         "$HOME/.config/workspace/rename.sh" 755
  install_file "$CONFIGS_DIR/borders/bordersrc"           "$HOME/.config/borders/bordersrc" 755
  bash "$CONFIGS_DIR/workspace/install.sh"

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

  # Workspace runtime: seeds spaces.json if missing, primes current.env,
  # nudges running daemons. Safe to re-run; preserves user renames.
  step "configuring workspace-awareness layer"
  "$HOME/.config/workspace/install.sh"
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
