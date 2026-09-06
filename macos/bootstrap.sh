#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture + migration history: docs/architecture.md.

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── preflight · macOS version floor ────────────────────────────────────────
# Two things downstream assume Tahoe (macOS 26): phase_apply retires
# Raycast *because* native Tahoe Spotlight replaced it as the launcher,
# and macos-defaults writes the Spotlight keys for Tahoe's two-section
# results pane. On 25 or older that pairing is silently destructive —
# the launcher goes away, and `defaults write` happily invents keys the
# old pane never reads, so nothing errors and nothing works.
#
# A warn, not an err: an old Mac can still take everything else, and the
# user gets to decide. Deliberately a local `sw_vers` read rather than
# the `softwareupdate -l` that used to live in update-system — this
# answers "is this Mac new enough for the repo", which is ours to know,
# instead of "does Apple have something queued", which is Apple's.
check_macos_floor() {
  local want=26 have major
  have="$(sw_vers -productVersion 2>/dev/null || true)"
  major="${have%%.*}"
  # Empty or non-numeric means sw_vers didn't answer in the shape we
  # parse; say so rather than pass a comparison we couldn't make.
  case "$major" in
    ''|*[!0-9]*)
      warn "couldn't read macOS version (sw_vers said '${have:-nothing}')"
      return 0
      ;;
  esac
  if (( major < want )); then
    warn "macOS $have is below the $want (Tahoe) floor — the Spotlight defaults and the Raycast teardown assume Tahoe"
  else
    ok "macOS $have (Tahoe floor $want)"
  fi
}

# ─── phase 1 · sudo ─────────────────────────────────────────────────────────
phase_sudo() {
  phase "sudo"
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
  # `|| true` so a dead keepalive doesn't overwrite the script's exit
  # status with the kill's 1. (On the success path the trap never fires —
  # phase_wizard exec's away — and the keepalive self-terminates via its
  # kill -0 check.)
  trap 'kill '"$!"' 2>/dev/null || true' EXIT
  ok "sudo cached"
}

# ─── phase 2 · packages ─────────────────────────────────────────────────────
phase_packages() {
  phase "packages"

  ensure_xcode_clt

  if ! have brew; then
    step "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    ok "Homebrew installed"
  fi

  local brewfile="$DOTFILES_DIR/macos/Brewfile"
  local brewfile_local="$DOTFILES_DIR/macos/Brewfile.local"

  # Brew Bundle no longer supports type flags (`--formula`, `--cask`) on
  # install. Restore the full Brewfile when interactive; otherwise ask Bundle
  # to skip every declared cask so headless runs don't wedge on sudo prompts.
  if has_tty && [[ -z "${BOOTSTRAP_SKIP_CASKS:-}" ]]; then
    step "installing macos/Brewfile"
    if brew bundle install --file="$brewfile" --no-upgrade 2>&1 | brew_quiet; then
      ok "Brewfile"
    else
      warn "macos/Brewfile install had failures"
    fi
  else
    local cask_skip
    cask_skip="$(brewfile_casks "$brewfile")"
    step "installing formulae from macos/Brewfile (casks skipped)"
    if HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" \
         brew bundle install --file="$brewfile" --no-upgrade 2>&1 | brew_quiet; then
      ok "formulae"
    else
      warn "macos/Brewfile formula install had failures"
    fi
    warn "skipping cask installs (no TTY or BOOTSTRAP_SKIP_CASKS=1)"
  fi

  # Per-Mac heavy apps. orbstack used to be the example here and no
  # longer is — containers are every Mac's, so it graduated to the
  # shared Brewfile. What's left is genuinely machine-specific, and
  # the Air has no Brewfile.local at all.
  if [[ -f "$brewfile_local" ]]; then
    step "installing macos/Brewfile.local (this-machine apps)"
    if brew bundle install --file="$brewfile_local" --no-upgrade 2>&1 | brew_quiet; then
      ok "Brewfile.local"
    else
      warn "macos/Brewfile.local install had failures"
    fi
  fi

  # Strip Gatekeeper quarantine so scripted `open -a` works pre-launch.
  for app in /Applications/Hyperkey.app /Applications/Helium.app; do
    [[ -d "$app" ]] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  done

  seed_hyperkey_defaults

  # Devin is a work tool that lives on the personal Macs too, for as long
  # as the work does — this repo never runs on the work machine, so here
  # is the only place it can be checked. Revisit if that job ends. No cask
  # exists, so brew can't own it; the app self-updates and bootstrap just
  # refuses to stay silent when it's missing.
  if [[ ! -d /Applications/Devin.app ]]; then
    warn "Devin.app missing — install from https://devin.ai (no cask)"
  fi

  # Upgrade pass — brew/mise/softwareupdate. Same logic the user runs
  # standalone as `update-sys`; bootstrap calls it so a fresh re-run
  # leaves the machine fully current, not just package-list-complete.
  # Non-fatal: a flaky upgrade must not abort before configs deploy.
  if bash "$DOTFILES_DIR/bin/update-system"; then
    ok "upgrade pass"
  else
    warn "update-system had failures — continuing to configs"
  fi
}

