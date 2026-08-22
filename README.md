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
Hyperkey + Docker.

No window manager. AeroSpace (and the sigil HUD stack behind it) is
retired — mouse + native macOS won; a tiler never earned its keep here.
Bootstrap actively tears it down on machines that still have it. History:
[docs/sigil-teardown.md](docs/sigil-teardown.md).

## Keymap

Caps is the center: **tap = `Esc`**, **hold = Hyper (⌃⌥⌘⇧)** — the Hyper
layer is currently unbound, held in reserve. The real keymap is tmux
(`C-Space` prefix), zsh, and nvim: [docs/keymap.md](docs/keymap.md).

## Permissions

One pane, ~30 seconds: Accessibility for Hyperkey · Raycast.
Wizard probes the actual grants first, only opens what's missing.
[docs/wizard.md](docs/wizard.md).

## Verify

```sh
ws-doctor                 # config-drift / script health — run this first when something's off
update-sys                # brew + mise + softwareupdate sweep (also runs at the end of bootstrap)
pgrep -x Hyperkey         # remap live
tests/run-all.sh          # pure-bash critical path (~1.5s)
```

## Troubleshoot

| Symptom | Fix |
|---|---|
| Caps-tap isn't Esc | `macos/permissions-wizard.sh --force`, check Hyperkey is running |
| Config edit not live | you edited the deployed copy — fix `configs/`, re-run bootstrap; `ws-doctor` catches the drift |
| Bootstrap hangs on cask | `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| Doubled chars over SSH | `infocmp -x xterm-ghostty | ssh user@host -- tic -x -` |

## Layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher
├── macos/  ubuntu/           # per-OS phases
├── lib/                      # bash helpers (logging, install_file, TCC probes)
├── bin/                      # update-system, ws-doctor
├── configs/                  # ghostty, tmux, zsh, nvim, …
└── docs/                     # architecture · keymap · wizard · macos-defaults · sigil-teardown
```

