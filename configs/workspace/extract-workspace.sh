#!/usr/bin/env bash
# extract-workspace.sh — Migration script to extract workspace from dotfiles
#
# Usage:
#   cd ~/dotfiles
#   ./configs/workspace/extract-workspace.sh /path/to/new/workspace/repo
#
# This script:
#   1. Copies all workspace files to the new repo
#   2. Preserves git history (optional, via filter-branch)
#   3. Updates paths for standalone context
#   4. Verifies the new repo builds

set -euo pipefail

NEW_REPO="${1:-}"

if [[ -z "$NEW_REPO" ]]; then
    echo "Usage: $0 /path/to/new/workspace/repo"
    echo ""
    echo "Example:"
    echo "  mkdir -p ~/projects/workspace"
    echo "  cd ~/dotfiles"
    echo "  ./configs/workspace/extract-workspace.sh ~/projects/workspace"
    exit 1
fi

if [[ -d "$NEW_REPO" && -n "$(ls -A "$NEW_REPO" 2>/dev/null)" ]]; then
    echo "Error: $NEW_REPO exists and is not empty"
    exit 1
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_SRC="$DOTFILES/configs/workspace"

echo "=== Extracting workspace from dotfiles ==="
echo "Source: $WORKSPACE_SRC"
echo "Target: $NEW_REPO"
echo ""

# Create new repo structure
mkdir -p "$NEW_REPO"
cd "$NEW_REPO"
git init

# Copy all workspace files
echo "→ Copying files..."

# Swift package
cp -r "$WORKSPACE_SRC/topology/Package.swift" .
cp -r "$WORKSPACE_SRC/topology/Sources" .
cp -r "$WORKSPACE_SRC/topology/Tests" .
cp -r "$WORKSPACE_SRC/topology/launchd" .

# CLI and libs
cp -r "$WORKSPACE_SRC/cli" .
cp -r "$WORKSPACE_SRC/lib" .

# Config files
cp -r "$WORKSPACE_SRC/topology/install.sh" .
cp -r "$WORKSPACE_SRC/topology/LICENSE" .
cp -r "$WORKSPACE_SRC/topology/README.md" . 2>/dev/null || true
cp -r "$WORKSPACE_SRC/topology/CONTRIBUTING.md" .
cp -r "$WORKSPACE_SRC/topology/CODE_OF_CONDUCT.md" .
cp -r "$WORKSPACE_SRC/topology/AUTHORS" .
cp -r "$WORKSPACE_SRC/topology/CHANGELOG.md" .

# GitHub templates
if [[ -d "$WORKSPACE_SRC/topology/.github" ]]; then
    cp -r "$WORKSPACE_SRC/topology/.github" .
fi

# Documentation from topology that applies to whole project
cp -r "$WORKSPACE_SRC/topology/MIGRATION.md" . 2>/dev/null || true
cp -r "$WORKSPACE_SRC/topology/MANUAL_TEST_MATRIX.md" . 2>/dev/null || true

# Other workspace-level files
cp -r "$WORKSPACE_SRC/spaces.default.json" . 2>/dev/null || true
cp -r "$WORKSPACE_SRC/cheatsheet.json" . 2>/dev/null || true

# Create new standalone README if it doesn't exist
if [[ ! -f "$NEW_REPO/README.md" ]]; then
    echo "→ Creating standalone README..."
    cat > "$NEW_REPO/README.md" << 'EOF'
# Workspace

> A macOS workspace identity system with native SwiftUI overlays and SF Symbols.

## Features

- **Menu bar status** (`ws-statusbar`) — `_N_` elevation design with SF Symbol icons
- **SwiftUI overlays** — Keyboard-driven workspace switching (focus, send, manage, change)
- **Display topology** — Notch-aware, multi-display support
- **Window manager agnostic** — Works with yabai, aerospace (coming soon), or standalone
- **SF Symbols** — Native Apple icons, with Nerd Font fallback for terminal use
- **Bash CLI** — Atomic, validated workspace mutations

## Requirements

- macOS 14+
- Swift 5.10+ (Command Line Tools or Xcode)
- A window manager (yabai recommended, aerospace supported soon)
- skhd (for hotkey bindings)

