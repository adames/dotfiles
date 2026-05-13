# Workspace identity — single source of truth for the slot LABELS that
# every workspace subsystem agrees on as the stable per-slot identity.
#
#   yabai-ensure-spaces.sh        → applies these labels with --label
#   workspace/reconcile-displays  → addresses spaces by these labels
#   workspace/spaces.default.json → fresh-install seed; the user-visible
#                                   NAMES happen to match these labels
#                                   but are mutable via `ws name` /
#                                   workspace/rename.sh. The LABELS
#                                   below are NOT mutable — yabai
#                                   addresses spaces by label across
#                                   plug/unplug, reorder, and reboot.
#
# Sourced by bash scripts; not used in zsh interactively. Colors and
# icons live in spaces.default.json (consumed via jq) so user edits to
# the JSON are honoured without a code change.
#
# Factory default: 2 slots, "home" on the laptop, "code" on the
# external (if any). When a new monitor is added, macOS auto-creates
# a fresh yabai space; we leave it in place and paint-all.sh renders
# it gracefully as a bare pill. Users can rename / customize with
# `ws name N <new>` and `ws icon N <glyph>`; adding more slots via
# `ws add` writes them into spaces.json with whatever name is given.

WORKSPACE_LABELS=(
  home      # 1  · laptop-locked default
  code      # 2  · terminal / dev workspace (Hyper+0 also jumps here)
)

# The label that lives on the laptop screen when an external monitor is
# attached. Must be the first entry of WORKSPACE_LABELS for the rest of
# the system to agree.
WORKSPACE_LAPTOP_LABEL="${WORKSPACE_LABELS[0]}"
