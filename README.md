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
wizard). Ubuntu is six (system / dotfiles / shell / runtimes / configs /
default-shell). The Ubuntu side skips yabai/Karabiner and leaves
zshrc/gitconfig to chezmoi.

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps → Hyper / Meh / Esc | Karabiner-Elements | [`karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling | yabai | [`yabairc`](configs/yabairc) |
| Hyper hotkeys → yabai | skhd | [`skhdrc`](configs/skhdrc) |
| Hyper+T/N terminal, Meh+arrow snaps, Hyper+0 cheatsheet | Hammerspoon | [`hammerspoon-init.lua`](configs/hammerspoon-init.lua) · [`hammerspoon-cheatsheet.lua`](configs/hammerspoon-cheatsheet.lua) |
| Hyper app launchers (Brave/Chrome/Safari/Claude) | Karabiner shell_command | [`karabiner.json`](configs/karabiner.json) |
| Terminal (Option = Meta) | Ghostty | [`ghostty-config`](configs/ghostty-config) |
| `C-Space` prefix · `prefix+f` sessionizer · vim-style nav | tmux | [`tmux.conf`](configs/tmux.conf) · [`tmux-sessionizer`](configs/tmux-sessionizer) |
| zsh: vi-mode · starship · direnv · autosuggestions · syntax-highlighting | zsh | [`zshrc`](configs/zshrc) |
| `Ctrl-R/T`, `Alt-C` (fd-backed) | fzf | wired in `zshrc` |
| `z foo` jump to frecent dir | zoxide | wired in `zshrc` |
| `rg` with sensible globs | ripgrep | [`ripgreprc`](configs/ripgreprc) |
| Side-by-side syntax-highlighted git diffs | git-delta | [`gitconfig`](configs/gitconfig) |
| Neovim 0.12+ · Lazy + 15 plugins (incl. harpoon, oil) | nvim | [`nvim-init.lua`](configs/nvim-init.lua) |
| Python: Pyright + Ruff (LSP) · debugpy (DAP) · pytest (neotest) | Mason | same |

## Daily-driver keymap

Full reference is `Hyper+0`. Layer split: **Hyper = navigate, Meh (Caps+Shift) = modify.**

```
Caps tap                      → Esc

# Hyper — navigate
Caps + hjkl                   → focus window
Caps + 1…5                    → focus space
Caps + return / f / e / r     → fullscreen / float / balance / rotate
Caps + t / n                  → new terminal tab / window
Caps + b / g / s / c          → Brave / Chrome / Safari / Claude
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

## Permission grants

The macOS bootstrap hands off to `permissions-wizard.sh` which walks
three System Settings panes. No paid Apple Developer ID, no signed
profiles — just open pane, flip toggles, ↵.

1. **Accessibility** — yabai, skhd, Hammerspoon, Karabiner-Elements
2. **Input Monitoring** — Karabiner-Elements, Karabiner-DriverKit-VirtualHIDDevice
3. **System Extensions** — approve Karabiner-DriverKit-VirtualHIDDevice

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

`install_file` byte-compares; re-running is cheap. First-time deploys
back up any pre-existing file to `*.bak`.

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

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                  # OS dispatcher
├── lib/common.sh                 # logging + install_file helpers
├── macos/
│   ├── bootstrap.sh              # 5 phases
│   └── permissions-wizard.sh     # opens 3 TCC panes, ↵ to advance
├── ubuntu/bootstrap.sh           # 6 phases
├── docs/{architecture,wizard}.md
└── configs/
    ├── karabiner.{json,md}       # Caps remap + JSON explainer
    ├── yabairc · skhdrc          # tiling + Hyper bindings
    ├── hammerspoon-{init,cheatsheet}.lua
    ├── ghostty-config
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