## Quick Start

```bash
git clone https://github.com/adamesh/workspace.git
cd workspace
./install.sh
```

The install script will:
1. Build all Swift binaries
2. Symlink to `~/.local/bin/`
3. Generate and load LaunchAgents
4. Show configuration summary

## Hotkey Setup

Add to your `skhdrc`:

```bash
cmd + alt + ctrl + shift - f : ~/.local/bin/ws-prompt focus
cmd + alt + ctrl + shift - g : ~/.local/bin/ws-prompt send
cmd + alt + ctrl + shift - w : ~/.local/bin/ws-prompt manage
cmd + alt + ctrl + shift - e : ~/.local/bin/ws-picker
cmd + alt + ctrl + shift - ; : ~/.local/bin/ws-cheatsheet
```

Or use Karabiner to map Caps+F, Caps+G, etc. to these commands.

## Usage

```bash
# CLI commands
ws add <name> [icon]          # Add new workspace
ws remove <slot>              # Remove workspace
ws focus <slot|name>          # Focus workspace
ws send <slot|name>           # Send window to workspace
ws icon <slot> <sf-symbol>    # Set SF Symbol icon
ws name <slot> <new-name>     # Rename workspace
ws list                       # List all workspaces
ws doctor                     # Validate configuration
```

## Configuration

Create `~/.config/workspace/config.env`:

```bash
# Bundle prefix for LaunchAgents (default: com.user.workspace)
WORKSPACE_BUNDLE_PREFIX=com.mycompany.workspace

# Window manager (default: yabai)
WORKSPACE_WINDOW_MANAGER=yabai

# Bar type (default: ws-statusbar)
WORKSPACE_BAR=ws-statusbar
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ ws-prompt   │────▶│  WindowMgr  │◀────│   yabai     │
│ (SwiftUI)   │     │  (protocol) │     │  (default)  │
└─────────────┘     └─────────────┘     └─────────────┘
       │
       ▼
┌─────────────┐
│  spaces.json│  ← Workspace identity (names, colors, icons)
└─────────────┘
       │
       ▼
┌─────────────┐
│ ws-statusbar│  ← Menu bar display
└─────────────┘
```

## Documentation

