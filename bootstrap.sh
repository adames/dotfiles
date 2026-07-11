#!/usr/bin/env bash
# bootstrap.sh — OS dispatcher.
#
# Detects the host OS and hands off to the right platform bootstrap.
# All real work lives in macos/ or ubuntu/. Shared helpers live in lib/.
#
# Override the repo URL with DOTFILES_REPO=...  (only used by ubuntu/).

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

case "$(uname -s)" in
  Darwin)
    exec "$DOTFILES_DIR/macos/bootstrap.sh" "$@"
    ;;
  Linux)
    # /etc/os-release is the systemd-standard identity file; matching
    # ID_LIKE too catches derivatives (Pop!_OS, Mint) that the old
    # lsb-release check missed.
    if [[ -r /etc/os-release ]] && grep -qiE '^ID(_LIKE)?=.*ubuntu' /etc/os-release; then
      exec "$DOTFILES_DIR/ubuntu/bootstrap.sh" "$@"
    fi
    err "unsupported Linux distribution (only Ubuntu is wired up)"
    exit 1
    ;;
  *)
    err "unsupported OS: $(uname -s)"
    exit 1
    ;;
esac
