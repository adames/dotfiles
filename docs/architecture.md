# Architecture

How Caps Lock becomes a window-focus command — and how the same key turns
the rest of the keyboard into a coherent dev surface.

## Layer stack

```mermaid
graph LR
  CapsLock([Caps Lock]) --> Karabiner
  Karabiner -->|"⌃⌥⌘⇧"| Hyper((Hyper))
  Karabiner -->|"⌃⌥⌘"| Meh((Meh))
  Karabiner -->|tap| Esc((Esc))

  Hyper --> skhd
  Meh --> skhd
  skhd -->|"yabai -m ..."| yabai

  Hyper --> Hammerspoon
  Hammerspoon -->|cmd+T/N| Terminal
  Hammerspoon -->|hs.webview Hyper+/| Cheatsheet[Cheatsheet overlay]

  yabai -->|space_changed signal| WorkspaceHandler[on-space-changed.sh]
  WorkspaceHandler -->|--trigger workspace_changed| SketchyBar[SketchyBar pill strip]
  WorkspaceHandler -->|active_color=| Borders[JankyBorders]
  WorkspaceHandler -->|set-environment| tmux

  yabai --> Windows[(macOS Windows)]
  Hammerspoon --> Windows

  Terminal --> Ghostty
  Ghostty --> tmux
  tmux --> zsh
  zsh -->|"$EDITOR"| Neovim
  zsh --> fzf & zoxide & direnv & starship
```

Caps Lock is intercepted by Karabiner, which re-emits one of three things
depending on what's held with it. **skhd** and **Hammerspoon** listen for
those re-emitted modifier sets and trigger shortcuts that drive **yabai**
and the terminal. Inside the terminal, **tmux** + **zsh** + **Neovim** form
the dev surface — every layer reusing the same vim-style hjkl + leader-key
mental model.

## The two Hyper levels

| User presses | Karabiner emits | Modifier set |
|---|---|---|
| Caps Lock alone (tap) | `Escape` | — |
| Caps Lock held | **Hyper** | `⌃⌥⌘⇧` (4) |
| Caps Lock + Shift held | **Meh** | `⌃⌥⌘` (3, Shift consumed) |

Why two levels: if Hyper itself contained Shift, then `Hyper + Shift + H`
would collapse to `Hyper + H`. By making Caps+Shift emit a *different*
combo (Meh), skhd binds them as separate shortcuts. JSON specifics in
[`configs/karabiner.md`](../configs/karabiner.md).

### Hyper = navigate, Meh = modify

The two layers carry a consistent semantic split:

| Layer | Role | Examples |
|---|---|---|
| **Hyper** | navigate / read-only | focus window (`hjkl`), focus space (`1..8`), focus display (`tab`), new terminal (`t`), launch app (`b`/`c`), cheatsheet (`0`) |
| **Meh**   | modify / destructive | swap window (`hjkl`), send-to-space (`1..8`), focus prev display (`tab`), manual snap (`arrows`) |

This is why the SIP-safe arrow snaps live on **Meh+arrows** rather than
Hyper+arrows — snapping is "manually move this window," which belongs in
the modify layer next to swap and send-to-space. It keeps the
hjkl-vs-arrows distinction coherent: `hjkl` is always yabai-managed
(tree-relative), arrows are always absolute-position (manual mode, for
floating or unmanaged windows like Ghostty and System Settings).

## Who owns what

| Concern | Owner | Config |
|---|---|---|
| Caps remap | Karabiner | `karabiner.json` |
| Window tiling (BSP, gaps, rules) | yabai | `yabairc` |
| Hyper window hotkeys | skhd | `skhdrc` |
| Hyper+T/N + Meh+arrows + Hyper+/ | Hammerspoon | `hammerspoon-init.lua` |
| Cheatsheet overlay | Hammerspoon | `hammerspoon-cheatsheet.lua` |
| Workspace pill strip (persistent 10-slot indicator) | SketchyBar | `sketchybar/sketchybarrc` · `sketchybar/plugins/space.sh` |
| Terminal app config | Ghostty | `ghostty-config` |
| Pane nav, sessionizer | tmux | `tmux.conf` + `tmux-sessionizer` |
| Shell layer | zsh | `zshrc` |
| ripgrep defaults | ripgrep | `ripgreprc` |
| Git pager | git + delta | `gitconfig` |
| Editor + plugins + LSP + DAP | Neovim + Lazy + Mason | `nvim-init.lua` |
| Plugin version pin | lazy.nvim | `nvim-lazy-lock.json` |

