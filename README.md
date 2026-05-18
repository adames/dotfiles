# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

Keyboard-first dev environment. Three rules:

1. **Caps Lock is the centre.** Tap = `Esc`, hold = `Hyper` (⌃⌥⌘⇧),
   hold + Shift = `Mod` (⌃⌥⌘). Karabiner remaps once; every layer
   below — yabai, tmux, Neovim — uses the same modifier-sets-scope model.
2. **One bootstrap, two platforms.** `bootstrap.sh` detects macOS or
   Ubuntu and dispatches. Idempotent.
3. **Edit `configs/`, never the deployed copy.** Bootstrap is the
   deployer; nothing under `configs/` is generated.

## Architecture

```
                       Caps Lock
                           │
                  ┌────────┴────────┐
                  │ Karabiner       │
                  │  • tap → Esc    │
                  │  • hold → Hyper │
                  │  • +Shift → Mod │
                  └────────┬────────┘
                           │
                          skhd ──────────────► (system Cmd-keys
                           │                    pass through)
              ┌────────────┼────────────┐
              ▼            ▼            ▼
            yabai       Terminal    Cheatsheet
         (BSP tiler)    Cmd+T/N    Hyper+; HUD
                       (osascript) (ws-cheatsheet)
```

Inside the terminal: Ghostty → tmux (`C-a`) → zsh → Neovim (`Space`
leader). Shell extras: fzf, zoxide, starship, direnv, vi-mode. Neovim:
pyright + ruff + dap-python + neotest.

Deep dive: [`docs/architecture.md`](docs/architecture.md). Permission
flow: [`docs/wizard.md`](docs/wizard.md). Karabiner JSON:
[`configs/karabiner.md`](configs/karabiner.md).

## Quick start

```sh
git clone "${DOTFILES_REPO:-git@github.com:adames/dotfiles.git}" ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS = 5 phases (sudo / packages / configs / defaults / wizard).
Ubuntu = 6 phases (terminfo / system / shell / runtimes / configs /
default-shell); skips yabai + Karabiner + Docker.

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps → Hyper / Mod / Esc | Karabiner-Elements | [`karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling | yabai | [`yabairc`](configs/yabairc) |
| Per-display workspace pill strip | SketchyBar | [`sketchybar/`](configs/sketchybar/) |
| Hyper/Mod hotkeys → yabai · launchers · cheatsheet · ws-prompt · ws-picker | skhd | [`skhdrc`](configs/skhdrc) |
| Workspace focus / send / edit overlays | ws-prompt (SwiftUI) | [`workspace/topology/Sources/ws-prompt/`](configs/workspace/topology/Sources/ws-prompt) |
| Change-workspace overlay (Caps+e) | ws-picker (SwiftUI) | [`workspace/topology/Sources/ws-picker/`](configs/workspace/topology/Sources/ws-picker) |
| Cheatsheet HUD (SwiftUI) | ws-cheatsheet | [`workspace/topology/Sources/ws-cheatsheet/`](configs/workspace/topology/Sources/ws-cheatsheet) · [`cheatsheet.json`](configs/workspace/cheatsheet.json) |
| Per-display SketchyBar autohide | ws-autohide | [`workspace/topology/Sources/ws-autohide/`](configs/workspace/topology/Sources/ws-autohide) |
| Cross-display topology + notch detection | ws-topologyd | [`workspace/topology/`](configs/workspace/topology) |
| New-window staging (center · focus · cross-space) | yabai signal + bash | [`workspace/stage-window.sh`](configs/workspace/stage-window.sh) |
| AX absolute-snap CLI (driven by Caps+h/j/k/l on floats) | ws-snap | [`workspace/topology/Sources/ws-snap/`](configs/workspace/topology/Sources/ws-snap) |
| Direction-aware Caps+h/j/k/l dispatch (floating→snap, tiled→focus) | ws-dir | [`bin/ws-dir`](bin/ws-dir) |
| Keymap / launcher health check (chord collisions, source-deploy drift, menu refs) | ws-doctor | [`bin/ws-doctor`](bin/ws-doctor) |
| Terminal · tmux · zsh · nvim | Ghostty + tmux + zsh + Neovim | [`ghostty-config`](configs/ghostty-config) · [`tmux.conf`](configs/tmux.conf) · [`zshrc`](configs/zshrc) · [`nvim-init.lua`](configs/nvim-init.lua) |
| LSP + DAP + tests for Python | Mason (pyright, ruff, debugpy, neotest) | same |
| Lazygit · OrbStack (Docker replacement) · git-delta | brew | — |

