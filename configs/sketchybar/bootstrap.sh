#!/usr/bin/env bash
# Idempotent SketchyBar setup. Re-running is safe: brew install no-ops if
# present, brew services restart cleanly replaces the running service, and
# the trigger at the end forces a repaint.

set -eu

# 1) Install sketchybar if missing.
if ! command -v sketchybar >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "bootstrap: brew not found — install Homebrew first" >&2
    exit 1
  fi
  brew tap FelixKratz/formulae 2>/dev/null || true
  brew install sketchybar
fi

# 2) Plugin scripts must be executable; sketchybarrc too (the brew service
# execs it directly). paint-all.sh is the sentinel-item plugin that
# runs the batched per-pill repaint on every workspace_changed event.
chmod +x "$HOME/.config/sketchybar/sketchybarrc"
chmod +x "$HOME/.config/sketchybar/plugins/paint-all.sh" 2>/dev/null || true

# 3) (Re)start the service. brew services restart re-execs sketchybar with
# the (re-read) sketchybarrc, so this is the canonical reload path.
brew services restart sketchybar >/dev/null

# 4) Give sketchybar a beat to bind to the bar, then force an initial paint.
sleep 0.3
sketchybar --trigger workspace_changed 2>/dev/null || true

echo "sketchybar: ready"