## Why skhd AND Hammerspoon?

- **skhd** uses `CGEventTap` to forward keystrokes to yabai. Fast, reliable,
  but no API for "send Cmd+T to whatever terminal app is open."
- **Hammerspoon** is Lua-scripted automation. We use it for things that
  need logic: targeting the user's terminal app, the SIP-safe arrow snaps
  (no-ops when yabai is up), and the Hyper+/ cheatsheet overlay.

## In-terminal layers

Once you're in the terminal, the same hjkl + leader-key model continues:

| Layer | Prefix / leader | Owns |
|---|---|---|
| **tmux**   | `C-Space`       | Pane focus (`hjkl`), splits (`v`/`s`), zoom (`z`), sessionizer (`f`), windows (`c`/`n`/`p`/`0..9`) |
| **zsh**    | (vi-mode `Esc`) | Vi normal-mode editing on the command line; fzf widgets `Ctrl-R/T`/`Alt-C`; zoxide `z` |
| **Neovim** | `Space`         | LSP (`gd`/`K`/`gr`/`<leader>ca`/`<leader>rn`), find (`<leader>f*`), debug (`<leader>d*`), test (`<leader>t*`) |

This works because **modifier sets the scope**: a bare `h` moves the cursor
in vim, `C-Space + h` moves the tmux pane focus, `Caps + h` moves the OS
window focus. Same letter, four contexts, no overlap.

## Python dev path

After bootstrap:

1. Open any `.py` file in nvim.
2. **Pyright** (types, definitions, hover) and **Ruff** (lint, format) attach.
3. Save the file → Ruff auto-formats via `BufWritePre`.
4. `<leader>db` to set a breakpoint, `<leader>tn` to run the nearest test.
5. `<leader>td` runs the nearest test under the debugger (debugpy).
6. `<leader>ts` toggles the neotest summary panel.

All servers (Pyright, Ruff, debugpy) come from Mason / mason-tool-installer,
pinned via `lazy-lock.json` so machines stay in lockstep.

## Permission gates

| Permission | Apps | Wizard pane |
|---|---|---|
| Accessibility | yabai · skhd · Hammerspoon · Karabiner-Elements | `Privacy_Accessibility` |
| Input Monitoring | Karabiner-Elements · Karabiner-DriverKit | `Privacy_ListenEvent` |
| System Extension approval | Karabiner-DriverKit-VirtualHIDDevice | `Privacy_SystemServices` |
| Spaces "Displays have separate Spaces" | yabai | bootstrap sets `defaults` — **logout required** |
| sudo (one-shot) | brew cask `installer -pkg` | `sudo -v` at start |

The wizard opens each pane and waits for ↵. Three panes, ~5 minutes total.
See [`wizard.md`](wizard.md).

## Workspace identity cascade

The 10-slot (extensible) workspace identity is a single piece of state
(`~/.config/workspace/spaces.json`) read by five subsystems. Mutations
go through one of two entry points (the `workspace` CLI or
`workspace/rename.sh` for the AppleScript flow) and fan out via the
cascade.

```mermaid
graph LR
  CLI[workspace CLI] -->|atomic write| JSON[(spaces.json)]
  Rename[rename.sh AppleScript] --> CLI
  JSON --> Hook[post-mutate.sh hook]
  JSON --> Cascade[on-space-changed.sh]
  yabai[yabai space_changed signal] --> Cascade
  Cascade --> EnvFile[(~/.cache/workspace/current.env)]
  Cascade --> TmuxEnv[tmux global env]
  Cascade --> Borders[JankyBorders]
  Cascade --> Sketchybar[SketchyBar]
  Cascade --> HS[Hammerspoon overlay]
  EnvFile --> Starship
  EnvFile --> Zsh[zsh precmd]
```

- **Source of truth**: `spaces.json` is per-machine, in `$HOME`, never
  committed. Bootstrap seeds it from `spaces.default.json` only when
  missing; user edits survive `bootstrap.sh` re-runs.
- **The CLI** (`~/.local/bin/workspace`) is the public mutation API.
  Subcommands cover name / color / icon / theme / add / remove / swap /
  move / rotate / reverse / reorder / layout / edit / reset / doctor.
  Every mutation is atomic (mktemp + jq + mv) and fires the cascade.
  Slot count is derived dynamically; the system tolerates any count
  ≥ 1 even though skhd hotkeys only bind 1..10. Any subcommand that
  takes a slot accepts either a numeric index or a unique slot name.
