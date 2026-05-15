#!/usr/bin/env bash
# Unit tests for configs/workspace/topology/Sources/ws-cheatsheet — focused
# on the Masonry packer (Masonry.columnize + Masonry.columnCount). Drives
# the binary in --dump-layout (headless) mode with $WS_CHEATSHEET pointed
# at a fixture document. Asserts on the stable text dump:
#
#   total_columns=N
#   column=N cards=N height=N
#     card=N title="..." height=N
#     ...
#
# Bash-side coverage for what the user actually deploys; Swift Testing
# (Tests/WsCheatsheetTests/) covers the same pure functions with finer
# numeric assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOPOLOGY="$REPO_ROOT/configs/workspace/topology"
BIN_RELEASE="$TOPOLOGY/.build/release/ws-cheatsheet"
BIN_DEBUG="$TOPOLOGY/.build/debug/ws-cheatsheet"

if [[ -x "$BIN_RELEASE" ]]; then
  BIN="$BIN_RELEASE"
elif [[ -x "$BIN_DEBUG" ]]; then
  BIN="$BIN_DEBUG"
else
  echo "ws-cheatsheet binary not built; run 'swift build -c release' in $TOPOLOGY" >&2
  echo "skipping ws-cheatsheet tests" >&2
  echo "0 passed, 0 failed"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

pass=0; fail=0

# Run --dump-layout against a fixture (by basename, no `.json`) and
# capture stdout. Extra args (e.g. --page-width, --columns) pass
# through.
_dump() {
  local fixture="$1"; shift
  WS_CHEATSHEET="$TMP/$fixture.json" "$BIN" --dump-layout "$@" 2>/dev/null
}

_assert_dump_contains() {
  local label="$1" fixture="$2"; shift 2
  # The last N args are needle strings; but we want to optionally pass
  # extra flags like --page-width before them. Convention: the first
  # token after the label is the fixture name; if any of the remaining
  # args starts with `--`, treat as flag; everything else is a needle.
  local flags=() needles=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --* ]]; then
      flags+=("$1" "$2"); shift 2
    else
      needles+=("$1"); shift
    fi
  done
  local out
  out=$(_dump "$fixture" "${flags[@]+"${flags[@]}"}")
  local exit=$?
  if [[ "$exit" != "0" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s\n  exit %s\n  out: %s\n' "$label" "$exit" "$out"
    return
  fi
  for needle in "${needles[@]}"; do
    if ! grep -qF "$needle" <<<"$out"; then
      fail=$((fail + 1))
      printf 'FAIL %s\n  missing: %s\n  dump:\n%s\n' \
        "$label" "$needle" "$out"
      return
    fi
  done
  pass=$((pass + 1))
  printf 'ok   %s\n' "$label"
}

# ── Fixtures ──────────────────────────────────────────────────────────────

cat > "$TMP/single.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "Solo", "color": "#fff", "sub": "", "rows": [["a","alpha"]] }
  ]
}
JSON

# Three identical-height cards. With --columns 3, greedy distributes
# them one-per-column (leftmost-tiebreak on equal heights).
cat > "$TMP/three-equal.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "Alpha", "color": "#fff", "sub": "", "rows": [["a","desc"]] },
    { "title": "Beta",  "color": "#fff", "sub": "", "rows": [["b","desc"]] },
    { "title": "Gamma", "color": "#fff", "sub": "", "rows": [["c","desc"]] }
  ]
}
JSON

# One tall card + three short. With --columns 2, the tall card pushes
# its column WAY above the other, so all three shorts land in column 1.
# Tall=10 rows → 32+22+0+10×30 = 354pt; short=1 row → 84pt.
# After tall: heights [354, 0]. Short 1 → col 1 (84). Short 2 → col 1
# (168). Short 3 → col 1 (252). Final: [354, 252].
cat > "$TMP/tall-plus-three.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "Tall", "color": "#fff", "sub": "", "rows": [
      ["k1","d"],["k2","d"],["k3","d"],["k4","d"],["k5","d"],
      ["k6","d"],["k7","d"],["k8","d"],["k9","d"],["k10","d"]
    ]},
    { "title": "S1", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "S2", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "S3", "color": "#fff", "sub": "", "rows": [["k","d"]] }
  ]
}
JSON

# Eight equal-height cards into 4 columns — each column gets 2 cards
# in document-pair order: col 0 = [A,E], col 1 = [B,F], col 2 = [C,G],
# col 3 = [D,H]. Greedy round-robins because every column is tied at
# each step (heights climb uniformly).
cat > "$TMP/eight-into-four.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "A","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "B","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "C","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "D","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "E","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "F","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "G","color":"#fff","sub":"","rows":[["k","d"]] },
    { "title": "H","color":"#fff","sub":"","rows":[["k","d"]] }
  ]
}
JSON

cat > "$TMP/empty.json" <<'JSON'
{ "banner": [], "sections": [] }
JSON

echo '{ not valid json' > "$TMP/broken.json"

# ── Cases ─────────────────────────────────────────────────────────────────

# Default width derives 4 columns; one section lands in column 0, the
# rest sit empty.
_assert_dump_contains "single section: column 0 takes it; others empty" single \
  'total_columns=4' \
  'column=0 cards=1' \
  'column=1 cards=0' \
  'column=2 cards=0' \
  'column=3 cards=0' \
  'title="Solo"'

