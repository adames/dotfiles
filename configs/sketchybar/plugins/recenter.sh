#!/usr/bin/env bash
# Per-display density + anchor math for the workspace pill strip.
#
# Anchor rule (user preference, 2026-05-13):
#   • Non-notched displays (M1 13", externals, others) → CENTERED in the
#     visible frame. Chain spans the middle of the display.
#   • Notched displays → SPLIT SYMMETRICALLY around the notch. Conceptually
#     the chain is centered on the screen; the camera housing carves a gap
#     in the middle. Half the pills sit right-anchored against the notch
#     in the left aux area, half sit left-anchored against the notch in
#     the right aux area.
#
# Item layout (no nav chevrons; user dropped them as visual noise):
#     [space.<min>, space.<next>, …, space.<max>]   per display, ordered.
#
# Density modes apply per display:
#     ratio = (visible_pills × pill_w) / usable_w
#     ratio ≤ 0.55     → SPARSE   gap=8pt
#     0.55 < r ≤ 0.85  → COMFORT  gap=2pt
#     r > 0.85         → DENSE    gap=0pt
#
# All sketchybar --set calls are accumulated into a single invocation at
# the end. This avoids the "paint to the right then snap" pulse that a
# two-pass (default-gap then override) write previously caused — every
# pill's final padding is computed once, then committed in a single
# atomic sketchybar transaction.

set -u

PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
WS_LAPTOP_UUID_FILE="${WS_LAPTOP_UUID_FILE:-$HOME/.config/workspace/laptop.uuid}"
WS_LAYOUT_ENV="${WS_LAYOUT_ENV:-$HOME/.cache/workspace/layout.env}"
WS_TUNING_CONF="${WS_TUNING_CONF:-$HOME/.config/workspace/sketchybar-tuning.env}"

LEGACY_PILL_AVG_WIDTH=38
LEFT_MARGIN=8
MIN_PAD=8

LEGACY_NOTCH_WIDTH=185
LEGACY_NOTCH_MAX_VISIBLE=10

SPARSE_MAX=55
COMFORT_MAX=85
SPARSE_GAP=8
COMFORT_GAP=2
DENSE_GAP=0

