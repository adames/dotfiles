# Architecture

Terminal is the dev surface. Window management is mouse + native macOS.
Everything else is a decision about what to carry, and the bar since the
2026-11 audit is: does a script, the editor or an agent call it? If only
a human at a keyboard would, and the history shows no human did, it goes.

## Stack

```
Ghostty → tmux (C-Space) → zsh (vi-mode) → Neovim (Space leader)
```

Stock keyboard: no remapper, no chord layer, no Accessibility grant.
Modifier sets the scope — bare `h` moves the vim cursor, `C-Space h`
moves the tmux pane. Same letter, no overlap. Bindings are documented
next to the code that defines them: the `# @cs row` blocks in
`configs/zshrc`, `configs/tmux.conf` and `configs/nvim-init.lua`.

Two deliberate choices in tmux.conf:

| Choice | Why |
|---|---|
| `C-Space C-Space` sends a literal `C-Space` | the prefix would otherwise swallow it from an inner program |
| no `Option/M-*` bindings | they collide with Ghostty's left-Alt bytes |

`escape-time 10` lets ESC sequences arrive whole without making nvim's
Esc feel laggy.

## Reaching an app

`⌘Space`, type its name. Spotlight on Tahoe answers questions too, so
the launcher is also the first place to ask something — which is what
made a dedicated hotkey layer worth less than it was, and why Hyperkey
went. If a direct key for one top app is ever wanted, the vanilla path is
the Shortcuts app: an "Open App" shortcut with a keyboard shortcut
attached. OS-native, no Accessibility grant, syncs with the Apple ID.
Not built; written down so it isn't rediscovered as a third-party app.
Spotlight's own tuning is in [macos-defaults.md](macos-defaults.md).

## Packages are declared, never assumed

**`macos/Brewfile` is the whole truth.** Anything in `brew leaves` or
`brew list --cask` that isn't declared there gets a line in the Brewfile
with its reason, or a sweep in `macos/retire.sh`. Nothing floats. Two
things are deliberately not brew's: pyright and vercel are `npm -g` into
`~/.local` (`install_npm_tools` in `lib/common.sh`), because brew's
pyright formula depends on unversioned `node` and would put a second
node major on every Mac. Ubuntu installs its editor tooling the same way.

`macos/retire.sh` is migration code, not steady state. It stamps a
`GENERATION` in `~/.local/state/dotfiles/retired` and a Mac already at
that generation exits in milliseconds. Adding a sweep means bumping the
generation, or the stamped Macs never see it. Its `~/Library` policy is
asymmetric on purpose: an app that holds no documents (a VPN client, a
keyboard remapper, a Wine wrapper) gets zapped; one that does (a browser,
an editor, a VM host) leaves its user data for you to delete.

## Runtimes: one of each

`node@24` is the only node. Every personal project pins 24 and the
Ubuntu box runs NodeSource 24, so a second major on the Mac is a bug
generator, not flexibility. `python@3.12` is the only python, with `uv`
for per-project versions. Both are keg-only, so `configs/zshenv` puts
their bin dirs on PATH by hand — see below for why it has to be `.zshenv`.

No version manager. mise was tried: every runtime it served was
byte-identical to a brew formula, through a shim layer, and its one real
feature (per-project switching) went unused for five weeks before anyone
noticed the `.nvmrc` files were being ignored. Versioned formulae pin
just as hard.

No Xcode. The Command Line Tools are installed and are the developer dir,
and `ensure_xcode_clt` in `macos/bootstrap.sh` keeps `xcode-select`
pointed at them. The reason this needs enforcing: install Xcode once (a
simulator, a Swift one-off, a tool that asks for it) and it takes over
`xcode-select`, so every `git`/`make`/`clang` shim resolves into
Xcode.app. Delete the bundle after that and they all break with "requires
Xcode" — and the reflex fix is to download it again. Pinning the developer
dir ends the loop; retire.sh deletes the bundle whenever it reappears.

## PATH lives in .zshenv, and why .zprofile exists

`.zshrc` is read by interactive shells and nothing else. With PATH set
only there, `node` was v24 when typed by hand and v26 everywhere else —
scripts, cron, editor subprocesses, and the non-interactive shells that
Claude Code and Devin run builds in. Reviewing on one runtime while the
agent that wrote the code built on another is an invisible bug generator:
both shells report success. (The v26 was brew's unversioned `node`, pulled
in by the pyright formula; it is gone now, but the rule below is what
stops the next accidental runtime from doing the same thing.)