## Daily-driver keymap

Full reference is `Hyper+;`. **Hyper = navigate, Mod (Caps+Shift) =
modify.** Window ops are direct chords; workspace ops use a one-shot
SwiftUI overlay (`ws-prompt`) — digit (1..0) commits instantly,
letters fuzzy-search names + Enter, Esc and click-elsewhere cancel.

```
Caps tap                       → Esc

# Hyper — navigate / open / commit (single-chord ops)
Caps + hjkl  (tiled)           → focus neighbour window
Caps + hjkl  (floating)        → snap: h left · l right · j center · k fill
Caps + v                       → toggle float (unfloat = snap to grid)
Caps + r                       → rotate space 90°
Caps + n  ·  Caps + p          → prev / next workspace (wraps)
Caps + tab                     → last / recent workspace
Caps + t / b / o / , / q       → terminal / browser / Finder / System Settings / notes
Caps + ;                       → toggle cheatsheet HUD
Caps + Esc                     → no-op (preserved as muscle-memory panic key)

# Workspace prompts — four overlays, one pattern
# digit commits · letters fuzzy-search · ↵ accepts · esc cancels
Caps + e                       → change workspace — fuzzy-search every window in every space; ↵ jumps to its space
Caps + f                       → focus workspace  — land on a workspace
Caps + g  ·  Caps + m          → go / send window — send window to workspace + follow
Caps + w                       → edit workspace:
                                  a add · r rename · i icon · d destroy
                                  ⇧L layout (save / load / delete)
                                  v verify · ? doctor

# Mod — modify (destructive / lifecycle)
Caps + Shift + hjkl            → swap window (tiled only)
Caps + Shift + q               → inbox

# Terminal
C-a  hjkl / v / s / z          → tmux pane nav / split / zoom (prefix = C-a)
C-a  f                         → fzf project sessionizer

# Neovim
<leader>ff / fg / fb           → fzf files / live-grep / buffers
<leader>ca / rn / =            → LSP code action / rename / format
-                              → oil (parent dir as a buffer)
<leader>ha / hh / 1…4          → harpoon add / menu / jump
<leader>bn / bp / bd / bo      → buffer next / prev / delete / close-others
]c / [c                        → next / prev git hunk (gitsigns)
<leader>gs / gh / gp / gb      → git status / stage hunk / preview / blame
<leader>db / dc / do / di      → DAP breakpoint / continue / over / into
<leader>tn / tf / ts           → test nearest / file / summary
```

## Workspace identity

**yabai owns space existence. `spaces.json` owns optional identity.**
Mission Control's `+` / `×` add and remove yabai spaces; `Caps+W`
(the manage / workspace overlay) drives the same operations through
yabai's scripting addition. The bar reflects whatever yabai reports.

Fresh installs ship an empty `spaces.json` — pills render as bare gray
`ws1`, `ws2`, … until you customize one:

```sh
ws name 1 home            # rename slot 1
ws icon 1 code            # SF Symbol name → auto-maps to Nerd Font
ws theme catppuccin       # palette across all slots (color is theme-driven)
```

Identity surfaces in four places: **tmux statusline**, **starship
prompt**, **SketchyBar pill strip**, and the **ws-cheatsheet HUD**.
All four read `~/.config/workspace/spaces.json` through the cascade.
Per-display assignment, notch-aware pill capping, and the
menu-bar-vs-pills autohide live in
[`docs/architecture.md`](docs/architecture.md).

### `ws` CLI

`~/.local/bin/ws` is the public mutation API — atomic write +
cascade refresh on every change. `ws --help` is the full reference.
Most-used:

```sh
ws status                  # all slots with color swatches
ws name N <new>            # rename (accepts current name or index)
ws icon N <glyph|sf-name>  # icon (Nerd Font glyph or SF Symbol name)
ws theme <name> [--with-icons]      # palette across all slots
ws add / ws remove N       # lifecycle (also available via manage overlay)
ws layout save/load/delete <name>   # snapshot / restore
ws doctor / ws verify      # schema check + end-to-end cascade test
```

