# lib/ws-doctor-checks.sh — the individual ws-doctor checks.
#
# Sourced by bin/ws-doctor after it defines the PASS/WARN/FAIL/SKIP
# recorders. Each check_* function is independent, appends one report
# line via those recorders, and never exits — so one run reports every
# problem at once. The dispatcher (CHECKS array) and the rendering live
# in bin/ws-doctor; this file is just the check bodies, split out to keep
# the entry point readable.
#
# Only one check survives. The aerospace-era checks (freshness, keystroke
# collision, app casing, daemon, phantom tiles) went with AeroSpace; the
# sigil-era ones (menu-item resolution, `tell application` targets) went
# with sigil — once the AppleScript that drove apps by menu-clicking was
# gone, both scanned a repo that no longer contained a single match and
# reported "none found" forever. Git history has the bodies if a future
# surface needs them back.
#
# These functions assume the caller has already sourced lib/common.sh
# (for `warn`) and exported DOTFILES_DIR.

# ─── source/deploy drift ────────────────────────────────────────────────────
# Configs in `~/dotfiles/configs/` are *copied* to runtime locations by
# bootstrap.sh. If a fix lands in only one of the two, the next bootstrap
# either reverts the fix (source stale) or the running system stays
# vulnerable (deploy stale).
#
# The pairs are read straight out of macos/bootstrap.sh's install_file
# calls rather than restated here. A hand-maintained list drifted the
# moment someone added a config — it covered 2 of 13 deployed files, so
# the drift this check exists to catch went unnoticed in ~/.zshrc,
# ~/.gitconfig, the nvim trio, and the rest. Parsing the one place that
# already knows the mapping keeps them in lockstep by construction.
#
# Hyperkey stores its config in user defaults, not a file we can
# pair-cmp, so it's still not represented here.
check_source_deploy_drift() {
  # macos/bootstrap.sh where it exists (any Mac, any full clone); a sparse
  # Linux clone prunes macos/, and ubuntu/bootstrap.sh's phase_configs uses
  # the identical install_file shape — parse whichever this clone runs.
  local bootstrap="$DOTFILES_DIR/macos/bootstrap.sh"
  [[ -f "$bootstrap" ]] || bootstrap="$DOTFILES_DIR/ubuntu/bootstrap.sh"
  if [[ ! -f "$bootstrap" ]]; then
    SKIP source-deploy-drift "no platform bootstrap found"
    return 0
  fi

  # install_file "<src>" "<dst>" [mode] — pull the two quoted paths and
  # expand the three variables bootstrap uses in them. Anything with an
  # unexpanded "$" left over is a shape we don't understand; skip it
  # loudly rather than silently comparing a literal path.
  local pairs=() unparsed=0 line src dst
  while IFS= read -r line; do
    src="$(sed -n 's/.*install_file[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$line")"
    dst="$(sed -n 's/.*install_file[[:space:]]*"[^"]*"[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$line")"
    [[ -n "$src" && -n "$dst" ]] || { unparsed=$((unparsed + 1)); continue; }
    src="${src//\$CONFIGS_DIR/$DOTFILES_DIR/configs}"
    src="${src//\$DOTFILES_DIR/$DOTFILES_DIR}"
    dst="${dst//\$HOME/$HOME}"
    if [[ "$src$dst" == *'$'* ]]; then
      unparsed=$((unparsed + 1))
      continue
    fi
    pairs+=("$src::$dst")
  done < <(grep -E '^[[:space:]]*install_file[[:space:]]+"' "$bootstrap")

  if (( ${#pairs[@]} == 0 )); then
    SKIP source-deploy-drift "no install_file pairs parsed from ${bootstrap#"$DOTFILES_DIR"/}"
    return 0
  fi

  local drifted=0 missing=0 detail="" pair
  for pair in "${pairs[@]}"; do
    src="${pair%%::*}"; dst="${pair#*::}"
    if [[ ! -f "$src" ]]; then
      missing=$((missing + 1))
      detail+="  missing source: ${src/#$HOME/~}"$'\n'
      continue
    fi
    if [[ ! -f "$dst" ]]; then
      missing=$((missing + 1))
      detail+="  not deployed: ${dst/#$HOME/~}"$'\n'
      continue
    fi
    if ! cmp -s "$src" "$dst"; then
      drifted=$((drifted + 1))
      detail+="  drift: ${src/#$HOME/~} vs ${dst/#$HOME/~}"$'\n'
    fi
  done

  (( unparsed > 0 )) && detail+="  $unparsed install_file line(s) not parsed"$'\n'

  # Every branch leads with "<N> configs" so the count is parseable from any
  # outcome — a CI runner with nothing deployed hits the WARN branch, and the
  # test that guards this check's coverage still needs to read N there.
  if (( drifted == 0 && missing == 0 && unparsed == 0 )); then
    PASS source-deploy-drift "${#pairs[@]} configs in sync"
  elif (( drifted == 0 )); then
    WARN source-deploy-drift "${#pairs[@]} configs: $missing missing, $unparsed unparsed"$'\n'"$detail"
  else
    FAIL source-deploy-drift "${#pairs[@]} configs: $drifted drifted; run: bash $bootstrap"$'\n'"$detail"
  fi
}