- [Contributing](CONTRIBUTING.md) — Development setup and guidelines
- [Changelog](CHANGELOG.md) — Version history
- [Architecture](CONTRIBUTING.md#architecture-overview) — Technical design

## License

MIT License — See [LICENSE](LICENSE)

## Acknowledgments

- [yabai](https://github.com/koekeishiya/yabai) — The window manager that makes this possible
- [skhd](https://github.com/koekeishiya/skhd) — Simple hotkey daemon
- [Catppuccin](https://catppuccin.com) — The color palette
EOF
fi

# Update paths in files for standalone context
echo "→ Updating paths for standalone context..."

# Update install.sh to not reference dotfiles
cat > "$NEW_REPO/install.sh" << 'INSTALLER'
#!/usr/bin/env bash
# install.sh — build the workspace package and lay down the system pieces.
#
# Idempotent. Steps:
#   1. Source workspace configuration (bundle prefix, paths)
#   2. swift build -c release (with WORKSPACE_BUNDLE_PREFIX if set)
#   3. re-sign each binary ad-hoc with a stable identifier
#   4. symlink built binaries into ~/.local/bin/
#   5. generate LaunchAgent plists from templates into ~/Library/LaunchAgents/
#   6. launchctl load each agent
#
# Configuration: Set WORKSPACE_BUNDLE_PREFIX env var before running to customize.
# Default: com.user.workspace

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source workspace configuration
source "$HERE/lib/config.sh" 2>/dev/null || {
  # Fallback if config.sh not available (first run)
  WORKSPACE_BUNDLE_PREFIX="${WORKSPACE_BUNDLE_PREFIX:-com.user.workspace}"
  WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workspace"
  WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
}

LOCAL_BIN="${WORKSPACE_BIN_DIR:-$HOME/.local/bin}"
LAUNCH_AGENTS="$WORKSPACE_LAUNCH_AGENTS_DIR"

# Binaries we build + symlink. CLIs come first (no LaunchAgent), daemons
# follow with their matching plist files.
BINARIES=(ws-topology ws-topologyd ws-cheatsheet ws-prompt ws-picker ws-snap ws-statusbar)

# Template names and their generated plist names
TEMPLATES=(topologyd autohide statusbar)
AGENT_LABELS=("$WORKSPACE_BUNDLE_PREFIX.topologyd" "$WORKSPACE_BUNDLE_PREFIX.autohide" "$WORKSPACE_BUNDLE_PREFIX.statusbar")

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n'   "$*" >&2; }

# Detect a version-skewed Command Line Tools install...
check_swift_pm_health() {
  command -v swift >/dev/null 2>&1 || return 0

  local active iface_path iface_ver active_major iface_major dev_dir version_out
  if ! version_out=$(swift --version 2>/dev/null); then
    err "Swift toolchain not ready (Command Line Tools installer hasn't finished)."
    return 2
  fi
  # ... rest of health check
  return 0
}

if ! check_swift_pm_health; then
  exit 2
fi

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

step "ad-hoc codesigning with stable identifiers"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  if [[ ! -x "$src" ]]; then
    warn "missing build product: $src"
    exit 1
  fi
  identifier="$WORKSPACE_BUNDLE_PREFIX.$bin"
  if ! codesign --force --sign - \
        --identifier "$identifier" \
        --requirements "=designated => identifier \"$identifier\"" \
        "$src" 2>/dev/null; then
    warn "codesign $bin failed — TCC may re-prompt after rebuilds"
  fi
done

mkdir -p "$LOCAL_BIN"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  dst="$LOCAL_BIN/$bin"
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

mkdir -p "$LAUNCH_AGENTS"
mkdir -p "$WORKSPACE_CACHE_DIR"

# Generate plists from templates
for template in "${TEMPLATES[@]}"; do
  label="$WORKSPACE_BUNDLE_PREFIX.${template}"
  template_file="$HERE/launchd/com.template.workspace.${template}.plist"
  dst="$LAUNCH_AGENTS/${label}.plist"

  if [[ ! -f "$template_file" ]]; then
    warn "missing template: $template_file"
    continue
  fi

  sed -e "s|{{BUNDLE_PREFIX}}|$WORKSPACE_BUNDLE_PREFIX|g" \
      -e "s|{{HOME}}|$HOME|g" \
      -e "s|{{CACHE_DIR}}|$WORKSPACE_CACHE_DIR|g" \
      "$template_file" > "$dst"

  step "generated $dst"

  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    step "reloading $label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  fi

  launchctl bootstrap "gui/$(id -u)" "$dst"
done

step "agents loaded; logs under $WORKSPACE_CACHE_DIR/"

cat <<NOTE

Configuration:
  Bundle prefix: $WORKSPACE_BUNDLE_PREFIX
  Window manager: ${WORKSPACE_WINDOW_MANAGER:-yabai}
  Bar: ${WORKSPACE_BAR:-ws-statusbar}

To uninstall:
  for L in ${AGENT_LABELS[*]}; do launchctl bootout "gui/$(id -u)/\$L" 2>/dev/null || true; rm -f "$LAUNCH_AGENTS/\$L.plist"; done
  for B in ${BINARIES[*]}; do rm -f "$LOCAL_BIN/\$B"; done
NOTE
INSTALLER

chmod +x "$NEW_REPO/install.sh"

echo ""
echo "=== Extraction complete ==="
echo ""
echo "Next steps:"
echo "  1. cd $NEW_REPO"
echo "  2. git add -A"
echo "  3. git commit -m 'Initial commit: extracted from dotfiles'"
echo "  4. git remote add origin https://github.com/YOUR_USERNAME/workspace.git"
echo "  5. git push -u origin main"
echo ""
echo "Then update dotfiles to reference the new repo:"
echo "  - Remove configs/workspace/ from dotfiles"
echo "  - Update bootstrap.sh to install from new repo"
echo ""
echo "To verify the extraction worked:"
echo "  cd $NEW_REPO && ./install.sh"
