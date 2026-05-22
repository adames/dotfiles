# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

MacOS-friendly lifestyle/development/deployment environment. Three rules:

1. **Caps Lock is the centre.** Hyperkey remaps Caps; every layer
   below — AeroSpace, tmux, Neovim — uses the same modifier-sets-scope
   model.
   1. Tap = `Esc`
   2. hold = `Hyper` (⌃⌥⌘⇧)
2. **One bootstrap, two platforms.** `bootstrap.sh` detects macOS or
   Ubuntu and dispatches. Idempotent.
3. **Edit `configs/`, never the deployed copy.** Bootstrap is the
   deployer; nothing under `configs/` is generated.

## Architecture

```
                       Caps Lock
                           │
                  ┌────────┴────────┐
                  │ Hyperkey        │
                  │  • tap → Esc    │
                  │  • hold → Hyper │
                  └────────┬────────┘
                           │
                       AeroSpace ──────────► (system Cmd-keys
                           │                  pass through)
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        aerospace.toml   Terminal    Cheatsheet
        (tiling +       Cmd+T/N    Hyper+; HUD
         chord disp.)   (osascript) (ws-cheatsheet)
```

Inside the terminal: Ghostty → tmux (`C-a`) → zsh → Neovim (`Space`
leader). Shell extras: fzf, zoxide, starship, direnv, vi-mode. Neovim:
pyright + ruff via brew; simple lspconfig; terminal-based debug/test.

Deep dive: [`docs/architecture.md`](docs/architecture.md). Permission
flow: [`docs/wizard.md`](docs/wizard.md). Chord inventory:
[`docs/keymap.md`](docs/keymap.md). Migration history (yabai →
AeroSpace, Karabiner → Hyperkey):
[`docs/archive/yabai-to-aerospace.md`](docs/archive/yabai-to-aerospace.md).

## Quick start

```sh
git clone "${DOTFILES_REPO:-git@github.com:adames/dotfiles.git}" ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS = 5 phases (sudo / packages / configs / defaults / wizard).
Ubuntu = 6 phases (terminfo / system / shell / runtimes / configs /
default-shell); skips AeroSpace + Hyperkey + Docker.

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps → Hyper / Esc | Hyperkey | (`com.knollsoft.Hyperkey` user defaults; cask install only — no file) |
| Window tiling + chord dispatch | AeroSpace | [`aerospace.toml`](configs/aerospace.toml) (sentinel-fenced; sigil owns the digit block) |
| Menu-bar workspace pill strip | ws-statusbar | [sigil](https://github.com/adames/sigil) |
| Workspace focus / send / manage overlays | ws-prompt (SwiftUI) | [sigil](https://github.com/adames/sigil) |
| Change-workspace overlay (Caps+e) | ws-picker (SwiftUI) | [sigil](https://github.com/adames/sigil) |
| Cheatsheet HUD (SwiftUI) | ws-cheatsheet | [sigil](https://github.com/adames/sigil) · `~/.config/workspace/cheatsheet.json` |
| Cross-display topology + notch detection | ws-topologyd | [sigil](https://github.com/adames/sigil) |
| AX absolute-snap CLI (driven by Caps+h/j/k/l on floats) | ws-snap | [sigil](https://github.com/adames/sigil) |
| Direction-aware Caps+h/j/k/l dispatch (floating→snap, tiled→focus) | ws-dir | [`bin/ws-dir`](bin/ws-dir) |
| Keymap / launcher health check (chord collisions, source-deploy drift, menu refs) | ws-doctor | [`bin/ws-doctor`](bin/ws-doctor) |
| Terminal · tmux · zsh · nvim | Ghostty + tmux + zsh + Neovim | [`ghostty-config`](configs/ghostty-config) · [`tmux.conf`](configs/tmux.conf) · [`zshrc`](configs/zshrc) · [`nvim-init.lua`](configs/nvim-init.lua) |
| LSP + DAP + tests for Python | Mason (pyright, ruff, debugpy, neotest) | same |
| Lazygit · OrbStack (Docker replacement) · git-delta | brew | — |

## Workspace Management (Sigil)

Workspace overlays and management are provided by **[Sigil](https://github.com/adames/sigil)** — a standalone Swift package that lives in its own repository.

**Clean separation workflow:**

```
~/projects/sigil          ← Development (git@github.com:adames/sigil.git)
~/.config/workspace/      ← Runtime (cloned by bootstrap, points to sigil)
~/dotfiles/               ← This repo (installs aerospace + Hyperkey, clones sigil)
```

**How it works:**
1. `bootstrap.sh` clones `git@github.com:adames/sigil.git` → `~/.config/workspace/`
2. Builds Swift binaries (`ws-prompt`, `ws-picker`, `ws-statusbar`, etc.)
3. Symlinks binaries to `~/.local/bin/`
4. Loads LaunchAgents for `ws-topologyd` and `ws-statusbar`

**Development:** Work in `~/projects/sigil` (or `~/.config/workspace`), push to GitHub. On new machines, bootstrap automatically pulls latest.

## Daily-driver keymap

Full reference is `Hyper+;`. **One Hyper layer; no Mod.** Window ops
are direct chords; workspace ops use a one-shot SwiftUI overlay
(`ws-prompt`) — digit (1..0) commits instantly, letters fuzzy-search
names + Enter, Esc and click-elsewhere cancel. SketchyBar pills show
slot color + name + SF Symbol icon; menu bar uses `_N_` elevation design.

```
Caps tap                       → Esc

