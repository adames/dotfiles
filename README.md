# dotfiles

A complete keyboard-first dev environment, built around three rules:

1. **Caps Lock is the centre.** Tap = `Esc`, hold = `Hyper` (⌃⌥⌘⇧),
   hold + Shift = `Meh` (⌃⌥⌘). Karabiner does the remap once, then
   every layer below — yabai, tmux, Neovim — uses it consistently.
2. **One bootstrap, two platforms.** `~/dotfiles/bootstrap.sh` detects
   macOS or Ubuntu and dispatches. Re-running is a no-op.
3. **Edit `configs/`, never the deployed copy.** The bootstrap is the
   source-of-truth deployer; nothing under `configs/` is generated.

## Architecture, in one diagram

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
  │   shell: fzf · zoxide · starship · direnv · zsh-vi-mode  │
  │   nvim:  pyright + ruff + dap-python + neotest           │
  └──────────────────────────────────────────────────────────┘
```

Full architecture details in **[`docs/architecture.md`](docs/architecture.md)**.
Permission wizard reference in **[`docs/wizard.md`](docs/wizard.md)**.
Karabiner JSON explained in **[`configs/karabiner.md`](configs/karabiner.md)**.

## Quick start

```sh
git clone "${DOTFILES_REPO:-git@github.com:adames/dotfiles.git}" ~/dotfiles
~/dotfiles/bootstrap.sh
```

Auto-detects macOS or Ubuntu and dispatches. One sudo prompt up front.

The macOS bootstrap runs five phases:

1. **sudo** — caches credential for the whole run
2. **packages** — Homebrew formulae (CLI + yabai + skhd) and GUI casks
3. **configs** — copies from `configs/` to canonical locations
4. **defaults** — `spans-displays`, iTerm Option-as-Meta, etc.
5. **wizard** — chains you through the seven TCC permission grants

The Ubuntu bootstrap runs six phases (system → dotfiles → shell → runtimes
→ configs → default shell). No yabai/Karabiner — the macOS layer is
desktop-specific. The shell + nvim stack is identical to the Mac.

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps Lock → Hyper / Meh / Esc | Karabiner-Elements | [`configs/karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling (BSP, gaps, rules) | yabai | [`configs/yabairc`](configs/yabairc) |
| `Hyper+H/J/K/L` focus, `+Shift` swap, `Hyper+1..5` spaces | skhd | [`configs/skhdrc`](configs/skhdrc) |
| `Hyper+T` / `Hyper+N` terminal tab/window | Hammerspoon | [`configs/hammerspoon-init.lua`](configs/hammerspoon-init.lua) |
| `Hyper+←/→/↑/↓` SIP-safe window snaps | Hammerspoon | same |
| `Hyper+0` cheatsheet overlay | Hammerspoon | [`configs/hammerspoon-cheatsheet.lua`](configs/hammerspoon-cheatsheet.lua) |
| Ghostty terminal config (Option = Meta) | Ghostty | [`configs/ghostty-config`](configs/ghostty-config) |
| `C-Space` prefix, vim-style pane nav, `prefix+f` sessionizer | tmux | [`configs/tmux.conf`](configs/tmux.conf) + [`configs/tmux-sessionizer`](configs/tmux-sessionizer) |
| zsh + vi-mode + starship + direnv + autosuggestions + syntax-highlighting | zsh | [`configs/zshrc`](configs/zshrc) |
| `Ctrl-R` history, `Ctrl-T` files, `Alt-C` cd  (fd-backed) | fzf | wired in `zshrc` |
| `z foo` jump-to-frecent dir | zoxide | wired in `zshrc` |
| `rg` ripgrep with sensible globs | ripgrep + `~/.ripgreprc` | [`configs/ripgreprc`](configs/ripgreprc) |
| Side-by-side syntax-highlighted git diffs | git-delta | [`configs/gitconfig`](configs/gitconfig) |
| Neovim 0.12+ with Lazy + 13 hand-picked plugins | nvim | [`configs/nvim-init.lua`](configs/nvim-init.lua) |
| Python: Pyright + Ruff (LSP) · debugpy (DAP) · pytest (neotest) | Mason-managed | same |
| `<Space>` leader, `<leader>d*` debug, `<leader>t*` test, `<leader>f*` find | nvim keymaps | same |

