#!/usr/bin/env bash
# Idempotent workspace-system bootstrap. Called from macos/bootstrap.sh
# phase_configs, but also safe to run standalone.
#
# install_file in lib/common.sh handles the script + lua + toml file
# copies. This script handles the parts that are NOT plain file copies:
#   1. ensure runtime directories exist
#   2. seed ~/.config/workspace/spaces.json ONLY if missing (preserves
#      user renames across bootstrap re-runs)
#   3. assert dependencies + minimum tmux version
#   4. nudge running yabai / Hammerspoon to pick up new signals + module

set -u

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors only when this is run standalone; sourcing common.sh from
# bootstrap would shadow these — bootstrap already prints its own banners.
if [[ -z "${C_RESET:-}" ]]; then
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
  else
    C_RESET=''; C_DIM=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''
  fi
  step() { printf '%s•%s %s\n' "$C_BLUE"  "$C_RESET" "$*"; }
  ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
  warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
  err()  { printf '%s✗%s %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
fi

# ── 1 · runtime dirs ─────────────────────────────────────────────────────
mkdir -p "$HOME/.config/workspace" "$HOME/.cache/workspace"

# ── 2 · seed spaces.json if missing ──────────────────────────────────────
target="$HOME/.config/workspace/spaces.json"
seed="$SELF_DIR/spaces.default.json"
if [[ ! -f "$target" ]]; then
  install -m 644 "$seed" "$target"
  ok "seeded ${target/#$HOME/~}"
else
  ok "preserving existing ${target/#$HOME/~} (renames intact)"
fi

# ── 3 · dependency assertions ────────────────────────────────────────────
missing=()
for bin in jq yabai hs tmux; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if (( ${#missing[@]} )); then
  warn "missing: ${missing[*]} — install via brew or run macos/bootstrap.sh"
fi

# tmux ≥ 3.2 required for #{E:VAR} interpolation in statusline.
if command -v tmux >/dev/null 2>&1; then
  v=$(tmux -V | awk '{print $2}' | sed 's/[^0-9.].*//')
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  if (( major < 3 )) || { (( major == 3 )) && (( minor < 2 )); }; then
    warn "tmux ${v} < 3.2 — #{E:VAR} interpolation won't render. brew upgrade tmux."
  fi
fi

# ── 4 · poke running daemons (optional, best-effort) ─────────────────────
if pgrep -x yabai >/dev/null 2>&1; then
  step "reloading yabai (registering space_changed signal)"
  yabai --restart-service >/dev/null 2>&1 || warn "yabai --restart-service failed"
fi

if pgrep -x Hammerspoon >/dev/null 2>&1 && command -v hs >/dev/null 2>&1; then
  step "reloading Hammerspoon (loading workspace module)"
  hs -c "hs.reload()" >/dev/null 2>&1 || warn "Hammerspoon reload failed"
fi

if pgrep -x skhd >/dev/null 2>&1; then
  step "reloading skhd (picking up Hyper+R binding)"
  skhd --reload >/dev/null 2>&1 || warn "skhd --reload failed"
fi

# Prime current.env so the very first new shell already has metadata.
"$SELF_DIR/on-space-changed.sh" >/dev/null 2>&1 || true

ok "workspace system ready"
