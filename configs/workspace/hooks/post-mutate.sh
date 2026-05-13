#!/usr/bin/env bash
set -u
cmd="${1:-}"
plugin_dir="$HOME/.config/sketchybar/plugins"

# SketchyBar repaint after slot-count / display changes.
if command -v sketchybar >/dev/null 2>&1 && pgrep -x sketchybar >/dev/null 2>&1; then
  case "$cmd" in
    add|remove|swap|move|rotate|reverse|reorder|theme|edit|reset|layout|topology)
      [[ -x "$plugin_dir/per-display-pills.sh" ]] && "$plugin_dir/per-display-pills.sh"
      ;;
  esac
fi

# Dynamic skhd bindings: regenerate the `spaces.skhdrc` fragment after any
# mutation that changes slot count or ordering. `topology` is fired by the
# ws-topologyd daemon on display reconfiguration; no slot-count change there,
# so we skip regeneration in that case.
if command -v ws-topology >/dev/null 2>&1; then
  case "$cmd" in
    add|remove|swap|move|rotate|reverse|reorder|reset)
      ws-topology emit-skhd --write --reload >/dev/null 2>&1 || true
      ;;
  esac
fi

exit 0
