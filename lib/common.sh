# lib/common.sh — shared helpers sourced by every platform bootstrap.
# Not executable on its own. Source it: `. "$DOTFILES_DIR/lib/common.sh"`.
#
# Provides:
#   • Locations:  DOTFILES_DIR, CONFIGS_DIR, DOTFILES_REPO
#   • Logging:    section/step/ok/warn/err/info  (color-aware, NO_COLOR honoured)
#   • Predicates: have, has_tty
#   • Files:      backup, install_file, ensure_dir
#
# Design rules:
#   • `step` is the workhorse — one line per individual operation.
#   • `section` opens a phase visually. Use sparingly: 4–8 sections per script.
#   • `ok`     marks a positive completion; `warn`/`err` go to stderr.
#   • Output stays grep-able: prefix glyphs are single chars, no leading spaces.

# ── locations ───────────────────────────────────────────────────────────────
: "${DOTFILES_DIR:=$HOME/dotfiles}"
: "${CONFIGS_DIR:=$DOTFILES_DIR/configs}"
: "${DOTFILES_REPO:=git@github.com:adames/dotfiles.git}"

# ── colour ──────────────────────────────────────────────────────────────────
# Disabled when stdout isn't a TTY (CI, piped) or NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m';   C_DIM=$'\033[2m';     C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m';   C_GREEN=$'\033[32m';  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m';    C_CYAN=$'\033[36m';   C_MAGENTA=$'\033[35m'
else
  C_RESET=''; C_DIM=''; C_BOLD=''
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_MAGENTA=''
fi

# ── logging ─────────────────────────────────────────────────────────────────
# section "Phase 2/6 · packages"
#   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#     Phase 2/6 · packages
#   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section() {
  local title="$1"
  local rule
  rule=$(printf '━%.0s' {1..68})
  printf '\n%s%s%s\n  %s%s%s\n%s%s%s\n' \
    "$C_BOLD$C_CYAN" "$rule" "$C_RESET" \
    "$C_BOLD" "$title" "$C_RESET" \
    "$C_DIM"  "$rule" "$C_RESET"
}

# Banner shown once at the top of a bootstrap. Two short lines, centred-ish.
banner() {
  local line1="$1" line2="${2:-}"
  local rule
  rule=$(printf '═%.0s' {1..68})
  printf '\n%s%s%s\n' "$C_BOLD$C_MAGENTA" "$rule" "$C_RESET"
  printf '  %s%s%s\n' "$C_BOLD" "$line1" "$C_RESET"
  [[ -n "$line2" ]] && printf '  %s%s%s\n' "$C_DIM" "$line2" "$C_RESET"
  printf '%s%s%s\n\n' "$C_BOLD$C_MAGENTA" "$rule" "$C_RESET"
}

# step  — neutral progress line.       •  installing CLI tools
# ok    — positive completion.         ✓  installed: ripgrep, fd, gh
# warn  — non-fatal issue (stderr).    !  iTerm2 prefs not found, skipping
# err   — fatal-ish (stderr).          ✗  unsupported OS
# info  — secondary detail (dim).        ↳  re-run with --step <name>
step() { printf '%s•%s %s\n'                       "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf '%s✓%s %s\n'                       "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n'                       "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s✗%s %s\n'                       "$C_RED"    "$C_RESET" "$*" >&2; }
info() { printf '%s  ↳ %s%s\n'                     "$C_DIM"    "$*"       "$C_RESET"; }

# Backwards-compat: older scripts still call log() — alias to step().
log()  { step "$@"; }

# ── predicates ──────────────────────────────────────────────────────────────
have()    { command -v "$1" >/dev/null 2>&1; }
has_tty() { [[ -t 0 && -t 1 ]]; }

# ── file deployment ─────────────────────────────────────────────────────────
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
  info "backed up $dst → $dst.bak"
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
  ok "installed ${dst/#$HOME/~}"
}

ensure_dir() { mkdir -p "$1"; }
