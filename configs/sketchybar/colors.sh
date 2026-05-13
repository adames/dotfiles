#!/usr/bin/env bash
# Catppuccin Mocha palette + sketchybar AARRGGBB constants. Sourced by
# sketchybarrc and plugins/paint-all.sh. Per-slot colors live in
# spaces.json (so user edits don't require a code change).

# Bar background — transparent so the system menu-bar blur shows through.
# That's the "native macOS feel" — sketchybar does not draw its own
# NSVisualEffectView; transparency + top position inherits the blur.
export BAR_COLOR=0x00000000

# Active-pill foreground. Catppuccin Mocha pastels all have luminance > 0.55
# (verified empirically in workspace.lua:67-73), so dark base text always
# reads cleanly on the filled pill regardless of which slot is active.
export ACTIVE_FG=0xff1e1e2e         # base

# Inactive label color. overlay0 (dim gray) keeps the workspace name legible
# without competing with the colored icon or the active pill.
export INACTIVE_LABEL=0xff6c7086    # overlay0
