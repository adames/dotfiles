#!/usr/bin/env bash
# install.sh — build the topology package and lay down the system pieces.
#
# Idempotent. Steps:
#   1. swift build -c release
#   2. symlink built binaries into ~/.local/bin/
#   3. copy the LaunchAgent plist into ~/Library/LaunchAgents/
#   4. launchctl load the agent
#
# Does NOT run the v1→v2 migration on spaces.json. Run that explicitly:
#   ~/.local/bin/ws-topology migrate           # dry-run, prints diff
#   ~/.local/bin/ws-topology migrate --apply   # writes; backs up to spaces.v1.json

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
AGENT_LABEL="com.adames.workspace.topologyd"
AGENT_SOURCE="$HERE/launchd/${AGENT_LABEL}.plist"
AGENT_TARGET="$LAUNCH_AGENTS/${AGENT_LABEL}.plist"

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

mkdir -p "$LOCAL_BIN"
for bin in ws-topology ws-topologyd ws-cheatsheet; do
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
if cmp -s "$AGENT_SOURCE" "$AGENT_TARGET" 2>/dev/null; then
  step "LaunchAgent plist already up-to-date at $AGENT_TARGET"
else
  cp "$AGENT_SOURCE" "$AGENT_TARGET"
  step "installed $AGENT_TARGET"
fi

if launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1; then
  step "reloading $AGENT_LABEL"
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
fi
launchctl bootstrap "gui/$(id -u)" "$AGENT_TARGET"
step "agent loaded; logs at ~/.cache/workspace/ws-topologyd.{log,err}"

cat <<NOTE

Next steps:
  1. Dry-run the spaces.json migration:
       ws-topology migrate
  2. If the diff looks right, apply it:
       ws-topology migrate --apply
  3. Regenerate the dynamic skhd fragment + reload skhd:
       ws-topology emit-skhd --write --reload

To uninstall:
  launchctl bootout "gui/$(id -u)" "$AGENT_TARGET"
  rm -f "$LOCAL_BIN/ws-topology" "$LOCAL_BIN/ws-topologyd"
  rm -f "$AGENT_TARGET"
NOTE
