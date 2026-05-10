#!/usr/bin/env bash
# Cross-platform bootstrap: macOS Hyper-key keybinding scheme + Ubuntu dev env.
# Idempotent. Backs up any pre-existing config to <file>.bak on first run.

set -euo pipefail

# ---- locations ---------------------------------------------------------------
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
CONFIGS_DIR="$DOTFILES_DIR/configs"

# ---- logging -----------------------------------------------------------------
log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- helpers -----------------------------------------------------------------
# Whether the current shell has a controlling TTY (interactive). Cask installs
# and password prompts require this; we degrade gracefully when missing.
has_tty() { [[ -t 0 && -t 1 ]]; }

# Backup once: only if dst exists, isn't a symlink, and no prior .bak. If a
# src is provided and dst already matches it, skip — we'd just be creating a
# useless duplicate of a config we already installed on a previous run.
backup() {
  local dst="$1" src="${2:-}"
  [[ -e "$dst" && ! -L "$dst" && ! -e "$dst.bak" ]] || return 0
  if [[ -n "$src" && -f "$src" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  cp -p "$dst" "$dst.bak"
  log "backed up $dst -> $dst.bak"
}

# Install src -> dst, creating parent dirs and backing up first time only when
# the existing dst is something other than our canonical src.
install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [[ ! -f "$src" ]]; then
    warn "skip $dst (source $src not present)"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  backup "$dst" "$src"
  # Skip the install entirely if dst already matches src — keeps logs quiet
  # on no-op re-runs.
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  install -m "$mode" "$src" "$dst"
  log "installed $dst"
}

ensure_dir() { mkdir -p "$1"; }

# ---- macOS permission helpers ------------------------------------------------
# Open System Settings (or older System Preferences) to a specific privacy pane.
# Pane names: Privacy_Accessibility, Privacy_InputMonitoring, Privacy_AllFiles.
mac_open_privacy_pane() {
  local pane="${1:-Privacy_Accessibility}"
  open "x-apple.systempreferences:com.apple.preference.security?$pane" 2>/dev/null || true
}

# Probe yabai status. Return codes:
#   0 = running OK
#   1 = not running, unknown reason
#   2 = not running, missing Accessibility
#   3 = not running, "Displays have separate Spaces" disabled (needs logout)
mac_yabai_status() {
  local logf="/tmp/yabai_$(id -un).err.log"
  local pid
  pid=$(launchctl list 2>/dev/null | awk '$3=="com.asmvik.yabai"{print $1}')
  if [[ "$pid" =~ ^[0-9]+$ && "$pid" != "0" ]]; then
    return 0
  fi
  if [[ -f "$logf" ]]; then
    # Look at only the LAST line (most recent abort reason) — earlier lines
    # may reflect issues that have since been fixed.
    local last
    last=$(tail -1 "$logf" 2>/dev/null)
    if grep -q "could not access accessibility" <<<"$last"; then return 2; fi
    if grep -q "display has separate spaces"     <<<"$last"; then return 3; fi
  fi
  return 1
}

# Probe skhd status. Return codes match yabai's accessibility variant:
#   0 = running, 1 = not running unknown, 2 = missing Accessibility.
mac_skhd_status() {
  local logf="/tmp/skhd_$(id -un).err.log"
  local pid
  pid=$(launchctl list 2>/dev/null | awk '$3=="com.koekeishiya.skhd"{print $1}')
  if [[ "$pid" =~ ^[0-9]+$ && "$pid" != "0" ]]; then
    return 0
  fi
  if [[ -f "$logf" ]] && tail -1 "$logf" 2>/dev/null \
       | grep -q "must be run with accessibility access"; then
    return 2
  fi
  return 1
}

# Interactive: open the Accessibility pane and wait for the user to confirm.
# No-op (with warning) when no TTY — the caller will surface a final summary.
mac_prompt_accessibility() {
  local who="$1"   # human-readable list of apps
  if ! has_tty; then
    warn "no TTY — cannot prompt; grant Accessibility manually to: $who"
    warn "  open: x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    return 1
  fi
  mac_open_privacy_pane Privacy_Accessibility
  cat >&2 <<EOF

>>> System Settings was opened to Privacy & Security → Accessibility.
    Enable: $who
    Then return to this terminal and press Enter (or Ctrl-C to skip).
EOF
  read -r _ </dev/tty
}

# ---- macOS bootstrap ---------------------------------------------------------
bootstrap_macos() {
  log "macOS detected — applying Hyper-key keybinding scheme"

  # Cask installs spawn `sudo /usr/sbin/installer` and prompt on the
  # controlling terminal. Without a TTY (e.g. running via an SSH non-tty or a
  # headless tool), those prompts go nowhere and the script hangs.
  if ! has_tty; then
    warn "no TTY detected — cask installs (Karabiner, Hammerspoon, Rectangle)"
    warn "and Accessibility prompts will be skipped. Re-run from a real terminal"
    warn "to install GUI apps, or set BOOTSTRAP_SKIP_CASKS=1 to silence this."
  fi

  # ---- Homebrew + tools --------------------------------------------------
  if ! have brew; then
    log "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  fi

  log "installing CLI tools"
  brew install --quiet git zsh tmux neovim direnv jq starship fzf >/dev/null

  log "installing yabai + skhd (formulae)"
  brew install --quiet koekeishiya/formulae/yabai >/dev/null || true
  brew install --quiet koekeishiya/formulae/skhd  >/dev/null || true

  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    log "installing GUI casks (will sudo-prompt for each .pkg)"
    brew install --cask karabiner-elements hammerspoon rectangle 2>&1 | \
      sed 's/^/    cask: /' || true
  else
    warn "skipping cask installs — run later: brew install --cask karabiner-elements hammerspoon rectangle"
  fi

  # Cask sanity: brew records a cask as installed once it's downloaded and
  # the artifact is staged, but if the .pkg installer was interrupted (e.g.
  # killed mid-sudo) the .app never lands. Detect and offer to re-run.
  if [[ ! -d /Applications/Karabiner-Elements.app ]]; then
    local pkg
    pkg=$(find /opt/homebrew/Caskroom/karabiner-elements -name "*.pkg" 2>/dev/null | head -1)
    if [[ -n "$pkg" ]]; then
      warn "Karabiner cask staged but .app missing — installer never ran"
      if has_tty; then
        log "running staged installer now (will sudo-prompt)"
        sudo installer -pkg "$pkg" -target / || warn "installer failed"
      else
        warn "fix later: sudo installer -pkg \"$pkg\" -target /"
      fi
    fi
  fi

  # ---- Configs -----------------------------------------------------------
  install_file "$CONFIGS_DIR/karabiner.json"        "$HOME/.config/karabiner/karabiner.json"
  install_file "$CONFIGS_DIR/skhdrc"                "$HOME/.skhdrc"
  install_file "$CONFIGS_DIR/yabairc"               "$HOME/.yabairc"             755
  install_file "$CONFIGS_DIR/hammerspoon-init.lua"        "$HOME/.hammerspoon/init.lua"
  install_file "$CONFIGS_DIR/hammerspoon-cheatsheet.lua"  "$HOME/.hammerspoon/cheatsheet.lua"
  install_file "$CONFIGS_DIR/tmux.conf"             "$HOME/.tmux.conf"

  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua" \
               "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # ---- macOS defaults ----------------------------------------------------
  # yabai requires "Displays have separate Spaces" (Mission Control). The
  # underlying default is com.apple.spaces spans-displays = 0 (false).
  # NB: change only takes effect after logout/login.
  local need_relogin=0
  if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]]; then
    log "setting com.apple.spaces spans-displays = false (yabai requirement)"
    defaults write com.apple.spaces spans-displays -bool false
    need_relogin=1
  fi

  if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
    log "configuring iTerm2 (Option = Meta)"
    defaults write com.googlecode.iterm2 "Left Option Key Sends" -string "Esc+"
  else
    warn "iTerm2 prefs not found — skipping (launch iTerm2 once, then re-run)"
  fi

  # ---- Start services (with permission-grant retry) ----------------------
  log "starting services (yabai, skhd)"
  have yabai && yabai --start-service >/dev/null 2>&1 || true
  have skhd  && skhd  --start-service >/dev/null 2>&1 || true
  sleep 1
  have yabai && yabai --restart-service >/dev/null 2>&1 || true
  have skhd  && skhd  --restart-service >/dev/null 2>&1 || true
  sleep 1

  # If services aborted on missing Accessibility, open System Settings + retry.
  local needs=()
  mac_yabai_status; local ys=$?
  mac_skhd_status;  local ss=$?
  [[ $ys -eq 2 ]] && needs+=("yabai")
  [[ $ss -eq 2 ]] && needs+=("skhd")

  if (( ${#needs[@]} > 0 )); then
    warn "services aborted on missing Accessibility: ${needs[*]}"
    if mac_prompt_accessibility "${needs[*]}, plus Hammerspoon and Karabiner-Elements"; then
      log "retrying services after permission grant"
      have yabai && yabai --restart-service >/dev/null 2>&1 || true
      have skhd  && skhd  --restart-service >/dev/null 2>&1 || true
      sleep 1
      mac_yabai_status; ys=$?
      mac_skhd_status;  ss=$?
    fi
  fi
  # Distinct messaging for the spans-displays case (logout-required).
  if [[ $ys -eq 3 ]]; then
    warn "yabai needs 'Displays have separate Spaces' (set, but requires logout/login)"
    need_relogin=1
  fi

  # ---- Karabiner reload --------------------------------------------------
  if launchctl list 2>/dev/null | grep -q "org.pqrs.service.karabiner_console_user_server"; then
    launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.karabiner_console_user_server" \
      >/dev/null 2>&1 || true
    log "Karabiner console_user_server kicked"
  else
    warn "Karabiner not loaded — launch Karabiner-Elements.app once to grant Input Monitoring"
  fi

  # ---- Hammerspoon reload ------------------------------------------------
  if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' \
      >/dev/null 2>&1 || true
    log "Hammerspoon reloaded"
  else
    warn "Hammerspoon not running — launch it once to enable Hyper+T / Hyper+N"
  fi

  # ---- Final summary -----------------------------------------------------
  echo ""
  log "===== bootstrap summary ====="
  if mac_yabai_status; then
    log "yabai:       running"
  else
    case $? in
      2) warn "yabai:       NOT running (missing Accessibility)" ;;
      3) warn "yabai:       NOT running (needs logout/login for spans-displays)" ;;
      *) warn "yabai:       NOT running (unknown — check /tmp/yabai_$(id -un).err.log)" ;;
    esac
  fi
  if mac_skhd_status; then
    log "skhd:        running"
  else
    case $? in
      2) warn "skhd:        NOT running (missing Accessibility)" ;;
      *) warn "skhd:        NOT running (unknown — check /tmp/skhd_$(id -un).err.log)" ;;
    esac
  fi
  [[ -d /Applications/Karabiner-Elements.app ]] && log "Karabiner:   installed"  || warn "Karabiner:   not installed (run: brew install --cask karabiner-elements)"
  [[ -d /Applications/Hammerspoon.app        ]] && log "Hammerspoon: installed"  || warn "Hammerspoon: not installed"
  pgrep -x "Hammerspoon" >/dev/null 2>&1 && log "Hammerspoon: running" || warn "Hammerspoon: not running (launch it manually once)"
  (( need_relogin )) && warn "** log out and log back in to apply spans-displays change **"

  cat <<'EOF'

