#!/usr/bin/env bash
# bootstrap.sh — OS dispatcher.
#
# Detects the host OS and hands off to the right platform bootstrap.
# All real work lives in macos/ or ubuntu/. Shared helpers live in lib/.
#
# Override the repo URL with DOTFILES_REPO=...  (only used by ubuntu/).

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"

case "$(uname -s)" in
  Darwin)
    exec "$DOTFILES_DIR/macos/bootstrap.sh" "$@"
    ;;
  Linux)
    if [[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release; then
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