- **Positional colors.** Reordering operations (`swap`, `move`,
  `rotate`, `reverse`, `reorder`) permute only the (name, icon) tuples
  — color stays anchored to slot index. This preserves muscle-memory
  ("orange always means slot 2") across reorderings. To change a
  slot's color, use `workspace color N #HEX` directly.
- **`on-space-changed.sh`** is the cascade entry point — called by the
  yabai `space_changed` signal *and* by every CLI mutation. It writes
  `current.env` atomically, pushes env into tmux, repaints borders,
  triggers sketchybar, and shows the HS overlay. Silent-on-absence per
  subsystem so Ubuntu and partial setups Just Work.
- **`hooks/post-mutate.sh`** is a user-owned extension point. The
  shipped default keeps SketchyBar's pill set in sync with spaces.json
  on `add` / `remove` (other mutations just need a repaint, which the
  cascade already fires). It receives `(subcommand, slot_indices...)`
  after every successful mutation and is gitconfig.local-style — never
  clobbered by bootstrap.
- **`lib/colors.sh`** owns the slot↔yabai-label mapping (core, forge,
  …). Labels are immutable so reconcile-displays.sh can address spaces
  by name across plug/unplug events. The CLI never touches labels —
  reorder permutes the (name, icon) tuples on top of stable
  label-anchored slots.

## SketchyBar coexistence with the macOS menu bar

Four layers cooperate so the pill strip shares space with the system
menu bar without replacing it:

| Layer | Setting | Effect |
|---|---|---|
| macOS | `_HIHideMenuBar=1` | Menu bar hides by default; reveals when cursor at top |
| SketchyBar | `topmost=off`, `y_offset=7` | Strip draws behind the menu bar; vertically centered in the y=0..40 band |
| yabai | `external_bar all:26:0` | BSP-tiled windows never enter the top 26px, so the strip is always exposed under normal tiling |
| Hammerspoon | [`sketchybar-autohide.lua`](../configs/hammerspoon-sketchybar-autohide.lua) | 100ms timer toggles `--bar y_offset` between 7 and -100 based on cursor y, with hysteresis: hide at `y<2`, re-show at `y >= screen.frame.y` |

The result: cursor at the very top → strip slides off-screen, menu bar
slides in. Cursor moves down past the menu bar's drawn region → menu
bar slides out, strip slides back. The two effectively "tag out" at
the same boundary.

**Horizontal centering.** [`sketchybar/plugins/recenter.sh`](../configs/sketchybar/plugins/recenter.sh)
rewrites `--bar padding_left` so the strip stays centered between the
corner and the notch as pills are added/removed. Called from
sketchybarrc at startup and from the post-mutate hook on add/remove.
Math: `padding = (screen_width/2 − NOTCH_WIDTH − pills_width) / 2`,
with `NOTCH_WIDTH=400` reserving a half-notch buffer on the right.

**Visible-pill cap.** Both sketchybarrc and the post-mutate hook
refuse to create `space.11+`. The dock shows at most 10 pills even
when `workspace count > 10`, mirroring the `Caps+1..0` hotkey range.

## File map

```
~/dotfiles/
├── bootstrap.sh
├── lib/common.sh                 # logging + install_file
├── macos/
│   ├── bootstrap.sh              # 5 phases
│   └── permissions-wizard.sh     # opens 3 TCC panes
├── ubuntu/bootstrap.sh           # 6 phases
├── docs/                         # this file + wizard.md
└── configs/                      # source-of-truth dotfiles
    ├── workspace/
    │   ├── cli/workspace              # CLI binary (→ ~/.local/bin/)
    │   ├── cli/test-cascade.sh        # `workspace verify` harness
    │   ├── themes/*.json              # canonical palettes
    │   ├── spaces.default.json        # seed
    │   ├── on-space-changed.sh        # cascade
    │   ├── rename.sh                  # AppleScript wrapper
    │   └── install.sh                 # workspace-system bootstrapper
    ├── sketchybar/
    │   ├── sketchybarrc               # bar geometry + pill loop
    │   ├── colors.sh                  # palette constants
    │   ├── plugins/space.sh           # per-pill repaint
    │   ├── plugins/recenter.sh        # horizontal centering math
    │   └── bootstrap.sh               # brew services start
    └── hammerspoon-sketchybar-autohide.lua   # cursor-y auto-hide
```

`install_file` byte-compares src vs dst and skips no-ops, so editing
`configs/foo` then running `bootstrap.sh` re-deploys exactly the diff.
