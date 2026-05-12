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
   (BSP tiler)  Cmd+T/N      Hyper+0 overlay
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
| Hyper hotkeys → yabai | skhd | [`skhdrc`](configs/skhdrc) |
| Hyper+T/N terminal, Meh+arrow snaps, Hyper+0 cheatsheet | Hammerspoon | [`hammerspoon-init.lua`](configs/hammerspoon-init.lua) · [`hammerspoon-cheatsheet.lua`](configs/hammerspoon-cheatsheet.lua) |
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

Full reference is `Hyper+0`. Layer split: **Hyper = navigate, Meh (Caps+Shift) = modify.**

```
Caps tap                      → Esc

# Hyper — navigate
Caps + hjkl                   → focus window
Caps + 1…5                    → focus space
Caps + return / f / e / r     → fullscreen / float / balance / rotate
Caps + t / n                  → new terminal tab / window
Caps + b / c                  → Brave (browser) / Claude
Caps + 0                      → toggle cheatsheet

# Meh — modify
Caps + Shift + hjkl           → swap window
Caps + Shift + 1…5            → send window to space N (and follow)
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

## One-time space setup

`Caps + 1…5` and `Caps + Shift + 1…5` need **5 BSP spaces per display.**
[`yabai-ensure-spaces.sh`](configs/yabai-ensure-spaces.sh) is called at
yabai startup and rebound to the `display_added` signal in
[`yabairc`](configs/yabairc), so attaching a monitor mid-session also
tops the new display up to 5 spaces without re-login. Installing the SA
is a one-time multi-reboot dance because macOS gates it behind SIP.
Procedure:

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

Cheatsheet: `Caps + 0` (live overlay; nothing on disk).

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
| `Caps + 0` cheatsheet doesn't appear | Hammerspoon not running / no Accessibility — `pgrep -x Hammerspoon` then re-run wizard |
| Neovim plugins missing | First-launch install in progress; open `nvim`, wait or `:Lazy sync` then `:MasonToolsInstall` |
| `pyright` doesn't attach to `*.py` | `:Mason` → `i` to install, or `:MasonToolsInstall` |
| SSH'ing into a fresh Ubuntu VPS from Ghostty: double characters, backspace inserts space | `TERM=xterm-ghostty` not in remote's terminfo. **From a local terminal:** `infocmp -x xterm-ghostty \| ssh user@host -- tic -x -`. Or run `~/dotfiles/bootstrap.sh` on the VPS once — phase 1 installs the entry to `~/.terminfo`. Extracting from Ghostty's bundle locally: `TERMINFO_DIRS=/Applications/Ghostty.app/Contents/Resources/terminfo infocmp -x xterm-ghostty` |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                  # OS dispatcher
├── lib/
│   ├── common.sh                 # logging + install_file helpers
│   └── macos-tcc.sh              # TCC probes for the gated wizard
├── macos/
│   ├── bootstrap.sh              # 5 phases (sudo / pkgs / configs / defaults / wizard)
│   ├── permissions-wizard.sh     # probe-gated; --force to walk every pane
│   └── yabai-sa-install.sh       # post-SIP-disable: install scripting addition + sudoers
├── ubuntu/bootstrap.sh           # 6 phases (terminfo / system / shell / runtimes / configs / shell)
├── docs/{architecture,wizard}.md
└── configs/
    ├── karabiner.{json,md}       # Caps remap + JSON explainer
    ├── yabairc                   # BSP tiling
    ├── yabai-ensure-spaces.sh    # idempotent N-spaces-per-display helper
    ├── skhdrc                    # Hyper bindings → yabai
    ├── hammerspoon-{init,cheatsheet}.lua
    ├── ghostty-config
    ├── xterm-ghostty.terminfo    # compiled into ~/.terminfo on Ubuntu boxes
    ├── tmux.conf · tmux-sessionizer
    ├── zshrc · gitconfig · ripgreprc
    └── nvim-{init.lua,lazy-lock.json,keymaps.lua}
```

## Design principles

- **Layered, not bundled.** Swap any one tool without touching the others.
- **Idempotent.** Re-running bootstrap is the supported way to apply edits.
- **Drift-resistant.** What's in `configs/` is what gets deployed; nvim
  `init.lua` and `lazy-lock.json` are tracked, so the editor is reproducible.
- **No paid Apple Developer ID.** Wizard chains through System Settings.
