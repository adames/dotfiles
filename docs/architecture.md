# Architecture

> For chord lookups, file:line pointers, and collision rules, see
> [keymap.md](keymap.md). This doc is the narrative and rationale.

> **Migration in flight (yabai → AeroSpace, Karabiner → Hyperkey).** Plan at
> [~/.claude/plans/let-s-migrate-to-aerospace-structured-bunny.md](../../../.claude/plans/let-s-migrate-to-aerospace-structured-bunny.md).
> Three contracts frozen during the migration; this section is the reference,
> the rest of the document still describes the live yabai-era stack until
> Phase 6 lands.
>
> 1. **`current.env`** renames `MACOS_SPACE_INDEX` → `MACOS_WORKSPACE_NAME`.
>    Out-of-repo consumers (tmux.conf, starship.toml) only read `_NAME`,
>    `_COLOR`, `_ICON`, `_ANSI` — no breakage. Same field set otherwise.
> 2. **`~/.config/aerospace/aerospace.toml`** is sentinel-fenced. User owns
>    everything except the block between `# >>> sigil generated >>>` and
>    `# <<< sigil generated <<<`. That block carries per-workspace digit
>    bindings + `exec-on-workspace-change` (the cascade replacing yabai's
>    `space_changed` signal). Written atomically by `ws-topology
>    emit-aerospace`, validated before write. Hand-edits inside the fence
>    are clobbered.
> 3. **`spaces.json` v3** keys on `"<displayUUID>:<workspaceName>"`.
>    `displayUUID` from `CGDisplayCreateUUIDFromDisplayID` (stable; AeroSpace
>    monitor ordinals are not). Migrated v2 slots land in `_unassigned:*`
>    until ws-topology reconciles them against live aerospace workspaces.

Caps Lock is king of the dev surface.

## Layer stack

```mermaid
graph LR
  CapsLock([Caps Lock]) --> Karabiner
  Karabiner -->|"⌃⌥⌘⇧"| Hyper((Hyper))
  Karabiner -->|"⌃⌥⌘"| Mod((Mod))
  Karabiner -->|tap| Esc((Esc))

  Hyper --> skhd
  Mod --> skhd
  skhd -->|"yabai -m ..."| yabai
  skhd -->|Caps+t / Caps+b| Launchers[ws-launch-* · bash auto-detect]
  skhd -->|Caps+;| WSCheatsheet[ws-cheatsheet · SwiftUI HUD]
  skhd -->|Caps+f / Caps+g · Caps+m / Caps+w| WSPrompt[ws-prompt · SwiftUI overlay]
  skhd -->|Caps+e| WSPicker[ws-picker · SwiftUI overlay]
  WSPrompt -->|ws-focus / ws-send-follow / ws / yabai| yabai
  WSPicker -->|yabai window --focus| yabai
  yabai -->|window_created signal| WSStage[stage-window.sh]
  yabai -->|space_changed signal| WorkspaceHandler[on-space-changed.sh]
  WorkspaceHandler -->|--trigger workspace_changed| SketchyBar[SketchyBar pill strip]
  WorkspaceHandler -->|set-environment| tmux

  yabai --> Windows[(macOS Windows)]
  WSStage --> Windows

  Ghostty --> tmux
  tmux --> zsh
  zsh -->|"$EDITOR"| Neovim
  zsh --> fzf & zoxide & direnv & starship
```

Karabiner intercepts Caps Lock and re-emits one of three things
depending on what's held with it. **skhd** dispatches each Hyper/Mod
chord to **yabai** (for tiling) or to a small Swift binary
(**ws-prompt**, **ws-cheatsheet**, **ws-snap**) where logic is needed.
Inside the terminal, **tmux** + **zsh** + **Neovim** form the dev
surface — every layer reusing the same vim-style hjkl + leader-key
mental model.

## The two Hyper levels

| User presses | Karabiner emits | Modifier set |
|---|---|---|
| Caps Lock alone (tap) | `Escape` | — |
| Caps Lock held | **Hyper** | `⌃⌥⌘⇧` (4) |
| Caps Lock + Shift held | **Mod** | `⌃⌥⌘` (3, Shift consumed) |

Why two levels: if Hyper contained Shift, `Hyper + Shift + H` would
collapse to `Hyper + H` — indistinguishable. By making `Caps + Shift`
emit a *different* combo (Mod), skhd binds them as separate chords.
JSON specifics in [`configs/karabiner.md`](../configs/karabiner.md).

### Hyper = navigate, Mod = modify

| Layer | Role | Examples |
|---|---|---|
| **Hyper** | navigate / read-only | focus neighbour (`hjkl` tiled) · snap float (`hjkl` floating), change workspace (`e`), focus workspace (`f`), go / send window (`g` / `m`), edit workspace (`w`), cycle workspace (`n`/`p`/`tab`), toggle float (`v`), rotate space (`r`), open app (`t`/`b`/`o`/`,`/`q`), cheatsheet (`;`) |
| **Mod**   | modify / destructive | swap window (`hjkl`), inbox (`q`) |

