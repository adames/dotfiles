# lib/common.sh — shared helpers sourced by every platform bootstrap.
# Not executable on its own. Source it: `. "$DOTFILES_DIR/lib/common.sh"`.

# Locations (callers may override DOTFILES_DIR before sourcing).
: "${DOTFILES_DIR:=$HOME/dotfiles}"
: "${CONFIGS_DIR:=$DOTFILES_DIR/configs}"
: "${DOTFILES_REPO:=git@github.com:adames/dotfiles.git}"

# Colored logging (FD 1 for log, FD 2 for warn/err).
log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Whether the current shell has a controlling TTY (interactive). Cask installs
# and password prompts require this; we degrade gracefully when missing.
has_tty() { [[ -t 0 && -t 1 ]]; }

# Backup once: only if dst exists, isn't a symlink, and no prior .bak. If a
# src is provided and dst already matches it byte-for-byte, skip — otherwise
# we'd create a useless duplicate on idempotent re-runs.
backup() {
  local dst="$1" src="${2:-}"
  [[ -e "$dst" && ! -L "$dst" && ! -e "$dst.bak" ]] || return 0
  if [[ -n "$src" && -f "$src" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  cp -p "$dst" "$dst.bak"
  log "backed up $dst -> $dst.bak"
}

# install_file <src> <dst> [mode]
# Copies src to dst with optional mode. Creates parent dirs. Backs up first
# time. No-ops cleanly when dst already matches src.
install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [[ ! -f "$src" ]]; then
    warn "skip $dst (source $src not present)"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  backup "$dst" "$src"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  install -m "$mode" "$src" "$dst"
  log "installed $dst"
}

ensure_dir() { mkdir -p "$1"; }