brewfile_casks() {
  local brewfile="$1"
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*cask[[:space:]]+"/ {
      line = $0
      sub(/^[[:space:]]*cask[[:space:]]+"/, "", line)
      sub(/".*/, "", line)
      print line
    }
  ' "$brewfile" | paste -sd' ' -
}

# Xcode Command Line Tools — brew needs them to install most formulae.
# Without them, the Homebrew installer drops you into a graphical
# "install developer tools" prompt that wedges any non-interactive run.
ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  step "installing Xcode Command Line Tools"
  if has_tty; then
    xcode-select --install 2>/dev/null || true
    err "complete the Xcode CLT prompt, then re-run this bootstrap"
    exit 1
  fi
  err "Xcode CLT missing and no TTY for the install prompt"
  exit 1
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
  # Quit is async — wait for the process to actually exit so its on-quit
  # prefs rewrite can't clobber ours (a fixed sleep lost the race on slow
  # machines). ~5s cap, then proceed regardless.
  local waited=0
  while pgrep -x Hyperkey >/dev/null 2>&1 && (( waited < 50 )); do
    sleep 0.1
    waited=$((waited + 1))
  done

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
  phase "deploy configs & defaults"

  : > "$HOME/.hushlogin"

  # Apply curated macOS defaults (Dark mode, Dock/Finder/Trackpad posture)
  # — see docs/macos-defaults.md for the table and hard limits.
  bash "$DOTFILES_DIR/macos/macos-defaults.sh"

  # Stop legacy services BEFORE deleting their configs — otherwise
  # Karabiner's grabber can wedge the input system on its way out.
  # `brew services list` costs ~1s, so capture it once, not per service.
  local brew_services
  brew_services="$(brew services list 2>/dev/null || true)"
  for svc in yabai skhd; do
    if grep -q "^$svc.*started" <<<"$brew_services"; then
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

  # AeroSpace retired (mouse + single screen won; tiling never earned its
  # keep). Quit the app, drop the cask, sweep its config. Idempotent — a
  # machine that never had it just no-ops through.
  if pgrep -x AeroSpace >/dev/null 2>&1; then
    step "stopping AeroSpace (retired)"
    osascript -e 'tell application "AeroSpace" to quit' 2>/dev/null || true
  fi
  if brew list --cask aerospace >/dev/null 2>&1; then
    step "uninstalling aerospace cask"
    brew uninstall --cask aerospace >/dev/null 2>&1 || warn "aerospace cask uninstall failed"
  fi
  rm -rf "$HOME/.config/aerospace"

  # Raycast retired too (native Tahoe Spotlight is the launcher). Same
  # idempotent teardown shape: quit, drop the cask, sweep local state.
  if pgrep -x Raycast >/dev/null 2>&1; then
    step "stopping Raycast (retired)"
    osascript -e 'tell application "Raycast" to quit' 2>/dev/null || true
  fi
  if brew list --cask raycast >/dev/null 2>&1; then
    step "uninstalling raycast cask"
    brew uninstall --cask raycast >/dev/null 2>&1 || warn "raycast cask uninstall failed"
  fi
  rm -rf "$HOME/Library/Application Support/com.raycast.macos" \
         "$HOME/Library/Caches/com.raycast.macos" \
         "$HOME/Library/Application Support/com.raycast.shared"
  defaults delete com.raycast.macos >/dev/null 2>&1 || true

  # Sigil (the Swift workspace package) is fully retired with AeroSpace —
  # its last survivor, the ws-cheatsheet HUD, was only reachable via the
  # Caps+/ chord that lived in aerospace.toml. Sweep the clone, its
  # symlinked binaries, and the rune generator that fed it.
  rm -rf "$HOME/.config/workspace"
  for bin in "$HOME/.local/bin/ws-"*; do
    [[ -e "$bin" || -L "$bin" ]] || continue
    [[ "${bin##*/}" == "ws-doctor" ]] || rm -f "$bin"
  done
  python3 -m pip uninstall --quiet --yes rune 2>/dev/null || true

  # Retired surfaces from earlier eras: sketchybar / borders. (The ws-*
  # launchers and ~/.config/workspace scripts are covered by the sigil
  # sweep above.)
  rm -rf "$HOME/.config/sketchybar"
  rm -rf "$HOME/.config/borders"

  prune_retired_apps
  prune_undeclared_formulae
  retire_mise

  deploy_configs
}

