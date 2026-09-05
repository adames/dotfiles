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

Packages are declared, never assumed: `macos/Brewfile` is the whole truth
for formulae, and bootstrap tears down what falls off it (2026-09: Firefox,
VS Code, ExpressVPN, and six stale formulae). `uv` is the Python entry
point; `pyright` + `ruff` are the servers behind nvim.

No window manager. AeroSpace (and the sigil HUD stack behind it) is
retired — mouse + native macOS won; a tiler never earned its keep here.
Bootstrap actively tears it down on machines that still have it. The
launcher is Spotlight (`⌘Space`); see
[docs/architecture.md](docs/architecture.md).

## Claude Code

`configs/CLAUDE.md` and `configs/claude-settings.json` deploy to `~/.claude/`.
Skills are a separate repo cloned *as* `~/.claude/skills` (bootstrap does it).
Project memory is **not** synced through git or iCloud; `backup-claude-memory`
mirrors `~/.claude/projects/*/memory/*.md` into `~/documents/claude-memory/`
(iCloud), and `--restore` seeds a fresh Mac. Session transcripts stay
per-machine — use `claude --remote-control` to reach a session from elsewhere.
Where files live overall: `~/documents/REORG-PLAN-2026-09-05.md`.

## Keymap

Caps is the center: **tap = `Esc`**, **hold = Hyper (⌃⌥⌘⇧)** — the Hyper
layer is currently unbound, held in reserve. The real keymap is tmux
(`C-Space` prefix), zsh, and nvim: [docs/keymap.md](docs/keymap.md).

## Permissions

One pane, ~30 seconds: Accessibility for Hyperkey.
Wizard probes the actual grants first, only opens what's missing.
[docs/wizard.md](docs/wizard.md).

## Verify

```sh
ws-doctor                 # config-drift / script health — run this first when something's off
update-sys                # brew + mise + softwareupdate sweep (also runs at the end of bootstrap)
pgrep -x Hyperkey         # remap live
tests/run-all.sh          # pure-bash critical path (~1.5s)
```

## Reading bootstrap output

Numbered phases, then a summary — the same shape on both platforms (macOS
has 4, Ubuntu 7; the numbers come from the phase list itself, so they can't
drift). Lines are graded, so a settled machine is quiet and anything worth
your attention is loud:

| Marker | Means |
|---|---|
| `[ok]` | already in the desired state, or just put there |
| `[note]` | true, useful, not a problem — e.g. a newer python exists but your mise config pins you below it |
| `[warn]` | a step was skipped or degraded; the run continued |
| `[err]` | a step failed |

Package-manager chatter is collapsed to a tally — `18 already installed`
for brew, `0 upgraded, 154 newly installed, 0 to remove` for apt — while
real installs, upgrades and errors print in full. Third-party installers
that draw progress bars on stderr (fzf, mise, starship) are silent unless
they fail, in which case you get all of their output. The closing block
counts each grade and replays every non-`[ok]` line, so you never scroll
back through a long run to find what happened.

Nothing here needs maintaining. `warn`/`err`/`note` in `lib/common.sh` feed
the summary themselves; the brew filter keys off brew's own verbs; and the
apt filter is an allowlist — it prints apt's one-line tally plus anything
apt flags, and drops everything else by default, so new apt chatter never
needs a new rule.

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
└── docs/                     # architecture · keymap · wizard · macos-defaults
```