All workspace operations go through `ws-prompt` and `ws-picker` —
one-shot SwiftUI overlays that capture keystrokes themselves and exit
on commit / cancel / blur / Esc; skhd never holds workspace state.
Four overlays, one pattern: **digit commits · letters fuzzy-search ·
↵ accepts · esc cancels** — pick by intent.

| Trigger | Prompt | What |
|---|---|---|
| `Caps + e`         | change workspace | `ws-picker` — fuzzy-search every window in every space; ↵ jumps to that window's space |
| `Caps + f`         | focus workspace  | digit (1..0) commits instantly · letters fuzzy-match name + Enter |
| `Caps + g`  ·  `Caps + m` | go (send window) | digit commits + follow · letters fuzzy-match name + Enter (`m` is an alias — "move" mnemonic) |
| `Caps + w`         | edit workspace | verb-picker: `a` add · `r` rename · `i` icon · `d` destroy · `⇧L` layout · `v` verify · `?` doctor |

The edit overlay is a multi-stage state machine (verb → target /
payload → confirm → result). Commits shell straight out to the `ws`
CLI and yabai; stdout + stderr surface in an in-overlay result panel.
Names are constrained to start with a non-digit (enforced by `ws
name`/`ws add`) so an all-numeric query unambiguously addresses a
slot index — the path to slot 11+ via numeric input.

New windows are auto-staged centered on the focused space by yabai's
`window_created` signal
([stage-window.sh](../configs/workspace/stage-window.sh)). Tile-vs-float
is the app/rule decision; staging just centers + focuses, and `Caps+v`
toggles float to commit a staged window into the BSP tiling.

## Who owns what