# Hyper — navigate / open / commit (single-chord ops)
Caps + hjkl  (tiled)           → focus neighbour window
Caps + hjkl  (floating)        → snap: h left · l right · j center · k fill
Caps + yuio                    → swap window left / down / up / right (was Caps+Shift+hjkl pre-Hyperkey)
Caps + v                       → toggle floating ↔ tiling
Caps + r                       → flatten + rotate workspace tree
Caps + n  ·  Caps + p          → prev / next workspace (wraps)
Caps + tab                     → last / recent workspace
Caps + 1..0                    → focus workspace N (sigil-generated)
Caps + t / b / o / , / q       → terminal / browser / Finder / System Settings / notes
Caps + x                       → inbox (was Caps+Shift+q pre-Hyperkey)
Caps + ;                       → toggle cheatsheet HUD

# Workspace prompts — four overlays, one pattern
# digit commits · letters fuzzy-search · ↵ accepts · esc cancels
Caps + e                       → change workspace — fuzzy-search every window in every space; ↵ jumps to its space
Caps + f                       → focus workspace  — land on a workspace
Caps + g  ·  Caps + m          → go / send window — send window to workspace + follow
Caps + w                       → edit workspace:
                                  r rename · i icon · color · v verify · ? doctor
                                  (add / destroy moved to aerospace.toml — see
                                   "Workspace identity" below)

# Terminal
C-a  hjkl / v / s / z          → tmux pane nav / split / zoom (prefix = C-a)
C-a  f                         → fzf project sessionizer

# Neovim
<leader>ff / fg / fb           → fzf files / live-grep / buffers
<leader>ca / rn / =            → LSP code action / rename / format
-                              → oil (parent dir as a buffer)
<leader>m{a-z} / '{a-z}         → marks (set / jump) — simpler than harpoon
<leader>bn / bp / bd / bo      → buffer next / prev / delete / close-others
<leader>gs                     → git status (fzf-lua)

# Debug & Test (terminal-based, simpler for learning)
# Use `python -m pdb script.py` or add `breakpoint()` in code
# Use `pytest -xvs test_file.py` in a tmux split
```

## Workspace identity

**`aerospace.toml` owns workspace existence. `spaces.json` owns optional
identity (name, color, icon).** See [Sigil](https://github.com/adames/sigil)
for the overlays and the `ws` CLI. Quick start:

```sh
ws name 1 home            # rename slot 1 (touches spaces.json only)
ws icon 1 code            # SF Symbol name
ws theme catppuccin       # set palette
```

Identity surfaces in: tmux, starship, SketchyBar, ws-cheatsheet HUD.
Per-machine files in `~/.config/workspace/` — never committed.

### Adding / destroying workspaces

Workspace existence is config-time under AeroSpace:

```sh
$EDITOR ~/.config/aerospace/aerospace.toml
# add or remove from [workspace-to-monitor-force-assignment]
aerospace reload-config
ws-topology emit-aerospace --write   # regenerates the sigil-fenced digit bindings
```

Don't use macOS green-button fullscreen on apps you want aerospace to
manage; it creates a native fullscreen space aerospace can't see.
Send the window to its own workspace with `Caps+G → digit` instead.

## OrbStack (Docker Desktop replacement)

`bootstrap.sh` installs `orbstack`. On a fresh launch it offers to
"Take over docker / docker-compose / kubectl" — accept; it rewrites
`/usr/local/bin/docker` and friends. Verify with `docker context ls`.
Native Apple Silicon, ~1s cold start.

## Permission grants

The macOS bootstrap hands off to `permissions-wizard.sh`, which probes
each TCC bit first (via [`lib/macos-tcc.sh`](lib/macos-tcc.sh)) and
only opens the Accessibility pane if any toggle is missing. One gate
post-Phase-6: **Accessibility** (AeroSpace · Hyperkey · ws-snap). No
more Input Monitoring or System Extensions — those were Karabiner
DriverKit requirements that retired with the Hyperkey migration.

```sh
~/dotfiles/macos/permissions-wizard.sh           # gated; ~2 s if all set
~/dotfiles/macos/permissions-wizard.sh --force   # walk every pane
```

See [`docs/wizard.md`](docs/wizard.md).

## Verification

```sh
aerospace list-windows --all --json | jq '.[]."app-name"'   # tiler is live
pgrep -x Hyperkey                                           # Hyperkey running
tmux show -gv prefix                                        # → C-a
zsh -ic 'type z' | head -1                                  # zoxide function
nvim --headless -c 'edit /tmp/x.py' -c 'sleep 3' \
     -c 'lua print(#vim.lsp.get_clients({bufnr=0}))' -c qall   # → 2
