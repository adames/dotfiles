#!/usr/bin/env bash
# Print "yes" / "no" based on whether the BUILT-IN display has a camera
# notch (the cutout). Used by per-display-pills.sh and recenter.sh to
# decide whether to apply the 10-pill cap and half-notch buffer.
#
# Detection: Apple model identifier via `sysctl hw.model`.
# Notched models (built-in display only):
#   MacBookPro18,1..4   - M1 Pro/Max (2021)
#   Mac14,[2,5,6,7,9,10,15]  - M2 lineup (2022/23): MacBook Air M2, 14"/16" MBP M2 Pro/Max
#   Mac15,*             - M3 lineup (2023): MacBook Air, 14"/16" MBP M3 family
#   Mac16,*             - M4 lineup (2024)
#   Mac17+,*            - forward-proof: assume future Apple laptops keep the notch
#
# Override hatch: set WS_LAPTOP_HAS_NOTCH=yes|no in the environment.
# External displays are always non-notched; this script only describes
# the laptop's built-in panel.

if [[ -n "${WS_LAPTOP_HAS_NOTCH:-}" ]]; then
  printf '%s\n' "$WS_LAPTOP_HAS_NOTCH"
  exit 0
fi

model=$(sysctl -n hw.model 2>/dev/null)

case "$model" in
  MacBookPro18,*)                  echo yes ;;
  Mac14,2|Mac14,5|Mac14,6|Mac14,7|Mac14,9|Mac14,10|Mac14,15) echo yes ;;
  Mac15,*|Mac16,*)                 echo yes ;;
  Mac17,*|Mac18,*|Mac19,*|Mac20,*) echo yes ;;
  *)                               echo no  ;;
esac
