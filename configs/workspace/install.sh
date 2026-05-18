#!/usr/bin/env bash
# Idempotent workspace-system bootstrap. Called from macos/bootstrap.sh
# phase_configs, but also safe to run standalone.
#
# install_file in lib/common.sh handles the script + lua + toml file
# copies. This script handles the parts that are NOT plain file copies:
#   1. ensure runtime directories exist
#   2. seed ~/.config/workspace/spaces.json ONLY if missing (preserves
#      user renames across bootstrap re-runs); MIGRATE existing v1 (1..8)
#      configs by appending slots 9 & 10 from the new defaults
#   3. capture laptop display UUID on a clean single-display run
#   4. assert dependencies + minimum tmux version
#   5. nudge running yabai / skhd to pick up new signals

set -u

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Re-sourcing common.sh from bootstrap is harmless (idempotent), so just
# always source it — single set of helpers, no conditional branching.
. "$DOTFILES_DIR/lib/common.sh"

# ── 1 · runtime dirs ─────────────────────────────────────────────────────
mkdir -p "$HOME/.config/workspace" "$HOME/.cache/workspace"

# ── 2 · seed / migrate spaces.json ───────────────────────────────────────
target="$HOME/.config/workspace/spaces.json"
seed="$SELF_DIR/spaces.default.json"

if [[ ! -f "$target" ]]; then
  install -m 644 "$seed" "$target"
  ok "seeded ${target/#$HOME/~} (empty — yabai owns existence, identity is opt-in)"
elif command -v jq >/dev/null 2>&1; then
  # No seed migration anymore. spaces.default.json is just `{spaces: {}}`
  # by design — yabai is the source of truth for which spaces exist, and
  # spaces.json's job is to layer optional name/color/icon on top of
  # whatever yabai reports. Existing user renames are always preserved.
  final=$(jq '.spaces | length' "$target" 2>/dev/null || echo 0)
  ok "preserving existing ${target/#$HOME/~} ($final slot identities)"
else
  ok "preserving existing ${target/#$HOME/~} (jq not available; no migration)"
fi

# ── 2.5 · canonical themes registry ──────────────────────────────────────
# Refresh canonical themes shipped from the repo (byte-compare; no-op if
# already up to date). User-added themes with different basenames are
# never touched — `install_file` only writes the specific destination.
themes_src_dir="$SELF_DIR/../themes"
if [[ -d "$themes_src_dir" ]] && command -v jq >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/workspace/themes"
  for theme_src in "$themes_src_dir"/*.json; do
    [[ -f "$theme_src" ]] || continue
    install_file "$theme_src" "$HOME/.config/workspace/themes/$(basename "$theme_src")"
  done
fi

# ── 2.6 · post-mutate hook stub (gitconfig.local-style: never clobber) ───
# The CLI invokes this hook after every successful mutation. Empty by
# default; users (or other programs) populate it to integrate with
# notifications, logging, etc. The workspace status bar (ws-statusbar)
# listens for workspace changes via polling and distributed notifications.
mkdir -p "$HOME/.config/workspace/hooks"
hook="$HOME/.config/workspace/hooks/post-mutate.sh"
if [[ ! -f "$hook" ]]; then
  cat > "$hook" <<'EOF'
#!/usr/bin/env bash
# Called by the `workspace` CLI after every successful mutation.
#   $1     = subcommand (name|color|icon|add|remove|swap|move|rotate|
#                        reverse|reorder|theme|edit|reset|layout)
#   $2..$N = slot indices touched (varies per subcommand)
#
# The workspace status bar (ws-statusbar) is a Swift app that polls
# spaces.json and shows workspace pills in the macOS status bar.
# It updates automatically; no explicit hook action needed.
#
# Customize freely — this file is per-machine, never clobbered.

set -u
cmd="${1:-}"

# Example: send a notification on workspace add
# case "$cmd" in
#   add) osascript -e 'display notification "New workspace created" with title "Workspace"' ;;
# esac

exit 0
EOF
  chmod 755 "$hook"
  ok "created ~/.config/workspace/hooks/post-mutate.sh (default)"
fi

# ── 3 · dependency assertions ────────────────────────────────────────────
missing=()
for bin in jq yabai tmux; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if (( ${#missing[@]} )); then
  warn "missing: ${missing[*]} — install via brew or run macos/bootstrap.sh"
fi

# ws-statusbar shows workspace pills in the macOS status bar.
# Built from Swift; no brew dependency. It will be started by
# launchd after the topology build step in bootstrap.
if [[ ! -x "$HOME/.local/bin/ws-statusbar" ]]; then
  step "ws-statusbar not yet built — will be installed by topology build"
fi

# tmux ≥ 3.2 required for #{E:VAR} interpolation in statusline.
if command -v tmux >/dev/null 2>&1; then
  v=$(tmux -V | awk '{print $2}' | sed 's/[^0-9.].*//')
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  if (( major < 3 )) || { (( major == 3 )) && (( minor < 2 )); }; then
    warn "tmux ${v} < 3.2 — #{E:VAR} interpolation won't render. brew upgrade tmux."
  fi
fi

# ── 5 · poke running daemons (optional, best-effort) ─────────────────────
if pgrep -x yabai >/dev/null 2>&1; then
  step "reloading yabai (registering new signals)"
  yabai --restart-service >/dev/null 2>&1 || warn "yabai --restart-service failed"
fi

if pgrep -x skhd >/dev/null 2>&1; then
  step "reloading skhd (picking up new bindings)"
  skhd --reload >/dev/null 2>&1 || warn "skhd --reload failed"
fi

# Start (or restart) ws-statusbar via launchd so the workspace
# pills appear in the macOS menu bar.
launchd_plist="$HOME/Library/LaunchAgents/com.user.ws-statusbar.plist"
if [[ -f "$launchd_plist" ]] && [[ -x "$HOME/.local/bin/ws-statusbar" ]]; then
  step "(re)starting ws-statusbar service"
  launchctl unload "$launchd_plist" 2>/dev/null || true
  launchctl load "$launchd_plist" 2>/dev/null || warn "ws-statusbar launchctl load failed"
fi

# Prime current.env so the very first new shell already has metadata.
"$SELF_DIR/on-space-changed.sh" >/dev/null 2>&1 || true

ok "workspace system ready"
