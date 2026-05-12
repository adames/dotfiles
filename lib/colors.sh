# Workspace identity — single source of truth for the slot LABELS that
# every workspace subsystem agrees on as the stable per-slot identity.
#
#   yabai-ensure-spaces.sh        → applies these labels with --label
#   workspace/reconcile-displays  → addresses spaces by these labels
#   workspace/spaces.default.json → the user-visible NAMES happen to
#                                   match these defaults but are mutable
#                                   via workspace/rename.sh; the labels
#                                   below are NOT mutable
#
# Sourced by bash scripts; not used in zsh interactively. The colors and
# icons live in spaces.default.json (consumed via jq) so user edits to
# the JSON are honoured without a code change.
#
# To add an 11th slot:
#   1. Add it to WORKSPACE_LABELS below
#   2. Add a "11" entry to spaces.default.json with the chosen color/icon
#   3. Add Caps + (no free digit; pick a punctuation key) to skhdrc
#   4. Update yabai-ensure-spaces.sh's TARGET arg if you go past 10

WORKSPACE_LABELS=(
  core      # 1  · always-on, laptop-locked
  forge     # 2  · primary project work
  codex     # 3  · learning · python · leetcode
  lex       # 4  · writing · docs · notes
  scope     # 5  · browser · research
  uplink    # 6  · ssh · vps · remote
  signal    # 7  · comms · chat · mail
  ledger    # 8  · admin · finance
  craft     # 9  · creative · music · design · gaming
  void      # 10 · scratch · throwaway · overflow
)

# The label that lives on the laptop screen when an external monitor is
# attached. Must be the first entry of WORKSPACE_LABELS for the rest of
# the system to agree.
WORKSPACE_LAPTOP_LABEL="${WORKSPACE_LABELS[0]}"
