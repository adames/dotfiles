#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture + migration history: docs/architecture.md.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 1 · sudo ─────────────────────────────────────────────────────────
phase_sudo() {
  section "Phase 1/4 · sudo"
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
  section "Phase 2/4 · packages"

  if ! have brew; then
    step "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    ok "Homebrew installed"
  fi

  step "installing CLI formulae"
  brew install --quiet \
    git zsh tmux direnv starship fzf \
    ripgrep fd git-delta zoxide gh lazygit \
    yazi \
    pyright ruff \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null
  ok "shell + dev tools (rg, fd, delta, zoxide, gh, lazygit, yazi, pyright, ruff …)"

  step "installing aerospace (window manager)"
  brew install --quiet --cask nikitabobko/tap/aerospace >/dev/null || true
  ok "aerospace"

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
  for app in /Applications/AeroSpace.app /Applications/Hyperkey.app /Applications/Helium.app; do
    [[ -d "$app" ]] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  done

  seed_hyperkey_defaults
}

# Seed Hyperkey (Caps→Hyper, tap-for-Esc). v1.56 reads from the bundle-id
# domain `com.knollsoft.Hyperkey` with the keys below; an older build (the
# one f17cf62 patched against) read from the plain `Hyperkey` domain with
# enableHyperKey/tapForEscape — those don't exist in v1.56, so the prior
# seeding was a no-op and every caps chord died until the user opened
# Hyperkey and re-toggled the switches by hand. Hyperkey rewrites its
# prefs on quit, so the write order matters: quit → write → relaunch.
# Idempotent.
seed_hyperkey_defaults() {
  [[ -d /Applications/Hyperkey.app ]] || return 0
  local domain="com.knollsoft.Hyperkey" ver
  ver=$(defaults read /Applications/Hyperkey.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo '?')
  step "seeding Hyperkey ($domain · v$ver)"

  osascript -e 'tell application "Hyperkey" to quit' 2>/dev/null || true
  # Give the prefs flush a beat before we overwrite.
  sleep 1

  # Caps→Hyper (capsLockRemapped=2, keyRemap=1), Hyper = ⌃⌥⌘⇧
  # (hyperFlags=1966080), tap-for-Esc on (executeQuickHyperKey=1) with
  # keycode 53 (kVK_Escape).
  defaults write "$domain" capsLockRemapped     -int  2
  defaults write "$domain" keyRemap             -int  1
  defaults write "$domain" hyperFlags           -int  1966080
  defaults write "$domain" quickHyperKeycode    -int  53
  defaults write "$domain" executeQuickHyperKey -int  1
  defaults write "$domain" launchOnLogin        -int  1

  # Relaunch in the background so the daemon picks up the seeded prefs
  # without stealing focus.
  open -ga Hyperkey 2>/dev/null || true
  ok "Hyperkey seeded (caps→hyper, tap-for-esc)"
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

  # Regenerate the cheatsheet HUD from @cs annotations via rune
  # (https://github.com/adames/rune — the generalized successor to the old
  # lib/cheatsheet-gen.py). Layout + sources live in workspace/rune.toml;
  # vim-motion/vim-edit are @cs blocks in nvim-init.lua now, not a fallback.
  step "regenerating workspace/cheatsheet.json (rune)"
  if ! command -v rune >/dev/null 2>&1; then
    step "installing rune (pip)"
    python3 -m pip install --user --quiet "git+https://github.com/adames/rune" \
      || warn "rune install failed — will fall back to the last committed cheatsheet.json"
  fi
  if command -v rune >/dev/null 2>&1 \
       && rune -c "$CONFIGS_DIR/workspace/rune.toml" build \
            -o "$CONFIGS_DIR/workspace/cheatsheet.json"; then
    ok "cheatsheet.json regenerated"
    install_file "$CONFIGS_DIR/workspace/cheatsheet.json" "$HOME/.config/workspace/cheatsheet.json"
  elif [[ -f "$CONFIGS_DIR/workspace/cheatsheet.json" ]]; then
    warn "rune unavailable/failed; installing the last committed cheatsheet.json"
    install_file "$CONFIGS_DIR/workspace/cheatsheet.json" "$HOME/.config/workspace/cheatsheet.json"
  else
    warn "no cheatsheet artifact available; leaving $HOME/.config/workspace/cheatsheet.json untouched"
  fi

  # Retired surfaces: sketchybar / yabai-era workspace scripts / borders.
  # Plus the dotfiles workspace helpers dropped with the sigil teardown
  # (replaced by native AeroSpace bindings — see docs/sigil-teardown.md).
  rm -f "$HOME/.local/bin/ws-dir"
  rm -f "$HOME/.local/bin/ws-grid"
  rm -f "$HOME/.local/bin/ws-launch-here"
  rm -f "$HOME/.local/bin/ws-mouse-follow"
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
  install_file "$CONFIGS_DIR/CLAUDE.md"                  "$HOME/.claude/CLAUDE.md"
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$DOTFILES_DIR/bin/ws-doctor"             "$HOME/.local/bin/ws-doctor" 755
  install_file "$DOTFILES_DIR/bin/ws-tmux-prefix"        "$HOME/.local/bin/ws-tmux-prefix" 755
  install_file "$CONFIGS_DIR/completions/_ws"            "$HOME/.config/zsh/completions/_ws"

  # Sigil clones to ~/.config/workspace/ and its install.sh builds +
  # symlinks the ws-* binaries into ~/.local/bin/. Post-teardown (see
  # docs/sigil-teardown.md) only ws-cheatsheet is wired to a chord
  # (Caps+/ HUD); sigil survives as that overlay renderer. install.sh
  # still builds the rest — trimming it is a deferred sigil-repo change.
  if [[ ! -d "$HOME/.config/workspace/.git" ]]; then
    step "installing workspace from https://github.com/adames/sigil"
    if command -v git >/dev/null 2>&1; then
      git clone --depth 1 https://github.com/adames/sigil.git "$HOME/.config/workspace"
      ok "workspace cloned"
    else
      warn "git not found — skipping workspace install"
      export BOOTSTRAP_SIGIL_BUILD_FAILED=1
    fi
  else
    step "workspace already installed at ~/.config/workspace/"
  fi

  if [[ -f "$HOME/.config/workspace/install.sh" ]]; then
    if command -v swift >/dev/null 2>&1; then
      step "building workspace (Swift toolchain found)"
      if ! bash "$HOME/.config/workspace/install.sh"; then
        warn "workspace install.sh failed (binaries may be stale or missing)"
        export BOOTSTRAP_SIGIL_BUILD_FAILED=1
      fi
    else
      warn "swift toolchain not found — workspace binaries will not be built;"
      warn "  install via 'xcode-select --install', then re-run this bootstrap"
      export BOOTSTRAP_SIGIL_BUILD_FAILED=1
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

  # Retry heals transient launchctl EIO from the first install.sh. Only
  # runs when the first pass failed — on a clean install the gate skips
  # a ~1.5s swift build + relink + launchctl reload that was duplicating
  # work.
  if [[ -n "${BOOTSTRAP_SIGIL_BUILD_FAILED:-}" && -f "$HOME/.config/workspace/install.sh" ]]; then
    step "retrying workspace runtime (first pass failed)"
    if bash "$HOME/.config/workspace/install.sh"; then
      unset BOOTSTRAP_SIGIL_BUILD_FAILED
    else
      warn "workspace runtime retry also failed"
    fi
  fi

  # Workspace digit bindings are now hand-written in aerospace.toml — the
  # ws-topology emit-aerospace step was removed with the sigil workspace
  # layer (see docs/sigil-teardown.md). aerospace.toml is the source of
  # truth; reload picks it up on next login or `aerospace reload-config`.
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