ws-doctor                                                   # keymap/launcher health — run this first if any chord feels off
```

Cheatsheet: `Caps + ;` (live overlay; nothing on disk to inspect).

## Testing

```sh
tests/run-all.sh        # ~1.5 s — critical path tests in tests/critical/
```

Pure-bash critical path tests covering bootstrap idempotency, config
drift, and ws-doctor. CI also runs `bash -n` on all scripts.

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
(ws-prompt, ws-picker, ws-cheatsheet, ws-statusbar, ws-snap, ws-topology) live in
the [sigil](https://github.com/adames/sigil) repo — bootstrap clones
it to `~/.config/workspace/` and rebuilds the Swift binaries.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bootstrap hangs on cask install | No TTY — `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| `aerospace: Can't connect to AeroSpace server` | AeroSpace.app not running — `open -a AeroSpace`. Grant Accessibility in System Settings if it's the first launch. |
| Hyperkey grants Accessibility but Caps still doesn't fire Hyper | Open Hyperkey from the menu bar; confirm "Enable Hyper Key" + "Tap for Escape" are ON. |
| `Caps + e` / `Caps + f` / `Caps + g` / `Caps + w` does nothing | `ws-prompt` / `ws-picker` / `ws-statusbar` missing — re-run `./bootstrap.sh` |
| `Caps + ;` cheatsheet doesn't appear | `ws-cheatsheet` missing from `~/.local/bin/` — same fix |
| Manage overlay's `add` / `destroy` shows "edit aerospace.toml" message | Working as intended — workspace existence is config-time under AeroSpace; edit the toml + `aerospace reload-config && ws-topology emit-aerospace --write`. |
| Workspace pills missing | `ws-statusbar` not running — `launchctl kickstart -k gui/$(id -u)/com.user.workspace.statusbar` |
| Workspace pill doesn't update on space switch | `~/.config/workspace/on-space-changed.sh` not firing — verify aerospace.toml's `exec-on-workspace-change` line points at it |
| Workspace chip missing from prompt / tmux | `~/.config/workspace/on-space-changed.sh` to prime current.env |
| AeroSpace workspaces land on the wrong monitor after hot-plug | AeroSpace's monitor ordinals can drift on hot-plug. Run `ws-topology` (rewrites spaces.json display UUID assignments via CG-stable UUIDs). |
| Neovim plugins missing | First-launch install in progress — open `nvim`, wait for lazy.nvim to install, then restart |
| SSH'ing into Ubuntu from Ghostty: doubled chars, broken backspace | `TERM=xterm-ghostty` not in remote terminfo. From local: `infocmp -x xterm-ghostty | ssh user@host -- tic -x -`. Or run bootstrap on the VPS once. |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                  # OS dispatcher
├── lib/                          # shared bash helpers (logging, install_file, TCC probes)
├── macos/                        # 4 phases (sudo, packages, apply, wizard)
├── ubuntu/bootstrap.sh           # 6 phases
├── docs/
│   ├── architecture.md · wizard.md · keymap.md
│   └── archive/yabai-to-aerospace.md   # migration history
└── configs/
    ├── aerospace.toml            # window tiling + Hyper chord dispatch (sentinel-fenced)
    ├── workspace/                # cheatsheet layout (the Swift package + spaces.json +
    │   └── cheatsheet-layout.json  on-space-changed.sh live in sigil; cloned to
    │                               ~/.config/workspace/ at bootstrap)
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

## AI Agent Collaboration

[`AGENTS.md`](AGENTS.md) is the one agent-facing file that ships in the
repo — read by Claude Code, Codex, Devin, Cursor, and anything else
following the cross-agent convention. It carries the persona (ricer:
infra/configs/shell/WM), the public-repo etiquette rules, and the
invariants / gotchas / locked-in choices for this tree.

Per-agent worktrees and per-agent live settings stay **out** of the
tracked tree — they belong under `~/personas/.<agent>/`:

| Agent | Worktree Directory |
|-------|--------------------|
| Claude | `~/personas/.claude/` |
| Windsurf | `~/personas/.windsurf/` |
| Devin | `~/personas/.devin/` |
| Cursor | `~/personas/.cursor/` |

### Shared Settings

`.settings.json` (tracked template) → `settings.json` (tracked live
copy). `settings.*.json` and `settings.local.json` are gitignored for
per-agent overrides.

```sh
cp ~/dotfiles/.settings.json ~/dotfiles/settings.json
```

The shared settings file defines allowed tools, workflows, and
constraints applied to every agent working on this project.
