#!/usr/bin/env bash
# Unit tests for configs/workspace/topology/Sources/ws-cheatsheet — focused
# on the ShelfLayout packer (CheatsheetData.splitIntoChunks +
# ShelfLayout.pack). Drives the binary in --dump-layout (headless) mode
# with $WS_CHEATSHEET pointed at a fixture document. Asserts on the
# stable text dump: line-oriented `key=value` records.
#
# Dump format:
#   total_shelves=N
#   shelf=N items=N max_height=N
#     item=N title="..." span=N height=N
#     ...

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

# Run --dump-layout against a fixture and capture stdout.
# Usage: _dump <fixture-name> [extra args...]
_dump() {
  local fixture="$1"; shift
  WS_CHEATSHEET="$TMP/$fixture.json" "$BIN" --dump-layout "$@" 2>/dev/null
}

# Assert that the named fixture produces a dump containing every given
# substring (one per arg after the fixture name). Useful when we care
# about presence rather than exact ordering.
_assert_dump_contains() {
  local label="$1" fixture="$2"; shift 2
  local out
  out=$(_dump "$fixture")
  local exit=$?
  if [[ "$exit" != "0" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s\n  exit %s\n  out: %s\n' "$label" "$exit" "$out"
    return
  fi
  for needle in "$@"; do
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

# Assert that a dump does NOT contain any of the given substrings.
_assert_dump_missing() {
  local label="$1" fixture="$2"; shift 2
  local out
  out=$(_dump "$fixture")
  for needle in "$@"; do
    if grep -qF "$needle" <<<"$out"; then
      fail=$((fail + 1))
      printf 'FAIL %s\n  unexpectedly present: %s\n  dump:\n%s\n' \
        "$label" "$needle" "$out"
      return
    fi
  done
  pass=$((pass + 1))
  printf 'ok   %s\n' "$label"
}

# ── Fixtures ──────────────────────────────────────────────────────────────

# Minimal: one short section. Expectation: one shelf, one item.
cat > "$TMP/minimal.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "Solo", "color": "#fff", "sub": "", "rows": [["a", "alpha"]] }
  ]
}
JSON

# Five narrow sections: fills shelf 0 (4 cards) and overflows to shelf 1.
cat > "$TMP/five-narrow.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "A", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "B", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "C", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "D", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "E", "color": "#fff", "sub": "", "rows": [["k","d"]] }
  ]
}
JSON

# Tall section declares splitAfter; its rows ARE tagged with the labels.
# Total height (~30pt × 30 rows + header ≈ 970pt) should exceed the
# default 1000pt * 0.38 = 380pt threshold and trigger a split.
cat > "$TMP/tall-with-splits.json" <<'JSON'
{
  "banner": [],
  "sections": [
    {
      "title": "Big",
      "color": "#fff",
      "sub": "tall section",
      "idea": "this is a tall section",
      "splitAfter": ["First", "Second", "Third"],
      "rows": [
        [":sub", "First"],
        ["k1","d1"],["k2","d2"],["k3","d3"],["k4","d4"],["k5","d5"],
        ["k6","d6"],["k7","d7"],["k8","d8"],["k9","d9"],["k10","d10"],
        [":sub", "Second"],
        ["k11","d11"],["k12","d12"],["k13","d13"],["k14","d14"],["k15","d15"],
        ["k16","d16"],["k17","d17"],["k18","d18"],["k19","d19"],["k20","d20"],
        [":sub", "Third"],
        ["k21","d21"],["k22","d22"],["k23","d23"],["k24","d24"],["k25","d25"],
        ["k26","d26"],["k27","d27"],["k28","d28"],["k29","d29"],["k30","d30"]
      ]
    }
  ]
}
JSON

# Same shape but short — sum of rows is well under threshold, so no split.
cat > "$TMP/short-with-splits.json" <<'JSON'
{
  "banner": [],
  "sections": [
    {
      "title": "Tiny",
      "color": "#fff",
      "sub": "short section",
      "splitAfter": ["First", "Second"],
      "rows": [
        [":sub", "First"],
        ["k1","d1"],
        [":sub", "Second"],
        ["k2","d2"]
      ]
    }
  ]
}
JSON

