# dotfiles

A unified **Hyper-key** keybinding scheme for macOS (Apple Silicon) plus a
minimal Ubuntu dev-env bootstrap. Caps Lock becomes Hyper (`⌃⌥⌘⇧`), Caps
Lock + Shift becomes Meh (`⌃⌥⌘`), tapping Caps Lock alone is Escape. Those
three remaps drive yabai window tiling, terminal hotkeys, a Hammerspoon
cheatsheet, tmux pane navigation, and Neovim leader bindings — consistently.

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
   (BSP tiler)  Cmd+T/N    ~/Desktop/Hyper-Keys.html
                            Hyper+0 overlay
```

Full architecture details: **[`docs/architecture.md`](docs/architecture.md)**.
Permission wizard reference: **[`docs/wizard.md`](docs/wizard.md)**.
Karabiner JSON explained: **[`configs/karabiner.md`](configs/karabiner.md)**.

## Quick start

```sh
# Clone (override DOTFILES_REPO to use a fork)
git clone "${DOTFILES_REPO:-git@github.com:adames/dotfiles.git}" ~/dotfiles

# Run — auto-detects macOS or Ubuntu and dispatches.
~/dotfiles/bootstrap.sh
```

You'll be prompted for sudo **once** at the start. The macOS bootstrap then:

1. Installs Homebrew (if missing) + CLI tools (git, tmux, neovim, fzf, …)
2. Installs yabai + skhd (formulae)
3. Installs Karabiner-Elements, Hammerspoon, Rectangle (casks)
4. Deploys all configs from `configs/` (`.bak`s any pre-existing files)
5. Sets macOS defaults (`spans-displays`, iTerm Option-as-Meta)
6. **Launches the permission wizard** — chains you through every TCC grant
   in sequence, opens the right System Settings pane for each, auto-advances
   when the grant is detected
7. Final dialog asks whether to log out now (required for `spans-displays`)

## What you get

| Layer | Tool | Source |
|---|---|---|
| Caps Lock → Hyper / Meh / Esc | Karabiner-Elements | [`configs/karabiner.json`](configs/karabiner.json) ([explained](configs/karabiner.md)) |
| Window tiling (BSP, gaps, rules) | yabai | [`configs/yabairc`](configs/yabairc) |
| `Hyper+H/J/K/L` focus, `Hyper+Shift+…` swap, `Hyper+1..5` spaces | skhd | [`configs/skhdrc`](configs/skhdrc) |
| `Hyper+T` / `Hyper+N` terminal tab/window | Hammerspoon | [`configs/hammerspoon-init.lua`](configs/hammerspoon-init.lua) |
| `Hyper+←/→/↑/↓` SIP-safe window snaps | Hammerspoon | same |
| `Hyper+0` cheatsheet overlay + `~/Desktop/Hyper-Keys.html` | Hammerspoon | [`configs/hammerspoon-cheatsheet.lua`](configs/hammerspoon-cheatsheet.lua) |
| `C-a` prefix, vim-style pane nav | tmux | [`configs/tmux.conf`](configs/tmux.conf) |
| `<Space>` leader + `h/j/k/l/e/g/t` | Neovim (drop-in) | [`configs/nvim-keymaps.lua`](configs/nvim-keymaps.lua) |
| `Esc+` Option-as-Meta | iTerm2 defaults | (set by bootstrap) |
| "Displays have separate Spaces" | macOS Mission Control | (set by bootstrap; **requires logout**) |

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

The wizard's trick: it **launches each app first**, so the entries appear in
the TCC list with toggles OFF. You just flip them — no dragging binaries.

See [`docs/wizard.md`](docs/wizard.md) for re-run instructions and per-step
troubleshooting.

## Verification

```sh
yabai -m query --windows | jq '.[].app'      # tiler is live, has windows
launchctl list | grep com.koekeishiya.skhd   # skhd PID > 0
tmux show -gv prefix                         # → 'C-a'
nvim --headless +'echo execute("nmap <Space>h")' +qa
# Karabiner: open Karabiner-EventViewer.app, press Caps Lock,
#   modifier column should show ⌃⌥⌘⇧
```

For the cheatsheet, press **`Hyper + 0`** (Caps + 0) or just open
`~/Desktop/Hyper-Keys.html` in any browser. The desktop file is regenerated
on every Hammerspoon load.

## Re-running

```sh
~/dotfiles/bootstrap.sh                          # idempotent; cmp-skips no-ops
~/dotfiles/macos/permissions-wizard.sh           # re-run wizard only
~/dotfiles/macos/permissions-wizard.sh --step accessibility-yabai
~/dotfiles/macos/permissions-wizard.sh --list    # show step names
~/dotfiles/macos/cheatsheet-deploy.sh            # regenerate desktop HTML
BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh   # for no-TTY / headless runs
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Bootstrap hangs on cask install | Running via a non-TTY shell (CI, ssh -T) | Run from a real terminal, or set `BOOTSTRAP_SKIP_CASKS=1` |
| `Warning: No services available to control with brew services` | Newer yabai/skhd formulae dropped brew-services support | Bootstrap already uses `--start-service` / `--restart-service` instead |
| "Karabiner installed but `.app` missing" | brew staged the cask but `installer -pkg` never ran | Bootstrap detects this and re-runs the staged installer when TTY present; or run `brew reinstall --cask karabiner-elements` |
| yabai logs `'display has separate spaces' is disabled` | The default was set but only re-read on fresh login | Log out and log back in |
| Hyper+0 cheatsheet doesn't appear | Hammerspoon not running or Accessibility not granted | `pgrep -ax Hammerspoon` → if empty, `open -a Hammerspoon` and re-run wizard |
| Wizard says "Karabiner accessibility: no" but Karabiner works | Terminal lacks Full Disk Access for the TCC.db read | The wizard's behavioral fallback (Karabiner-Core-Service-rev2 alive) handles this; if still mis-detected, grant Terminal FDA |
| yabai/skhd abort with "accessibility access" | Permissions were never granted, or recently revoked | Re-run wizard: `~/dotfiles/macos/permissions-wizard.sh` |
| spans-displays setting won't stick | You haven't logged out | The wizard's final dialog offers a one-click logout |

## Repository layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher (~25 lines)
├── README.md
├── lib/
│   ├── common.sh            # log/warn/err + backup/install_file helpers
│   └── macos-tcc.sh         # TCC.db reads + per-app permission probes
├── macos/
│   ├── bootstrap.sh         # brew + casks + configs + defaults + wizard
│   ├── permissions-wizard.sh # proactive permission chain (--step <name>)
│   └── cheatsheet-deploy.sh # regenerate ~/Desktop/Hyper-Keys.html
├── ubuntu/
│   └── bootstrap.sh         # apt + chezmoi + mise + Docker + Claude CLI
├── configs/                  # source of truth for all installed configs
│   ├── karabiner.json       # ← explained in karabiner.md
│   ├── karabiner.md
│   ├── yabairc
│   ├── skhdrc
│   ├── hammerspoon-init.lua
│   ├── hammerspoon-cheatsheet.lua
│   ├── tmux.conf
│   └── nvim-keymaps.lua
└── docs/
    ├── architecture.md      # layer diagram + Hyper/Meh explanation
    └── wizard.md            # permission-wizard reference
```

Source-of-truth principle: **edit configs in `configs/`**, then re-run the
bootstrap to deploy. The bootstrap is byte-comparison aware — it skips no-op
copies and never creates duplicate `.bak` files on idempotent re-runs.
