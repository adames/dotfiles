# Workspace Topology

A small native Swift helper plus a handful of bash adapters that together
make a notched MacBook Pro, a non-notched MacBook Pro, and any external
monitor render a consistent, identity-rich workspace bar — without using
private APIs, model tables, or fragile raw glyph bytes in JSON.

This is the macOS end of the larger `workspace` identity system. It
publishes one normalized cache file (`~/.cache/workspace/layout.env`)
that every shell adapter (SketchyBar plugins, the cascade, the workspace
CLI) reads to drive layout, max-visible counts, and notch geometry.

## What it owns

| Subsystem | Purpose |
|---|---|
| **Native Swift package** | `ws-topology` (one-shot CLI) + `ws-topologyd` (long-running launchd agent). Enumerates `NSScreen.screens`, classifies each into `notchedBuiltIn` / `compactBuiltIn` / `externalRectangular` / `mirrorSecondary`, debounces Core Graphics reconfig callbacks, and writes `topology.json` + `layout.env`. |
| **Typed icon spec** | `IconSpec { kind, codepoint, fontFamily, fallbackSfSymbol, fallbackText, userOverridden }`. v1→v2 migration tool. Persistence is ASCII-escaped (`\uXXXX`) so PUA bytes never appear in JSON. |
| **Per-host overlay** | `spaces.<hostname>.json` overrides the shared `spaces.json` on this machine. `workspace host` subcommands. Resolution helper sourced by every cascade reader. |
| **Cache-driven shell adapters** | The SketchyBar plugins (`notch-detect.sh`, `per-display-pills.sh`, `paint-all.sh`) and the cascade (`on-space-changed.sh`) prefer `layout.env` / `iconSpec.codepoint`, with legacy heuristics retained as boot-time fallbacks. `paint-all.sh` is the centralized batched-repaint plugin subscribed to `workspace_changed` via a single hidden sentinel item in `sketchybarrc`. Items anchored `left`, no centering math. |
| **Layout policy** | Notched: pills split symmetrically around the camera housing, the two halves anchored to `auxiliaryTopLeftArea.maxX` and `auxiliaryTopRightArea.minX`. Non-notched: pills centered in `visibleFrame`. Density mode (sparse / comfort / dense) picks gap from `(N × pill_w) / usable_w`. |
| **Cheatsheet HUD** | `ws-cheatsheet` SwiftUI window (Caps+; via skhd). Section data lives in hand-editable `~/.config/workspace/cheatsheet.json`. Single-instance toggle via PID file. Replaced 410 lines of Hammerspoon Lua + HTML/CSS. |
| **Floating-window snaps** | `ws-snap` (Mod+arrows via skhd). One-shot AX writes to move yabai-unmanaged windows. Replaces the Hammerspoon `setFrame` block — same geometry fractions, no Lua runtime. |
| **SketchyBar autohide** | `ws-autohide` launchd agent. 100ms cursor poller: when the cursor enters the top 2px of any display, that display's pills slide off and the auto-hide menu bar reveals. Other displays unaffected. Replaces the Hammerspoon timer. |
| **Side surfaces** | JankyBorders `active_color` re-asserted on `window_focused`. |

## File layout

```
.config/workspace/topology/                   ← Swift package home (this dir)
├── Package.swift                             swift-tools 5.10, deployment .macOS(.v14)
├── Sources/
│   ├── DisplayTopology/                      NSScreen + CGDisplay enumeration; debounce coalescer
│   ├── LayoutPolicy/                         pure [DisplaySnapshot] → [LayoutPolicy]
│   ├── WorkspaceState/                       IconSpec + WorkspaceStateStore + v1→v2 Migration
│   ├── AdaptersAppKit/                       window-delegate sample, accessibility probe (+ ObjC bridge)
│   ├── ws-topology/                          one-shot CLI
│   ├── ws-topologyd/                         launchd agent (CGDisplayRegisterReconfigurationCallback)
│   ├── ws-cheatsheet/                        SwiftUI HUD (Caps+; via skhd)
│   ├── ws-autohide/                          launchd agent — SketchyBar per-display autohide poller
│   └── ws-snap/                              one-shot AX CLI — Mod+arrows floating-window snaps
├── Tests/                                    XCTest suites (require full Xcode; see "Testing")
├── launchd/
│   ├── com.adames.workspace.topologyd.plist
│   └── com.adames.workspace.autohide.plist
├── install.sh                                build + symlink + load
├── MIGRATION.md                              v1 → v2 spaces.json
└── MANUAL_TEST_MATRIX.md                     hardware scenarios

.config/sketchybar/plugins/
├── notch-detect.sh                           cache-first; sysctl fallback
├── per-display-pills.sh                      bulk display-assignment + drawing in one sketchybar call
                                              (recenter.sh retired with the left-aligned navbar refactor)
├── paint-all.sh                              batched all-pill repaint; sentinel-item subscriber
                                              (ssh-chip.sh retired — complexity cleanup)

.config/workspace/
├── spaces.json                               v2 — single source of truth
├── spaces.<hostname>.json                    optional per-host overlay
├── on-space-changed.sh                       cascade entry point
├── borders-refresh.sh                        re-assert JankyBorders active_color on window_focused
├── lib/resolve-config.sh                     sources WS_CONFIG = host overlay if present
└── hooks/post-mutate.sh                      regenerate skhd fragment, ping sketchybar
```

