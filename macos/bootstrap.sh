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
  # Keepalive: refresh the sudo ticket every 50s so phases that shell out
  # to long-running tools (swift build, brew autoupdate) don't re-prompt.
  # `sudo -nv` is "validate or fail silently"; stderr is suppressed so
  # the "password is required" line from an expired ticket can't bleed
  # into concurrent build output. The loop exits cleanly once validation
  # starts failing — better to drop the keepalive than to spam errors.
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

  # AeroSpace (nikitabobko/tap/aerospace) is the window manager:
  # userspace, no SIP modification, no scripting addition. Replaces
  # yabai + skhd in one cask — aerospace ships its own keybinding daemon.
  step "installing aerospace (window manager)"
  brew install --quiet --cask nikitabobko/tap/aerospace >/dev/null || true
  ok "aerospace"

  step "workspace status bar (ws-statusbar) — built from Swift"
  # ws-statusbar replaces sketchybar for workspace pills
  # Built as part of topology install below
  ok "ws-statusbar (topology build)"

  # JetBrains Mono Nerd Font: required for the pill strip's PUA glyphs
  # (registered Core Text family is "JetBrainsMono Nerd Font"). Without
  # it, sketchybar falls back to a non-Nerd font and renders blank icons.
  step "installing JetBrains Mono Nerd Font (cask)"
  brew install --quiet --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 || true
  ok "font-jetbrains-mono-nerd-font"

  # orbstack replaces docker-desktop — leaner, native Apple Silicon, faster
  # cold start. If docker-desktop is installed, see the migration note in
  # README.md → "Switching from Docker Desktop".
  local casks="karabiner-elements ghostty raycast orbstack"
  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing GUI casks: $casks"
    # shellcheck disable=SC2086
    brew install --cask $casks 2>&1 | sed "s/^/    /" || true
    ok "casks installed (or already present)"
  else
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
    step "later: brew install --cask $casks"
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

