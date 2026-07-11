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

macOS: 4 phases. Ubuntu: 7 (0–6), skips AeroSpace + Hyperkey + Docker.

Window tiling is native AeroSpace. The cheatsheet HUD (`Caps + /`) is
the one piece still building from
[sigil](https://github.com/adames/sigil) (cloned to
`~/.config/workspace/`, swift-built, symlinked into `~/.local/bin/`) —
sigil's workspace-management layer was torn down, see
[docs/sigil-teardown.md](docs/sigil-teardown.md).

## Keymap

Live cheatsheet: `Caps + /`. Full inventory:
[docs/keymap.md](docs/keymap.md). Verb names the chord.

```
Caps tap                  → Esc
Caps + hjkl               → focus neighbour
Caps + yuio               → swap window
Caps + d                  → move window to next display
Caps + v / g / r          → float ↔ tile · grid (rows of 2) · rotate grid (cycles windows through grid slots)
Caps + x / z              → close window · fullscreen
Caps + -/= / e / ⌫ / ⏎    → resize / balance / close-all-but / reload
Caps + n/p / tab / 1..0   → workspace prev/next · last · go N
Caps + t / b / . / , / ; / '   → terminal / browser / Finder / settings / notes / inbox
Caps + /                  → cheatsheet HUD toggle
Caps + space              → enter tmux mode (direct commands, no keystroke injection)

tmux prefix h/j/k/l v/s z d r x f → pane nav / split / zoom / detach / reload / kill / sessionizer
nvim <leader> ff/fg/fb rn/=       → fzf / LSP rename / format
```

Caps+c (fuzzy window switcher) and Caps+f (send-and-follow) were
dropped in the sigil teardown, no native replacement yet — free
chords. Full detail: [docs/keymap.md](docs/keymap.md).

Free Hyper letters: `c f m q s w`. Re-derive:
`grep -nE '^cmd-alt-ctrl-shift-' ~/.config/aerospace/aerospace.toml`.

## Permissions

One pane, ~30 seconds: Accessibility for AeroSpace · Hyperkey ·
Raycast. Wizard probes first, only opens what's missing.
[docs/wizard.md](docs/wizard.md).

## Verify

```sh
ws-doctor                 # keymap / launcher health — run this first when something's off
update-sys                # brew + mise + softwareupdate sweep (also runs at the end of bootstrap)
aerospace list-windows --all --json | jq '.[]."app-name"'   # tiler live
pgrep -x Hyperkey         # remap live
tests/run-all.sh          # pure-bash critical path (~1.5s)
```

## Troubleshoot

| Symptom | Fix |
|---|---|
| Any chord no-op / feels stale | `aerospace reload-config` (or Caps+⏎), then `ws-doctor` |
| Cheatsheet doesn't show | `ws-cheatsheet` missing/not built — re-run bootstrap |
| New window doesn't settle into the grid | `ws-grid apply` to force it; `ws-grid auto` to check the detect hook is on |
| Wrong monitor after hot-plug | `[workspace-to-monitor-force-assignment]` in aerospace.toml pins everything to monitor 1 — edit + `aerospace reload-config` |
| Bootstrap hangs on cask | `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| Doubled chars over SSH | `infocmp -x xterm-ghostty | ssh user@host -- tic -x -` |

## Layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher
├── macos/  ubuntu/           # per-OS phases
├── lib/                      # bash helpers (logging, install_file, TCC probes)
├── bin/                      # update-system, ws-doctor, ws-grid, ws-tmux-prefix
├── configs/                  # aerospace.toml, ghostty, tmux, zsh, nvim, …
└── docs/                     # architecture.md · keymap.md · wizard.md
```

