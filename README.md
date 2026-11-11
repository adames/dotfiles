# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

macOS + Ubuntu. One `bootstrap.sh` for both, idempotent — re-running it
is the only verb, so there is no half-applied state to reason about. Edit
`configs/`, never the deployed copy: bootstrap *copies* files out, so a
fix made to `~/.zshrc` lasts until the next run and then silently
vanishes. `ws-doctor` exists to catch exactly that.

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
Windows — a WSL distro's clipboard isn't Windows', so a yank would
otherwise go nowhere.

On a machine this repo doesn't own — the work Mac, a borrowed box —
deploy the portable core and nothing else. What crosses between machines
is muscle memory (the tmux prefix, vi-mode, the nvim leader), not
machinery, and a work Mac has its own rules about what gets installed:

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
  truth; `brew leaves` should hold nothing it doesn't list. A package that
  floats is a difference between the two Macs nobody notices until the
  fresh one lacks it. Anything that falls off is torn down by
  `macos/retire.sh`, a one-shot stamped per machine so a settled Mac
  spends milliseconds on it instead of seconds of brew forks every run.
- **One node, one python.** `node@24` is the major every project pins and
  the Ubuntu box runs; `python@3.12` plus `uv` for anything per-project.
  Two majors on one machine is how I once reviewed on node 24 while the
  agent built on 26 and both shells reported success. PATH lives in
  `.zshenv` for the same reason: it is the one file every zsh reads, so
  an agent's non-interactive shell gets the runtimes a typed command does.
- **Two language servers, for reading code:** pyright and `tsc --lsp`
  (TypeScript 7's native server). Reading, because agents write most of
  it now; `gd`, `gr` and `K` are how I check their work. pyright is
  `npm -g` into `~/.local` rather than brew because brew's formula drags
  in a second node (see above). nvim gates each server on its binary, so
  a machine without one just edits instead of erroring on every buffer.
- **Stock keyboard, stock launcher.** No remapper, no tiler. `⌘Space` and
  an app's name is how you reach it; Spotlight now answers questions too,
  which made the first keystroke of any hotkey layer worth less than the
  cask, bootstrap phase and Accessibility grant it cost.
- **No Xcode.** The Command Line Tools are the developer dir and bootstrap
  keeps `xcode-select` pointed there. Without that pin, one Xcode install
  takes over the developer dir, and deleting it later breaks every
  `git`/`make`/`clang` shim — which is how it kept getting reinstalled.

## Claude Code

`configs/CLAUDE.md` and `configs/claude-settings.json` deploy to
`~/.claude/`. Skills live in a separate repo, `~/code/skills`, because
they serve every harness (Claude Code, Codex, Devin, ChatGPT), not this
one; its `install.sh` symlinks them into `~/.claude/skills`. Project
memory is Claude's own working state and churns every session, so it is
neither in git (noise) nor live in iCloud (a sync mid-write can clobber
it). Instead `backup-claude-memory` *copies* `~/.claude/projects/*/memory/*.md`
into `~/documents/claude-memory/` (iCloud), and `--restore` seeds a fresh
Mac. Session transcripts stay per-machine — `claude --remote-control`
reaches a session from elsewhere.

## Verify

```sh
ws-doctor                 # does every deployed config still match configs/?
update-sys                # brew + mas (macOS) · apt (Ubuntu) · npm -g @latest (both)
tests/run-all.sh          # pure-bash critical path (~2.5s)
```

`ws-doctor` reads the same manifest the bootstraps deploy from, so its
coverage can't drift from reality. `update-sys` covers npm globals
because `npm install -g` is install-once: nothing else would ever move
pyright forward. The tests deploy into a throwaway `HOME` and look at
what lands, never grep source text — a test that a script *contains* a
string passes while the thing it names is broken.

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
