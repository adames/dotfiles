# Platform manifest — single source of truth for platform-specific paths.
#
# Sourced by ubuntu/sparse-checkout.sh (and any future cross-platform
# bootstrap helper). When you add a new file/directory that is meaningful
# on only one platform, list it here. Sparse-checkout then keeps non-
# matching clones (e.g. the Ubuntu VPS) free of files they will never use.
#
# Convention:
#   • Paths are relative to the repo root.
#   • Trailing slash means "this directory and everything in it".
#   • No leading slash; sparse-checkout.sh anchors them.
#
# This file deliberately does NOT drive install_file calls in the per-
# platform bootstrap scripts. Each bootstrap explicitly lists what it
# deploys (one source of truth for "what runs on this OS"). The manifest
# is the source of truth for "what files exist on this OS's clone." Two
# axes, two files — keeps the deploy logic auditable at a glance.

# macOS-only paths: aerospace, sketchybar, workspace identity-cascade
# shell scripts (aerospace-driven via exec-on-workspace-change), and
# the macOS bootstrap directory. The Swift workspace package lives in
# a separate repo (sigil, cloned to ~/.config/workspace/ at bootstrap),
# not under dotfiles. Hyperkey is .app-only (no file in configs/), so
# nothing to list for it here.
MACOS_ONLY_PATHS=(
  "configs/aerospace.toml"
  "configs/sketchybar/"
  "configs/workspace/on-space-changed.sh"
  "configs/workspace/on-space-destroyed.sh"
  "configs/workspace/install.sh"
  "configs/workspace/hooks/"
  "configs/ghostty-config"
  "macos/"
)

# Linux-only paths: currently empty. Add entries here if a file is
# Linux-exclusive (e.g. a systemd unit, an apt repo key script).
LINUX_ONLY_PATHS=()