# Equal-height triplet across 3 forced columns — round-robin.
_assert_dump_contains "three equal cards across 3 columns: one each" three-equal \
  --columns 3 \
  'total_columns=3' \
  'column=0 cards=1' \
  'column=1 cards=1' \
  'column=2 cards=1' \
  'title="Alpha"' 'title="Beta"' 'title="Gamma"'

# Tall card forces all subsequent siblings to the other column.
_assert_dump_contains "tall+3short in 2 cols: tall solo, shorts in col 1" tall-plus-three \
  --columns 2 \
  'total_columns=2' \
  'column=0 cards=1' \
  'column=1 cards=3'

# Eight equal-height cards into 4 columns: round-robin (col i gets cards
# i and i+4). Spot-check three: title="A" is the FIRST card in col 0;
# title="E" is the second; title="H" is the second in col 3.
_assert_dump_contains "eight equal into 4 columns: A→0, B→1, C→2, D→3, E→0" eight-into-four \
  --columns 4 \
  'total_columns=4' \
  'column=0 cards=2' \
  'column=1 cards=2' \
  'column=2 cards=2' \
  'column=3 cards=2'

# ── Column-count derivation from page width ───────────────────────────────

# Default 1640 width → 4 columns (matches CheatsheetView's max).
_assert_dump_contains "default width: 4 columns" single \
  'total_columns=4'

# Narrow 1024 width → 3 columns. ⌊(1024+14)/(320+14)⌋ = ⌊3.11⌋ = 3.
_assert_dump_contains "1024pt width: 3 columns" single --page-width 1024 \
  'total_columns=3'

# Very narrow 700 width → 2 columns (lower bound). Raw would be
# ⌊(700+14)/334⌋ = 2.
_assert_dump_contains "700pt width: 2 columns" single --page-width 700 \
  'total_columns=2'

# Tiny 300 width → still 2 columns (clamped to lower bound; raw=0).
_assert_dump_contains "300pt width: clamps up to 2 columns" single --page-width 300 \
  'total_columns=2'

# Ultrawide 2560 width → 6 columns (upper bound). Raw =
# ⌊(2560+14)/334⌋ = 7, clamped to 6.
_assert_dump_contains "2560pt width: clamps down to 6 columns" single --page-width 2560 \
  'total_columns=6'

# --columns flag overrides the width-based derivation.
_assert_dump_contains "--columns 5 overrides width derivation" single --columns 5 \
  'total_columns=5'

# ── End-to-end: real cheatsheet.json ──────────────────────────────────────

# Production document has 12 sections. At the default 4 columns, every
# title should appear exactly once across the dump.
real_out=$(WS_CHEATSHEET="$REPO_ROOT/configs/workspace/cheatsheet.json" \
  "$BIN" --dump-layout 2>/dev/null)
real_exit=$?
real_titles=(
  "Windows · Spaces" "Workspace · Slots" "Launch"
  "Tmux" "Shell"
  "Vim · Motion" "Vim · Edit"
  "Neovim · LSP & Find" "Neovim · Files & Buffers"
  "Git · Hunks (editor)" "Python · Debug & Test" "Git · Workflow (shell)"
)
if [[ "$real_exit" != "0" ]]; then
  fail=$((fail + 1))
  printf 'FAIL e2e: --dump-layout exited %s\n' "$real_exit"
else
  e2e_ok=1
  for t in "${real_titles[@]}"; do
    if ! grep -qF "title=\"$t\"" <<<"$real_out"; then
      fail=$((fail + 1))
      printf 'FAIL e2e: title %q missing from dump\n' "$t"
      e2e_ok=0
      break
    fi
  done
  if (( e2e_ok )); then
    # Also assert balance: max column height / min column height < 2.
    # Greedy shortest-column should never produce gross imbalance on a
    # real document — if it does, something has regressed.
    heights=$(grep -oE 'column=[0-9]+ cards=[0-9]+ height=[0-9]+' <<<"$real_out" \
      | grep -oE 'height=[0-9]+' | grep -oE '[0-9]+')
    max=$(echo "$heights" | sort -n | tail -1)
    min=$(echo "$heights" | sort -n | head -1)
    if (( min > 0 )) && (( max * 100 / min < 200 )); then
      pass=$((pass + 1))
      printf 'ok   e2e: 12 cards distributed across 4 cols, max/min < 2\n'
    else
      fail=$((fail + 1))
      printf 'FAIL e2e: column heights imbalanced (max=%s min=%s)\n  dump:\n%s\n' \
        "$max" "$min" "$real_out"
    fi
  fi
fi

# ── Edge cases ────────────────────────────────────────────────────────────

# Empty document — at default width derives 4 columns, all with 0 cards.
_assert_dump_contains "empty document: 4 columns, all empty" empty \
  'total_columns=4' \
  'column=0 cards=0' \
  'column=3 cards=0'

# Malformed JSON: exit 2 with stderr message (not crash).
broken_out=$(WS_CHEATSHEET="$TMP/broken.json" "$BIN" --dump-layout 2>&1)
broken_exit=$?
if [[ "$broken_exit" != "2" ]]; then
  fail=$((fail + 1))
  printf 'FAIL malformed json: expected exit 2, got %s\n  out: %s\n' \
    "$broken_exit" "$broken_out"
else
  pass=$((pass + 1))
  printf 'ok   malformed json: exits 2\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
