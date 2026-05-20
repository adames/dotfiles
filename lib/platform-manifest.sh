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

# macOS-only paths. The Swift workspace package (sigil) lives in a
# separate repo cloned at bootstrap, not under dotfiles. Hyperkey is
# .app-only (no file in configs/).
MACOS_ONLY_PATHS=(
  "configs/aerospace.toml"
  "configs/ghostty-config"
  "macos/"
)

# Linux-only paths: currently empty. Add entries here if a file is
# Linux-exclusive (e.g. a systemd unit, an apt repo key script).
LINUX_ONLY_PATHS=()