# Card with splitAfter that doesn't match any actual rows — should be a
# no-op even if the section is tall enough to trigger the threshold.
cat > "$TMP/orphan-splits.json" <<'JSON'
{
  "banner": [],
  "sections": [
    {
      "title": "Orphan",
      "color": "#fff",
      "sub": "",
      "splitAfter": ["NotInRows", "AlsoMissing"],
      "rows": [
        ["k1","d1"],["k2","d2"],["k3","d3"],["k4","d4"],["k5","d5"],
        ["k6","d6"],["k7","d7"],["k8","d8"],["k9","d9"],["k10","d10"],
        ["k11","d11"],["k12","d12"],["k13","d13"],["k14","d14"],["k15","d15"]
      ]
    }
  ]
}
JSON

# Wide-card span promotion: a 2-span-capable card lands on a shelf with
# only one other narrow card. Rebalancer should promote to span 2 so
# the empty-slot penalty (40 × empty count) drops to zero.
cat > "$TMP/wide-on-light-shelf.json" <<'JSON'
{
  "banner": [],
  "sections": [
    {
      "title": "Wide",
      "color": "#fff",
      "sub": "",
      "allowedSpans": [1, 2],
      "preferredSpan": 2,
      "rows": [["k","d"]]
    },
    { "title": "Narrow", "color": "#fff", "sub": "", "rows": [["k","d"]] }
  ]
}
JSON

# Wide-card with preferred=2 in a 4-card lineup. Greedy takes span 2
# immediately, filling the shelf at A+Wide+C (1+2+1=4); D overflows to
# shelf 1. Distinct from "wide-on-full-shelf" — the preferredSpan hint
# is the dominant signal in phase 3, so the shelf isn't "full" so much
# as "filled-to-budget-by-Wide".
cat > "$TMP/wide-preferred-2.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "A", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    {
      "title": "Wide",
      "color": "#fff",
      "sub": "",
      "allowedSpans": [1, 2],
      "preferredSpan": 2,
      "rows": [["k","d"]]
    },
    { "title": "C", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "D", "color": "#fff", "sub": "", "rows": [["k","d"]] }
  ]
}
JSON