## Daily-driver keymap surface

The complete reference is the live `Hyper+0` overlay. Quick mental map:

```
Caps tap                      → Esc
Caps + hjkl                   → focus / swap window
Caps + 1…5                    → switch space
Caps + return / f / e / r     → fullscreen / float / balance / rotate
Caps + t / n                  → new terminal tab / window
Caps + 0                      → toggle this cheatsheet

C-Space  hjkl / v / s / z     → tmux pane nav / split / zoom
C-Space  f                    → fzf project sessionizer

<leader>ff / fg / fb          → fzf files / live-grep / buffers
<leader>ca / rn / =           → LSP code action / rename / format
<leader>db / dc / do / di     → DAP breakpoint / continue / over / into
<leader>tn / tf / ts          → test nearest / file / summary
```

## The seven permission gates the wizard chains through

These are macOS TCC (Transparency, Consent, Control) grants — every one
requires a click in System Settings; no script can grant them silently
without a paid Apple Developer ID. The wizard makes the click sequence
trivial: it opens each pane, prompts via native dialog, and auto-advances
when it detects the grant.

1. Accessibility → yabai
2. Accessibility → skhd
3. Accessibility → Hammerspoon
4. Accessibility → Karabiner-Elements
5. Input Monitoring → Karabiner-Elements
6. Input Monitoring → Karabiner-DriverKit-VirtualHIDDevice
7. System Extension approval → Karabiner-DriverKit

The wizard's trick: it **launches each app first**, so the entries appear
in the TCC list with toggles OFF. You just flip them — no dragging
binaries through Finder's `+` dialog.

See [`docs/wizard.md`](docs/wizard.md) for re-run instructions and per-step
troubleshooting.

## Verification

```sh
# Window/keyboard layer
yabai -m query --windows | jq '.[].app'           # tiler is live
launchctl list | grep com.koekeishiya.skhd        # skhd PID > 0

# Terminal + shell
tmux show -gv prefix                              # → C-Space
zsh -ic 'bindkey | grep "fzf-history-widget"'     # Ctrl-R bound to fzf
zsh -ic 'type z' | head -1                        # z is a function (zoxide)

# Editor — open any .py file and check LSPs attached
nvim --headless -c 'edit /tmp/x.py' -c 'sleep 3' \
     -c 'lua print(#vim.lsp.get_clients({bufnr=0}))' -c qall   # → 2

# Karabiner: open Karabiner-EventViewer.app, press Caps Lock
#   modifier column should show ⌃⌥⌘⇧
```

For the cheatsheet, press **`Caps + 0`** — the Hammerspoon overlay
renders live (no file written).

## Re-running

```sh
~/dotfiles/bootstrap.sh                          # idempotent; cmp-skips no-ops
~/dotfiles/macos/permissions-wizard.sh           # wizard only
~/dotfiles/macos/permissions-wizard.sh --list    # show step names
~/dotfiles/macos/permissions-wizard.sh --step accessibility-yabai
BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh   # no-TTY / headless
NO_COLOR=1 ~/dotfiles/bootstrap.sh               # plain output
```

## Editing

The bootstrap is the deployer; `configs/` is the source of truth. The
workflow:

```sh
$EDITOR ~/dotfiles/configs/zshrc       # edit
~/dotfiles/bootstrap.sh                # re-deploy
```

`install_file` does byte-comparison and skips no-ops, so re-running is
cheap. First-time deploys back up any pre-existing file to `*.bak`.