>>> Verify:
    - karabiner: open "Karabiner-EventViewer", press Caps Lock, see ^⌥⌘⇧
    - yabai:     yabai -m query --windows | jq '.[].app'
    - skhd:      pgrep -af skhd
    - tmux:      tmux show -gv prefix    # should print 'C-a'
    - nvim:      :verbose nmap <Space>h  # should map to <C-w>h
EOF
}

# ---- Ubuntu bootstrap --------------------------------------------------------
bootstrap_ubuntu() {
  log "Ubuntu detected — bootstrapping minerva dev env"

  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  log "installing system packages"
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y git curl zsh build-essential direnv tmux htop neovim jq

  log "installing chezmoi + applying dotfiles"
  if ! have chezmoi; then
    curl -fsLS https://get.chezmoi.io | bash -s -- -b "$HOME/.local/bin"
  fi
  if [[ ! -d "$HOME/.local/share/chezmoi" ]]; then
    chezmoi init git@github.com:adames/dotfiles.git
  fi
  chezmoi apply --force || warn "chezmoi apply had warnings"

  log "installing Starship"
  if ! have starship; then
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
  fi

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

  # Drop tmux.conf and nvim keymaps from this dotfiles repo too
  install_file "$CONFIGS_DIR/tmux.conf"        "$HOME/.tmux.conf"
  ensure_dir "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua" "$HOME/.config/nvim/after/plugin/keymaps.lua"

  log "setting default shell to zsh"
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    sudo chsh -s "$(command -v zsh)" "$USER" || warn "chsh failed; run manually"
  fi

  log "bootstrap complete — log out and back in for shell change to apply"
}

# ---- entry -------------------------------------------------------------------
main() {
  case "$(uname -s)" in
    Darwin) bootstrap_macos ;;
    Linux)
      if [[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release; then
        bootstrap_ubuntu
      else
        err "unsupported Linux distribution (only Ubuntu is wired up)"
        exit 1
      fi
      ;;
    *)
      err "unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac
}

main "$@"
