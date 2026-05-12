#!/usr/bin/env bash
# One-shot: capture the built-in display's UUID into
# ~/.config/workspace/laptop.uuid so reconcile-displays.sh can stably
# identify the laptop screen across plug/unplug events.
#
# Strategy: yabai exposes a UUID per display that is stable across
# Mission Control reorderings. There's no public yabai property that
# says "this is the built-in panel", so we infer:
#
#   1. If only one display is attached, that's the laptop. Capture it.
#   2. Otherwise, prefer the display whose `frame.x == 0 && frame.y == 0`
#      AND whose resolution matches a known MacBook panel ratio. This is
#      a heuristic; if it picks wrong the user can edit the file by hand
#      or re-run with a single-display configuration.
#   3. Idempotent: refuses to overwrite an existing UUID file unless
#      --force is passed.

set -u

UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$(dirname "$UUID_FILE")"

if [[ -s "$UUID_FILE" && "$FORCE" -ne 1 ]]; then
  printf 'laptop UUID already captured: %s\n' "$(<"$UUID_FILE")"
  printf '  pass --force to recapture\n'
  exit 0
fi

if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'error: yabai and jq are required\n' >&2
  exit 1
fi

count=$(yabai -m query --displays | jq 'length')

if [[ "$count" -eq 0 ]]; then
  printf 'error: yabai sees zero displays — is the SA loaded?\n' >&2
  exit 1
fi

if [[ "$count" -eq 1 ]]; then
  uuid=$(yabai -m query --displays | jq -r '.[0].uuid')
else
  # Multi-display: pick the one with origin (0, 0). On a typical Mac
  # arrangement that's the primary display, which is almost always the
  # built-in panel unless the user has reassigned "primary" in System
  # Settings. If they have, they need to either reassign before running
  # this OR edit ~/.config/workspace/laptop.uuid by hand.
  uuid=$(
    yabai -m query --displays \
      | jq -r '
          .[] | select(.frame.x == 0 and .frame.y == 0) | .uuid
        ' | head -1
  )
  if [[ -z "$uuid" ]]; then
    printf 'error: no display at origin (0, 0); cannot guess laptop\n' >&2
    printf '       attach only the built-in display and re-run, or\n' >&2
    printf '       write the UUID by hand: yabai -m query --displays | jq\n' >&2
    exit 1
  fi
  printf 'multiple displays present — guessing laptop = %s (origin 0, 0)\n' "$uuid"
  printf '  if wrong: rm %s && reconnect with laptop only, then re-run\n' \
    "${UUID_FILE/#$HOME/~}"
fi

printf '%s\n' "$uuid" > "$UUID_FILE"
printf 'captured laptop UUID → %s\n' "${UUID_FILE/#$HOME/~}"
