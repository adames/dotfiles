#!/usr/bin/env bash
# Append default identity entries to spaces.json after yabai gains a
# space — symmetric counterpart to on-space-destroyed.sh.
#
# Fired from yabai's `space_created` signal (see configs/yabairc).
# Mission Control's `+` button and `yabai -m space --create` both
# trigger this signal; without this handler, Mission Control adds
# leak as "yabai has N spaces, spaces.json has M < N" drift — the
# user sees an unlabeled pill (or no pill at all on cold rebuild).
#
# Source-of-truth model (mirrored from on-space-destroyed.sh):
#   • yabai     = source of truth for space EXISTENCE
#   • spaces.json = source of truth for space IDENTITY (name/color/icon)
#
# Implementation: delegate to `ws add --no-prompt`, which already
# knows the spelled-out default naming convention (one, two, …, twenty,
# then ws21+), default-color-for-slot logic, and v2 iconSpec shape.
# WS_GROW_YABAI_ON_ADD=0 keeps `ws add` from re-calling
# `yabai -m space --create` — yabai already created the space, that's
# why we're here.
#
# Idempotent: if spaces.json already has an entry for the new yabai
# index (e.g., `ws add foo` raced ahead and wrote slot 7 itself), we
# no-op. `flock` serialises concurrent firings (rare, but Mission
# Control + and a near-simultaneous `ws add` can both fire signals).

set -u

# Per-host overlay → WS_CONFIG. Don't shadow if the caller pre-set it.
if [[ -z "${WS_CONFIG:-}" && -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/resolve-config.sh"
fi
WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
WS_BIN="${WS_BIN:-$HOME/.local/bin/ws}"

[[ -r "$WS_CONFIG" ]] || exit 0
command -v jq    >/dev/null 2>&1 || exit 0
command -v yabai >/dev/null 2>&1 || exit 0
[[ -x "$WS_BIN" ]] || exit 0

# yabai fires space_created before the in-memory state settles. Brief
# delay so the query reflects the post-create count — matches the
# 0.1s sleep on-space-destroyed.sh uses for the inverse race.
sleep 0.1

# Serialise concurrent firings. flock on a lock file in /tmp is
# portable; -n means "fail fast if held" so we don't pile up handlers
# behind a slow run. The lock is per-user (/tmp/<uid>-…) to avoid
# clobbering another login.
LOCK="/tmp/ws-on-space-created.$(id -u).lock"
exec 9>"$LOCK" || exit 0
command -v flock >/dev/null 2>&1 && flock -n 9 || true

yabai_count=$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null)
[[ -z "$yabai_count" || "$yabai_count" -lt 1 ]] && exit 0

json_count=$(jq '.spaces | length' "$WS_CONFIG" 2>/dev/null || echo 0)
[[ "$json_count" -ge "$yabai_count" ]] && exit 0   # nothing to grow

# Append one default identity per missing slot. `ws add` (with
# WS_GROW_YABAI_ON_ADD=0) auto-picks the next slot index and applies
# the spelled-out default name + theme-derived color + kind=none icon
# with the stop.fill fallback. No-prompt mode skips the interactive
# TTY paths (we're a yabai signal handler, no terminal anyway).
missing=$(( yabai_count - json_count ))
for (( i = 0; i < missing; i++ )); do
  WS_GROW_YABAI_ON_ADD=0 "$WS_BIN" add --no-prompt </dev/null >/dev/null 2>&1 || true
done
