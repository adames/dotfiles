# dotfiles

Keyboard-first dev environment. Three rules:

1. **Caps Lock is the centre.** Tap = `Esc`, hold = `Hyper` (⌃⌥⌘⇧),
   hold + Shift = `Meh` (⌃⌥⌘). Karabiner remaps once; every layer
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
                  │  • +Shift → Meh │
                  └────────┬────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
       skhd          Hammerspoon       (system Cmd-keys
        │           ┌──────┴──────┐    pass through)
        ▼           ▼             ▼
      yabai     Terminal      Cheatsheet
   (BSP tiler)  Cmd+T/N      Hyper+/ overlay
        │
        ▼
  ┌──────────────────────────────────────────────────────────┐
  │ inside the terminal: Ghostty → tmux → zsh → Neovim       │
  │   tmux prefix = C-Space     leader = Space               │
  │   shell: fzf · zoxide · starship · direnv · vi-mode      │
  │   nvim:  pyright + ruff + dap-python + neotest           │
  └──────────────────────────────────────────────────────────┘
```

Details: [`docs/architecture.md`](docs/architecture.md). Permission flow:
[`docs/wizard.md`](docs/wizard.md). Karabiner JSON: [`configs/karabiner.md`](configs/karabiner.md).

## Quick start

```sh
git clone "${DOTFILES_REPO:-git@github.com:adames/dotfiles.git}" ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS bootstrap is five phases (sudo / packages / configs / defaults /
wizard). Ubuntu is six (terminfo / system / shell / runtimes / configs /
default-shell). The Ubuntu side skips yabai/Karabiner, omits Docker
(OrbStack covers containers on the Mac side; the VPS doesn't need them
locally), and ships an `xterm-ghostty` terminfo entry so SSH'ing in from
Ghostty doesn't break zsh's line editor.

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps → Hyper / Meh / Esc | Karabiner-Elements | [`karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling | yabai | [`yabairc`](configs/yabairc) |
| Neon window borders (per-workspace colour) | JankyBorders | [`borders/bordersrc`](configs/borders/bordersrc) |
| Hyper hotkeys → yabai | skhd | [`skhdrc`](configs/skhdrc) |
| Hyper+T/N terminal, Meh+arrow snaps, Hyper+/ cheatsheet | Hammerspoon | [`hammerspoon-init.lua`](configs/hammerspoon-init.lua) · [`hammerspoon-cheatsheet.lua`](configs/hammerspoon-cheatsheet.lua) |
| 10-slot workspace identity (color + icon + name → tmux + prompt + borders) | yabai signal + scripts | [`workspace/`](configs/workspace/) · [`lib/colors.sh`](lib/colors.sh) |
| Hyper app launchers (Brave, Claude) | Karabiner shell_command | [`karabiner.json`](configs/karabiner.json) |
| Terminal (Option = Meta) | Ghostty | [`ghostty-config`](configs/ghostty-config) |
| `C-Space` prefix · `prefix+f` sessionizer · vim-style nav | tmux | [`tmux.conf`](configs/tmux.conf) · [`tmux-sessionizer`](configs/tmux-sessionizer) |
| zsh: vi-mode · starship · direnv · autosuggestions · syntax-highlighting | zsh | [`zshrc`](configs/zshrc) |
| `Ctrl-R/T`, `Alt-C` (fd-backed) | fzf | wired in `zshrc` |
| `z foo` jump to frecent dir | zoxide | wired in `zshrc` |
| `rg` with sensible globs | ripgrep | [`ripgreprc`](configs/ripgreprc) |
| Side-by-side syntax-highlighted git diffs | git-delta | [`gitconfig`](configs/gitconfig) |
| Neovim 0.12+ · Lazy + 16 plugins (incl. harpoon, oil, lazygit) | nvim | [`nvim-init.lua`](configs/nvim-init.lua) |
| Python: Pyright + Ruff (LSP) · debugpy (DAP) · pytest (neotest) | Mason | same |
| Git TUI (`lazygit` CLI · `<leader>gG` in nvim) | lazygit | brew formula |
| Docker / Compose / Kubernetes (~1s cold start, native Apple Silicon) | OrbStack | brew cask · replaces Docker Desktop |

## Daily-driver keymap

Full reference is `Hyper+/`. Layer split: **Hyper = navigate, Meh (Caps+Shift) = modify.**

```
Caps tap                      → Esc

# Hyper — navigate
Caps + hjkl                   → focus window
Caps + 1…9, 0                 → focus slot 1..10 (core/forge/codex/lex/scope/uplink/signal/ledger/craft/void)
Caps + return / f / e / r     → fullscreen / float / balance / rotate
Caps + t / n                  → new terminal tab / window
Caps + b / c                  → Brave (browser) / Claude
Caps + /                      → toggle cheatsheet

# Meh — modify
Caps + Shift + hjkl           → swap window
Caps + Shift + 1…9, 0         → send window to slot N (and follow)
Caps + Shift + ←→↑↓           → manual snap for floats / non-yabai windows

# Terminal
C-Space  hjkl / v / s / z     → tmux pane nav / split / zoom
C-Space  f                    → fzf project sessionizer

# Neovim
<leader>ff / fg / fb          → fzf files / live-grep / buffers
<leader>ca / rn / =           → LSP code action / rename / format
-                             → oil (parent dir as a buffer)
<leader>ha / hh / 1…4         → harpoon add / menu / jump
<leader>bn / bp / bd / bo     → buffer next / prev / delete / close-others
]c / [c                       → next / prev git hunk (gitsigns)
<leader>gs / gh / gp / gb     → git status / stage hunk / preview / blame
<leader>db / dc / do / di     → DAP breakpoint / continue / over / into
<leader>tn / tf / ts          → test nearest / file / summary
```

## Workspace identity (10 slots)

`Caps + 1…9, 0` focus a slot. There are **10 slots total** with stable
identities — color, icon, and default name — defined in
[`configs/workspace/spaces.default.json`](configs/workspace/spaces.default.json):

| # | Slot | Color (Catppuccin) | Purpose |
|---|---|---|---|
| 1 | **core**    `Caps+1` |  mauve    | Always-on command center · primary terminal |
| 2 | **forge**   `Caps+2` |  peach    | Primary TypeScript project work |
| 3 | **codex**   `Caps+3` |  yellow   | Learning · Python · LeetCode · scratch |
| 4 | **lex**     `Caps+4` |  green    | Writing · docs · notes · journals |
| 5 | **scope**   `Caps+5` |  teal     | Browser · research · www |
| 6 | **uplink**  `Caps+6` |  sky      | SSH · VPS · remote shells |
| 7 | **signal**  `Caps+7` |  sapphire | Comms · chat · mail |
| 8 | **ledger**  `Caps+8` |  blue     | Admin · freelance · billing |
| 9 | **craft**   `Caps+9` |  lavender | Creative · music · design · gaming |
| 10 | **void**   `Caps+0` |  overlay0 | Scratch · throwaway · overflow |

Identity surfaces:

- **Window borders** — focused window gets the slot's neon colour via
  [JankyBorders](https://github.com/FelixKratz/JankyBorders).
- **Tmux statusline** — left chip shows icon + name in slot colour.
- **Starship prompt** — leftmost segment is the workspace chip.
- **Hammerspoon overlay** — brief OSD on space switch.

Slot **name is renameable** (run [`workspace/rename.sh`](configs/workspace/rename.sh)
or edit `~/.config/workspace/spaces.json`); the **color and icon are
fixed to the slot** so muscle-memory ("orange means slot 2") survives a
rename. Slot identity stable across display moves: the system addresses
spaces by yabai label (`core`, `forge`, …), not by volatile index.

**Display lock**: when a monitor is attached, slot 1 (`core`) stays on
the laptop screen and slots 2..10 migrate to the external. Single-display
mode keeps everything on the laptop. The reconciliation logic lives in
[`workspace/reconcile-displays.sh`](configs/workspace/reconcile-displays.sh)
and runs on `display_added`/`removed`/`changed`. **One-time setup**:
plug only the laptop in and run `~/.config/workspace/laptop-uuid-init.sh`
to capture the built-in panel's UUID — the reconciler uses it to identify
the laptop across plug/unplug events. The first bootstrap run does this
automatically if exactly one display is attached.

[`yabai-ensure-spaces.sh`](configs/yabai-ensure-spaces.sh) is called at
yabai startup and rebound to the `display_added` signal in
[`yabairc`](configs/yabairc); it ensures exactly 10 spaces total and
applies the slot labels. Installing the SA is a one-time multi-reboot
dance because macOS gates it behind SIP. Procedure:

1. **Disable SIP from Recovery** (this is the part you have to do by hand):
   ```
   sudo shutdown -h now
   # hold power button → "Loading startup options"
   # Options → Continue → admin login
   # menu bar: Utilities → Terminal
   csrutil disable
   # 'y' → admin password → reboot
   ```
2. **Apple Silicon only — set the arm64e boot-arg, then reboot once more.**
   yabai is arm64, Dock.app is arm64e; cross-ABI mach injection needs
   this flag or `--load-sa` silently fails inside Dock:
   ```
   sudo nvram boot-args="-arm64e_preview_abi"
   sudo reboot
   ```
3. **Install the SA + sudoers entry**:
   ```
   ~/dotfiles/macos/yabai-sa-install.sh
   ```
   The script verifies SIP + boot-args, runs `sudo yabai --load-sa`
   (yabai 7.x: one command installs + loads the SA into Dock.app),
   writes a hash-pinned `/etc/sudoers.d/yabai` so subsequent `--load-sa`
   calls at login are passwordless, restarts yabai, and tests `--create`
   actually works.
4. **Re-run after yabai upgrades** — `brew upgrade yabai` changes the
   binary hash; re-run `yabai-sa-install.sh` to refresh the sudoers entry,
   otherwise the SA silently stops auto-loading.

Don't use macOS green-button (⛶) fullscreen on apps you want yabai to
manage — it creates a native fullscreen space yabai cannot touch. Use
`Caps + Return` for yabai-managed zoom instead.

### Customizing workspaces — the `workspace` CLI

`~/.local/bin/workspace` wraps every spaces.json mutation with an atomic
write and a re-fire of the cascade (tmux / starship / borders /
sketchybar / hammerspoon all repaint within ~50ms):

```
# inspection
workspace status                  # all slots with color swatches
workspace get core                # one slot as JSON (accepts name OR index)
workspace count                   # current slot count
workspace doctor                  # validate schema
workspace verify                  # run end-to-end test harness

# point edits
workspace name 3 lab              # rename slot 3
workspace name core kernel        # … or address it by current name
workspace color 3 "#ffaabb"       # recolor slot 3
workspace icon 3 ""              # set slot 3 icon (PUA glyphs preserved)

# reordering ergonomics (positional colors: only name + icon move)
workspace swap core scope         # exchange two slots' name & icon
workspace move codex 1            # codex → slot 1; others shift
workspace move codex before forge # natural-language adjacency
workspace move codex after lex
workspace rotate 1                # shift all (name, icon) right by 1
workspace rotate -1               # shift left
workspace reverse                 # mirror the slot order
workspace reorder 2 1 3 4 5 6 7 8 9 10   # full permutation

# count changes (sketchybar pill count tracks automatically via hook)
workspace add lab "#ffaabb" ""    # append a new slot (count → 11)
workspace remove 11               # delete slot 11
workspace remove lab              # … or by name

# themes
workspace themes
workspace theme tokyonight
workspace theme catppuccin-mocha --with-icons

# saved layouts (per-machine snapshots of spaces.json)
workspace layout save morning
workspace layout list
workspace layout load morning -y
workspace layout delete morning -y

# escape hatches
workspace edit                    # $EDITOR on spaces.json
workspace reset -y                # restore from spaces.default.json
```

**Positional colors.** Slot N's color is intrinsic to position N. When
you `swap`, `move`, `rotate`, `reverse`, or `reorder`, only the
`(name, icon)` tuples permute — the color palette stays anchored to
slot indices. Use `workspace color N #HEX` to change a slot's color
directly. (Orange always means slot 2, regardless of what's currently
named there.)

**Slot identifiers.** Anywhere a slot is expected — `name`, `color`,
`icon`, `get`, `remove`, `swap`, `move` — you can pass either a numeric
index OR a unique slot name. `workspace move codex before forge`.

**Per-machine, not committed.** `~/.config/workspace/spaces.json`,
saved layouts in `~/.config/workspace/layouts/`, and any custom themes
in `~/.config/workspace/themes/` all live in `$HOME` — they survive
bootstrap re-runs and are never written back to the repo.

**Themes** at `~/.config/workspace/themes/<name>.json`. Drop a JSON
file matching `{"name": "...", "colors": [...N hex strings]}` (optionally
with an `icons[]` array) and it's auto-discovered by `workspace themes`.
Canonical palettes shipped by bootstrap: `catppuccin-mocha` (default),
`catppuccin-frappe`, `gruvbox-dark`, `tokyonight`, `rose-pine`.

**Slot count is flexible.** The CLI derives the current count from
`spaces.json` rather than hardcoding 10. `add` / `remove` are
first-class, and the default post-mutate hook keeps the SketchyBar
pill count in sync (add → new pill appears, remove → old pill is
removed; on `--reload` sketchybarrc reads the current count). Hotkeys
remain bound to slots 1..10 in `~/.skhdrc`; slots beyond 10 are
reachable via yabai's own CLI or by adding skhd bindings yourself.

**Extension point.** Each mutation invokes
`~/.config/workspace/hooks/post-mutate.sh` with args
`(subcommand, slot_indices...)`. The default shipped stub keeps
SketchyBar's pill set in sync on `add` / `remove`; edit it freely to
also send notifications, log changes, kick other status bars, etc.
The hook is per-machine and never clobbered.

## Switching from Docker Desktop to OrbStack

`bootstrap.sh` installs `orbstack` (cask). To complete the swap on a
machine that already has Docker Desktop:

```sh
# 1. Quit Docker Desktop if it's running.
osascript -e 'quit app "Docker"'

# 2. Open OrbStack — on first launch it offers to "Take over docker / docker-compose / kubectl".
#    Click yes; it rewrites /usr/local/bin/docker and friends.
open -a OrbStack

# 3. Verify the docker CLI now points at OrbStack.
docker context ls                                # → expect 'orbstack' as current
docker ps                                        # → talks to OrbStack daemon

# 4. Uninstall Docker Desktop once you're confident.
brew uninstall --cask docker-desktop
rm -rf ~/Library/Containers/com.docker.docker ~/Library/Application\ Support/Docker\ Desktop
```

OrbStack is a drop-in `docker` / `docker-compose` replacement with
native Apple Silicon performance and ~1-second cold start vs Docker
Desktop's ~30s. Use it the same way.

## Permission grants

The macOS bootstrap hands off to `permissions-wizard.sh`, which **probes
each TCC bit first** (via [`lib/macos-tcc.sh`](lib/macos-tcc.sh)) and
only opens System Settings panes that have missing toggles. On a
re-bootstrap of a working machine, the wizard finishes in ~2 seconds
without ever popping a window. Probes don't require Full Disk Access —
they use `launchctl` liveness, `systemextensionsctl list`, and
Hammerspoon's `hs.accessibilityState()` over the AppleScript bridge.

Three gates:

1. **Accessibility** — yabai, skhd, Hammerspoon, Karabiner-Elements
2. **Input Monitoring** — Karabiner-Elements, Karabiner-DriverKit-VirtualHIDDevice
3. **System Extensions** — approve Karabiner-DriverKit-VirtualHIDDevice

If a probe disagrees with reality (false negative → pane opens but
nothing to toggle; false positive → pane skipped when grant is missing),
run with `--force` to bypass probes and walk every pane:

```sh
~/dotfiles/macos/permissions-wizard.sh --force
```

The wizard launches each app first so the entries appear in the panes
with toggles OFF — no dragging binaries through Finder's `+` dialog.
See [`docs/wizard.md`](docs/wizard.md).

## Verification

```sh
# Window/keyboard
yabai -m query --windows | jq '.[].app'           # tiler is live
launchctl list | grep com.koekeishiya.skhd        # skhd PID > 0

# Terminal + shell
tmux show -gv prefix                              # → C-Space
zsh -ic 'bindkey | grep fzf-history-widget' | head -1
zsh -ic 'type z' | head -1                        # zoxide function

# Editor — open any .py and check 2 LSPs attached
nvim --headless -c 'edit /tmp/x.py' -c 'sleep 3' \
     -c 'lua print(#vim.lsp.get_clients({bufnr=0}))' -c qall   # → 2
```

Cheatsheet: `Caps + /` (live overlay; nothing on disk).

## Re-running

```sh
~/dotfiles/bootstrap.sh                          # idempotent
~/dotfiles/macos/permissions-wizard.sh           # wizard alone
BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh   # no-TTY / headless
NO_COLOR=1 ~/dotfiles/bootstrap.sh               # plain output
```

## Editing

```sh
$EDITOR ~/dotfiles/configs/zshrc
~/dotfiles/bootstrap.sh
```

`install_file` byte-compares; re-running is cheap. No `.bak` is written
— git history is the source of truth for what was there before.

Hammerspoon Lua reloads automatically on `.lua` save (pathwatcher).
Tmux: `prefix + r`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bootstrap hangs on cask install | No TTY — `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| "Karabiner installed but `.app` missing" | `installer -pkg` was interrupted; bootstrap re-runs the staged installer when TTY is present, or `brew reinstall --cask karabiner-elements` |
| yabai logs `'display has separate spaces' is disabled` | Log out and back in |
| `Caps + /` cheatsheet doesn't appear | Hammerspoon not running / no Accessibility — `pgrep -x Hammerspoon` then re-run wizard |
| Window borders missing | `borders` not installed or daemon dead — `brew install FelixKratz/formulae/borders` then `~/.config/borders/bordersrc &` |
| Workspace chip missing from prompt / tmux | yabai signal didn't fire yet — `~/.config/workspace/on-space-changed.sh` to prime; check `~/.cache/workspace/current.env` populated |
| Slot 1 lands on the monitor instead of the laptop | UUID capture missed or wrong — `~/.config/workspace/laptop-uuid-init.sh --force` with only the built-in panel attached |
| Neovim plugins missing | First-launch install in progress; open `nvim`, wait or `:Lazy sync` then `:MasonToolsInstall` |
| `pyright` doesn't attach to `*.py` | `:Mason` → `i` to install, or `:MasonToolsInstall` |
| SSH'ing into a fresh Ubuntu VPS from Ghostty: double characters, backspace inserts space | `TERM=xterm-ghostty` not in remote's terminfo. **From a local terminal:** `infocmp -x xterm-ghostty \| ssh user@host -- tic -x -`. Or run `~/dotfiles/bootstrap.sh` on the VPS once — phase 1 installs the entry to `~/.terminfo`. Extracting from Ghostty's bundle locally: `TERMINFO_DIRS=/Applications/Ghostty.app/Contents/Resources/terminfo infocmp -x xterm-ghostty` |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                  # OS dispatcher
├── lib/
│   ├── common.sh                 # logging + install_file helpers
│   ├── colors.sh                 # workspace palette + icons (single source of truth)
│   └── macos-tcc.sh              # TCC probes for the gated wizard
├── macos/
│   ├── bootstrap.sh              # 5 phases (sudo / pkgs / configs / defaults / wizard)
│   ├── permissions-wizard.sh     # probe-gated; --force to walk every pane
│   └── yabai-sa-install.sh       # post-SIP-disable: install scripting addition + sudoers
├── ubuntu/bootstrap.sh           # 6 phases (terminfo / system / shell / runtimes / configs / shell)
├── docs/{architecture,wizard}.md
└── configs/
    ├── karabiner.{json,md}       # Caps remap + JSON explainer
    ├── yabairc                   # BSP tiling + workspace + display signals
    ├── yabai-ensure-spaces.sh    # ensures 10 BSP spaces total + applies labels
    ├── skhdrc                    # Hyper bindings → yabai (1..9, 0 + Hyper+/)
    ├── hammerspoon-{init,cheatsheet}.lua
    ├── workspace/                # 10-slot identity layer
    │   ├── spaces.default.json   #  · slot → name/color/icon defaults
    │   ├── on-space-changed.sh   #  · yabai signal handler (env file + tmux + borders)
    │   ├── reconcile-displays.sh #  · slot 1 → laptop, 2..10 → monitor
    │   ├── laptop-uuid-init.sh   #  · captures built-in display UUID
    │   ├── rename.sh             #  · osascript-prompted slot rename
    │   └── install.sh            #  · seeds + migrates + restarts daemons
    ├── borders/bordersrc         # JankyBorders launch script + defaults
    ├── starship.toml             # prompt + workspace chip
    ├── ghostty-config
    ├── xterm-ghostty.terminfo    # compiled into ~/.terminfo on Ubuntu boxes
    ├── tmux.conf · tmux-sessionizer
    ├── zshrc · gitconfig · ripgreprc
    ├── jetbrains-purge.sh        # gated, dry-run-by-default IDE rip-out
    └── nvim-{init.lua,lazy-lock.json,keymaps.lua}
```

## Design principles

- **Layered, not bundled.** Swap any one tool without touching the others.
- **Idempotent.** Re-running bootstrap is the supported way to apply edits.
- **Drift-resistant.** What's in `configs/` is what gets deployed; nvim
  `init.lua` and `lazy-lock.json` are tracked, so the editor is reproducible.
- **No paid Apple Developer ID.** Wizard chains through System Settings.
