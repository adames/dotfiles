#!/usr/bin/env bash
# Idempotent macOS bootstrap. Env: BOOTSTRAP_SKIP_CASKS=1, NO_COLOR=1.
# Architecture + migration history: docs/architecture.md.

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

  # Everything this repo used to run — Karabiner, yabai/skhd, AeroSpace,
  # Raycast, sigil, mise, and the apps and formulae the 2026-09 prune took
  # — is torn down by a one-shot that stamps itself when it completes. It
  # cost ~4s of brew forks on every run of every settled Mac while it lived
  # here; now a machine already at its generation exits in milliseconds.
  bash "$DOTFILES_DIR/macos/retire.sh" || warn "one-shot teardown had failures"

  deploy_configs
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
  # ~/.local/bin is where this repo's own tools land, and it matches the
  # Ubuntu bootstrap's PATH posture. The Python user-base bin that used to
  # be appended here (~/Library/Python/3.x/bin) went with the last
  # `pip --user` console script: pipx and rune are retired, and uv installs
  # into ~/.local/bin like everything else.
  export PATH="$HOME/.local/bin:$PATH"

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
