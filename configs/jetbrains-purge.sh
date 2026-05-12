#!/usr/bin/env bash
# Rip JetBrains tooling and its scattered Library/* artifacts off the
# system. Dry-run by default — pass --commit to actually delete things.
# Project directories (~/IdeaProjects, ~/WebstormProjects) are LEFT
# ALONE unless --delete-projects is also passed; they're user code.
#
# Nothing in bootstrap.sh invokes this; the user runs it explicitly when
# the IDEs are no longer needed. Pattern matches the rest of the repo's
# "no destructive defaults" tone.
#
# Usage:
#   bash configs/jetbrains-purge.sh                       # dry run, lists everything
#   bash configs/jetbrains-purge.sh --commit              # actually remove IDE cruft + casks
#   bash configs/jetbrains-purge.sh --commit --delete-projects
#                                                          # ALSO remove ~/IdeaProjects
#                                                          # and ~/WebstormProjects (user code!)

set -u

. "${DOTFILES_DIR:-$HOME/dotfiles}/lib/common.sh"

COMMIT=0
DELETE_PROJECTS=0
for arg in "$@"; do
  case "$arg" in
    --commit)            COMMIT=1 ;;
    --delete-projects)   DELETE_PROJECTS=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      printf 'unknown flag: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

mode() { printf '%s%s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }

if (( COMMIT == 0 )); then
  mode "── DRY RUN ── nothing will be deleted. Pass --commit to act."
else
  mode "── COMMIT MODE ── selected items WILL be deleted."
fi
echo

# ── 1 · refuse if anything JetBrains is running ─────────────────────────
running=$(
  pgrep -if 'idea|webstorm|pycharm|datagrip|rubymine|goland|clion|rider|phpstorm|jetbrains' \
    2>/dev/null | wc -l | tr -d ' '
)
if [[ "$running" != "0" ]]; then
  err "JetBrains processes still running ($running). Quit them and rerun."
  pgrep -ifl 'idea|webstorm|pycharm|datagrip|rubymine|goland|clion|rider|phpstorm|jetbrains'
  exit 1
fi

# Helper. List then optionally remove.
maybe_rm() {
  local label="$1"; shift
  local found=0
  for path in "$@"; do
    # Glob expansion happens at the call site; an unmatched literal
    # comes through verbatim — skip it.
    if [[ ! -e "$path" && ! -L "$path" ]]; then continue; fi
    found=1
    if (( COMMIT == 1 )); then
      printf '  rm -rf %s\n' "${path/#$HOME/~}"
      rm -rf -- "$path"
    else
      printf '  would rm -rf %s\n' "${path/#$HOME/~}"
    fi
  done
  if (( found == 0 )); then
    printf '  %s(none present)%s\n' "$C_DIM" "$C_RESET"
  fi
}

# ── 2 · IDE Library cruft ───────────────────────────────────────────────
step "JetBrains config / caches / logs / saved state"
maybe_rm "JetBrains app support" \
  "$HOME/Library/Application Support/JetBrains" \
  "$HOME/Library/Caches/JetBrains" \
  "$HOME/Library/Logs/JetBrains"

step "JetBrains preference plists"
# Glob expansion — the array form would prevent it; keep as positional.
shopt -s nullglob
maybe_rm "Preferences" \
  "$HOME"/Library/Preferences/com.jetbrains.* \
  "$HOME"/Library/Preferences/jetbrains.*
maybe_rm "Saved Application State" \
  "$HOME"/Library/Saved\ Application\ State/com.jetbrains.*.savedState
shopt -u nullglob

# ── 3 · brew casks ──────────────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
  step "JetBrains brew casks"
  installed=$(
    brew list --cask 2>/dev/null \
      | grep -iE '^(intellij-idea|intellij-idea-ce|webstorm|pycharm|pycharm-ce|datagrip|rubymine|goland|clion|rider|phpstorm|jetbrains-toolbox)$' \
      || true
  )
  if [[ -z "$installed" ]]; then
    printf '  %s(no JetBrains casks installed)%s\n' "$C_DIM" "$C_RESET"
  else
    while read -r cask; do
      [[ -z "$cask" ]] && continue
      if (( COMMIT == 1 )); then
        printf '  brew uninstall --cask %s\n' "$cask"
        brew uninstall --cask "$cask" 2>&1 | sed 's/^/    /'
      else
        printf '  would brew uninstall --cask %s\n' "$cask"
      fi
    done <<< "$installed"
  fi
else
  warn "brew not on PATH — skipping cask removal"
fi

# ── 4 · project directories (gated separately) ──────────────────────────
step "Project directories"
projects=()
[[ -d "$HOME/IdeaProjects" ]]      && projects+=("$HOME/IdeaProjects")
[[ -d "$HOME/WebstormProjects" ]]  && projects+=("$HOME/WebstormProjects")

if [[ ${#projects[@]} -eq 0 ]]; then
  printf '  %s(no project dirs to consider)%s\n' "$C_DIM" "$C_RESET"
elif (( DELETE_PROJECTS == 0 )); then
  warn "leaving project dirs in place (require --delete-projects to remove):"
  for p in "${projects[@]}"; do
    printf '    %s  %s%s\n' "${p/#$HOME/~}" "$C_DIM" \
      "($(find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') subdirs)$C_RESET"
  done
  printf '  %sback up first: tar -czf ~/jetbrains-projects-$(date +%%F).tgz %s%s\n' \
    "$C_DIM" "${projects[*]/#$HOME/~}" "$C_RESET"
else
  warn "DELETING project dirs (--delete-projects passed):"
  maybe_rm "Project dirs" "${projects[@]}"
fi

# ── 5 · advisories ──────────────────────────────────────────────────────
echo
warn "~/.gradle is shared between JetBrains and other tooling (Android Studio, CLI gradle, AGP) — this script never touches it. Inspect by hand if you're sure: rm -rf ~/.gradle"
warn "Per-project .idea/ folders inside any retained project dir stay in place — they go with the project."

if (( COMMIT == 0 )); then
  echo
  ok  "dry run complete — pass --commit to remove the items above"
else
  echo
  ok  "commit complete"
fi
