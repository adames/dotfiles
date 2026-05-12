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
#   4. assert dependencies + minimum tmux version + JankyBorders presence
#   5. nudge running yabai / Hammerspoon / skhd to pick up new signals

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
  ok "seeded ${target/#$HOME/~}"
elif command -v jq >/dev/null 2>&1; then
  # Migration: existing config from the 8-slot era is missing keys "9"
  # and "10". Add them (with default name/colour/icon from the seed)
  # without touching any user renames on slots 1..8.
  missing_slots=$(
    jq -r --slurpfile seed "$seed" '
      ($seed[0].spaces | keys_unsorted) - (.spaces | keys_unsorted)
      | .[]
    ' "$target" 2>/dev/null
  )
  if [[ -n "$missing_slots" ]]; then
    step "migrating ${target/#$HOME/~} — appending missing slots: $(echo "$missing_slots" | tr '\n' ' ')"
    tmp=$(mktemp) || exit 1
    # Right-bias merge: seed supplies any missing slot, user-edited keys
    # win on slots present in both. `*` deep-merges objects in jq.
    jq --slurpfile seed "$seed" '
      .version = ($seed[0].version // 2)
      | .spaces = (($seed[0].spaces) * (.spaces // {}))
    ' "$target" > "$tmp" && mv -f "$tmp" "$target"
    # Post-condition: migration must produce at least the seed's 10 slots
    # (extras from `workspace add` are fine). Anything less is a bug in
    # the merge — refuse to leave a corrupt config.
    final=$(jq '.spaces | length' "$target" 2>/dev/null || echo 0)
    if (( final < 10 )); then
      err "migration produced $final slots (expected ≥ 10) — leaving original at ${target}.broken"
      mv "$target" "${target}.broken" 2>/dev/null
      exit 1
    fi
    ok "migrated to $final slots (existing renames preserved)"
  else
    final=$(jq '.spaces | length' "$target" 2>/dev/null || echo 0)
    if [[ "$final" != "10" ]]; then
      info "existing ${target/#$HOME/~} has $final slots (not the canonical 10) — preserving as-is"
    else
      ok "preserving existing ${target/#$HOME/~} (renames intact)"
    fi
  fi
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
recenter() { [[ -x "$plugin_dir/recenter.sh" ]] && "$plugin_dir/recenter.sh"; }

case "$cmd" in
  add)
    new_slot="${2:-}"
    [[ -z "$new_slot" ]] && exit 0
    # Hard cap: dock shows at most 10 pills even if slot count grows.
    if (( new_slot <= 10 )); then
      sketchybar --add item "space.$new_slot" left \
                 --set "space.$new_slot" \
                    script="$plugin_dir/space.sh" \
                    click_script="yabai -m space --focus $new_slot" \
                 --subscribe "space.$new_slot" workspace_changed \
                 --trigger workspace_changed >/dev/null 2>&1 || true
      recenter
    fi
    ;;
  remove)
    cur=$(command -v workspace >/dev/null 2>&1 \
            && workspace count 2>/dev/null \
            || jq '.spaces | keys | length' "$HOME/.config/workspace/spaces.json" 2>/dev/null \
            || echo 0)
    old_max=$((cur + 1))
    # Only the topmost pill (≤10) actually exists in sketchybar.
    if (( old_max <= 10 )); then
      sketchybar --remove "space.$old_max" \
                 --trigger workspace_changed >/dev/null 2>&1 || true
      recenter
    fi
    ;;
esac
exit 0
EOF
  chmod 755 "$hook"
  ok "created ~/.config/workspace/hooks/post-mutate.sh (sketchybar-aware default)"
fi

# ── 3 · laptop UUID capture (single-display only, idempotent) ────────────
uuid_file="$HOME/.config/workspace/laptop.uuid"
if [[ ! -s "$uuid_file" ]] && command -v yabai >/dev/null 2>&1; then
  display_count=$(yabai -m query --displays 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
  if [[ "$display_count" -eq 1 ]]; then
    "$SELF_DIR/laptop-uuid-init.sh" >/dev/null && \
      ok "captured laptop display UUID"
  else
    warn "skip laptop UUID capture: ${display_count} displays attached — run laptop-uuid-init.sh manually with only the built-in panel connected, OR write the UUID by hand to ${uuid_file/#$HOME/~}"
  fi
fi

# ── 4 · dependency assertions ────────────────────────────────────────────
missing=()
for bin in jq yabai hs tmux; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if (( ${#missing[@]} )); then
  warn "missing: ${missing[*]} — install via brew or run macos/bootstrap.sh"
fi

# JankyBorders is a separate brew tap — don't fail without it (some
# users may opt out), just warn so the missing border layer is obvious.
if ! command -v borders >/dev/null 2>&1; then
  warn "borders not installed — neon window borders disabled. Install: brew tap FelixKratz/formulae && brew install borders"
fi

# SketchyBar drives the workspace-pill strip. Optional like borders —
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

if pgrep -x Hammerspoon >/dev/null 2>&1 && command -v hs >/dev/null 2>&1; then
  step "reloading Hammerspoon"
  hs -c "hs.reload()" >/dev/null 2>&1 || warn "Hammerspoon reload failed"
fi

if pgrep -x skhd >/dev/null 2>&1; then
  step "reloading skhd (picking up new bindings)"
  skhd --reload >/dev/null 2>&1 || warn "skhd --reload failed"
fi

# Restart borders so it picks up bordersrc on next launch.
if pgrep -x borders >/dev/null 2>&1; then
  step "restarting borders daemon"
  pkill -x borders 2>/dev/null || true
  sleep 0.2
fi
if command -v borders >/dev/null 2>&1 && [[ -x "$HOME/.config/borders/bordersrc" ]]; then
  ( "$HOME/.config/borders/bordersrc" >/dev/null 2>&1 & ) || true
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