# The portable core: every file that is just as true on a machine this
# repo doesn't own. No brew, no defaults, no teardown, no wizard — so
# `BOOTSTRAP_CONFIGS_ONLY=1 ./bootstrap.sh` is a safe thing to run on a
# locked-down or borrowed Mac, and a work-friendly fork of this repo can
# be this function plus configs/.
#
# ghostty-config is deployed unconditionally: it's an inert file under
# ~/.config/ghostty, and a machine on iTerm2 simply never reads it.
deploy_configs() {
  install_file "$CONFIGS_DIR/ghostty-config"             "$HOME/.config/ghostty/config"
  install_file "$CONFIGS_DIR/tmux.conf"                  "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/zshrc"                      "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/starship.toml"              "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/gitconfig"                  "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/ripgreprc"                  "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/CLAUDE.md"                  "$HOME/.claude/CLAUDE.md"
  install_file "$CONFIGS_DIR/claude-settings.json"       "$HOME/.claude/settings.json"
  install_file "$DOTFILES_DIR/bin/backup-claude-memory"  "$HOME/.local/bin/backup-claude-memory.sh" 755
  ensure_claude_skills
  install_file "$CONFIGS_DIR/tmux-sessionizer"           "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$DOTFILES_DIR/bin/ws-doctor"             "$HOME/.local/bin/ws-doctor" 755
  install_file "$DOTFILES_DIR/bin/update-system"         "$HOME/.local/bin/update-system" 755
  rm -f "$HOME/.config/zsh/completions/_ws"

  install_file "$CONFIGS_DIR/nvim-init.lua"              "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json"        "$HOME/.config/nvim/lazy-lock.json"
  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"           "$HOME/.config/nvim/after/plugin/keymaps.lua"

  ensure_gitconfig_local
}

