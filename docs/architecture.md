# Architecture

Terminal is the dev surface; window management is mouse + native macOS.

## Stack

```
Caps Lock → Hyperkey ─┬─ tap → Esc
                      └─ hold → Hyper (⌃⌥⌘⇧) — unbound, held in reserve

Ghostty → tmux (C-Space) → zsh (vi-mode) → Neovim (Space leader)
```

Modifier sets the scope: bare `h` moves the vim cursor, `C-Space h`
moves the tmux pane. Same letter, no overlap. Bindings are documented
next to the code that defines them: the `# @cs row` blocks in
`configs/zshrc`, `configs/tmux.conf` and `configs/nvim-init.lua`.

Two collisions are resolved on purpose:

| Collision | Resolution |
|---|---|
| Caps-tap `Esc` vs Ghostty option-as-alt | `escape-time 10` in tmux.conf gives ESC time |
| tmux prefix `C-Space` vs inner program wanting literal `C-Space` | `C-Space C-Space` (`send-prefix` binding) |

No `Option/M-*` tmux bindings — they collide with Ghostty's left-Alt bytes.

## Packages are declared, never assumed

**`macos/Brewfile` is the whole truth.** Anything in `brew leaves` or
`brew list --cask` that isn't declared there gets a line in the Brewfile
with its reason, or a sweep in `macos/retire.sh`. Nothing floats. The
one documented exception is Xcode: a `mas` line would front-load a
~30 GB download onto every fresh bootstrap, so it stays hand-installed.

`macos/retire.sh` is migration code, not steady state. It stamps a
`GENERATION` in `~/.local/state/dotfiles/retired` and a Mac already at
that generation exits in milliseconds. Adding a sweep means bumping the
generation, or the stamped Macs never see it. Its `~/Library` policy is
asymmetric on purpose: an app that holds no documents (a VPN client, a
Wine wrapper, Tor Browser) gets zapped; one that does (Firefox, VS Code,
a VM host) leaves its user data for you to delete.

## Retired, and why

Each of these was tried, and each is torn down by `macos/retire.sh` on
a Mac that still carries it. Listed so nobody re-discovers them.

- **Karabiner, yabai, skhd, sketchybar, borders** — the pre-Hyperkey
  keyboard and tiling stack. Karabiner's grabber can wedge input on the
  way out, so services are stopped before configs are removed.
- **AeroSpace, sigil, rune, the cheatsheet HUD** (2026-08) — a tiler and
  the Hyper chord layer that drove it. Mouse + one screen did the work.
  Hyperkey survives for tap-Caps = Esc; the Hyper layer is empty.
- **Raycast** — native Tahoe Spotlight is the launcher. This is why
  `macos/bootstrap.sh` warns below macOS 26: the Spotlight defaults and
  the Raycast teardown both assume Tahoe.
- **mise** (2026-09) — every runtime it served was byte-identical to a
  brew formula, through a shim layer, and its one real feature
  (per-project switching) was silently unused for five weeks. Runtimes
  are brew's on macOS. On Ubuntu the same retirement cost three install
  paths (NodeSource, the nvim tarball, `npm -g`), accepted with eyes
  open; `bin/update-system` exists to keep those current.
- **direnv, ruff, pipx, resvg, watchman, ruby, git-filter-repo** —
  authoring conveniences and one-offs. The work is reading code that
  harnesses wrote, not typing it; `pyright` stays for exactly that.
- **Firefox, VS Code, ExpressVPN, HandBrake, Keynote, Pages, MD Viewer,
  Elmedia, Reader, QuickMD** — a fourth browser, an idle editor, a
  second VPN with a privileged daemon, and duplicates of ffmpeg, IINA,
  glow and PDF Expert.
- **Tor Browser, Sikarugir + cabextract, UTM, exercism** — an
  experiment's leftovers. Tor's cask pointed at a dmg that 404'd and
  took every `brew upgrade` down with it; that's how the audit started.
- **The permission wizard** — 190 lines to open one System Settings pane.
  It's a phase in `macos/bootstrap.sh` now: probe TCC.db, open the
  Accessibility pane only if the grant can't be confirmed.