| Concern | Owner | Config |
|---|---|---|
| Caps remap | Karabiner | `karabiner.json` |
| Window tiling (BSP, gaps, rules) | yabai | `yabairc` |
| Hyper/Mod hotkey dispatch | skhd | `skhdrc` |
| Workspace focus / send / edit overlays | ws-prompt (SwiftUI; edit = multi-stage state machine over `ws`) | [sigil](https://github.com/adames/sigil)/Sources/ws-prompt/ |
| Change-workspace overlay (Caps+e) | ws-picker (SwiftUI; fuzzy-search every window in every space, ↵ jumps to its space) | [sigil](https://github.com/adames/sigil)/Sources/ws-picker/ |
| New-window staging | bash + yabai signal | `configs/workspace/stage-window.sh` |
| AX absolute-snap CLI (manual use) | ws-snap | [sigil](https://github.com/adames/sigil)/Sources/ws-snap/ |
| SketchyBar per-display autohide | ws-autohide (LaunchAgent) | [sigil](https://github.com/adames/sigil)/Sources/ws-autohide/ |
| Cheatsheet HUD | ws-cheatsheet | `configs/workspace/cheatsheet.json` + [sigil](https://github.com/adames/sigil)/Sources/ws-cheatsheet/ |
| Cross-display topology (notch + per-display layout) | ws-topologyd (LaunchAgent) | [sigil](https://github.com/adames/sigil)/Sources/ws-topologyd/ |
| Workspace pill strip | SketchyBar | `configs/sketchybar/` |
| Terminal · tmux · zsh · nvim | Ghostty + tmux + zsh + Neovim/Mason | respective configs |

## Why skhd plus small Swift CLIs?

**skhd** forwards keystrokes via `CGEventTap` — fast, stateless, but
it only knows how to fire shell commands. Anything that needs macOS
API access is its own one-shot binary, shipped by the Swift package
in the [sigil](https://github.com/adames/sigil) repo (cloned to
`~/.config/workspace/` by bootstrap):

- **ws-prompt** — SwiftUI overlay for Caps+f (focus workspace) / Caps+g · Caps+m
  (go / send window) / Caps+w (edit workspace). Captures keys itself;
  exits on commit / cancel / blur. Edit is a multi-stage state
  machine that shells out to `ws` and yabai and surfaces captured
  output in a result panel.
- **ws-picker** — SwiftUI window picker (Caps+e — the "change workspace"
  prompt). Lists every visible yabai window across every space,
  fuzzy-filters by app + title + space; focusing the pick implicitly
  jumps to that window's space (yabai follows the window). Same
  overlay shape as ws-prompt — they share the WsUI design tokens
  (Catppuccin palette, pill geometry, fuzzy matcher).
- **ws-cheatsheet** — SwiftUI HUD (Caps+;). Single-instance toggle
  via PID file.
- **ws-snap** — AX-based absolute snap CLI for floating windows.
  Invoked by `ws-dir` from Caps+h/j/k/l when the focused window is
  floating (h=left, l=right, j=center, k=max).
- **ws-autohide** — only long-running helper. LaunchAgent-managed
  cursor poller (100 ms) that hides each display's SketchyBar pills
  when the cursor approaches its top edge. Yabai display indices are
  cached and invalidated on `didChangeScreenParameters`; popup-menu
  detection is gated on the cursor being near an unhide boundary.

Smaller surface than the old skhd + Hammerspoon split — no Lua
runtime, no extra Accessibility-permissioned daemon.

## In-terminal layers

Once you're in the terminal the same hjkl + leader-key model continues:

| Layer | Prefix / leader | Owns |
|---|---|---|
| **tmux**   | `C-Space` | Pane focus (`hjkl`), splits (`v`/`s`), zoom (`z`), sessionizer (`f`), windows (`c`/`n`/`p`/`0..9`) |
| **zsh**    | (vi-mode `Esc`) | Vi normal-mode editing on the command line; fzf widgets `Ctrl-R/T`/`Alt-C`; zoxide `z` |
| **Neovim** | `Space`         | LSP (`gd`/`K`/`gr`/`<leader>ca`/`<leader>rn`), find (`<leader>f*`), debug (`<leader>d*`), test (`<leader>t*`) |

Modifier sets the scope: bare `h` moves the cursor in vim, `C-Space  h`
moves the tmux pane focus, `Caps + h` moves the OS window focus. Same
letter, four contexts, no overlap.

## Python dev path

After bootstrap, open any `.py` file in nvim. **Pyright** (types,
definitions, hover) and **Ruff** (lint, format) attach. Save → Ruff
auto-formats via `BufWritePre`. `<leader>tn` runs the nearest test;
`<leader>td` runs it under debugpy; `<leader>ts` toggles the neotest
summary. Servers come from Mason / mason-tool-installer, pinned via
`lazy-lock.json`.

## Permission gates

| Permission | Apps | Wizard pane |
|---|---|---|
| Accessibility | yabai · skhd · ws-snap · Karabiner-Elements | `Privacy_Accessibility` |
| Input Monitoring | Karabiner-Elements · Karabiner-DriverKit | `Privacy_ListenEvent` |
| System Extension approval | Karabiner-DriverKit-VirtualHIDDevice | `Privacy_SystemServices` |
| Spaces "Displays have separate Spaces" | yabai | bootstrap sets `defaults` — **logout required** |
| sudo (one-shot) | brew cask `installer -pkg` | `sudo -v` at start |

The wizard opens each pane and waits for ↵. Three panes, ~5 minutes
total. Probes first via [`lib/macos-tcc.sh`](../lib/macos-tcc.sh) so a
working machine finishes in ~2 seconds. See [`wizard.md`](wizard.md).

## Workspace system

Workspace overlays and management come from **[Sigil](https://github.com/adames/sigil)** — see its README for the full cascade architecture.

**Integration point:** yabai provides space existence; Sigil provides
optional identity (name, color, icon) and overlays (`ws-prompt`,
`ws-picker`, `ws-cheatsheet`). The dotfiles configure skhd to trigger
these overlays and SketchyBar to render the pills.

## SketchyBar coexistence with the macOS menu bar

Layers cooperate so the pill strip shares space with the system menu
bar without replacing it, and each display gets its own per-monitor
pill set:

| Layer | Setting | Effect |
|---|---|---|
| macOS | `_HIHideMenuBar=1` | Menu bar hides by default; reveals when cursor at top |
| SketchyBar | `topmost=off`, `y_offset=7` | Strip draws behind the menu bar; vertically centered in y=0..40 |
| SketchyBar items | `display=<N>` per pill | Each pill visible only on its owning yabai display |
| yabai | `external_bar all:26:0` | BSP-tiled windows never enter the top 26px |
| ws-autohide | LaunchAgent | 100 ms cursor poller; toggles each pill's `y_offset` based on per-display cursor.y |

Result: cursor at the very top of display N → display N's pills slide
off-screen, the macOS menu bar reveals on N. Cursor elsewhere → that
display's strip stays put. Other displays are unaffected.

**Per-display pill assignment + name chip** is owned by
[`plugins/per-display-pills.sh`](../configs/sketchybar/plugins/per-display-pills.sh).
It queries yabai, sets `display=<idx>` on each pill, creates one
`workspace.name.<D>` chip per display (the always-visible "you are
here" label), and adds/removes items so the sketchybar set tracks
yabai exactly. Re-fires from yabai's `display_added` / `removed` /
`changed` signals — *not* `space_changed`, because per-pill display
assignment doesn't change on focus.

**Notch detection + visible cap.**
[`plugins/notch-detect.sh`](../configs/sketchybar/plugins/notch-detect.sh)
sources `~/.cache/workspace/layout.env`, written by `ws-topologyd`
from `NSScreen.safeAreaInsets` — the authoritative API for camera
housing geometry. On notched laptops' built-in displays, visible pills
are capped at 10 (or `WS_MAX_VISIBLE_SLOTS_<id>` when published).
Non-notched displays show all assigned pills.