Color is **theme-driven and positional** — `ws theme NAME` sets the
palette across all slots; `swap`/`move`/`rotate`/`reverse`/`reorder`
permute only `(name, icon)`; the palette stays anchored to slot index.
Slot identifiers accept either a numeric index or a unique name.
`~/.config/workspace/{spaces.json,layouts/,themes/}` are per-machine
and never committed.

### yabai scripting addition

`Caps+W → a` / `d` (the manage prompt's add / destroy verbs) call
`yabai -m space --create` / `--destroy`, which need yabai's scripting
addition loaded into Dock.app. Mission Control's `+` / `×` doesn't —
those go through macOS directly. One-time SIP-gated install:

1. Disable SIP from Recovery (`csrutil disable`, reboot).
2. Apple Silicon only: `sudo nvram boot-args="-arm64e_preview_abi" && sudo reboot`.
3. `~/dotfiles/macos/yabai-sa-install.sh` — installs the SA, writes a
   hash-pinned `/etc/sudoers.d/yabai` for passwordless `--load-sa` at
   login, tests `--create` actually works.

Re-run `yabai-sa-install.sh` after `brew upgrade yabai` — the binary
hash changes and the sudoers entry needs to track it.

Don't use macOS green-button fullscreen on apps you want yabai to
manage; it creates a native fullscreen space yabai can't touch. Send
the window to its own slot with `Caps+G → digit` instead.

## OrbStack (Docker Desktop replacement)

`bootstrap.sh` installs `orbstack`. On a fresh launch it offers to
"Take over docker / docker-compose / kubectl" — accept; it rewrites
`/usr/local/bin/docker` and friends. Verify with `docker context ls`.
Native Apple Silicon, ~1s cold start.

## Permission grants

The macOS bootstrap hands off to `permissions-wizard.sh`, which probes
each TCC bit first (via [`lib/macos-tcc.sh`](lib/macos-tcc.sh)) and
only opens System Settings panes that have missing toggles. Three
gates: **Accessibility**, **Input Monitoring**, **System Extensions**.

```sh
~/dotfiles/macos/permissions-wizard.sh           # gated; ~2 s if all set
~/dotfiles/macos/permissions-wizard.sh --force   # walk every pane
```

See [`docs/wizard.md`](docs/wizard.md).

## Verification

```sh
yabai -m query --windows | jq '.[].app'           # tiler is live
launchctl list | grep com.koekeishiya.skhd        # skhd PID > 0
tmux show -gv prefix                              # → C-a
zsh -ic 'type z' | head -1                        # zoxide function
nvim --headless -c 'edit /tmp/x.py' -c 'sleep 3' \
     -c 'lua print(#vim.lsp.get_clients({bufnr=0}))' -c qall   # → 2
ws-doctor                                         # keymap/launcher health — run this first if any chord feels off
```

Cheatsheet: `Caps + ;` (live overlay; nothing on disk to inspect).

## Testing

```sh
tests/run-all.sh        # ~1.5 s — every tests/unit/*.test.sh
```

Pure-bash unit tests; stub yabai/osascript via `tests/fixtures/`. CI
also runs `bash -n`, `jq -e`, a karabiner.json structural invariant,
and a tmux config parse on every PR.

`ws verify` runs the end-to-end harness against your real
`~/.config/workspace/spaces.json` under a trap-based restore — treat
as a manual check, not a hot loop.

## Re-running / editing

```sh
$EDITOR ~/dotfiles/configs/zshrc
~/dotfiles/bootstrap.sh                          # idempotent
BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh   # no-TTY / headless
NO_COLOR=1 ~/dotfiles/bootstrap.sh               # plain output
```

`install_file` byte-compares; re-running is cheap. Native helpers
(ws-prompt, ws-cheatsheet, ws-autohide, ws-snap, ws-topology) live
under `configs/workspace/topology/` and rebuild on every bootstrap.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bootstrap hangs on cask install | No TTY — `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| "Karabiner installed but `.app` missing" | `installer -pkg` interrupted — `brew reinstall --cask karabiner-elements` |
| yabai logs `'display has separate spaces' is disabled` | Log out and back in |
| `Caps + e` / `Caps + f` / `Caps + g` / `Caps + w` does nothing | `ws-prompt` / `ws-picker` missing — re-run `~/.config/workspace/topology/install.sh` |
| `Caps + ;` cheatsheet doesn't appear | `ws-cheatsheet` missing from `~/.local/bin/` — same fix |
| Manage overlay's `add` / `destroy` fails with "scripting-addition" | yabai SA not loaded — `sudo yabai --load-sa && killall Dock`, or re-run `yabai-sa-install.sh` |
| Workspace pills missing | `sketchybar` not running — `brew services restart sketchybar`. Glyphs blank → Nerd Font missing (`brew install --cask font-jetbrains-mono-nerd-font`) |
| Workspace pill doesn't update on space switch | `sketchybar --trigger workspace_changed`; if no-op, `brew services restart sketchybar` |
| Workspace chip missing from prompt / tmux | `~/.config/workspace/on-space-changed.sh` to prime current.env |
| Slot 1 lands on the wrong display | yabai owns space-to-display. Drag the space in Mission Control; yabai persists. |
| Neovim plugins missing | First-launch install in progress — open `nvim`, wait or `:Lazy sync`, then `:MasonToolsInstall` |
| SSH'ing into Ubuntu from Ghostty: doubled chars, broken backspace | `TERM=xterm-ghostty` not in remote terminfo. From local: `infocmp -x xterm-ghostty | ssh user@host -- tic -x -`. Or run bootstrap on the VPS once. |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                  # OS dispatcher
├── lib/                          # shared bash helpers (logging, install_file, TCC probes)
├── macos/                        # 5 phases + permissions wizard + yabai-sa-install
├── ubuntu/bootstrap.sh           # 6 phases
├── docs/{architecture,wizard}.md
└── configs/
    ├── karabiner.{json,md}       # Caps remap + JSON explainer
    ├── yabairc                   # BSP tiling + workspace + display signals
    ├── skhdrc                    # Hyper/Mod bindings
    ├── workspace/                # workspace identity layer
    │   ├── spaces.default.json   #  · empty seed
    │   ├── cli/ws                #  · the public mutation API
    │   ├── on-space-*.sh         #  · yabai signal handlers
    │   ├── topology/             #  · Swift package (ws-prompt, ws-cheatsheet, ws-autohide, ws-snap, ws-topology(d))
    │   └── cheatsheet.json       #  · HUD content
    ├── sketchybar/               # per-display workspace pill strip
    ├── starship.toml · ghostty-config · tmux.conf · tmux-sessionizer
    ├── zshrc · gitconfig · ripgreprc
    └── nvim-{init.lua,lazy-lock.json,keymaps.lua}
```

## Design principles

- **Layered, not bundled.** Swap any one tool without touching the others.
- **Idempotent.** Re-running bootstrap is the supported way to apply edits.
- **Drift-resistant.** What's in `configs/` is what gets deployed; nvim
  `init.lua` and `lazy-lock.json` are tracked, so the editor is reproducible.
- **No paid Apple Developer ID.** Wizard chains through System Settings.
- **Agent-agnostic.** No AI assistant references in any tracked file.

## AI Agent Collaboration

This repository is designed for collaboration with multiple AI assistants (Claude, Windsurf, Devin, Cursor, etc.) without conflicts or agent-specific branding.

### Agent Workspace Locations

Agent-specific files live in `~/personas/`, **never** in this repository:

| Agent | Workspace Directory | Persona File |
|-------|---------------------|--------------|
| Claude | `~/personas/.claude/` | `~/personas/ricer.md` |
| Windsurf | `~/personas/.windsurf/` | `~/personas/ricer.md` |
| Devin | `~/personas/.devin/` | `~/personas/ricer.md` |
| Cursor | `~/personas/.cursor/` | `~/personas/ricer.md` |

The persona file (`~/personas/ricer.md`) contains project-specific instructions for AI assistants working on this dotfiles repository.

### Shared Settings

`.settings.json` (tracked template) → `settings.json` (gitignored, live):

```sh
# Copy template to live settings
cp ~/dotfiles/.settings.json ~/dotfiles/settings.json

# Edit as needed
```

The shared settings file defines allowed tools, workflows, and constraints that apply to all AI agents working on this project.

### Rules for AI Assistants

1. **Leave no trace.** No agent references in commits, PRs, branches, code, or documentation.
2. **Use intent-based branch names:** `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `ci/`.
3. **Author attribution:** Human identity only; no `Co-Authored-By:` or generation badges.
4. **Workspace isolation:** Each agent uses its own directory in `~/personas/`, never in `~/dotfiles/`.
