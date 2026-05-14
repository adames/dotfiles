# dotfiles

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
                           │
                          skhd ──────────────► (system Cmd-keys
                           │                    pass through)
              ┌────────────┼────────────┐
              ▼            ▼            ▼
            yabai       Terminal    Cheatsheet
         (BSP tiler)    Cmd+T/N    Hyper+; HUD
                       (osascript) (ws-cheatsheet)
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
| Caps → Hyper / Mod / Esc | Karabiner-Elements | [`karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling | yabai | [`yabairc`](configs/yabairc) |
| Neon window borders (per-workspace colour) | JankyBorders | [`borders/bordersrc`](configs/borders/bordersrc) |
| Persistent workspace pill strip (always-visible per-display indicator) | SketchyBar | [`sketchybar/`](configs/sketchybar/) |
| Hyper/Mod hotkeys → yabai · terminal · app launchers · cheatsheet · snaps | skhd | [`skhdrc`](configs/skhdrc) |
| Mod+arrow snaps for floating windows (AX) | ws-snap | [`workspace/topology/Sources/ws-snap/`](configs/workspace/topology/Sources/ws-snap) |
| SketchyBar per-display autohide (cursor poller, LaunchAgent) | ws-autohide | [`workspace/topology/Sources/ws-autohide/`](configs/workspace/topology/Sources/ws-autohide) |
| Cheatsheet HUD (native SwiftUI) | ws-cheatsheet | [`workspace/topology/Sources/ws-cheatsheet/`](configs/workspace/topology/Sources/ws-cheatsheet) · [`workspace/cheatsheet.json`](configs/workspace/cheatsheet.json) |
| Cross-display topology + per-display layout policy (notch-aware) | ws-topologyd (LaunchAgent) | [`workspace/topology/`](configs/workspace/topology) |
| Per-slot workspace identity (color + icon + name → tmux + prompt + borders + pills) | yabai signal + scripts | [`workspace/`](configs/workspace/) |
| Hyper app launchers (browser, terminal, Finder, Settings, Claude, Spotify) | skhd | [`skhdrc`](configs/skhdrc) |
| Terminal (Option = Meta) | Ghostty | [`ghostty-config`](configs/ghostty-config) |
| `C-Space` prefix · `prefix+f` sessionizer · vim-style nav | tmux | [`tmux.conf`](configs/tmux.conf) · [`tmux-sessionizer`](configs/tmux-sessionizer) |
| zsh: vi-mode · starship · direnv · autosuggestions · syntax-highlighting | zsh | [`zshrc`](configs/zshrc) |
| `Ctrl-R/T`, `Alt-C` (fd-backed) | fzf | wired in `zshrc` |
| `z foo` jump to frecent dir | zoxide | wired in `zshrc` |
| `rg` with sensible globs | ripgrep | [`ripgreprc`](configs/ripgreprc) |
| Side-by-side syntax-highlighted git diffs | git-delta | [`gitconfig`](configs/gitconfig) |
| Neovim 0.12+ · Lazy + 23 plugins (incl. harpoon, oil, gitsigns) | nvim | [`nvim-init.lua`](configs/nvim-init.lua) |
| Python: Pyright + Ruff (LSP) · debugpy (DAP) · pytest (neotest) | Mason | same |
| Git TUI (run `lazygit` from a terminal / tmux pane) | lazygit | brew formula |
| Docker / Compose / Kubernetes (~1s cold start, native Apple Silicon) | OrbStack | brew cask · replaces Docker Desktop |

## Daily-driver keymap

Full reference is `Hyper+;`. Layer split: **Hyper = navigate, Mod (Caps+Shift) = modify.**

```
Caps tap                      → Esc

# Hyper — navigate / open
Caps + hjkl                   → focus window
Caps + 1..9, 0                → focus slot N (0 = slot 10)
Caps + return / e / r         → fullscreen / balance / rotate
Caps + t                      → new terminal window (auto-detect)
Caps + b                      → new browser window (auto-detect)
Caps + f                      → new Finder window
Caps + s                      → System Settings
Caps + c / m                  → Claude / Spotify
Caps + ;                      → toggle cheatsheet

# Mod — modify
Caps + Shift + hjkl           → swap window
Caps + Shift + 1..9, 0        → send window to slot N (and follow)
Caps + Shift + f              → float / unfloat window
Caps + Shift + r              → rename current workspace
Caps + Shift + -              → remove current workspace
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

## Workspace identity

**yabai owns space existence. `spaces.json` owns optional identity.**
We don't manipulate yabai — Mission Control + / × is how spaces are
created and destroyed; the bar reflects whatever yabai reports.

A fresh install ships an empty `spaces.json` (no slot identities).
Pills render as bare gray `ws1`, `ws2`, … until you customize one:

```sh
ws name 1 work            # rename slot 1
ws icon 1 code            # set an SF Symbol icon (auto-maps to Nerd Font)
ws color 1 "#a6e3a1"      # any hex
```

The slot count is whatever yabai has — `Caps+1..0` focuses slot N,
silently no-ops if N doesn't exist. Mission Control's `+` / `×` Space
gestures keep the bar in lock-step (yabai's `space_created` /
`space_destroyed` signals are wired to per-display-pills.sh and
on-space-destroyed.sh).

Seed file (intentionally empty):
[`configs/workspace/spaces.default.json`](configs/workspace/spaces.default.json).

Identity surfaces:

- **Window borders** — focused window gets the slot's neon colour via
  [JankyBorders](https://github.com/FelixKratz/JankyBorders).
- **Tmux statusline** — left chip shows icon + name in slot colour.
- **Starship prompt** — leftmost segment is the workspace chip.
- **SketchyBar pill strip** — persistent row of catppuccin pills at
  the top of each display, showing ONLY the workspaces yabai assigns
  to that display. The active slot is filled; others show number +
  nerd-font glyph in the slot's colour. Pill metadata source of truth
  is `~/.config/workspace/spaces.json` (drives tmux/starship/borders
  too); per-display assignment is driven by `yabai -m query --spaces`
  via [`sketchybar/plugins/per-display-pills.sh`](configs/sketchybar/plugins/per-display-pills.sh)
  and pills repaint via a custom event fired from
  [`workspace/on-space-changed.sh`](configs/workspace/on-space-changed.sh).
  Config: [`sketchybar/`](configs/sketchybar/).

**Per-display rendering.** Each pill's `display=<idx>` mask is set by
[`per-display-pills.sh`](configs/sketchybar/plugins/per-display-pills.sh)
based on yabai's space-to-display mapping. Plug in a monitor → yabai
assigns it new spaces → the display gets its own pill set. Plug out →
pills migrate with their spaces back to the laptop. Re-fires on yabai
`display_added` / `display_removed` / `display_changed` / `space_changed`,
and from the post-mutate hook on `workspace add` / `remove`.

**Bar / menu-bar coexistence.** macOS auto-hide menu bar is on
(`NSGlobalDomain._HIHideMenuBar=1`). When the cursor leaves the top
edge of a display, that display's pill strip is visible and clickable;
when the cursor crosses back up, the strip slides off-screen and the
macOS menu bar reveals in the same space. Driven by the
[`ws-autohide`](configs/workspace/topology/Sources/ws-autohide)
launchd agent — a 100ms cursor poller that toggles each pill's
`y_offset` based on cursor.y RELATIVE to its current display (hide
at `rel_y < 2`, re-show at `rel_y >= frame.maxY - visibleFrame.maxY`).
Per-display — moving the cursor between monitors only hides the side
you're approaching. yabai's [`external_bar all:26:0`](configs/yabairc)
reserves the top 26px on every display so BSP-tiled windows never
encroach.

**Slot identity.** Color is **positional** — slot N keeps its colour
across `swap` / `move` / `rotate` / `reverse` / `reorder` ("orange
always means slot 2"). Name and icon are what move when you
reorder. Use `workspace color N #HEX` to change a slot's colour
directly.

**Visible-pill cap (notch-aware).** Notched MacBook Pros cap visible
pills at 10 on the built-in display (matches the `Caps+1..0` hotkey
range and the geometric constraint of the camera notch). Non-notched
displays (externals, MBAir / 13" Pro built-in) show all assigned
pills, centered between the left and right edges. Notch detection
uses [`plugins/notch-detect.sh`](configs/sketchybar/plugins/notch-detect.sh)
(model identifier match against MacBookPro18,*, Mac14-20,*); override
with `WS_LAPTOP_HAS_NOTCH=yes|no` in the environment.

**Display assignment**: yabai owns it. Each space lives on a display
because macOS/yabai puts it there; we don't move spaces around at boot
or on display events. Drag spaces between monitors in Mission Control
to lay them out the way you like — yabai persists the assignment.

**`yabai -m space --create` / `--destroy` need the scripting addition.**
Mission Control's `+` / `×` buttons don't (those go through macOS
directly). Installing the SA is a one-time multi-reboot dance because
macOS gates it behind SIP. Procedure:

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

### Customizing workspaces — the `ws` CLI

`~/.local/bin/ws` wraps every spaces.json mutation with an atomic
write and a re-fire of the cascade (tmux / starship / borders /
sketchybar all repaint within ~50ms). The old `workspace` name remains
as a compat symlink, so existing muscle-memory keeps working.

```
# inspection
ws status                  # all slots with color swatches
ws get 1                # one slot as JSON (accepts name OR index)
ws count                   # current slot count
ws doctor                  # validate schema
ws verify                  # run end-to-end test harness

# point edits
ws name 3 lab              # rename slot 3
ws name 1 work            # … or address it by current name (after you set one)
ws color 3 "#ffaabb"       # recolor slot 3
ws icon 3 play.fill        # set icon via SF Symbol name (→ )
ws icon 3 ""              # … or paste a literal Nerd Font glyph
ws icon search lock        # discover SF names that have Nerd Font mappings

# reordering ergonomics (positional colors: only name + icon move)
ws swap 1 2         # exchange two slots' name & icon
ws move 3 1            # slot 3 → slot 1; others shift
ws move 3 before 2     # natural-language adjacency
ws move 3 after 4
ws rotate 1                # shift all (name, icon) right by 1
ws rotate -1               # shift left
ws reverse                 # mirror the slot order
ws reorder 2 1 3 4 5 6 7 8 9 10   # full permutation

# count changes (sketchybar pill count tracks automatically via hook)
ws add                     # interactive: prompts for name, icon, color
ws add lab "#ffaabb" ""    # … or pass them positionally (--no-prompt for scripts)
ws remove 11               # delete slot 11 (prompts unless -y)
ws remove lab -y           # … or by name, no confirm

# themes
ws themes
ws theme tokyonight
ws theme catppuccin-mocha --with-icons

# saved layouts (per-machine snapshots of spaces.json)
ws layout save morning
ws layout list
ws layout load morning -y
ws layout delete morning -y

# escape hatches
ws edit                    # $EDITOR on spaces.json
ws reset -y                # restore from spaces.default.json

# system
ws refresh                 # force-rerun cascade (current.env + pills)
ws refresh --full          # also kickstart the topology daemon
ws host                    # show effective config + overlay status
ws host init               # fork off a per-host overlay (spaces.<hostname>.json)
ws host reset              # remove overlay, fall back to shared
ws migrate --apply         # import a legacy v1 spaces.json (idempotent on v2)
```

**Positional colors.** Slot N's color is intrinsic to position N. When
you `swap`, `move`, `rotate`, `reverse`, or `reorder`, only the
`(name, icon)` tuples permute — the color palette stays anchored to
slot indices. Use `ws color N #HEX` to change a slot's color directly.
(Orange always means slot 2, regardless of what's currently named
there.)

**Hotkey remove.** `Hyper+Shift+-` removes the currently focused slot
(`ws remove $MACOS_SPACE_INDEX -y`). There's no companion add hotkey
right now — the previous Hyper+Shift+= binding spawned a Ghostty window
and typed `ws add` into it, which was unreliable; run `ws add` from
your shell directly until we find a better entry point. Subcommands
and slot identifiers tab-complete in zsh and bash when the completion
file is sourced (handled by `zshrc` / `bashrc`).

**Slot identifiers.** Anywhere a slot is expected — `name`, `color`,
`icon`, `get`, `remove`, `swap`, `move` — you can pass either a numeric
index OR a unique slot name. `ws move 3 before 2`.

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
first-class, and the default post-mutate hook keeps the SketchyBar pill
count in sync. Slot-focus hotkeys are *generated* on every mutation:
`ws-topology emit-skhd --write` regenerates `~/.config/skhd/spaces.skhdrc`
(loaded via `.load` from the main `skhdrc`) for `min(slotCount, 10)`
slots — the 10-cap is a digit-keyboard hardware limit. Slots beyond 10
are reachable via yabai's own CLI or a leader-prefix scheme you add
manually.

**Per-host overlay.** Need different slot identities on your laptop vs
desktop? `workspace host init` forks the shared `spaces.json` into
`spaces.<hostname>.json` (e.g. `spaces.m3.json`); the cascade and CLI
both prefer the host file when present. `workspace host reset` removes
the overlay; the machine falls back to the shared default. Both files
sync with the rest of your config via your usual dotfiles workflow.

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
they use `launchctl` liveness and `systemextensionsctl list`.

Three gates:

1. **Accessibility** — yabai, skhd, ws-snap, Karabiner-Elements
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

Cheatsheet: `Caps + ;` (live overlay; nothing on disk).

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

Native helpers (ws-snap / ws-autohide / ws-cheatsheet / ws-topology) live
under `configs/workspace/topology/`; re-running `bootstrap.sh` re-builds
and re-links them. Tmux: `prefix + r`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bootstrap hangs on cask install | No TTY — `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| "Karabiner installed but `.app` missing" | `installer -pkg` was interrupted; bootstrap re-runs the staged installer when TTY is present, or `brew reinstall --cask karabiner-elements` |
| yabai logs `'display has separate spaces' is disabled` | Log out and back in |
| `Caps + ;` cheatsheet doesn't appear | `ws-cheatsheet` missing from `~/.local/bin/` — re-run `~/.config/workspace/topology/install.sh` |
| Window borders missing | `borders` not installed or daemon dead — `brew install FelixKratz/formulae/borders` then `~/.config/borders/bordersrc &` |
| Workspace pills missing from menu/bottom bar | `sketchybar` not installed or service dead — `brew install FelixKratz/formulae/sketchybar` then `brew services restart sketchybar`. Pills painted but blank glyphs → wrong font family in `sketchybarrc` (must be `"JetBrainsMono NF"` with the space) |
| Workspace pill doesn't update on space switch | `on-space-changed.sh` ran but sketchybar trigger silent — `sketchybar --trigger workspace_changed` to repaint; if that does nothing, `brew services restart sketchybar` |
| Workspace chip missing from prompt / tmux | yabai signal didn't fire yet — `~/.config/workspace/on-space-changed.sh` to prime; check `~/.cache/workspace/current.env` populated |
| Slot 1 lands on the wrong display | yabai owns space-to-display assignment. Drag the space in Mission Control to where you want it — yabai persists the assignment across reboots. |
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
    ├── skhdrc                    # Hyper/Mod bindings → yabai · ws-snap · ws-cheatsheet · apps
    ├── workspace/                # workspace identity layer (optional name/color/icon per yabai space)
    │   ├── spaces.default.json   #  · empty seed (yabai owns existence; identity is opt-in)
    │   ├── on-space-changed.sh   #  · yabai signal handler (env file + tmux + borders + sketchybar)
    │   ├── on-space-destroyed.sh #  · prune orphan slot from spaces.json after yabai destroys a space
    │   ├── rename.sh             #  · osascript-prompted slot rename
    │   ├── topology/             #  · Swift package: ws-topology(d), ws-cheatsheet, ws-snap, ws-autohide
    │   └── install.sh            #  · seeds + restarts daemons
    ├── borders/bordersrc         # JankyBorders launch script + defaults
    ├── sketchybar/               # persistent workspace pill strip
    │   ├── sketchybarrc          #  · bar geometry + space items + workspace.paint sentinel
    │   ├── colors.sh             #  · catppuccin AARRGGBB constants
    │   ├── plugins/paint-all.sh  #  · batched all-pill repaint (single sketchybar transaction)
    │   └── bootstrap.sh          #  · idempotent installer (brew + service start)
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
