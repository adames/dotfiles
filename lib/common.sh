# Shared bootstrap helpers. Source: `. "$DOTFILES_DIR/lib/common.sh"`.

: "${DOTFILES_DIR:=$HOME/dotfiles}"
: "${CONFIGS_DIR:=$DOTFILES_DIR/configs}"
: "${DOTFILES_REPO:=git@github.com:adames/dotfiles.git}"

# Colour off when stdout isn't a tty or NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m';   C_DIM=$'\033[2m';     C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m';   C_GREEN=$'\033[32m';  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m';    C_CYAN=$'\033[36m';   C_MAGENTA=$'\033[35m'
else
  C_RESET=''; C_DIM=''; C_BOLD=''
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_MAGENTA=''
fi

banner() {
  local rule; rule=$(printf '═%.0s' {1..68})
  printf '\n%s%s%s\n' "$C_BOLD$C_MAGENTA" "$rule" "$C_RESET"
  printf '  %s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
  [[ -n "${2:-}" ]] && printf '  %s%s%s\n' "$C_DIM" "$2" "$C_RESET"
  printf '%s%s%s\n\n' "$C_BOLD$C_MAGENTA" "$rule" "$C_RESET"
}

section() {
  local rule; rule=$(printf '━%.0s' {1..68})
  printf '\n%s%s%s\n  %s%s%s\n%s%s%s\n' \
    "$C_BOLD$C_CYAN" "$rule" "$C_RESET" \
    "$C_BOLD" "$1" "$C_RESET" \
    "$C_DIM"  "$rule" "$C_RESET"
}

step() { printf '%s•%s %s\n'   "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf '%s✓%s %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n'   "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s✗%s %s\n'   "$C_RED"    "$C_RESET" "$*" >&2; }
info() { printf '%s  ↳ %s%s\n' "$C_DIM"    "$*"       "$C_RESET"; }
log()  { step "$@"; }   # back-compat alias

have()    { command -v "$1" >/dev/null 2>&1; }
has_tty() { [[ -t 0 && -t 1 ]]; }

# Backup once: dst exists, isn't a symlink, no prior .bak, and dst differs from src.
backup() {
  local dst="$1" src="${2:-}"
  [[ -e "$dst" && ! -L "$dst" && ! -e "$dst.bak" ]] || return 0
  [[ -n "$src" && -f "$src" ]] && cmp -s "$src" "$dst" && return 0
  cp -p "$dst" "$dst.bak"
  info "backed up $dst → $dst.bak"
}

# install_file <src> <dst> [mode]  — byte-compare; no-op if identical.
install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  [[ -f "$src" ]] || { warn "skip $dst (source missing: $src)"; return 0; }
  mkdir -p "$(dirname "$dst")"
  backup "$dst" "$src"
  [[ -f "$dst" ]] && cmp -s "$src" "$dst" && return 0
  install -m "$mode" "$src" "$dst"
  ok "installed ${dst/#$HOME/~}"
}

ensure_dir() { mkdir -p "$1"; }