# ─── phase 3 · apply configs + macOS defaults ───────────────────────────────
phase_apply() {
  section "Phase 3/4 · deploy configs & defaults"

  # Suppress the macOS login banner ("Last login: ...") that login(1)
  # prints into every new terminal. Empty file is the canonical opt-out.
  : > "$HOME/.hushlogin"

  # Window/keyboard
  install_file "$CONFIGS_DIR/karabiner.json"             "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/aerospace.toml"             "$HOME/.config/aerospace/aerospace.toml"
  # Clean up retired yabai / skhd surface. Idempotent: no-op once gone.
  # The new aerospace.toml is sentinel-fenced — sigil's `ws-topology
  # emit-aerospace --write` keeps the [mode.main.binding] block in sync
  # with spaces.json; the rest of aerospace.toml is hand-owned.
  rm -f "$HOME/.skhdrc"
  rm -f "$HOME/.yabairc"
  rm -rf "$HOME/.config/yabai"
  rm -rf "$HOME/.config/skhd"

  # Cheatsheet HUD content. Regenerated from @cs annotations in the
  # upstream config files (skhdrc, tmux.conf, nvim-init.lua, …) plus the
  # column→family layout. Generator failure is non-fatal: install_file
  # then deploys whatever cheatsheet.json is on disk (the committed
  # artifact acts as a safety net).
  step "regenerating workspace/cheatsheet.json from annotated configs"
  if python3 "$DOTFILES_DIR/lib/cheatsheet-gen.py" \
       --repo-root "$DOTFILES_DIR" \
       --layout    "$CONFIGS_DIR/workspace/cheatsheet-layout.json" \
       --out       "$CONFIGS_DIR/workspace/cheatsheet.json"; then
    ok "cheatsheet.json regenerated"
  else
    warn "cheatsheet generator failed; falling back to committed cheatsheet.json"
  fi
  install_file "$CONFIGS_DIR/workspace/cheatsheet.json"   "$HOME/.config/workspace/cheatsheet.json"

  # Workspace status bar (ws-statusbar) — native macOS status bar
  # No sketchybar configs needed; the Swift app manages its own display.
  # Clean up old sketchybar configs if present.
  rm -rf "$HOME/.config/sketchybar"

  # Workspace files are now installed from https://github.com/adames/sigil
  # (cloned and built in the workspace installation section below)
  # Retired: cleanup old workspace files that were previously installed directly
  rm -f "$HOME/.config/workspace/rename.sh"
  rm -f "$HOME/.local/bin/ws-info"
  rm -f "$HOME/.local/bin/ws-destroy-current"

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
  # `ws` is the canonical name; `workspace` is kept as a compat symlink
  # so older bindings and muscle-memory keep working.
  # Workspace CLI (ws) is installed by workspace repo's install.sh
  # which clones to ~/.config/workspace/ and builds the Swift binaries
  # ws-prompt overlay helpers (Caps+space focus, Caps+return send).
  # Shell completions for `ws` (and the `workspace` alias).
  # Note: The `ws` binary is installed by workspace repo's install.sh
  # These completions work with the workspace CLI.
  install_file "$CONFIGS_DIR/completions/_ws"               "$HOME/.config/zsh/completions/_ws"
  install_file "$CONFIGS_DIR/completions/ws.bash"           "$HOME/.config/bash/completions/ws.bash"

  # Workspace identity layer. AeroSpace owns existence (declared in
  # ~/.config/aerospace/aerospace.toml as [workspace-to-monitor-force-
  # assignment]); spaces.json layers optional name/color/icon on top.
  # Default ships empty — pills show bare "ws1", "ws2", etc. until you
  # `ws name N <name>`.
  # Workspace files are now installed from https://github.com/adames/sigil
  # Retired file cleanup:
  rm -f "$HOME/.config/workspace/borders-refresh.sh"
  rm -f "$HOME/.config/workspace/lib/colors.sh"
  rm -f "$HOME/.config/workspace/reconcile-displays.sh"
  rm -f "$HOME/.config/workspace/laptop-uuid-init.sh"
  rm -f "$HOME/.config/workspace/laptop.uuid"
  # Note: ws-doctor and ws-dir remain in dotfiles bin/ as general utilities
  # Clean up legacy sketchybar-related files
  rm -f "$HOME/.config/workspace/sketchybar-tuning.env"
  # Retired: ~/.config/borders/ (JankyBorders removed). Clean up if
  # present from older deploys.
  rm -rf "$HOME/.config/borders"
  # (workspace/install.sh runs once at the end of this phase from the
  # deployed copy — see "configuring workspace-awareness layer" below.
  # Earlier this block called it twice, which printed every reload
  # banner twice.)

  # Workspace: install from separate repository (extracted from dotfiles)
  # https://github.com/adames/sigil
  # Clones to ~/.config/workspace/ and builds Swift binaries.
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
    # Optional: pull latest changes (disabled by default for stability)
    # (cd "$HOME/.config/workspace" && git pull --ff-only) || true
  fi

  # Build and install workspace binaries if Swift is available
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

  # Editor — lazy.nvim self-installs on first nvim launch
  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  mkdir -p "$HOME/.config/nvim/after/plugin"
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

  # Workspace runtime configuration: seeds spaces.json if missing,
  # primes current.env, nudges running daemons. Safe to re-run.
  step "configuring workspace runtime"
  if [[ -f "$HOME/.config/workspace/install.sh" ]]; then
    # Re-run install.sh to ensure everything is properly configured
    bash "$HOME/.config/workspace/install.sh" || warn "workspace runtime config had issues"
  fi

  # macOS defaults (folded into apply phase). AeroSpace requires the
  # opposite of yabai here: `displays-have-separate-spaces` must stay on
  # (the macOS default), and `spans-displays` is irrelevant because
  # AeroSpace stacks every workspace on Space 1 of each monitor and
  # show/hides windows itself.
}

# ─── phase 4 · permission wizard ────────────────────────────────────────────
phase_wizard() {
  section "Phase 4/4 · permission wizard"
  step "handing off to permissions-wizard.sh"
  exec "$DOTFILES_DIR/macos/permissions-wizard.sh"
}

# ─── entry ──────────────────────────────────────────────────────────────────
main() {
  section "Hyper-key dotfiles bootstrap (macOS)"
  phase_sudo
  phase_packages
  phase_apply    # configs + defaults combined
  phase_wizard   # exec-replaces
}

main "$@"
