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
# sketchybar pill management, notifications, logging, etc.
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
# Default behavior: keep SketchyBar's pill set in lock-step with
# spaces.json on add/remove. All other mutations only need a repaint,
# which the cascade (on-space-changed.sh) already fires via the
# workspace_changed event.
#
# Customize freely — this file is per-machine, never clobbered.

set -u
cmd="${1:-}"

if ! command -v sketchybar >/dev/null 2>&1; then exit 0; fi
if ! pgrep -x sketchybar >/dev/null 2>&1; then exit 0; fi

plugin_dir="$HOME/.config/sketchybar/plugins"

case "$cmd" in
  add|remove|swap|move|rotate|reverse|reorder|theme|edit|reset|layout)
    # per-display-pills.sh is the single source of truth for "what
    # pills exist and where". It adds/removes items as needed, applies
    # display=<N> per item, hides overflow on notched laptops, then
    # triggers workspace_changed so paint-all.sh repaints.
    [[ -x "$plugin_dir/per-display-pills.sh" ]] && "$plugin_dir/per-display-pills.sh"
    ;;
esac
exit 0
EOF
  chmod 755 "$hook"
  ok "created ~/.config/workspace/hooks/post-mutate.sh (sketchybar-aware default)"
fi

# ── 3 · dependency assertions ────────────────────────────────────────────
missing=()
for bin in jq yabai tmux; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if (( ${#missing[@]} )); then
  warn "missing: ${missing[*]} — install via brew or run macos/bootstrap.sh"
fi

# SketchyBar drives the workspace-pill strip. Optional —
# system stays usable without it (on-space-changed.sh is silent on
# absence), but the persistent indicator is gone until installed.
if ! command -v sketchybar >/dev/null 2>&1; then
  warn "sketchybar not installed — workspace pills disabled. Install: brew tap FelixKratz/formulae && brew install sketchybar"
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

# Start (or restart) sketchybar via its brew service so the workspace
# pills appear. brew services restart is idempotent — replaces the
# running instance cleanly with the (re-read) sketchybarrc.
if command -v sketchybar >/dev/null 2>&1; then
  step "(re)starting sketchybar service"
  brew services restart sketchybar >/dev/null 2>&1 || warn "sketchybar restart failed"
fi

# Prime current.env so the very first new shell already has metadata.
"$SELF_DIR/on-space-changed.sh" >/dev/null 2>&1 || true

ok "workspace system ready"
