# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

macOS + Ubuntu. One `bootstrap.sh` for both, idempotent. Edit `configs/`,
never the deployed copy.

Small on purpose. The terminal is where coding agents work, not where I
type — a year of shell history is mostly `cd`, `ls` and `git pull` — so
what's here is the shell those agents run in, the editor I read code
with, and the handful of GUI apps every Mac should have. Nothing needs a
permission pane, a kernel extension or a daemon. What was tried and cut,
and why, is in [docs/architecture.md](docs/architecture.md).

## Install

```sh
git clone git@github.com:adames/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS runs 3 phases (sudo · packages · configs + defaults), Ubuntu 6. WSL
is detected and takes the Ubuntu path, with the clipboard routed into
Windows.

On a machine this repo doesn't own — the work Mac, a borrowed box —
deploy the portable core and nothing else:

```sh
BOOTSTRAP_CONFIGS_ONLY=1 ~/dotfiles/bootstrap.sh
```

That's zsh, tmux, nvim, git, starship, ripgrep, npm's prefix and the
Claude config. No Homebrew, no macOS defaults, no teardown, no `chsh`.

## What's in it

```
Ghostty → tmux (C-Space) → zsh (vi-mode, fzf, zoxide) → Neovim (Space leader)
```

- **Packages are declared, never assumed.** `macos/Brewfile` is the whole
  truth; `brew leaves` should hold nothing it doesn't list. Anything that
  falls off is torn down by `macos/retire.sh`, a one-shot stamped per
  machine.
- **One node, one python.** `node@24` is the major every project pins and
  the Ubuntu box runs; `python@3.12` plus `uv` for anything per-project.
  PATH lives in `.zshenv` so agents' non-interactive shells get the same
  runtimes a typed command does.
- **Two language servers, for reading code:** pyright (`npm -g` into
  `~/.local`, both platforms) and `tsc --lsp` (TypeScript 7's native
  server). nvim gates each on its binary, so a machine without one just
  edits.
- **Stock keyboard, stock launcher.** No remapper, no tiler. `⌘Space` and
  an app's name is how you reach it.
- **No Xcode.** The Command Line Tools are the developer dir and bootstrap
  keeps `xcode-select` pointed there, so a stray Xcode install is a
  download, not a dependency.

## Claude Code

`configs/CLAUDE.md` and `configs/claude-settings.json` deploy to
`~/.claude/`. Skills live in a separate repo, `~/code/skills`, whose
`install.sh` symlinks them into `~/.claude/skills`. Project memory is
not synced through git or iCloud; `backup-claude-memory` mirrors
`~/.claude/projects/*/memory/*.md` into `~/documents/claude-memory/`
(iCloud), and `--restore` seeds a fresh Mac. Session transcripts stay
per-machine — `claude --remote-control` reaches a session from elsewhere.

## Verify

```sh
ws-doctor                 # does every deployed config still match configs/?
update-sys                # brew + mas (macOS) · apt (Ubuntu) · npm -g @latest (both)
tests/run-all.sh          # pure-bash critical path (~2.5s)
```

## Reading bootstrap output

Numbered phases, then a summary — the same shape on both platforms, and
the phase count comes from the phase list itself so headers can't drift.
Lines are graded, so a settled machine is quiet and anything worth your
attention is loud:

| Marker | Means |
|---|---|
| `[ok]` | already in the desired state, or just put there |
| `[note]` | true, useful, not a problem — e.g. apt held a package back |
| `[warn]` | a step was skipped or degraded; the run continued |
| `[err]` | a step failed |

Package-manager chatter collapses to a tally — `18 already installed` for
brew, `0 upgraded, 154 newly installed, 0 to remove` for apt — while real
installs, upgrades and errors print in full. Third-party installers that
draw progress bars (fzf, starship, `npm -g`) are silent unless they fail,
in which case you get all of their output. The closing block counts each
grade and replays every non-`[ok]` line.

## Troubleshoot

| Symptom | Fix |
|---|---|
| `python3` is 3.9, or `node` is the wrong major | a shell that missed `~/.zshenv`/`~/.zprofile` — re-run bootstrap, then `exec zsh` |
| `git`/`make`/`clang` say "requires Xcode" | `xcode-select -p` points at a deleted Xcode.app — `sudo xcode-select --switch /Library/Developer/CommandLineTools` (bootstrap does this) |
| Config edit not live | you edited the deployed copy — fix `configs/`, re-run bootstrap; `ws-doctor` catches the drift |
| Bootstrap hangs on cask | `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| Doubled chars over SSH | `infocmp -x xterm-ghostty \| ssh user@host -- tic -x -` |

## Layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher
├── macos/  ubuntu/           # per-OS phases (+ macos/retire.sh, the one-shot teardown)
├── lib/                      # bash helpers: logging, install_file, the deploy manifest, npm tools
├── bin/                      # update-system, ws-doctor, backup-claude-memory
├── configs/                  # ghostty, tmux, zsh, nvim, git, npm, starship, …
└── docs/                     # architecture · macos-defaults
```
