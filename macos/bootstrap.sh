#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture: docs/architecture.md.

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── preflight · macOS version floor ────────────────────────────────────────
# Two things downstream assume Tahoe (macOS 26): macos/retire.sh drops
# Raycast *because* native Tahoe Spotlight replaced it as the launcher,
# and macos-defaults writes the Spotlight keys for Tahoe's two-section
# results pane. On 25 or older that pairing is silently destructive —
# the launcher goes away, and `defaults write` happily invents keys the
# old pane never reads, so nothing errors and nothing works.
#
# A warn, not an err: an old Mac can still take everything else, and the
# user gets to decide. A local `sw_vers` read, never `softwareupdate -l`:
# "is this Mac new enough for the repo" is ours to know; "does Apple have
# something queued" is Apple's, and it costs a network round trip.
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
    warn "no TTY — cask installs will be skipped"
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
  # status with the kill's 1.
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

  # `brew bundle install` has no `--formula`/`--cask` flags any more. Full
  # Brewfile when interactive; otherwise ask Bundle to skip every declared
  # cask so headless runs don't wedge on sudo prompts.
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

  # Strip Gatekeeper quarantine so scripted `open -a` works pre-launch.
  for app in /Applications/Helium.app; do
    [[ -d "$app" ]] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  done

  # pyright (the Python LSP) and vercel (the deploy CLI the Claude Code
  # plugin shells out to) are `npm -g` into ~/.local — not brew, because
  # brew's pyright drags in a second node. Same function Ubuntu uses.
  install_npm_tools pyright vercel

  # Devin is a work tool that lives on the personal Macs too, for as long
  # as the work does — this repo never runs on the work machine, so here
  # is the only place it can be checked. Revisit if that job ends. No cask
  # exists, so brew can't own it; the app self-updates and bootstrap just
  # refuses to stay silent when it's missing.
  if [[ ! -d /Applications/Devin.app ]]; then
    warn "Devin.app missing — install from https://devin.ai (no cask)"
  fi

  # Upgrade pass — brew + mas. Same script the user runs standalone as
  # `update-sys`; bootstrap calls it so a fresh re-run
  # leaves the machine fully current, not just package-list-complete.
  # Non-fatal: a flaky upgrade must not abort before configs deploy.
  if bash "$DOTFILES_DIR/bin/update-system"; then
    ok "upgrade pass"
  else
    warn "update-system had failures — continuing to configs"
  fi
}

# The cask names from a Brewfile, space-joined for
# HOMEBREW_BUNDLE_CASK_SKIP. The `^[[:space:]]*cask` anchor already skips
# commented-out lines, since a `#` would come first.
brewfile_casks() {
  awk -F'"' '/^[[:space:]]*cask[[:space:]]+"/ { print $2 }' "$1" | paste -sd' ' -
}

# Command Line Tools, and ONLY the Command Line Tools. Full Xcode kept
# coming back: install it once (a simulator, a Swift one-off, a tool that
# asks for it) and it takes over `xcode-select`, so every git / make /
# clang / python3 shim resolves into Xcode.app. Delete the bundle after
# that and they all break with "tool requires Xcode" — and the reflex fix
# is to download Xcode again. That is the dance. Pinning the developer
# dir to the CLT ends it: Xcode becomes a disposable 4 GB download that
# retire.sh removes, not a dependency anything resolves through.
ensure_xcode_clt() {
  local clt=/Library/Developer/CommandLineTools cur
  if [[ ! -d "$clt" ]]; then
    step "installing Xcode Command Line Tools"
    if has_tty; then
      xcode-select --install 2>/dev/null || true
      err "complete the Xcode CLT prompt, then re-run this bootstrap"
      exit 1
    fi
    err "Xcode CLT missing and no TTY for the install prompt"
    exit 1
  fi
  cur="$(xcode-select -p 2>/dev/null || true)"
  [[ "$cur" == "$clt" ]] && return 0
  step "pointing xcode-select at the CLT (was: ${cur:-unset})"
  if sudo -n xcode-select --switch "$clt" 2>/dev/null; then
    ok "developer dir → $clt"
  else
    warn "needs sudo: xcode-select --switch $clt"
  fi
}

# ─── phase 3 · apply configs + macOS defaults ───────────────────────────────
phase_apply() {
  phase "deploy configs & defaults"

  : > "$HOME/.hushlogin"

  # Apply curated macOS defaults (Dark mode, Dock/Finder/Trackpad posture)
  # — see docs/macos-defaults.md for the table and hard limits.
  bash "$DOTFILES_DIR/macos/macos-defaults.sh"

  # Retired software is torn down by a one-shot that stamps its generation
  # per machine; a settled Mac exits it in milliseconds.
  bash "$DOTFILES_DIR/macos/retire.sh" || warn "one-shot teardown had failures"

  deploy_configs
}

main() {
  section "dotfiles bootstrap (macOS)"
  # ~/.local/bin is where this repo's own tools land (uv and npm -g too).
  # node@24 is keg-only, so its npm needs putting on PATH by hand here —
  # bash doesn't read configs/zshenv.
  export PATH="$HOME/.local/bin:/opt/homebrew/opt/node@24/bin:$PATH"

  # Configs-only mode: the portable core and nothing else. No sudo, no
  # brew, no macOS defaults, no teardown of another machine's apps. For
  # a Mac this repo doesn't own.
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
  local phases=(phase_sudo phase_packages phase_apply)
  PHASE_TOTAL=${#phases[@]}
  local p
  for p in "${phases[@]}"; do "$p"; done
  run_summary
}

main "$@"