So PATH lives in `configs/zshenv`, which every zsh reads. That alone is
not enough, and the failure looks like it should be:

| Shell | .zshenv only | + .zprofile |
|---|---|---|
| `zsh -c` (non-interactive) | 24 / 3.12 | 24 / 3.12 |
| `zsh -i -c` (interactive) | 24 / 3.12 | 24 / 3.12 |
| `zsh -l -c` (login) | **node 26, python 3.9.6** | 24 / 3.12 |

The login row is Apple's `path_helper`, run from `/etc/zprofile`. It
rebuilds PATH from `/etc/paths` with the system directories first and
everything else appended — silently undoing `.zshenv` and resolving
`python3` to macOS's system 3.9. Ghostty opens login shells, so this is
the common case. `configs/zprofile` re-asserts PATH after `path_helper`
has run: one line sourcing `.zshenv`, made idempotent by `typeset -U
PATH`.

## Two Macs, one work machine

This repo installs on personal machines only. The work Mac has its own
restrictions and its own tools — iTerm2 instead of Ghostty, Notion
instead of Obsidian — and bootstrap is never run there.

What crosses the gap is muscle memory, not machinery: the tmux prefix,
the zsh vi-mode surface, the nvim leader map, the git config. Those are
`deploy_configs` in `lib/common.sh`, which touches nothing host-specific:

```sh
BOOTSTRAP_CONFIGS_ONLY=1 ~/dotfiles/bootstrap.sh
```

deploys exactly that core — no Homebrew, no macOS defaults, no teardown,
no `chsh`. It is also the shape of a work-friendly fork: that one
function plus `configs/`.

Terminal parity is the one manual step. `configs/ghostty-config` sets
left Option as Alt so tmux and vim see the modifier; iTerm2 needs the
same thing set by hand (Profiles → Keys → Left Option key → Esc+).

## Anywhere: macOS, a Linux server, WSL

"Works on whatever machine I'm sitting at" is a requirement, not a nice
to have. WSL is Ubuntu for every purpose here except one, so it gets a
name (`is_wsl` in `lib/common.sh`) rather than a platform directory.

The exception is the clipboard, and it's config rather than packages:

| Context | Clipboard route |
|---|---|
| macOS | native (nvim finds `pbcopy`) |
| WSL | `clip.exe` to copy, `powershell Get-Clipboard` to paste |
| SSH (Linux server) | OSC 52 — the terminal owns it |
| tmux, everywhere | OSC 52 (`set -s set-clipboard on`) |

WSL uses the two binaries Windows already ships rather than `win32yank`,
which is faster but means downloading an `.exe` and keeping it current.
`Get-Clipboard` returns CRLF, so the paste command strips `\r`.

## bash 3.2 is the floor

macOS ships bash 3.2 and always will — bash went GPLv3 at 4.0, which
Apple won't ship — so `#!/usr/bin/env bash` means 3.2 on any Mac without
brew's bash, which is every fresh Mac since the Brewfile declares none.
`tests/critical/script-syntax.test.sh` fails on bash-4-only constructs,
so the floor is enforced rather than remembered.

## The fleet

Two Macs, both MacBook Pros: **`m1`** (Apple M1) and **`m3`** (M3 Max),
plus a Linux box (`minerva`) used as a playground and a work Mac this
repo never touches. m1 is not an Air, whatever older comments called it.
Both Macs run the same Brewfile; there is no per-machine package file.

## Who owns what