## Cache surfaces (the render hot-path)

| File | Writer | Consumers | What's in it |
|---|---|---|---|
| `~/.config/workspace/spaces.json` (v2) | `workspace` CLI, `ws-topology migrate` | everyone | slot identity: `{name, color, iconSpec, stableLogicalLabel}` |
| `~/.cache/workspace/current.env` | `on-space-changed.sh` (atomic mv) | tmux, starship, borders, `paint-all.sh` | focused-space `MACOS_SPACE_{INDEX,NAME,COLOR,ICON,DISPLAY,ANSI}` |
| `~/.cache/workspace/topology.json` | `ws-topologyd` (atomic mv) | future native bar, diagnostics | per-display snapshot + policy |
| `~/.cache/workspace/layout.env` | `ws-topologyd` (atomic mv) | `notch-detect.sh`, `per-display-pills.sh` | `WS_LAPTOP_HAS_NOTCH`, `WS_LAPTOP_DISPLAY_ID`, `WS_MAX_VISIBLE_SLOTS_<id>` (active consumers); the daemon still publishes `WS_TOP_REGION_W_<id>` / `WS_NOTCH_X_<id>` / `WS_NOTCH_W_<id>` / `WS_PILL_AVG_WIDTH_PT_<id>` for diagnostics, but no shell consumer reads them after the left-aligned navbar refactor retired `recenter.sh`. |

`current.env` is keyed on focused space; `layout.env` is keyed on display.
They never overlap.

## Layout rules

**Layout: left-aligned, no centering math.** The previous version of
this section described a notched/non-notched split-and-center layout
implemented by `recenter.sh`, with density modes (sparse / comfort /
dense) picking inter-pill gaps from `(N × pill_w) / usable_w`. That
all got ripped out in the left-aligned refactor — items now anchor
left and SketchyBar lays them out from the screen corner toward the
center automatically. The only Swift-side input still consumed is
`WS_MAX_VISIBLE_SLOTS_<id>`, which caps the count on notched
displays so pills don't slide under the camera housing. The
LayoutPolicy module still computes the older auxiliary-region geometry
for diagnostic completeness, but no shell adapter reads it.

## Build / install

```bash
~/.config/workspace/topology/install.sh
```

Builds with `swift build -c release`, symlinks `ws-topology` and
`ws-topologyd` into `~/.local/bin/`, copies the LaunchAgent plist into
`~/Library/LaunchAgents/`, and `launchctl bootstrap`s the agent.

Requires Swift 5.10+ (ships with Command Line Tools 15) and macOS 14+.
Tested on macOS 26.3.1 / Mac15,10 (M3 Max 14") and MacBookPro17,1 (M1 13").

## CLI quickstart

```bash
ws-topology dump                                # current display snapshot, JSON
ws-topology layout                              # per-display layout policy, JSON
ws-topology migrate                             # dry-run v1 → v2; prints to stdout
ws-topology migrate --apply                     # writes v2 (idempotent on v2 inputs)
ws-topology resolve-icon <slot> --surface=font|native
ws-topology emit-skhd --write --reload          # regenerate ~/.config/skhd/spaces.skhdrc

workspace migrate                               # delegates to ws-topology migrate
workspace host {status,init,reset,list}         # per-host overlay management
workspace icon <slot> <glyph>                   # sets iconSpec.codepoint + userOverridden=true
workspace name <slot> <new>                     # rename — preserves overrides
```

## Testing

XCTest ships with full Xcode but **not** with Command Line Tools alone.
`swift build` works on CLT-only machines; `swift test` does not. Install
Xcode to run the suites. Files in `Tests/` are valid and exercise:

