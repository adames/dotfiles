# dotfiles

Hyper-key keybinding scheme for macOS (Apple Silicon) and a minimal Ubuntu dev
env. Caps Lock becomes Hyper (⌃⌥⌘⇧) and drives a unified scheme across the
window manager (yabai+skhd), Hammerspoon hotkeys, tmux, and Neovim.

## Quick start

```sh
git clone https://github.com/<you>/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

The script auto-detects the OS:

- **macOS**: installs Homebrew + tools, deploys configs, starts services, opens
  System Settings to grant Accessibility, prints a verification summary.
- **Ubuntu**: installs apt packages, chezmoi, mise, Docker, Claude CLI, deploys
  tmux/Neovim configs.

It is **idempotent**: re-running won't re-back up or re-install anything that's
already in place.

## What you get

| Layer | Tool | Config |
|---|---|---|
| Caps Lock → Hyper / Esc | Karabiner-Elements | `configs/karabiner.json` |
| Window tiling (BSP) | yabai | `configs/yabairc` |
| Global hotkeys (Hyper+hjkl, Hyper+Shift+hjkl, Hyper+1..5, …) | skhd | `configs/skhdrc` |
| Hyper+T / Hyper+N (terminal), Hyper+arrows (snap), Hyper+/ Hyper+0 (cheatsheet) | Hammerspoon | `configs/hammerspoon-init.lua`, `configs/hammerspoon-cheatsheet.lua` |
| `C-a` prefix, vim pane nav | tmux | `configs/tmux.conf` |
| `<Space>` leader, `<leader>h/j/k/l/e/g/t` | Neovim (drop-in, no init.lua mutation) | `configs/nvim-keymaps.lua` |
| `Esc+` Option-as-Meta | iTerm2 defaults | (set by bootstrap) |
| Separate-spaces toggle | macOS | (set by bootstrap, requires logout) |

## Manual one-time steps the bootstrap can't do for you

1. **Grant Accessibility** to yabai, skhd, Hammerspoon, Karabiner-Elements
   (System Settings → Privacy & Security → Accessibility). The script opens
   the right pane and waits for you to confirm.
2. **Launch Karabiner-Elements once** so its login agents register.
3. **Log out and log back in** — required for the
   `com.apple.spaces spans-displays = false` change yabai depends on.
4. **Optional**: partial-disable SIP if you want yabai's full feature set.
   Without it, basic tiling still works; Hammerspoon's Hyper+arrow snaps
   serve as a SIP-safe fallback.

## Hyper key reference

After logging back in, **Hyper+/** or **Hyper+0** opens an HTML overlay
listing every binding. A static copy is regenerated each Hammerspoon load at
`~/Desktop/Hyper-Keys.html`.

## Verifying

```sh
# yabai is tiling
yabai -m query --windows | jq '.[].app'

# skhd is alive (you'll see PID > 0 and status 0)
launchctl list | grep com.koekeishiya.skhd

# tmux prefix
tmux show -gv prefix          # → 'C-a'

# Neovim leader bindings
nvim --headless +'echo execute("nmap <Space>h")' +qa

# Karabiner Hyper output (open Karabiner-EventViewer.app, press Caps Lock)
# Should show ^⌥⌘⇧
```

## Layout

```
dotfiles/
├── README.md
├── bootstrap.sh             # cross-platform, idempotent, OS-aware
└── configs/
    ├── karabiner.json
    ├── skhdrc
    ├── yabairc              # marked executable on install
    ├── hammerspoon-init.lua
    ├── hammerspoon-cheatsheet.lua
    ├── tmux.conf
    └── nvim-keymaps.lua     # installed to ~/.config/nvim/after/plugin/keymaps.lua
```

## Re-running

```sh
~/dotfiles/bootstrap.sh                 # re-apply (idempotent)
BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh   # headless / no-TTY
```