# Wide-capable card with preferred=1 amongst three narrow siblings on
# one shelf. Greedy takes preferred=1, so all four pack onto shelf 0
# (1+1+1+1=4). Rebalance enumerates: [1,1,1,1] sums to 4 (no empties,
# zero preferred-miss); any [.,2,.,.] combo sums ≥5 and is skipped.
# So Wide stays at span 1 — preferredSpan wins when balance ties.
cat > "$TMP/wide-preferred-1-on-full.json" <<'JSON'
{
  "banner": [],
  "sections": [
    { "title": "A", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    {
      "title": "Wide",
      "color": "#fff",
      "sub": "",
      "allowedSpans": [1, 2],
      "preferredSpan": 1,
      "rows": [["k","d"]]
    },
    { "title": "C", "color": "#fff", "sub": "", "rows": [["k","d"]] },
    { "title": "D", "color": "#fff", "sub": "", "rows": [["k","d"]] }
  ]
}
JSON

# Bare-minimum split: tall section with splitAfter triggering. Each
# emitted chunk should carry the subsection label into its title.
# (Repeat from tall-with-splits but assert on the title format.)

# ── Cases ─────────────────────────────────────────────────────────────────

_assert_dump_contains "minimal: one shelf with one span-1 item" minimal \
  'total_shelves=1' \
  'shelf=0 items=1' \
  'title="Solo" span=1'

_assert_dump_contains "five narrow cards: two shelves [4 + 1]" five-narrow \
  'total_shelves=2' \
  'shelf=0 items=4' \
  'shelf=1 items=1' \
  'title="A" span=1' \
  'title="E" span=1'

_assert_dump_contains "tall card with splitAfter: produces three chunks" tall-with-splits \
  'title="Big · First"' \
  'title="Big · Second"' \
  'title="Big · Third"'

# After splitting, the original "Big" title should NOT appear standalone
# (every emitted chunk carries a suffix).
_assert_dump_missing "tall-split: original title gone" tall-with-splits \
  'title="Big" '

# A 30-row tall section emits 3 chunks; with 4 columns per shelf they
# all fit on a single shelf alongside no other cards.
_assert_dump_contains "tall-split: three chunks pack to one shelf" tall-with-splits \
  'total_shelves=1' \
  'shelf=0 items=3'

# Short section with splitAfter declared but under threshold: no split.
_assert_dump_contains "short section: splitAfter ignored, single card" short-with-splits \
  'total_shelves=1' \
  'shelf=0 items=1' \
  'title="Tiny" span=1'

# Orphan splitAfter (labels don't match any :sub markers) on a tall
# section: split still triggers, but produces 1 chunk (no markers to
# split at). The single chunk keeps the original title.
_assert_dump_contains "orphan splitAfter: one chunk, original title kept" orphan-splits \
  'total_shelves=1' \
  'title="Orphan"'

# Wide card on a light shelf: promotes to span 2 (no empty slots ⇒
# scoring prefers it).
_assert_dump_contains "wide+narrow: wide promotes to span 2" wide-on-light-shelf \
  'total_shelves=1' \
  'title="Wide" span=2' \
  'title="Narrow" span=1'

# Wide with preferred=2: greedy fills shelf with A+Wide(2)+C; D overflows.
_assert_dump_contains "wide preferred=2: fills shelf at span 2, D overflows" wide-preferred-2 \
  'total_shelves=2' \
  'shelf=0 items=3' \
  'shelf=1 items=1' \
  'title="Wide" span=2' \
  'title="D" span=1'

# Wide with preferred=1 amongst 3 narrows: stays span 1 because the
# rebalancer's preferred-miss penalty + empty-slot zero on [1,1,1,1]
# beats any promotion (which would sum > 4 and be skipped).
_assert_dump_contains "wide preferred=1 with 3 narrows: stays span 1" wide-preferred-1-on-full \
  'total_shelves=1' \
  'shelf=0 items=4' \
  'title="Wide" span=1'

# ── End-to-end: real cheatsheet.json ──────────────────────────────────────

# Reuse the deployed cheatsheet.json (the worktree copy). Expect both
# TMUX and WINDOWS·SPACES to be split into the named chunks.
e2e_out=$(WS_CHEATSHEET="$REPO_ROOT/configs/workspace/cheatsheet.json" \
  "$BIN" --dump-layout 2>/dev/null)
e2e_exit=$?
if [[ "$e2e_exit" != "0" ]]; then
  fail=$((fail + 1))
  printf 'FAIL e2e: --dump-layout exited %s\n' "$e2e_exit"
else
  for needle in \
    'title="Tmux · Panes"' \
    'title="Tmux · Windows"' \
    'title="Tmux · Sessions"' \
    'title="Windows · Spaces · Focus"' \
    'title="Windows · Spaces · Layout"' \
    'title="Windows · Spaces · Cycle"'; do
    if ! grep -qF "$needle" <<<"$e2e_out"; then
      fail=$((fail + 1))
      printf 'FAIL e2e: missing chunk %s\n' "$needle"
      e2e_exit=1
      break
    fi
  done
  if [[ "$e2e_exit" == "0" ]]; then
    pass=$((pass + 1))
    printf 'ok   e2e: real cheatsheet.json splits Tmux + Windows·Spaces\n'
  fi
fi

# ── Edge cases ────────────────────────────────────────────────────────────

# Empty fixture (no sections) — should produce zero shelves cleanly.
cat > "$TMP/empty.json" <<'JSON'
{ "banner": [], "sections": [] }
JSON
_assert_dump_contains "empty document: zero shelves" empty 'total_shelves=0'

# Malformed JSON: binary should exit non-zero with stderr message.
echo '{ not valid json' > "$TMP/broken.json"
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

# ── Page-dimension overrides ──────────────────────────────────────────────

# Same tall fixture, but page-height=100 makes the threshold (38) very
# small, so even short sections would trigger splits. Use this to verify
# the page-height flag is respected.
small_page_out=$(WS_CHEATSHEET="$TMP/short-with-splits.json" \
  "$BIN" --dump-layout --page-height 100 2>/dev/null)
if grep -qF 'title="Tiny · First"' <<<"$small_page_out" \
   && grep -qF 'title="Tiny · Second"' <<<"$small_page_out"; then
  pass=$((pass + 1))
  printf 'ok   --page-height shrinks threshold and forces split\n'
else
  fail=$((fail + 1))
  printf 'FAIL --page-height did not affect split decision\n  dump:\n%s\n' \
    "$small_page_out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