- `LayoutPolicyTests/` — notched / compact / external / mirror / fallback
  resolution. Fixtures modeled on `Mac15,10` and `MacBookPro17,1`.
- `WorkspaceStateTests/` — IconResolver fallback chain, v1→v2 migration
  idempotence, override-survives-rename invariant, invalid-glyph
  graceful fallback.
- `DisplayTopologyTests/ReconfigCoalescerTests` — 50ms trailing debounce
  behavior under bursts.
- `Tests/UITests/` — scaffolding for XCUIAutomation host-app tests.
  These currently `XCTSkipIf(true)` because Swift Package Manager
  doesn't provide a host application target; flesh them out by creating
  a thin macOS app target in Xcode that links `AdaptersAppKit`.

## Tuning

After the left-aligned refactor there is nothing user-tunable in the
navbar layout — items lay out from the left corner with a fixed
inter-pill gap. The previously documented `WS_NOTCH_PAD_LEFT_PT` /
`_RIGHT_PT` / `WS_NOTCH_PADDING_PT` knobs and the
`~/.config/workspace/sketchybar-tuning.env` file are retired and no
longer read by any consumer.

## What it replaces

| Before | After |
|---|---|
| `sysctl hw.model` notch detection table | `NSScreen.safeAreaInsets.top > 0` via daemon |
| `NOTCH_WIDTH=400` heuristic in `recenter.sh` | recenter retired; left-aligned layout sidesteps the notch geometry entirely. `WS_TOP_REGION_W_<id>` / `WS_NOTCH_W_<id>` still published for diagnostics. |
| `NOTCH_MAX_VISIBLE=10` constant | `WS_MAX_VISIBLE_SLOTS_<id>` (derived from combined aux width) |
| Raw Nerd Font PUA bytes in JSON `.icon` | `iconSpec.codepoint = "\uXXXX"`; literal glyph reconstructed only at the env sink |
| Static `cmd + alt + ctrl + shift - N` block in `skhdrc` | Generated `~/.config/skhd/spaces.skhdrc` loaded via `.load`, regenerated by `ws-topology emit-skhd` after every workspace mutation |
| Per-consumer rediscovery of display roles via yabai queries | Single `layout.env` from `ws-topologyd` |
| `space_changed` triggered full chain rebuild + two-pass write | Single-pass batched writes; `per-display-pills.sh` only re-runs on display events |
| Duplicate `workspace_on_space_change` signal firing cascade twice | Single `ws_space_changed` registration |
| Nav chevrons (`<` / `>`) bracketing the pills | Removed — pills speak for themselves |

## OSLog channels

Subsystem `com.adames.workspace.topology`. Categories: `topology`, `policy`, `icon`, `accessibility`.

```bash
log stream --predicate 'subsystem == "com.adames.workspace.topology"'
```

## Rollback

| What | How |
|---|---|
| spaces.json edit | edit by hand or use `workspace name/color/icon` — every mutation atomic via `_NORMALIZE` |
| Topology daemon | `launchctl bootout "gui/$(id -u)/com.adames.workspace.topologyd"` |
| Per-host overlay | `workspace host reset` |
| Notch padding | retired with the left-aligned refactor (no longer tunable / needed) |
| Border refresh signal | `yabai -m signal --remove ws_borders_window_focused` |
| Plugin edits | `cd ~/dotfiles && git checkout configs/sketchybar configs/workspace` then re-run `macos/bootstrap.sh` |

## Out of scope / deferred

- **Adopted-display modal** — first-time prompt when an unknown monitor appears. Not implemented.
- **Menu-bar auto-hide** via `kAXMenuOpenedNotification` in `ws-topologyd`. Not implemented.
- **Leader-prefix hotkeys for slots > 10** — currently capped at 10 by digit-key hardware; overflow reachable via `workspace focus <name>`.
- **Auto-iconing from slot names when `userOverridden == false`** — SF Symbol dictionary in `sf-to-nerd.json` covers ~113 common names; fuzzy match for arbitrary renamed slots is a follow-up.
- **External monitor model identification** — layout policy uses runtime density classification, so identification is not blocking.

## What ships in the package

`ws-topology` (one-shot CLI), `ws-topologyd` (launchd agent), and
`ws-cheatsheet` (SwiftUI HUD that replaces the previous `cheatsheet.lua`
overlay; content lives in `~/.config/workspace/cheatsheet.json`). The
package's [install.sh](install.sh) builds + symlinks all three.