# ─── the 2026-09 prune ──────────────────────────────────────────────────────
# Hand-installed .apps (no cask ever owned them) that lost their argument:
#
#   Firefox      — a fourth browser. Chrome and Helium are the two in use.
#   VS Code      — the editor is nvim + Claude Code. Idle since May.
#   ExpressVPN   — a second VPN client. ProtonVPN is the declared one.
#
# And the App Store tier, re-downloadable at any time since the purchases
# stay on the Apple ID — which is exactly why they don't need to sit on
# every disk:
#
#   Keynote      — never opened on this machine.
#   Pages        — same. Ships as "Pages Creator Studio.app" here: the
#                  bundle is com.apple.Pages, just renamed on disk, so
#                  the loop matches the filename rather than the app name.
#   MD Viewer    — 381 MB to render markdown. `glow` does it in 10 MB and
#                  works over SSH too. PDFgear stays: it's the current
#                  PDF app, bought in June.
#   Elmedia      — lost to IINA, which is now a declared cask.
#   HandBrake    — never launched, and ffmpeg (declared) does the job
#                  from the terminal.
#
# App bundles only. Browser profiles and editor settings under
# ~/Library/Application Support are deliberately NOT swept: bookmarks and
# saved logins are not ours to delete, and a re-download re-adopts them.
# Delete those by hand if you want the disk back.
prune_retired_apps() {
  local app
  for app in Firefox "Visual Studio Code" ExpressVPN \
             Keynote "Pages Creator Studio" "MD Viewer" "Elmedia Player" \
             HandBrake; do
    [[ -d "/Applications/$app.app" ]] || continue
    step "removing /Applications/$app.app (retired)"
    osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
    if rm -rf "/Applications/$app.app" 2>/dev/null; then
      ok "$app removed"
    # An .app installed by a pkg can be root-owned; retry under the sudo
    # already cached in phase 1. -n so a run without it warns instead of
    # blocking on a password prompt nobody is watching.
    elif sudo -n rm -rf "/Applications/$app.app" 2>/dev/null; then
      ok "$app removed (sudo)"
    else
      warn "$app.app could not be removed — delete it by hand"
    fi
  done

  # ExpressVPN ships a privileged daemon that keeps running after the app
  # is gone. Nothing else in this repo installs a LaunchDaemon, so this
  # stays a named special case rather than a generic sweep.
  local daemon=/Library/LaunchDaemons/com.expressvpn.expressvpnd.plist
  if [[ -f "$daemon" ]]; then
    step "unloading ExpressVPN privileged daemon"
    if sudo -n launchctl bootout system "$daemon" 2>/dev/null \
         && sudo -n rm -f "$daemon" 2>/dev/null; then
      ok "expressvpnd unloaded and removed"
    else
      warn "expressvpnd still installed — needs sudo: launchctl bootout system $daemon"
    fi
  fi

  sweep_expressvpn_leftovers
}

# ExpressVPN's own trail: prefs, caches, logs, a crash report, and a
# root-owned socket directory — all of which outlive both the .app and
# the daemon, and none of which is user data worth keeping (a VPN client
# holds no documents). Firefox and VS Code are deliberately NOT swept
# this way: their support directories hold bookmarks, saved logins and
# editor settings, which are yours to delete, not bootstrap's.
#
# Globs need nullglob — an unmatched pattern would otherwise be passed to
# rm as a literal path. Idempotent: everything here is `rm -rf` on a path
# that is usually already gone.
sweep_expressvpn_leftovers() {
  local found=0 p
  shopt -s nullglob
  local paths=(
    "$HOME/Library/Application Support/com.expressvpn.ExpressVPN"
    "$HOME/Library/Preferences/com.expressvpn.ExpressVPN.plist"
    "$HOME/Library/Caches/com.expressvpn.ExpressVPN"
    "$HOME/Library/HTTPStorages/com.expressvpn.ExpressVPN"
    "$HOME/Library/Logs/ExpressVPN"
    "$HOME/Library/Application Support/CrashReporter/ExpressVPN_"*.plist
  )
  shopt -u nullglob
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    found=1
    rm -rf "$p" 2>/dev/null || warn "could not remove $p"
  done

  # Root-owned, and left behind holding a dead expressvpnd.socket.
  local sys="/Library/Application Support/com.expressvpn.ExpressVPN"
  if [[ -d "$sys" ]]; then
    found=1
    if ! sudo -n rm -rf "$sys" 2>/dev/null; then
      warn "ExpressVPN system dir remains — needs sudo: rm -rf \"$sys\""
    fi
  fi

  # `(( found )) && ok …` would be a set -e footgun: with found=0 the
  # AND-list returns 1 and aborts the whole bootstrap. Spelled as an if.
  if (( found )); then
    ok "swept ExpressVPN leftovers"
  fi
}

