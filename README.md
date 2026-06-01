# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

macOS + Ubuntu. Caps Lock is the center: tap = `Esc`, hold = `Hyper`
(⌃⌥⌘⇧). One `bootstrap.sh` for both platforms, idempotent. Edit
`configs/`, never the deployed copy.

## Install

```sh
git clone git@github.com:adames/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS: 5 phases. Ubuntu: 6, skips AeroSpace + Hyperkey + Docker.

Window manager + workspace overlays come from
[sigil](https://github.com/adames/sigil) (cloned to
`~/.config/workspace/`, swift-built, symlinked into `~/.local/bin/`).

## Keymap

Live cheatsheet: `Caps + /`. Full inventory:
[docs/keymap.md](docs/keymap.md). Verb names the chord.

```
Caps tap                  → Esc
Caps + hjkl  (tiled)      → focus neighbour
Caps + hjkl  (floating)   → snap: h left · l right · j center · k fill
Caps + yuio               → swap window
Caps + d                  → move window to next display
Caps + v / r / x / z      → float · rotate tree · close · fullscreen
Caps + s → -/= b ⌫ ⏎      → resize / balance / close-all-but / reload
Caps + n/p / tab / 1..0   → workspace prev/next · last · go N
Caps + c                  → change application (fuzzy by app + title)
Caps + e                  → edit workspace (rename / icon / color)
Caps + f                  → follow (send window + travel)
Caps + g                  → go to workspace (prompt)
Caps + t / b / . / , / ; / '   → terminal / browser / Finder / settings / notes / inbox
Caps + space              → tmux prefix (C-Space)

tmux prefix h/j/k/l v/s z d r x f → pane nav / split / zoom / detach / reload / kill / sessionizer
nvim <leader> ff/fg/fb ca/rn/=   → fzf / LSP code action / rename / format
```

Free Hyper letters: `a m q w`. Re-derive:
`grep -nE '^cmd-alt-ctrl-shift-' ~/.config/aerospace/aerospace.toml`.

## Permissions

One pane, ~30 seconds: Accessibility for AeroSpace · Hyperkey · ws-snap.
Wizard probes first, only opens what's missing.
[docs/wizard.md](docs/wizard.md).

## Verify

```sh
ws-doctor                 # keymap / launcher health — run this first when something's off
aerospace list-windows --all --json | jq '.[]."app-name"'   # tiler live
pgrep -x Hyperkey         # remap live
tests/run-all.sh          # pure-bash critical path (~1.5s)
```

## Troubleshoot

| Symptom | Fix |
|---|---|
| `Caps + c/e/f/g` no-op | `ws-prompt` / `ws-picker` missing — re-run bootstrap |
| Cheatsheet doesn't show | `ws-cheatsheet` missing — same fix |
| Workspace pills missing | `launchctl kickstart -k gui/$(id -u)/com.user.workspace.statusbar` |
| Workspace pill stale | `~/.config/workspace/on-space-changed.sh` not firing — check `exec-on-workspace-change` in aerospace.toml |
| Wrong monitor after hot-plug | `ws-topology` to rewrite spaces.json display UUIDs |
| Bootstrap hangs on cask | `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| Doubled chars over SSH | `infocmp -x xterm-ghostty | ssh user@host -- tic -x -` |

## Layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher
├── macos/  ubuntu/           # per-OS phases
├── lib/                      # bash helpers (logging, install_file, TCC probes)
├── bin/                      # ws-dir, ws-doctor, ws-launch-here, ws-tmux-prefix
├── configs/                  # aerospace.toml, ghostty, tmux, zsh, nvim, …
└── docs/                     # architecture.md · keymap.md · wizard.md
```

