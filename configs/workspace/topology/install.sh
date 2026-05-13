#!/usr/bin/env bash
# install.sh — build the topology package and lay down the system pieces.
#
# Idempotent. Steps:
#   1. swift build -c release
#   2. symlink built binaries into ~/.local/bin/
#   3. copy the LaunchAgent plists into ~/Library/LaunchAgents/
#   4. launchctl load each agent
#
# Does NOT run the v1→v2 migration on spaces.json. Run that explicitly:
#   ~/.local/bin/ws-topology migrate           # dry-run, prints diff
#   ~/.local/bin/ws-topology migrate --apply   # writes; backs up to spaces.v1.json

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

# Binaries we build + symlink. CLIs come first (no LaunchAgent), daemons
# follow with their matching plist files.
BINARIES=(ws-topology ws-topologyd ws-cheatsheet ws-autohide ws-snap)
AGENT_LABELS=(com.adames.workspace.topologyd com.adames.workspace.autohide)

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

mkdir -p "$LOCAL_BIN"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  dst="$LOCAL_BIN/$bin"
  if [[ ! -x "$src" ]]; then
    warn "missing build product: $src"
    exit 1
  fi
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

mkdir -p "$LAUNCH_AGENTS"
for label in "${AGENT_LABELS[@]}"; do
  src="$HERE/launchd/${label}.plist"
  dst="$LAUNCH_AGENTS/${label}.plist"
  if cmp -s "$src" "$dst" 2>/dev/null; then
    step "LaunchAgent plist already up-to-date: $dst"
  else
    cp "$src" "$dst"
    step "installed $dst"
  fi

  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    step "reloading $label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  fi
  launchctl bootstrap "gui/$(id -u)" "$dst"
done
step "agents loaded; logs under ~/.cache/workspace/"

cat <<NOTE

Next steps:
  1. Dry-run the spaces.json migration:
       ws-topology migrate
  2. If the diff looks right, apply it:
       ws-topology migrate --apply
  3. Regenerate the dynamic skhd fragment + reload skhd:
       ws-topology emit-skhd --write --reload

To uninstall:
  for L in ${AGENT_LABELS[*]}; do launchctl bootout "gui/\$(id -u)" "$LAUNCH_AGENTS/\$L.plist"; rm -f "$LAUNCH_AGENTS/\$L.plist"; done
  for B in ${BINARIES[*]}; do rm -f "$LOCAL_BIN/\$B"; done
NOTE
