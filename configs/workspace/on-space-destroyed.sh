#!/usr/bin/env bash
# Prune orphan slots from spaces.json after a yabai space is destroyed.
#
# Fired from yabai's `space_destroyed` signal (see configs/yabairc).
# yabai destroys ONE space and renumbers the survivors down. We respond
# by truncating spaces.json so its slot count matches yabai's new
# count — slots whose index > current yabai count are removed.
#
# Source-of-truth model (locked in by this handler):
#   • yabai     = source of truth for space EXISTENCE
#   • spaces.json = source of truth for space IDENTITY (name/color/icon)
#
# Limitation: yabai renumbers survivors after a mid-list destroy, so the
# identity-to-space association may shift for surviving slots. Example:
# yabai had [1,2,3,4,5] with identities [stream,hub,grid,vault,oracle];
# user destroys yabai space 3 via Mission Control. yabai now has [1,2,3,4]
# which were formerly [1,2,4,5]. We truncate spaces.json to 4 entries
# (drop slot 5/oracle); the remaining slots 3 and 4 still display
# "grid" and "vault" identities even though yabai now points them at
# the windows of what was "vault" and "oracle". The user can rename
# with `ws name <slot> <new>` to re-sync. For predictable mid-list
# semantics, use `ws remove <slot>` instead of Mission Control.
#
# Tail-only destruction (the common case — Mission Control's "x" on the
# last space) works cleanly: yabai count drops by 1, the highest slot
# is pruned, surviving slots keep their identities exactly.

set -u

# Per-host overlay → WS_CONFIG. Don't shadow if the caller pre-set it.
if [[ -z "${WS_CONFIG:-}" && -r "$HOME/.config/workspace/lib/resolve-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/workspace/lib/resolve-config.sh"
fi
WS_CONFIG="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"

[[ -r "$WS_CONFIG" ]] || exit 0
command -v jq    >/dev/null 2>&1 || exit 0
command -v yabai >/dev/null 2>&1 || exit 0

# yabai might fire space_destroyed before the in-memory state settles.
# Small delay so the query reflects the post-destroy count.
sleep 0.1

yabai_count=$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null)
[[ -z "$yabai_count" || "$yabai_count" -lt 1 ]] && exit 0

json_count=$(jq '.spaces | length' "$WS_CONFIG" 2>/dev/null || echo 0)
[[ "$json_count" -le "$yabai_count" ]] && exit 0   # nothing to prune

# Atomic prune: keep slot indices 1..yabai_count, drop the rest.
tmp=$(mktemp) || exit 1
if jq --argjson n "$yabai_count" '
  .spaces = (
    .spaces
    | to_entries
    | map(select((.key | tonumber) <= $n))
    | from_entries
  )
' "$WS_CONFIG" > "$tmp"; then
  mv -f "$tmp" "$WS_CONFIG"
else
  rm -f "$tmp"
  exit 1
fi

# Refresh the workspace identity surfaces. on-space-changed.sh
# re-writes current.env, pushes tmux env, and triggers
# workspace_changed so paint-all.sh re-renders.
[[ -x "$HOME/.config/workspace/on-space-changed.sh" ]] && \
  "$HOME/.config/workspace/on-space-changed.sh" >/dev/null 2>&1 || true
