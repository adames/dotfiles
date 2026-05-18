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
    git zsh tmux neovim direnv jq starship fzf \
    ripgrep fd git-delta zoxide gh lazygit \
    zsh-autosuggestions zsh-syntax-highlighting >/dev/null
  ok "shell + dev tools (rg, fd, delta, zoxide, gh, lazygit, …)"

  step "installing yabai + skhd (koekeishiya tap)"
  brew install --quiet koekeishiya/formulae/yabai >/dev/null || true
  brew install --quiet koekeishiya/formulae/skhd  >/dev/null || true
  ok "yabai + skhd"

  step "installing SketchyBar (FelixKratz tap) — workspace pill strip"
  brew install --quiet FelixKratz/formulae/sketchybar >/dev/null || true
  ok "sketchybar"

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

# ─── phase 3 · apply configs + macOS defaults ───────────────────────────────
phase_apply() {
  section "Phase 3/4 · deploy configs & defaults"

  # Suppress the macOS login banner ("Last login: ...") that login(1)
  # prints into every new terminal. Empty file is the canonical opt-out.
  : > "$HOME/.hushlogin"

  # Window/keyboard
  install_file "$CONFIGS_DIR/karabiner.json"             "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/skhdrc"                     "$HOME/.skhdrc"
  install_file "$CONFIGS_DIR/yabairc"                    "$HOME/.yabairc"             755
  # Clean up retired manipulation scripts. yabai-ensure-spaces.sh,
  # reconcile-displays.sh, laptop-uuid-init.sh, and lib/colors.sh
  # all enforced a fixed slot count + per-display routing via labels.
  # Retired: yabai owns existence (Mission Control runs it), spaces.json
  # owns optional identity. Idempotent: no-op once gone.
  rm -f "$HOME/.config/yabai/ensure-spaces.sh"
  # Hammerspoon is retired. ws-autohide (configs/workspace/topology/Sources/
  # ws-autohide) is the launchd-managed SketchyBar autohide poller, ws-snap
  # is an AX absolute-snap CLI (not bound to a chord today; new windows
  # are auto-staged via stage-window.sh from the yabai window_created
  # signal), and skhd owns the rest of what used to live in
  # hammerspoon-init.lua. The cheatsheet HUD is the SwiftUI
  # ws-cheatsheet — all reachable via the topology Swift package below.

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

  # SketchyBar workspace-pill strip. Persistent workspace indicator,
  # always visible. Items, colours and plugins live under
  # configs/sketchybar/. brew service is started by workspace/install.sh.
  # Per-display autohide is owned by ws-autohide (Swift launchd agent).
  # paint-all.sh is the centralized batched-repaint plugin subscribed
  # via the workspace.paint sentinel item in sketchybarrc.
  install_file "$CONFIGS_DIR/sketchybar/sketchybarrc"               "$HOME/.config/sketchybar/sketchybarrc"               755
  install_file "$CONFIGS_DIR/sketchybar/colors.sh"                  "$HOME/.config/sketchybar/colors.sh"
  install_file "$CONFIGS_DIR/sketchybar/plugins/paint-all.sh"       "$HOME/.config/sketchybar/plugins/paint-all.sh"       755
  install_file "$CONFIGS_DIR/sketchybar/plugins/per-display-pills.sh" "$HOME/.config/sketchybar/plugins/per-display-pills.sh" 755
  install_file "$CONFIGS_DIR/sketchybar/plugins/clock.sh"           "$HOME/.config/sketchybar/plugins/clock.sh"           755
  install_file "$CONFIGS_DIR/sketchybar/bootstrap.sh"               "$HOME/.config/sketchybar/bootstrap.sh"               755
  # Clean up plugins retired across recent refactors:
  # space.sh (per-pill renderer; replaced by paint-all.sh sentinel),
  # recenter.sh (split-around-notch geometry; left-aligned now),
  # notch-detect.sh (gated a visibility cap that's now gone),
  # ssh-chip.sh (outbound-SSH presence chip; removed as complexity).
  # Idempotent: no-op once gone.
  rm -f "$HOME/.config/sketchybar/plugins/space.sh"
  rm -f "$HOME/.config/sketchybar/plugins/recenter.sh"
  rm -f "$HOME/.config/sketchybar/plugins/notch-detect.sh"
  rm -f "$HOME/.config/sketchybar/plugins/ssh-chip.sh"

  # Workspace-awareness layer: yabai signal handler + window staging.
  # spaces.json is NOT install_file'd because that would clobber the
  # user's renames; workspace/install.sh below seeds it only when missing.
  install_file "$CONFIGS_DIR/workspace/on-space-changed.sh"   "$HOME/.config/workspace/on-space-changed.sh"   755
  install_file "$CONFIGS_DIR/workspace/on-space-created.sh"   "$HOME/.config/workspace/on-space-created.sh"   755
  install_file "$CONFIGS_DIR/workspace/on-space-destroyed.sh" "$HOME/.config/workspace/on-space-destroyed.sh" 755
  install_file "$CONFIGS_DIR/workspace/stage-window.sh"       "$HOME/.config/workspace/stage-window.sh"       755
  install_file "$CONFIGS_DIR/workspace/install.sh"          "$HOME/.config/workspace/install.sh"          755
  install_file "$CONFIGS_DIR/workspace/spaces.default.json" "$HOME/.config/workspace/spaces.default.json"
  # Retired: rename.sh / ws-info / ws-destroy-current were dispatch
  # targets for the original (broken) manage palette. The new ws-prompt
  # manage overlay calls `ws name` / `ws remove` / `ws doctor` directly,
  # so the shims are dead. Clean up older deploys.
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
  install_file "$CONFIGS_DIR/workspace/cli/ws"              "$HOME/.local/bin/ws"                              755
  ln -sf "ws" "$HOME/.local/bin/workspace"
  install_file "$CONFIGS_DIR/workspace/cli/test-cascade.sh" "$HOME/.config/workspace/cli/test-cascade.sh"      755
  # ws-prompt overlay helpers (Caps+space focus, Caps+return send).
  # Wrap raw yabai calls with existence checks + loud failure
  # notifications so the focus/send prompts never silently no-op.
  install_file "$CONFIGS_DIR/workspace/cli/ws-focus"            "$HOME/.local/bin/ws-focus"            755
  install_file "$CONFIGS_DIR/workspace/cli/ws-send-follow"      "$HOME/.local/bin/ws-send-follow"      755
  # Shell completions for `ws` (and the `workspace` alias). zshrc adds
  # ~/.config/zsh/completions to fpath; bashrc (if present) sources
  # ~/.config/bash/completions/ws.bash.
  install_file "$CONFIGS_DIR/completions/_ws"               "$HOME/.config/zsh/completions/_ws"
  install_file "$CONFIGS_DIR/completions/ws.bash"           "$HOME/.config/bash/completions/ws.bash"

  # Workspace identity layer. yabai owns existence (which spaces, on
  # which display) via macOS / Mission Control; spaces.json layers
  # optional name/color/icon on top. Default ships empty — pills show
  # bare "ws1", "ws2", etc. until you `ws name N <name>`.
  install_file "$CONFIGS_DIR/workspace/spaces.default.json" "$HOME/.config/workspace/spaces.default.json"
  install_file "$CONFIGS_DIR/workspace/on-space-changed.sh"   "$HOME/.config/workspace/on-space-changed.sh"   755
  install_file "$CONFIGS_DIR/workspace/on-space-created.sh"   "$HOME/.config/workspace/on-space-created.sh"   755
  install_file "$CONFIGS_DIR/workspace/on-space-destroyed.sh" "$HOME/.config/workspace/on-space-destroyed.sh" 755
  # Retired: borders-refresh.sh — JankyBorders removed. Clean up if
  # present from older deploys.
  rm -f "$HOME/.config/workspace/borders-refresh.sh"
  # Retired with the "yabai owns existence" refactor — cleanup if
  # present from older deploys.
  rm -f "$HOME/.config/workspace/lib/colors.sh"
  rm -f "$HOME/.config/workspace/reconcile-displays.sh"
  rm -f "$HOME/.config/workspace/laptop-uuid-init.sh"
  rm -f "$HOME/.config/workspace/laptop.uuid"
  install_file "$CONFIGS_DIR/workspace/lib/resolve-config.sh" "$HOME/.config/workspace/lib/resolve-config.sh"
  install_file "$CONFIGS_DIR/workspace/lib/icon-decode.sh"  "$HOME/.config/workspace/lib/icon-decode.sh"
  install_file "$CONFIGS_DIR/workspace/lib/hex-ansi.sh"     "$HOME/.config/workspace/lib/hex-ansi.sh"
  install_file "$CONFIGS_DIR/workspace/lib/sf-to-nerd.json" "$HOME/.config/workspace/lib/sf-to-nerd.json"
  install_file "$CONFIGS_DIR/workspace/hooks/post-mutate.sh" "$HOME/.config/workspace/hooks/post-mutate.sh" 755
  # ws-launch-*: auto-detect the user's preferred terminal / browser /
  # notes / inbox app and open it. No hardcoded app names; override with
  # $WS_TERMINAL_APP / $WS_BROWSER_APP / $WS_NOTES_APP / $WS_INBOX_APP
  # (or $WS_INBOX_VAULT). Wired to Caps+t / Caps+b / Caps+q / Caps+Shift+q
  # in skhdrc.
  install_file "$CONFIGS_DIR/workspace/launch-terminal.sh"  "$HOME/.local/bin/ws-launch-terminal"             755
  install_file "$CONFIGS_DIR/workspace/launch-browser.sh"   "$HOME/.local/bin/ws-launch-browser"              755
  install_file "$CONFIGS_DIR/workspace/launch-notes.sh"     "$HOME/.local/bin/ws-launch-notes"                755
  install_file "$CONFIGS_DIR/workspace/launch-inbox.sh"     "$HOME/.local/bin/ws-launch-inbox"                755
  # ws-doctor: keymap / launcher health check. Catches keystroke-injection
  # collisions, source/deploy drift, broken menu-item refs, stale skhd.
  install_file "$DOTFILES_DIR/bin/ws-doctor"                "$HOME/.local/bin/ws-doctor"                       755
  # ws-dir: direction-aware Caps+hjkl. Floating → ws-snap; tiled →
  # yabai --window --focus. Single source of truth for the float/tile
  # branch so skhdrc rows stay one-liners.
  install_file "$DOTFILES_DIR/bin/ws-dir"                   "$HOME/.local/bin/ws-dir"                          755
  # Clean up the notch-padding tuning env retired by the left-aligned
  # navbar refactor. The file had user edits, but the only consumer
  # (recenter.sh) is gone — nothing reads it now. Idempotent.
  rm -f "$HOME/.config/workspace/sketchybar-tuning.env"
  # Retired: ~/.config/borders/ (JankyBorders removed). Clean up if
  # present from older deploys.
  rm -rf "$HOME/.config/borders"
  # (workspace/install.sh runs once at the end of this phase from the
  # deployed copy — see "configuring workspace-awareness layer" below.
  # Earlier this block called it twice, which printed every reload
  # banner twice.)

  # Native display-topology helper (ws-topology / ws-topologyd). Source
  # tree is vendored under configs/workspace/topology/. The package's own
  # install.sh builds + symlinks the binaries into ~/.local/bin and loads
  # the LaunchAgent. swift toolchain is required (ships with Command Line
  # Tools); if absent, the shell adapters fall back to legacy heuristics.
  if [[ -d "$CONFIGS_DIR/workspace/topology" ]]; then
    step "syncing topology Swift package source"
    rsync -a --delete-after \
      --exclude='.build' --exclude='Package.resolved' --exclude='.swiftpm' --exclude='.DS_Store' \
      "$CONFIGS_DIR/workspace/topology/" "$HOME/.config/workspace/topology/"
    if command -v swift >/dev/null 2>&1; then
      # Capture the exit code so the permissions wizard can adjust its
      # ws-snap prompt and print a follow-up block at the end. install.sh
      # exits 2 specifically for "CLT version-skewed" — both that and any
      # other build failure mean ws-snap (et al.) won't exist on this run.
      if ! bash "$HOME/.config/workspace/topology/install.sh"; then
        warn "topology install.sh failed (binaries may be stale or missing)"
        export BOOTSTRAP_TOPOLOGY_FAILED=1
      fi
    else
      warn "swift toolchain not found — topology daemon will not be built;"
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

  # Workspace runtime: seeds spaces.json if missing, primes current.env,
  # nudges running daemons. Safe to re-run; preserves user renames.
  step "configuring workspace-awareness layer"
  "$HOME/.config/workspace/install.sh"

  # macOS defaults (folded into apply phase)
  if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]]; then
    step "spans-displays → false (yabai requirement)"
    defaults write com.apple.spaces spans-displays -bool false
    ok "logout required to take effect"
  fi
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