| Concern | Owner |
|---|---|
| Keyboard | stock macOS; Caps → Esc is a Modifier Keys toggle if ever wanted |
| Window management | macOS native + mouse |
| Launcher / reaching apps | Spotlight (`⌘Space`) — tuned in [macos-defaults.md](macos-defaults.md) |
| Developer dir | Command Line Tools, pinned by `ensure_xcode_clt`; no Xcode |
| Terminal multiplexing | tmux (`C-Space`) |
| Runtimes (macOS) | brew — `node@24`, `python@3.12`, `neovim`, `tree-sitter-cli`, `typescript` · `npm -g` into `~/.local` — pyright, vercel |
| Runtimes (Ubuntu) | NodeSource apt (node 24) · system python3 (3.12) · pinned nvim release tarball · `npm -g` into `~/.local` — tree-sitter-cli, pyright, typescript |
| Package updates | `bin/update-system` — brew + mas (macOS) · apt + nvim-pin check (Ubuntu) · `npm -g @latest` for whatever is in `~/.local/lib/node_modules` (both) |
| What gets deployed where | `config_manifest` in `lib/common.sh` — read by both bootstraps and by ws-doctor |
| Health check | `bin/ws-doctor` (config source/deploy drift) |
| One-time teardown | `macos/retire.sh`, stamped at `~/.local/state/dotfiles/retired` |
| Containers | OrbStack — idle until a `docker` command; `docker system prune` is its diet |
| Clipboard | terminal via OSC 52; WSL via clip.exe / Get-Clipboard |
| Shell floor | bash 3.2 (macOS ships no newer), enforced by tests |
| Run output | `lib/common.sh` — graded lines, `brew_quiet`/`apt_quiet`, `run_summary` |

No DriverKit kext, no scripting addition, no SIP modification, no
window-manager daemon, no input monitor, no Accessibility grant.

## Kept on purpose

Stated so a future audit doesn't cut them:

- **nvim, its two language servers, tmux, fzf, starship** — the
  flexibility reserve. Cheap to carry, and they are what makes any
  machine I sit at immediately usable, typed or not.
- **OrbStack** — the container option. The app is 700 MB and idle until
  a `docker` command wakes it; what grows is its data disk, and the
  answer to that is `docker system prune`, not uninstalling.
- **yazi** — the overlap with `oil.nvim` is real and it isn't
  load-bearing. I like it. (It lost video thumbnails when ffmpeg went;
  nothing else.)
- **Two browsers** — Chrome and Helium, for different purposes.

Declined: git aliases and difftastic (delta as pager is enough), a
version manager (see Runtimes), and anything that needs a permission
pane.

## Retired, and why

Each of these was tried, and `macos/retire.sh` tears it down on a Mac
that still carries it. Listed so nobody re-discovers them.

**Keyboard and windows.** Karabiner, yabai, skhd, sketchybar, borders,
then AeroSpace with the sigil/rune chord layer and a cheatsheet HUD
(2026-08), then Hyperkey alone for tap-Caps = Esc (2026-11). Mouse and
one screen did the work; the Hyper side was unbound for three months
before it went; one key did not justify a cask, a bootstrap phase, a TCC
probe and an Accessibility grant. Raycast went the same way — Tahoe's
Spotlight is the launcher, which is why `macos/bootstrap.sh` warns below
macOS 26.

**Runtimes.** mise (2026-09; see Runtimes). The brew pyright formula and
the node 26 it dragged in (2026-11; see Packages). Xcode (2026-11; see
Runtimes — the dance is explained there).

**Formulae nobody called.** direnv, ruff, pipx, resvg, watchman, ruby,
git-filter-repo (2026-09) — authoring conveniences for a workflow that
had become reading, not typing. glow, htop, lazygit, ffmpeg (2026-11) —
a year of history showed zero, two, three and zero uses. tmux-sessionizer
(2026-11) — zero uses; its project root was a directory that no longer
existed.

**Apps.** Firefox, VS Code, ExpressVPN (and its privileged daemon),
HandBrake, Keynote, Pages, MD Viewer, Elmedia, Reader, QuickMD — a fourth
browser, an idle editor, a second VPN, and duplicates of things already
chosen. Tor Browser, Sikarugir + cabextract, UTM, exercism — one
experiment's leftovers; Tor's cask pointed at a dmg that 404'd and took
every `brew upgrade` down with it, which is how the first audit started.

**Coding practice** (2026-11). leetcode-os and its nvim glue — a plugin
spec the managed init.lua never imported, with four plugins sitting
unused in lazy's install dir — plus the `tutor` skill. Practice ended;
the repos stay on GitHub.

**Repo machinery.** The permission wizard (190 lines to open one System
Settings pane; became a phase, then went entirely with Hyperkey).
sparse-checkout on the Linux clone (93 lines to exclude files that cost
nothing). Tests that grep source text — a test that a script *contains* a
string passes while the thing it names is broken; the suite asserts
behaviour by deploying into a throwaway HOME. `ensure_claude_skills`,
which cloned a repo that was no longer how skills arrive and warned on
every run.
