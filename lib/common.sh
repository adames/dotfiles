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

# Run log — every warn/err also appends here so the end-of-run summary can
# replay them without any call site having to opt in. It's a FILE, not an
# array, because bootstrap shells out to separate processes (update-system,
# macos-defaults.sh, the wizard); an array would only ever collect the
# parent's own warnings. Exported, so children append to the same log.
# A caller that sources common.sh outside a bootstrap run (ws-doctor) gets
# one too and simply never prints a summary.
if [[ -z "${DOTFILES_RUN_LOG:-}" ]]; then
  # Explicit XXXXXX template, not `mktemp -t dotfiles-run`: BSD/macOS mktemp
  # appends the random suffix for you, GNU/Linux mktemp rejects the template
  # outright ("too few X's"). Under ubuntu/bootstrap.sh's `set -euo pipefail`
  # that aborted the run on the first sourced line. Fall back to a PID-named
  # path so a read-only or unusual TMPDIR degrades instead of killing the run.
  DOTFILES_RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/dotfiles-run.XXXXXX" 2>/dev/null \
                      || printf '%s/dotfiles-run.%s' "${TMPDIR:-/tmp}" "$$")"
  export DOTFILES_RUN_LOG
  : "${DOTFILES_RUN_START:=$SECONDS}"
  export DOTFILES_RUN_START
fi

section() { printf '\n%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }

step() { printf '%s-->%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
         printf 'WARN\t%s\n' "$*" >> "$DOTFILES_RUN_LOG" 2>/dev/null || true; }
err()  { printf '%s[err]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
         printf 'ERR\t%s\n' "$*" >> "$DOTFILES_RUN_LOG" 2>/dev/null || true; }

# note <msg> — a real finding that isn't a failure. Things like "a newer
# python exists but your mise config pins you below it": burying that under
# [ok] is how it goes unread for months, but it isn't a warning either.
note() { printf '%s[note]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
         printf 'NOTE\t%s\n' "$*" >> "$DOTFILES_RUN_LOG" 2>/dev/null || true; }

# brew_quiet — filter for `brew bundle` output. On a settled machine every
# one of the ~25 entries prints "Using <pkg>", which buries the two lines
# that matter. Collapse those into a count; pass Installing/Upgrading/Error
# through verbatim, since those ARE the state change or the failure.
# Zero maintenance: it keys off brew's verbs, not off our package list.
brew_quiet() {
  awk -v ind="    " '
    /^Using /                    { using++;   next }
    /^Skipping /                 { skipped++; next }
    /^`brew bundle` complete!/   { next }        # our tally replaces it
    { print ind $0 }                             # Installing/Upgrading/errors
    END {
      line = ""
      if (using)   line = using " already installed"
      if (skipped) line = line (line ? " · " : "") skipped " skipped"
      if (line)    print ind line
    }
  '
}

# apt_quiet — filter for apt-get. Allowlist, not blocklist: apt's verbose
# output is mostly multi-line package manifests with indented continuation
# lines, so "drop these prefixes" let ~100 lines of dependency names through
# on a first install. Print only what carries information — apt's own
# one-line tally, and anything it flags as a problem — and drop the rest.
# Robust by construction: new apt chatter is dropped by default rather than
# needing a new rule here.
apt_quiet() {
  awk -v ind="    " '
    /upgraded,.*newly installed/          { tally = $0; next }
    /^[EW]:/                              { print ind $0; next }
    /^(dpkg|apt): error/                  { print ind $0; next }
    /[Ee]rror:/                           { print ind $0; next }
    { next }
    END { if (tally) print ind tally }
  '
}

# run_quiet <label> <cmd…> — for third-party installers that spray progress
# bars over stderr (the fzf and mise installers both do, and `>/dev/null`
# misses them because they write to fd 2). Swallow the output on success;
# replay all of it on failure, which is the only time anyone wants it.
run_quiet() {
  local label="$1"; shift
  local out status=0
  # `if` context so `set -e` doesn't abort before we can report.
  if out="$("$@" 2>&1)"; then status=0; else status=$?; fi
  if (( status != 0 )); then
    err "$label failed (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
  return "$status"
}

# phase <title> — auto-numbered section header. The count comes from the
# PHASES array the caller iterates, so inserting, removing or reordering a
# phase never means renumbering the rest by hand. (ubuntu/bootstrap.sh used
# to label seven phases "0/6" through "6/6".)
PHASE_N=0
phase() {
  PHASE_N=$((PHASE_N + 1))
  section "Phase $PHASE_N/${PHASE_TOTAL:-?} · $*"
}

# run_summary — the closing block. Reads the run log, so it needs no
# cooperation from any phase: whatever called warn/err/note shows up.
run_summary() {
  local warns errs notes elapsed
  # `grep -c` already prints 0 when nothing matches — it just exits 1 while
  # doing so. `|| true` swallows the status; `|| echo 0` would append a
  # second zero and feed "0\n0" into the arithmetic below.
  warns=$(grep -c '^WARN' "$DOTFILES_RUN_LOG" 2>/dev/null || true)
  errs=$(grep  -c '^ERR'  "$DOTFILES_RUN_LOG" 2>/dev/null || true)
  notes=$(grep -c '^NOTE' "$DOTFILES_RUN_LOG" 2>/dev/null || true)
  : "${warns:=0}" "${errs:=0}" "${notes:=0}"
  elapsed=$(( SECONDS - ${DOTFILES_RUN_START:-0} ))

  if (( errs > 0 )); then
    section "Finished with errors · ${elapsed}s"
  elif (( warns > 0 )); then
    section "Finished with warnings · ${elapsed}s"
  else
    section "All good · ${elapsed}s"
  fi
  printf '    %d error · %d warning · %d note\n' "$errs" "$warns" "$notes"

  # Replay the non-ok lines so a long scrollback doesn't hide them.
  if (( errs + warns + notes > 0 )); then
    printf '\n'
    local kind msg colour
    while IFS=$'\t' read -r kind msg; do
      case "$kind" in
        ERR)  colour="$C_RED" ;;
        WARN) colour="$C_YELLOW" ;;
        *)    colour="$C_BLUE" ;;
      esac
      printf '    %s%-6s%s %s\n' "$colour" "$(tr A-Z a-z <<<"$kind")" "$C_RESET" "$msg"
    done < "$DOTFILES_RUN_LOG"
  fi
  printf '\n'
}

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

# ensure_claude_skills — ~/.claude/skills is its own repo (adames/claude-skills),
# cloned *as* that directory so Claude Code discovers skills without copying.
# Clone if absent; if the dir exists without .git, leave it and warn — local
# skills there would be lost by a blind clone.
ensure_claude_skills() {
  local dir="$HOME/.claude/skills"
  if [[ -d "$dir/.git" ]]; then return 0; fi
  if [[ -d "$dir" ]]; then warn "~/.claude/skills exists but is not the claude-skills repo — see its README"; return 0; fi
  if git clone -q git@github.com:adames/claude-skills.git "$dir" 2>/dev/null; then
    ok "cloned claude-skills -> ~/.claude/skills"
  else
    warn "could not clone claude-skills (no SSH key yet?) — rerun bootstrap after keys are set"
  fi
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

