# dotfiles

[![lint](https://github.com/adames/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/adames/dotfiles/actions/workflows/lint.yml)

macOS + Ubuntu. One `bootstrap.sh` for both platforms, idempotent. Edit
`configs/`, never the deployed copy. Small on purpose: the terminal is
where coding agents work, not where I type, so what's here is the shell
they run in, the editor I read with, and nothing that needs a permission
pane.

## Install

```sh
git clone git@github.com:adames/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

macOS: 3 phases. Ubuntu: 6. WSL runs the Ubuntu path — it's detected,
and the clipboard is routed into Windows for you.

On a machine this repo doesn't own — a work Mac, a borrowed box — deploy
the portable core and nothing else:

```sh
BOOTSTRAP_CONFIGS_ONLY=1 ~/dotfiles/bootstrap.sh
```

That's zsh, tmux, nvim, git, starship, ripgrep and the Claude config: no
Homebrew, no macOS defaults, no app teardown, no `chsh`. Same flag on
both platforms. See
[docs/architecture.md](docs/architecture.md) for what stays behind the
line and why.

Packages are declared, never assumed: `macos/Brewfile` is the whole truth.
Anything that falls off it is torn down by `macos/retire.sh`, a one-shot
stamped per machine. Editor stack is nvim with two language servers —
`pyright` for Python (`npm -g` into `~/.local`, both platforms) and
`tsc --lsp` (TypeScript 7's native server) for JS/TS — and `uv` for
Python tooling. One node: `node@24`, the major every project pins.

No window manager, no keyboard remapper: mouse + native macOS, Spotlight
(`⌘Space`) as the launcher. Xcode is not installed — the Command Line
Tools are the developer dir and bootstrap keeps it that way. What was
tried and retired, and why, is in
[docs/architecture.md](docs/architecture.md).

## Claude Code

`configs/CLAUDE.md` and `configs/claude-settings.json` deploy to `~/.claude/`.
Skills come from `~/code/skills`, whose `install.sh` symlinks them into
`~/.claude/skills` (clone it, run it; bootstrap doesn't).
Project memory is **not** synced through git or iCloud; `backup-claude-memory`
mirrors `~/.claude/projects/*/memory/*.md` into `~/documents/claude-memory/`
(iCloud), and `--restore` seeds a fresh Mac. Session transcripts stay
per-machine — use `claude --remote-control` to reach a session from elsewhere.
Where files live overall: `~/documents/REORG-PLAN-2026-09-05.md`.

## Keymap

Stock macOS. The keymap that matters is tmux (`C-Space` prefix), zsh
vi-mode, and nvim (Space leader), documented in the `# @cs row` blocks
next to each binding in `configs/`. Caps Lock is a Caps Lock; if you want
it as `Esc`, macOS does that natively (Keyboard → Keyboard Shortcuts →
Modifier Keys), per keyboard, by hand. Reaching an app is `⌘Space` and
its name. Collisions and how they're resolved:
[docs/architecture.md](docs/architecture.md).

## Permissions

None. Nothing bootstrap installs needs a Privacy & Security grant.

## Verify

```sh
ws-doctor                 # does every deployed config still match configs/?
update-sys                # package sweep: brew + mas (macOS) / apt (Ubuntu) + npm -g @latest (both)
tests/run-all.sh          # pure-bash critical path (~2.5s)
```

## Reading bootstrap output

Numbered phases, then a summary — the same shape on both platforms (macOS
has 3, Ubuntu 6; the numbers come from the phase list itself, so they can't
drift). Lines are graded, so a settled machine is quiet and anything worth
your attention is loud:

| Marker | Means |
|---|---|
| `[ok]` | already in the desired state, or just put there |
| `[note]` | true, useful, not a problem — e.g. apt held a package back, or a reboot is pending |
| `[warn]` | a step was skipped or degraded; the run continued |
| `[err]` | a step failed |

Package-manager chatter is collapsed to a tally — `18 already installed`
for brew, `0 upgraded, 154 newly installed, 0 to remove` for apt — while
real installs, upgrades and errors print in full. Third-party installers
that draw progress bars on stderr (fzf, starship, `npm -g`) are silent unless
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
| `python3` is 3.9, or `node` is the wrong major | a shell that missed `~/.zshenv`/`~/.zprofile` — re-run bootstrap, then `exec zsh` |
| `git`/`make`/`clang` say "requires Xcode" | `xcode-select -p` points at a deleted Xcode.app — `sudo xcode-select --switch /Library/Developer/CommandLineTools` (bootstrap does this) |
| Config edit not live | you edited the deployed copy — fix `configs/`, re-run bootstrap; `ws-doctor` catches the drift |
| Bootstrap hangs on cask | `BOOTSTRAP_SKIP_CASKS=1 ~/dotfiles/bootstrap.sh` |
| Doubled chars over SSH | `infocmp -x xterm-ghostty | ssh user@host -- tic -x -` |

## Layout

```
~/dotfiles/
├── bootstrap.sh              # OS dispatcher
├── macos/  ubuntu/           # per-OS phases (+ macos/retire.sh, the one-shot teardown)
├── lib/                      # bash helpers (logging, install_file, deploy manifest)
├── bin/                      # update-system, ws-doctor
├── configs/                  # ghostty, tmux, zsh, nvim, …
└── docs/                     # architecture · macos-defaults
```

