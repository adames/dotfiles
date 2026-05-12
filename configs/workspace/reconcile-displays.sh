#!/usr/bin/env bash
# Reconcile space ↔ display assignment so that the laptop screen always
# hosts slot 1 ("core") and any external display hosts slots 2..10.
#
# Triggered by yabai signals: display_added, display_removed, display_changed.
# Idempotent. Safe to run by hand. Requires the yabai scripting addition
# for `yabai -m space N --display M` to actually move the space.
#
# Display identification: macOS' yabai display *index* is volatile (it
# renumbers on plug/unplug), so we resolve through the *UUID* of the
# built-in panel, captured once by laptop-uuid-init.sh.

set -u

WS_LAPTOP_UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"
WS_RECONCILE_LOCK="${WS_RECONCILE_LOCK:-$HOME/.cache/workspace/.reconcile.lock}"
WS_DEBOUNCE_MS=200

mkdir -p "$(dirname "$WS_RECONCILE_LOCK")"

# Single source of truth for slot labels. Same fallback logic as
# yabai-ensure-spaces.sh so both stay in lockstep.
for _src in \
  "${DOTFILES_DIR:-$HOME/dotfiles}/lib/colors.sh" \
  "$HOME/.config/workspace/lib/colors.sh"; do
  if [ -r "$_src" ]; then
    # shellcheck source=/dev/null
    . "$_src"
    break
  fi
done
if [ "${#WORKSPACE_LABELS[@]}" -lt 10 ]; then
  WORKSPACE_LABELS=(core forge codex lex scope uplink signal ledger craft void)
fi
WORKSPACE_LAPTOP_LABEL="${WORKSPACE_LAPTOP_LABEL:-${WORKSPACE_LABELS[0]}}"

# Coalesce signal storms (display_added + display_changed often fire
# back-to-back when a monitor wakes from sleep). flock with -n: if
# another invocation already holds the lock, drop this one — the held
# invocation will run with the latest yabai state.
exec 9>"$WS_RECONCILE_LOCK"
flock -n 9 || exit 0

# Tiny debounce so we observe the post-event yabai state, not the
# transient one. 200ms is below human perception but above yabai's own
# event coalescing window.
sleep "$(awk "BEGIN { print $WS_DEBOUNCE_MS / 1000 }")"

command -v yabai >/dev/null 2>&1 || exit 0
command -v jq    >/dev/null 2>&1 || exit 0

# How many displays does yabai see right now?
display_count=$(yabai -m query --displays 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
[[ "$display_count" -lt 1 ]] && exit 0

# Single-display mode: every space is on the laptop by definition.
# Nothing to reconcile.
if [[ "$display_count" -lt 2 ]]; then
  exit 0
fi

# Multi-display mode: need the laptop's identity to route slot 1 home.
# If the UUID file is missing the user hasn't run laptop-uuid-init.sh
# (or is bootstrapping on a machine whose first sighting was multi-
# display, which is ambiguous). Emit one OSD and bail rather than
# guessing — guessing the wrong display would shovel space 1 onto the
# external monitor on every plug, which is the opposite of what the
# user asked for.
if [[ ! -r "$WS_LAPTOP_UUID_FILE" ]]; then
  if command -v hs >/dev/null 2>&1; then
    hs -c 'hs.alert.show("workspace: laptop UUID not captured — run laptop-uuid-init.sh")' \
      >/dev/null 2>&1 || true
  fi
  exit 0
fi

LAPTOP_UUID=$(<"$WS_LAPTOP_UUID_FILE")
[[ -z "$LAPTOP_UUID" ]] && exit 0

# Resolve LAPTOP_IDX (= yabai index of the built-in display) and EXT_IDX
# (= lowest-index non-laptop display) from a single displays query, and
# build a label→display map from a single spaces query. yabai's RPC is
# ~5ms per call; the loop below would otherwise fire 9 spaces queries.
DISPLAYS_JSON=$(yabai -m query --displays 2>/dev/null)
SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
[[ -z "$DISPLAYS_JSON" || -z "$SPACES_JSON" ]] && exit 0

read -r LAPTOP_IDX EXT_IDX < <(
  printf '%s' "$DISPLAYS_JSON" | jq -r --arg u "$LAPTOP_UUID" '
    "\(([.[] | select(.uuid == $u) | .index] | first) // "") \(([.[] | select(.uuid != $u) | .index] | min) // "")"
  '
)

# Laptop not currently attached (clamshell with externals only) → no
# slot to lock home, leave assignments alone.
[[ -z "$LAPTOP_IDX" || "$LAPTOP_IDX" == "null" ]] && exit 0
[[ -z "$EXT_IDX"    || "$EXT_IDX"    == "null" ]] && exit 0

# Build label→display lookup once via jq.
declare -A SLOT_DISPLAY=()
while IFS=$'\t' read -r label disp; do
  [[ -n "$label" ]] && SLOT_DISPLAY["$label"]="$disp"
done < <(printf '%s' "$SPACES_JSON" | jq -r '.[] | "\(.label)\t\(.display)"')

# Laptop slot → laptop display.
if [[ -n "${SLOT_DISPLAY[$WORKSPACE_LAPTOP_LABEL]:-}" \
   && "${SLOT_DISPLAY[$WORKSPACE_LAPTOP_LABEL]}" != "$LAPTOP_IDX" ]]; then
  yabai -m space "$WORKSPACE_LAPTOP_LABEL" --display "$LAPTOP_IDX" 2>/dev/null || true
fi

# All other slots → external (only when currently mis-routed to laptop).
for label in "${WORKSPACE_LABELS[@]}"; do
  [[ "$label" == "$WORKSPACE_LAPTOP_LABEL" ]] && continue
  current="${SLOT_DISPLAY[$label]:-}"
  [[ -z "$current" ]] && continue
  if [[ "$current" == "$LAPTOP_IDX" ]]; then
    yabai -m space "$label" --display "$EXT_IDX" 2>/dev/null || true
  fi
done

# Refresh the workspace identity surfaces — the focused space may have
# moved displays even though its label is unchanged.
"$(dirname "$0")/on-space-changed.sh" >/dev/null 2>&1 || true