For Hammerspoon Lua files, the watcher in `hammerspoon-init.lua` reloads
automatically on any `.lua` save under `~/.hammerspoon/`. For tmux:
`tmux source-file ~/.tmux.conf` (or `prefix + r`).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Bootstrap hangs on cask install | Running via a non-TTY shell (CI, ssh -T) | Run from a real terminal, or set `BOOTSTRAP_SKIP_CASKS=1` |
| `Warning: No services available to control with brew services` | Newer yabai/skhd dropped brew-services | The bootstrap uses `--start-service` already — safe to ignore |
| "Karabiner installed but `.app` missing" | brew staged the cask but `installer -pkg` never ran | Bootstrap detects this and re-runs the staged installer when TTY present; or `brew reinstall --cask karabiner-elements` |
| yabai logs `'display has separate spaces' is disabled` | The default was set but only re-read on fresh login | Log out and log back in |
| `Caps + 0` cheatsheet doesn't appear | Hammerspoon not running or Accessibility not granted | `pgrep -x Hammerspoon` → if empty, `open -a Hammerspoon` and re-run wizard |
| Wizard says "Karabiner accessibility: no" but Karabiner works | Terminal lacks Full Disk Access for the TCC.db read | Behavioral fallback (Karabiner-Core-Service-rev2 alive) handles it; if still mis-detected, grant Terminal FDA |
| yabai/skhd abort with "accessibility access" | Permissions never granted, or recently revoked | Re-run the wizard |
| `spans-displays` setting won't stick | You haven't logged out | The wizard's final dialog offers a one-click logout |
| Neovim plugins missing | First-launch install in progress | Open `nvim`, wait ~30s for Lazy + Mason, or run `:Lazy sync` then `:MasonToolsInstall` |
| `pyright` doesn't attach to `*.py` | Mason hasn't installed it yet | In nvim: `:Mason` → `i` to install, or `:MasonToolsInstall` |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh                      # OS dispatcher (~25 lines)
├── README.md
├── lib/
│   ├── common.sh                     # logging + install_file + helpers
│   └── macos-tcc.sh                  # TCC.db reads + permission probes
├── macos/
│   ├── bootstrap.sh                  # 5-phase: sudo/pkg/configs/defaults/wizard
│   └── permissions-wizard.sh         # 3-phase TCC chaining (--step <name>)
├── ubuntu/
│   └── bootstrap.sh                  # 6-phase Ubuntu/minerva bootstrap
├── docs/
│   ├── architecture.md               # layer diagram + Hyper/Meh details
│   └── wizard.md                     # permission wizard reference
└── configs/                          # source-of-truth dotfiles
    ├── karabiner.json                # ← explained in karabiner.md
    ├── karabiner.md
    ├── yabairc                       # window tiling (BSP, gaps, rules)
    ├── skhdrc                        # Hyper hotkeys → yabai
    ├── hammerspoon-init.lua          # Hyper+T/N terminal targeting
    ├── hammerspoon-cheatsheet.lua    # Hyper+0 overlay (8-card layout)
    ├── ghostty-config                # terminal: Option-as-Meta
    ├── tmux.conf                     # prefix=C-Space, vim-style nav
    ├── tmux-sessionizer              # fzf project picker → tmux session
    ├── zshrc                         # vi-mode, fzf, zoxide, starship, direnv
    ├── gitconfig                     # delta pager + structural; user → ~/.gitconfig.local
    ├── ripgreprc                     # smart-case, hidden, sensible globs
    ├── nvim-init.lua                 # Lazy + LSP + DAP + neotest + treesitter
    ├── nvim-lazy-lock.json           # plugin version pin (reproducibility)
    └── nvim-keymaps.lua              # leader=Space (drop-in slot)
```

## Design principles

- **Layered, not bundled.** Each layer is replaceable without touching
  the others. Swap Ghostty for iTerm, Catppuccin for Tokyo Night,
  zsh-syntax-highlighting for fast-syntax-highlighting — none of it
  requires touching the other layers.
- **Idempotent.** Every bootstrap step uses byte-comparison or "is X
  installed?" checks. Re-running is the supported way to apply edits.
- **Drift-resistant.** What's in `configs/` is what gets deployed. The
  full Neovim `init.lua` and `lazy-lock.json` are tracked, so the editor
  is reproducible across machines.
- **No paid Apple Developer ID required.** Skips signed `.mobileconfig`
  PPPC profiles entirely; the wizard chains the user through System
  Settings instead.