# User tuning. Precedence: env-var override > config file > default 0.
if [[ -z "${WS_NOTCH_PADDING_PT:-}" && -r "$WS_TUNING_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$WS_TUNING_CONF" 2>/dev/null || true
fi
WS_NOTCH_PADDING_PT="${WS_NOTCH_PADDING_PT:-0}"

command -v sketchybar >/dev/null 2>&1 || exit 0
pgrep -x sketchybar >/dev/null 2>&1 || exit 0
command -v yabai >/dev/null 2>&1 || exit 0
yabai -m query --displays >/dev/null 2>&1 || exit 0

if [[ -r "$WS_LAYOUT_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$WS_LAYOUT_ENV" 2>/dev/null || true
fi

laptop_idx=""
if command -v jq >/dev/null 2>&1; then
  if [[ -r "$WS_LAPTOP_UUID_FILE" ]]; then
    laptop_uuid=$(<"$WS_LAPTOP_UUID_FILE")
    laptop_idx=$(yabai -m query --displays 2>/dev/null \
      | jq -r --arg u "$laptop_uuid" '[.[] | select(.uuid == $u) | .index] | first // empty' 2>/dev/null)
  fi
  if [[ -z "$laptop_idx" ]]; then
    laptop_idx=$(yabai -m query --displays 2>/dev/null \
      | jq -r '[.[] | select(.frame.x == 0 and .frame.y == 0) | .index] | first // empty' 2>/dev/null)
  fi
fi
notch_host=$("$PLUGIN_DIR/notch-detect.sh" 2>/dev/null || echo no)

# Pull the per-display facts into a single TSV blob so the loop below
# runs in the main shell (no subshell). Bash herestrings preserve the
# accumulator array across iterations.
displays_info=$(
  yabai -m query --displays 2>/dev/null \
    | jq -r '.[] | "\(.index)\t\(.frame.w)\t\(.spaces | map(tostring) | join(","))"'
)

args=()
while IFS=$'\t' read -r display width sid_csv; do
  [[ -z "$display" ]] && continue
  IFS=',' read -ra sids <<<"$sid_csv"
  total=${#sids[@]}

  is_laptop=no
  cgid=""
  if [[ "$notch_host" == "yes" \
        && -n "$laptop_idx" \
        && "$display" == "$laptop_idx" ]]; then
    is_laptop=yes
    cgid="${WS_LAPTOP_DISPLAY_ID:-}"
  fi

  pill_w=$LEGACY_PILL_AVG_WIDTH
  if [[ -n "$cgid" ]]; then
    var_pw="WS_PILL_AVG_WIDTH_PT_${cgid}"
    [[ -n "${!var_pw:-}" ]] && pill_w="${!var_pw%.*}"
  fi
  (( pill_w < 1 )) && pill_w=$LEGACY_PILL_AVG_WIDTH

  visible_count=$total
  if [[ "$is_laptop" == "yes" ]]; then
    if [[ -n "$cgid" ]]; then
      var_mvs="WS_MAX_VISIBLE_SLOTS_${cgid}"
      if [[ -n "${!var_mvs:-}" ]]; then
        (( visible_count > ${!var_mvs} )) && visible_count=${!var_mvs}
      fi
    elif [[ "$notch_host" == "yes" ]]; then
      (( visible_count > LEGACY_NOTCH_MAX_VISIBLE )) && visible_count=$LEGACY_NOTCH_MAX_VISIBLE
    fi
  fi
  (( visible_count < 1 )) && continue

  if [[ "$is_laptop" == "yes" ]]; then
    usable_left=""
    usable_right=""
    if [[ -n "$cgid" ]]; then
      var_topw="WS_TOP_REGION_W_${cgid}"
      var_rightw="WS_TOP_REGION_RIGHT_W_${cgid}"
      [[ -n "${!var_topw:-}" ]] && usable_left="${!var_topw%.*}"
      [[ -n "${!var_rightw:-}" ]] && usable_right="${!var_rightw%.*}"
    fi
    if [[ -z "$usable_left" ]]; then
      usable_left=$(( ( ${width%.*} - LEGACY_NOTCH_WIDTH ) / 2 ))
      usable_right=$usable_left
    fi
    usable=$(( usable_left + usable_right ))
  else
    usable=$(( ${width%.*} ))
  fi

  # Density classification.
  pills_w_raw=$(( visible_count * pill_w ))
  ratio_pct=$(( pills_w_raw * 100 / usable ))
  if   (( ratio_pct <= SPARSE_MAX  )); then gap=$SPARSE_GAP
  elif (( ratio_pct <= COMFORT_MAX )); then gap=$COMFORT_GAP
  else                                       gap=$DENSE_GAP
  fi

  # Compute the per-pill role and its specific padding ONCE.
  if [[ "$is_laptop" == "yes" ]]; then
    notch_x=""; notch_w=""
    if [[ -n "$cgid" ]]; then
      var_nx="WS_NOTCH_X_${cgid}"
      var_nw="WS_NOTCH_W_${cgid}"
      [[ -n "${!var_nx:-}" ]] && notch_x="${!var_nx%.*}"
      [[ -n "${!var_nw:-}" ]] && notch_w="${!var_nw%.*}"
    fi
    if [[ -z "$notch_x" ]]; then
      notch_x=$(( ( ${width%.*} - LEGACY_NOTCH_WIDTH ) / 2 ))
      notch_w=$LEGACY_NOTCH_WIDTH
    fi
    eff_notch_x=$(( notch_x - WS_NOTCH_PADDING_PT ))
    eff_notch_w=$(( notch_w + 2 * WS_NOTCH_PADDING_PT ))

    L=$(( (visible_count + 1) / 2 ))
    chain_w_left=$(( L * pill_w + (L - 1) * gap ))
    anchor_pad=$(( eff_notch_x - chain_w_left ))
    (( anchor_pad < MIN_PAD )) && anchor_pad=$MIN_PAD
    cross_notch_pad=$(( eff_notch_w + LEFT_MARGIN ))

    first_left_sid="${sids[0]}"
    # First right-half pill (0-indexed at L). May not exist if visible_count is small.
    first_right_sid=""
    if (( visible_count > L )); then
      first_right_sid="${sids[$L]}"
    fi

    for sid in "${sids[@]}"; do
      if [[ "$sid" == "$first_left_sid" ]]; then
        pad=$anchor_pad
      elif [[ -n "$first_right_sid" && "$sid" == "$first_right_sid" ]]; then
        pad=$cross_notch_pad
      else
        pad=$gap
      fi
      args+=(--set "space.$sid" "padding_left=$pad" "padding_right=0")
    done
  else
    chain_w=$(( visible_count * pill_w + (visible_count - 1) * gap ))
    pad_anchor=$(( (usable - chain_w) / 2 ))
    (( pad_anchor < MIN_PAD )) && pad_anchor=$MIN_PAD
    first_sid="${sids[0]}"
    for sid in "${sids[@]}"; do
      if [[ "$sid" == "$first_sid" ]]; then
        pad=$pad_anchor
      else
        pad=$gap
      fi
      args+=(--set "space.$sid" "padding_left=$pad" "padding_right=0")
    done
  fi
done <<< "$displays_info"

# Single batched commit. Sketchybar processes the whole arg list in one
# transaction → one redraw → no intermediate flicker.
args+=(--bar padding_left=0 padding_right=0)
if (( ${#args[@]} > 0 )); then
  sketchybar "${args[@]}" >/dev/null 2>&1 || true
fi
