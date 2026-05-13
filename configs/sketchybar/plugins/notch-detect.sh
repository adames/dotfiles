#!/usr/bin/env bash
# Print "yes" / "no" based on whether the BUILT-IN display has a camera
# notch (the cutout). Used by per-display-pills.sh and recenter.sh to
# decide whether to apply the 10-pill cap and half-notch buffer.
#
# Detection priority:
#   1. WS_LAPTOP_HAS_NOTCH env override (manual override hatch)
#   2. WS_LAPTOP_HAS_NOTCH from ~/.cache/workspace/layout.env, written by
#      ws-topologyd from NSScreen.safeAreaInsets — the authoritative API
#      for notch geometry. This is the canonical source when the daemon
#      is running.
#   3. Apple model identifier via `sysctl hw.model` — preserved as a
#      boot-time fallback for when SketchyBar queries this script before
#      the daemon has published its first layout.env (small race window
#      at user login).
#
# External displays are always non-notched; this script only describes
# the laptop's built-in panel.

set -u

if [[ -n "${WS_LAPTOP_HAS_NOTCH:-}" ]]; then
  printf '%s\n' "$WS_LAPTOP_HAS_NOTCH"
  exit 0
fi

WS_LAYOUT_ENV="${WS_LAYOUT_ENV:-$HOME/.cache/workspace/layout.env}"
if [[ -r "$WS_LAYOUT_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$WS_LAYOUT_ENV" 2>/dev/null || true
  if [[ -n "${WS_LAPTOP_HAS_NOTCH:-}" ]]; then
    printf '%s\n' "$WS_LAPTOP_HAS_NOTCH"
    exit 0
  fi
fi

# Boot-time fallback. Notched models (built-in display only):
#   MacBookPro18,1..4   - M1 Pro/Max (2021)
#   Mac14,[2,5,6,7,9,10,15]  - M2 lineup (2022/23): MacBook Air M2, 14"/16" MBP M2 Pro/Max
#   Mac15,*             - M3 lineup (2023): MacBook Air, 14"/16" MBP M3 family
#   Mac16,*             - M4 lineup (2024)
#   Mac17+,*            - forward-proof: assume future Apple laptops keep the notch
model=$(sysctl -n hw.model 2>/dev/null)

case "$model" in
  MacBookPro18,*)                  echo yes ;;
  Mac14,2|Mac14,5|Mac14,6|Mac14,7|Mac14,9|Mac14,10|Mac14,15) echo yes ;;
  Mac15,*|Mac16,*)                 echo yes ;;
  Mac17,*|Mac18,*|Mac19,*|Mac20,*) echo yes ;;
  *)                               echo no  ;;
esac