- **sparse-checkout on the Linux clone** — 93 lines to exclude one
  ghostty config and `macos/` from a clone where they cost nothing.
- **Tests that grep source text** — a test that a script *contains* a
  string passes while the thing it names is broken. The suite asserts
  behaviour: deploy into a throwaway HOME and look at what lands.

Kept on preference, stated so a future audit doesn't cut it: **yazi**.
The overlap with `oil.nvim` is real and it isn't load-bearing. I like
it. Everything else here earns its place on the work it does.

Declined: git aliases and difftastic. delta as pager is enough.

## Two Macs, one work machine

This repo installs on personal machines only. The work Mac has its own
restrictions and its own tools — iTerm2 instead of Ghostty, Notion
instead of Obsidian — and bootstrap is never run there.

What crosses the gap is muscle memory, not machinery: the tmux prefix,
the zsh vi-mode surface, the nvim leader map, the git aliases. Those are
`deploy_configs` in `lib/common.sh`, which touches nothing host-specific:

```sh
BOOTSTRAP_CONFIGS_ONLY=1 ~/dotfiles/bootstrap.sh
```

deploys exactly that core — no Homebrew, no macOS defaults, no teardown,
no Accessibility prompt, no `chsh`. It is also the shape of a
work-friendly fork: that one function plus `configs/`.

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

## PATH lives in .zshenv, and why .zprofile exists

`.zshrc` is read by interactive shells and nothing else. With PATH set
only there, `node` was v24 when typed by hand and v26 everywhere else —
scripts, cron, editor subprocesses, and the non-interactive shells that
Claude Code and Devin run builds in. Reviewing on one runtime while the
agent that wrote the code built on another is an invisible bug generator:
both shells report success.

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

## bash 3.2 is the floor

macOS ships bash 3.2 and always will — bash went GPLv3 at 4.0, which
Apple won't ship — so `#!/usr/bin/env bash` means 3.2 on any Mac without
brew's bash, which is every fresh Mac since the Brewfile declares none.
`tests/critical/script-syntax.test.sh` fails on bash-4-only constructs,
so the floor is enforced rather than remembered.

## The fleet

Two Macs, both MacBook Pros: **`m1`** (Apple M1) and **`m3`** (M3 Max),
plus a Linux box used as a playground and a work Mac this repo never
touches. m1 is not an Air, whatever older comments called it. Both Macs
run the same Brewfile; there is no per-machine package file.

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap (tap = Esc) | Hyperkey (user defaults, seeded by `macos/bootstrap.sh`) |
| Accessibility grant for Hyperkey | `phase_accessibility` in `macos/bootstrap.sh` |
| Window management | macOS native + mouse |
| Launcher | Spotlight (`⌘Space`) — see [macos-defaults.md](macos-defaults.md) |
| Terminal multiplexing | tmux (`C-Space`) |
| Health check | `bin/ws-doctor` (config source/deploy drift) |
| What gets deployed where | `config_manifest` in `lib/common.sh` — read by both bootstraps and by ws-doctor |
| One-time teardown | `macos/retire.sh`, stamped at `~/.local/state/dotfiles/retired` |
| Package updates | `bin/update-system` — brew + mas (macOS) · apt + `npm -g @latest` + nvim-pin check (Ubuntu) |
| Runtimes (macOS) | brew — `node@24`, `python@3.12`, `neovim`, `tree-sitter-cli` |
| Runtimes (Ubuntu) | NodeSource apt (node 24) · system python3 (3.12) · pinned nvim release tarball · `npm -g` (tree-sitter-cli, pyright, typescript) |
| Clipboard | terminal via OSC 52; WSL via clip.exe / Get-Clipboard |
| Shell floor | bash 3.2 (macOS ships no newer), enforced by tests |
| Run output | `lib/common.sh` — graded lines, `brew_quiet`/`apt_quiet`, `run_summary` |

No DriverKit kext, no scripting addition, no SIP modification, no
window-manager daemon.
