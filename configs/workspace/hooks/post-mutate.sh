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

# NOTE: this hook used to regenerate ~/.config/skhd/spaces.skhdrc via
# `ws-topology emit-skhd --write --reload` after every workspace
# mutation. That fragment is gone — Hyper+digit / Mod+digit bindings
# are now inlined directly in configs/skhdrc (skhd's `.load` directive
# couldn't expand `~` reliably, and the bindings don't actually need to
# vary by slot count: yabai is silent on `--space N --focus` for an
# index that doesn't exist).
#
# If you want to layer additional behaviour on workspace mutations
# (sketchybar repaint kicks above are the canonical example), add it
# above. The `topology` cmd is fired by the ws-topologyd daemon on
# display reconfig; the other cmds come from the `ws` CLI's mutations.

exit 0
