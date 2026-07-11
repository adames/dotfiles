# Shared bootstrap helpers. Source: `. "$DOTFILES_DIR/lib/common.sh"`

set -u

: "${DOTFILES_DIR:=$HOME/dotfiles}"
: "${CONFIGS_DIR:=$DOTFILES_DIR/configs}"
: "${DOTFILES_REPO:=git@github.com:adames/dotfiles.git}"

# Colour off when stdout isn't a tty or NO_COLOR is set
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=''; C_BOLD=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''
fi

section() { printf '\n%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }

step() { printf '%s-->%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[err]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }
# Interactive ⇔ stdin is a tty. stdin ONLY — gating on stdout too made
# `./bootstrap.sh | tee log` go headless (casks skipped, sudo not cached).
has_tty() { [[ -t 0 ]]; }

# install_file <src> <dst> [mode] — byte-compare; no-op if identical
install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  [[ -f "$src" ]] || { warn "skip $dst (source missing: $src)"; return 0; }
  mkdir -p "$(dirname "$dst")"
  [[ -f "$dst" ]] && cmp -s "$src" "$dst" && return 0
  install -m "$mode" "$src" "$dst"
  ok "installed ${dst/#$HOME/~}"
}

# ensure_gitconfig_local — one-time ~/.gitconfig.local stub. User identity
# lives there (untracked, [include]'d by configs/gitconfig); both platform
# bootstraps call this so the two paths stay symmetric.
ensure_gitconfig_local() {
  [[ -f "$HOME/.gitconfig.local" ]] && return 0
  cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
	email = you@example.com
	name = Your Name
EOF
  ok "created ~/.gitconfig.local stub — edit user.email / user.name"
}