# Formulae that drifted into `brew leaves` and outlived their reason.
# resvg + pipx fed rune (retired with the cheatsheet HUD), watchman was
# React Native, ruby and git-filter-repo were one-offs. Nothing on this
# machine depends on any of them — the Brewfile is now the whole truth
# for formulae, so anything undeclared either gets a line there or a line
# here. Guarded by `brew uses --installed`: a formula something else pulled
# in since is kept, loudly.
prune_undeclared_formulae() {
  have brew || return 0
  local f users
  # python@3.14 is here as pipx's orphan: brew pulled it in as a dependency,
  # and removing pipx left it a leaf. Python on these machines is mise's
  # 3.12 — a second interpreter on PATH is exactly the kind of drift that
  # makes `python3` mean different things on two Macs.
  # direnv and ruff went with the authoring workflow (2026-09): no .envrc
  # exists on either machine, and ruff is a formatter/linter for code you
  # write by hand. pyright stays — reading unfamiliar Python is the job now.
  for f in resvg pipx watchman ruby git-filter-repo python@3.14 direnv ruff; do
    brew list --formula "$f" >/dev/null 2>&1 || continue
    users="$(brew uses --installed "$f" 2>/dev/null | tr '\n' ' ')"
    if [[ -n "${users// /}" ]]; then
      note "keeping $f — still used by: ${users% }"
      continue
    fi
    step "uninstalling undeclared formula: $f"
    if brew uninstall --formula "$f" >/dev/null 2>&1; then
      ok "$f uninstalled"
    else
      warn "$f uninstall failed"
    fi
  done
}

# mise is retired on macOS (it stays on the Ubuntu playground, where
# apt's node is years behind). It was handing out versions byte-identical
# to brew's — node 24.20.0, python 3.12.14, tree-sitter 0.27.0, neovim
# 0.12.5 — through a shim layer, and the per-project switching that would
# have paid for that layer was never in use: the .nvmrc files in ~/code
# were silently ignored for five weeks. node@24 and python@3.12 pin just
# as hard, and uv handles per-project Python properly.
#
# Order matters: the Brewfile has already installed the replacements by
# the time phase_apply runs, so nothing is without a node or a python
# between the uninstall and the next shell. Idempotent.
retire_mise() {
  have brew || return 0
  if brew list --formula mise >/dev/null 2>&1; then
    step "uninstalling mise (macOS runtimes are brew's now)"
    if brew uninstall --formula mise >/dev/null 2>&1; then
      ok "mise uninstalled"
    else
      warn "mise uninstall failed"
    fi
  fi
  # The install tree survives a brew uninstall — ~350 MB of runtimes plus
  # the shims that shadowed brew's binaries on PATH.
  rm -rf "$HOME/.local/share/mise" "$HOME/.cache/mise" "$HOME/.config/mise"
}

# ─── phase 4 · permission wizard ────────────────────────────────────────────
phase_wizard() {
  phase "permission wizard"
  step "handing off to permissions-wizard.sh"
  # Called, not exec'd: exec replaces this process, which would skip both
  # run_summary and phase_sudo's keepalive-killing EXIT trap. The wizard's
  # own exit code is advisory (it's a walk-through, not a gate).
  bash "$DOTFILES_DIR/macos/permissions-wizard.sh" \
    || warn "permissions wizard exited non-zero"
}

main() {
  section "Hyper-key dotfiles bootstrap (macOS)"
  # pip --user console scripts land in the Python user-base bin
  # (~/Library/Python/3.x/bin) — off PATH on a fresh Mac. ~/.local/bin
  # matches the Ubuntu bootstrap's PATH posture. The xcode-select gate
  # keeps the python3 CLT shim from popping the GUI installer prompt
  # before ensure_xcode_clt handles it deliberately.
  local pyuser=
  if xcode-select -p >/dev/null 2>&1; then
    pyuser="$(python3 -m site --user-base 2>/dev/null || true)"
  fi
  export PATH="$HOME/.local/bin${pyuser:+:$pyuser/bin}:$PATH"

  # Configs-only mode: the portable core and nothing else. No sudo, no
  # brew, no macOS defaults, no teardown of another machine's apps, no
  # TCC wizard. For a Mac this repo doesn't own.
  if [[ -n "${BOOTSTRAP_CONFIGS_ONLY:-}" ]]; then
    PHASE_TOTAL=1
    phase "deploy configs (configs-only mode)"
    deploy_configs
    run_summary
    return
  fi

  check_macos_floor

  # Same self-numbering list as ubuntu/bootstrap.sh — phase() takes the total
  # from here, so the headers can never drift out of sync with reality.
  local phases=(phase_sudo phase_packages phase_apply phase_wizard)
  PHASE_TOTAL=${#phases[@]}
  local p
  for p in "${phases[@]}"; do "$p"; done
  run_summary
}

main "$@"
