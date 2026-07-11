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

macOS: 4 phases. Ubuntu: 6 (after a phase-0 sparse-checkout prune), skips
AeroSpace + Hyperkey + Docker.

Window management is native [AeroSpace](https://github.com/nikitabobko/AeroSpace),
driven by a hand-written `aerospace.toml`. The only sigil-built artifact is
the `Caps + /` cheatsheet HUD — [sigil](https://github.com/adames/sigil) is
cloned to `~/.config/workspace/`, swift-built, and its `ws-cheatsheet` binary
symlinked into `~/.local/bin/`. See [docs/sigil-teardown.md](docs/sigil-teardown.md).

## Keymap

Caps is the center: **tap = `Esc`**, **hold = Hyper (⌃⌥⌘⇧)**. Verb names
the chord. From Hyper: `hjkl` focus · `yuio` move · `g`/`r` grid/rotate ·
`v`/`x`/`z` float/close/fullscreen · digits + `n`/`p`/`tab` workspaces ·
home-row + punctuation launch apps · `space` enters a one-shot tmux mode.

The full inventory is [docs/keymap.md](docs/keymap.md); the live HUD
(`Caps + /`) is generated from the `# @cs` annotations beside each binding
in `configs/`, so it never drifts from the bindings. This README keeps no
per-chord copy — that copy is what used to rot.

Free Hyper letters: `c f m q s w`. Re-derive:
`grep -nE '^cmd-alt-ctrl-shift-' ~/.config/aerospace/aerospace.toml`.

## Permissions

One pane, ~30 seconds: Accessibility for AeroSpace · Hyperkey · Raycast.
Wizard probes the actual grants first, only opens what's missing.
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
| A chord does nothing | `aerospace reload-config` (`Caps + ⏎`), then `ws-doctor` |
| "Granted" but a chord stays dead | `macos/permissions-wizard.sh --force` |
| Cheatsheet doesn't show | `ws-cheatsheet` missing — re-run bootstrap (rebuilds the sigil HUD binary) |
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
└── docs/                     # architecture · keymap · wizard · macos-defaults · sigil-teardown
```

