#!/usr/bin/env bash
# Ensure yabai has exactly TARGET (default 10) spaces total across all
# displays, then apply stable labels by index. Called by ~/.yabairc at
# startup AND by the display_added signal so attaching/detaching a
# monitor mid-session also reaches the right total without re-login.
#
# Requires the yabai scripting addition. If SA is not loaded,
# `--create` and `--destroy` print
# "cannot create/destroy space due to an error with the scripting-addition"
# and we break the inner loop — no infinite spin, just a no-op until the
# user runs macos/yabai-sa-install.sh.
#
# Destruction is OPT-IN. Default behaviour is to top up only; if the
# user has more spaces than TARGET (e.g., from a prior 12-space layout)
# we warn and leave them. Pass TARGET_STRICT=1 to actually destroy
# extras — that operation may carry windows with it, so it's not a safe
# default.

set -e

TARGET="${1:-10}"

# Single source of truth for the slot labels: lib/colors.sh. Sourced
# from either the dotfiles checkout or the deployed library copy at
# ~/.config/workspace/lib/colors.sh (dropped there by the workspace
# install.sh). Falls back to inline defaults if neither is reachable —
# the script must keep working even when the dotfiles tree is missing
# (e.g., on a fresh boot before bootstrap re-runs).
for _src in \
  "${DOTFILES_DIR:-$HOME/dotfiles}/lib/colors.sh" \
  "$HOME/.config/workspace/lib/colors.sh"; do
  if [ -r "$_src" ]; then
    # shellcheck source=/dev/null
    . "$_src"
    break
  fi
done
if [ "${#WORKSPACE_LABELS[@]}" -gt 0 ]; then
  LABELS=("${WORKSPACE_LABELS[@]}")
else
  LABELS=(core forge codex lex scope uplink signal ledger craft void)
fi

# Save original focused display; the create-loop moves focus per-display
# because `yabai -m space --create` operates on the currently focused
# one. We restore at the end so the user doesn't notice the shuffle.
ORIG="$(yabai -m query --displays --display 2>/dev/null | jq '.index // 1')"

# ── 1 · top up to TARGET ────────────────────────────────────────────────
# Focus display 1 so all new spaces land there; the reconcile-displays
# helper redistributes them based on which screen is the laptop.
yabai -m display --focus 1 2>/dev/null || true

current=$(yabai -m query --spaces 2>/dev/null | jq 'length')
while (( current < TARGET )); do
  if ! yabai -m space --create 2>/dev/null; then
    break
  fi
  current=$(yabai -m query --spaces | jq 'length')
done

# ── 2 · destroy extras (opt-in) ─────────────────────────────────────────
if (( current > TARGET )); then
  if [[ "${TARGET_STRICT:-0}" == 1 ]]; then
    while (( current > TARGET )); do
      last=$(yabai -m query --spaces | jq '[.[].index] | max')
      yabai -m space --destroy "$last" 2>/dev/null || break
      current=$(yabai -m query --spaces | jq 'length')
    done
  else
    printf 'yabai-ensure-spaces: %d spaces present, target %d — leaving extras (set TARGET_STRICT=1 to destroy)\n' \
      "$current" "$TARGET" >&2
  fi
fi

# ── 3 · apply stable labels by index ────────────────────────────────────
# Labels are how every other workspace component (on-space-changed.sh,
# reconcile-displays.sh, jankyborders setter) identifies a space across
# display moves and reorderings. Re-labelling to the same value is a
# no-op for yabai, so this loop is safe to run on every boot.
i=1
for label in "${LABELS[@]}"; do
  yabai -m space "$i" --label "$label" 2>/dev/null || true
  ((i++)) || true
done

yabai -m display --focus "$ORIG" 2>/dev/null || true
