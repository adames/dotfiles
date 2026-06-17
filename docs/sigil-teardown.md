# Sigil teardown — migrate workspace layer to native AeroSpace

Decision (2026-06-17): rip out sigil's workspace-management layer and
drive everything from a hand-written `aerospace.toml`. Keep **only** the
cheatsheet (`ws-cheatsheet` + `WsUI` + `cheatsheet.json` +
`lib/cheatsheet-gen.py`). We'll rebuild any gaps natively in AeroSpace
or find a better workflow there — not port sigil features 1:1.

Why: the sigil-generated digit block drifted (Caps+2 → `workspace 10`,
a lexical-sort bug in `spaces.json` ordering), the focus-follow round-
trips through a shell binary and feels slow, and the dynamic display
topology layer makes multi-monitor annoying. `spaces.json` is already
empty and feeds no bar — the identity layer earns nothing today.

## Runtime hooks (top of configs/aerospace.toml)

- `on-focus-changed`: replace `…/ws-mouse-follow` with native
  `move-mouse window-lazy-center` (in-process; fixes the slow follow).
- `exec-on-workspace-change`: delete — `on-space-changed.sh` is empty.
- `on-window-detected … ws-grid detect` catch-all: delete (native tiles
  new windows). Keep the `layout floating` dialog rules above it.

## Main-mode chords

| Chord      | Current (sigil)            | Native replacement                       |
|------------|----------------------------|------------------------------------------|
| Caps+hjkl  | ws-dir (float-snap/focus)  | `focus left/down/up/right` (float-snap dropped) |
| Caps+yuio  | move left/down/up/right    | native — keep                            |
| Caps+a     | focus-back-and-forth       | native — keep                            |
| Caps+c     | ws-picker (fuzzy switcher) | drop (no native equiv)                   |
| Caps+d     | move-node-to-monitor       | native — keep                            |
| Caps+v     | layout floating tiling     | native — keep                            |
| Caps+g     | ws-grid apply              | drop (native auto-tiles)                 |
| Caps+r     | ws-grid rotate             | `layout horizontal vertical`             |
| Caps+-/=/e/⌫| resize/balance/close-others| native — keep                            |
| Caps+n/p   | ws-focus prev/next         | `workspace --wrap-around prev/next`      |
| Caps+tab   | ws-focus last              | `workspace-back-and-forth`               |
| Caps+f     | ws-prompt send (picker)    | drop; optionally `move-node-to-workspace N` |
| Caps+t/b/;/'| ws-launch-here apps       | drop (accept activate jump, or rebuild)  |
| Caps+/     | ws-cheatsheet --toggle     | **KEEP**                                 |
| Caps+1…0   | workspace 1…10 (fenced)    | hand-write static, remove sigil fences   |
| force-assignment table | fenced           | hand-write static "1"=1…"10"=1, remove fences |

## Bootstrap (macos/bootstrap.sh)

- Keep: cheatsheet regen block + sigil clone (ws-cheatsheet builds from it).
- Remove: `ws-topology emit-aerospace --write --validate --reload` step
  (this is what re-introduces the digit bug).
- Remove: `spaces.json` install/handling.
- `install.sh` still builds all ws-* binaries; only ws-cheatsheet is
  needed. Trimming it is a sigil-repo change — deferred ("keep cheatsheet
  as-is").

## Deleted (native-replaceable)

ws-topology, ws-topologyd, WorkspaceState, DisplayTopology, LayoutPolicy,
AerospaceEmit, the `ws` CLI + ws-focus + completions, ws-grid, ws-dir,
ws-mouse-follow, ws-picker, ws-prompt, ws-launch-here, ws-snap,
spaces.json. (~4,400 Swift + ~1,400 shell lines.)

## Kept

ws-cheatsheet + WsUI + cheatsheet.json + lib/cheatsheet-gen.py (~1,750
lines). Self-contained; no dependency on the workspace code.

## Accepted losses

- Fuzzy window picker (Caps+c) — no native equivalent.
- Float-snapping (Caps+hjkl on floats) — AeroSpace has no float positioning.
- Send-window picker (Caps+f) — replace with direct move bindings if wanted.
- No-jump app launching (Caps+t/b/;/') — `open -a` jumps to existing window.

## Docs to update alongside

docs/keymap.md, docs/architecture.md — both describe the sigil layer.
