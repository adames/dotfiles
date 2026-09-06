# Architecture

Terminal is the dev surface; window management is mouse + native macOS.
Chord lookups + collisions live in [keymap.md](keymap.md).

## Stack

```
Caps Lock → Hyperkey ─┬─ tap → Esc
                      └─ hold → Hyper (⌃⌥⌘⇧) — unbound, held in reserve

Ghostty → tmux (C-Space) → zsh (vi-mode) → Neovim (Space leader)
```

Modifier sets the scope: bare `h` moves the vim cursor, `C-Space h`
moves the tmux pane. Same letter, no overlap.

## The AeroSpace retirement (2026-08)

AeroSpace — and before it the whole sigil workspace layer — is gone. The honest audit: a
mouse and a single screen were doing the work; the tiler, its Hyper
chord layer, the `ws-grid` helper, the cheatsheet HUD, and the rune
generator that fed it were maintenance without payoff. Bootstrap now
tears the stack down on machines that still carry it (quits the app,
uninstalls the cask, sweeps `~/.config/aerospace` and
`~/.config/workspace`, prunes the `ws-*` binaries). Hyperkey survives
for tap-Caps = Esc; the Hyper layer is intentionally empty.

## The 2026-09 prune

An audit against actual use, not intent. Removed: **Firefox** (a fourth
browser — Chrome and Helium do the work), **VS Code** (idle since May;
the editor is nvim + Claude Code), **ExpressVPN** (a second VPN client
behind ProtonVPN, plus a privileged daemon that outlived it). App
bundles and the ExpressVPN daemon are torn down by `phase_apply`.

A second pass took the App Store tier: **Keynote** and **Pages** (never
opened here), **MD Viewer** (381 MB to render markdown), and **Elmedia
Player** (lost to IINA on merit). Purchases stay on the Apple ID, so
these are one click away if a machine ever needs them — which is the
argument against keeping them resident on every disk. **PDFgear** stays;
it's the current PDF app. **Zoom** stays, for interviews. **UTM** stays:
rarely used, but nothing else opens a VM.

Markdown viewing is `glow` now — one viewer, 10 MB, and the same command
over SSH on the Linux box, which a GUI app can't do. Obsidian is still
where markdown gets written. **IINA** is a declared cask rather than a
hand-installed app, so it lands on every Mac.

The `~/Library` trail gets asymmetric treatment on purpose. ExpressVPN's
prefs, caches, logs and root-owned socket dir are swept — a VPN client
holds no documents, and every one of those outlives both the app and the
daemon. Firefox's and VS Code's are not: bookmarks, saved logins and
editor settings are yours to delete, not bootstrap's.

Also removed: `resvg` and `pipx` (fed rune, retired with the cheatsheet
HUD), `watchman` (React Native era), `ruby` and `git-filter-repo`
(one-offs). Nothing depended on any of them.

Added, because the stack is JS/TS at home and Python at work:
`typescript` (nvim had treesitter for `.ts` but no server behind `gd`)
and `uv` (the Python entry point, and pipx's replacement).

Adopted, because both Macs already had them undeclared — a fresh machine
would have deployed nvim's config with no nvim: `neovim`, `jq`, `htop`,
`ffmpeg`.

The JS/TS server is `tsc --lsp` — TypeScript 7's own Go-native LSP —
configured by hand in `nvim-init.lua` rather than through lspconfig's
`ts_ls`. The obvious choice, `typescript-language-server`, is broken
against Homebrew today: it wraps `tsserver.js`, which TypeScript 7 no
longer ships, so it installs cleanly and then dies on every buffer with
"Could not find a valid TypeScript installation". The native server also
needs no `node_modules`, so a loose `.ts` file anywhere gets diagnostics.

The rule this leaves behind: **`macos/Brewfile` is the whole truth for
formulae.** Anything that shows up in `brew leaves` and isn't declared
there gets a line in the Brewfile with its reason, or a line in
`prune_undeclared_formulae`. Nothing floats.

## Two Macs, one work machine

This repo installs on personal machines only. The work Mac has its own
restrictions and its own tools — iTerm2 instead of Ghostty, Notion
instead of Obsidian — and bootstrap is never run there.

What crosses the gap is muscle memory, not machinery: the tmux prefix,
the zsh vi-mode surface, the nvim leader map, the git aliases. Those live
in `deploy_configs()` (macOS) / `phase_configs` (Ubuntu) and touch
nothing host-specific, so:

```sh
BOOTSTRAP_CONFIGS_ONLY=1 ~/dotfiles/bootstrap.sh
```

deploys exactly that core — no Homebrew, no macOS defaults, no teardown
of another machine's apps, no TCC wizard, no `chsh`. It is also the
shape of a work-friendly fork: that one function plus `configs/`.

Terminal parity is the one manual step. `configs/ghostty-config` sets
left Option as Alt so tmux and vim see the modifier; iTerm2 needs the
same thing set by hand (Profiles → Keys → Left Option key → Esc+).

## Dropping mise (2026-09)

mise managed node, python, neovim and tree-sitter on macOS. Every version
it handed out was byte-identical to a Homebrew formula — node 24.20.0,
python 3.12.14, tree-sitter 0.27.0, neovim 0.12.5 — reached through a
shim layer that also shadowed brew's own `nvim`. The one thing it offered
that brew can't, per-project version switching, was never in use: the
`.nvmrc` files in `~/code` were silently ignored (mise's
`idiomatic_version_file_enable_tools` defaults to empty) and nobody
noticed for five weeks, while an orphaned node 22 sat there taking
362 MB.

So runtimes are brew's now. Versioned formulae pin exactly as hard —
`node@24` stays on 24 through a `brew upgrade` — and `uv` handles
per-project Python better than a global pin ever did. One package
manager, no shims, and `which node` answers honestly.

Two edges worth remembering. Versioned formulae are keg-only, so
`configs/zshrc` puts their bin dirs on PATH by hand; `python@3.12` goes
in via `libexec/bin`, the only place brew provides a bare `python3` —
without it, `python3` falls through to macOS's system 3.9. And the CLI
nvim-treesitter shells out to is `tree-sitter-cli`; the `tree-sitter`
formula is the C library, and installing that one gets you no binary at
all.

mise stays on the Ubuntu playground, where apt's node is years behind and
mise is the cheapest fix. The activation block in `configs/zshrc` is
gated on Linux rather than deleted, so one shared zshrc still serves both.

## The AI-authored era (2026-09)

The work changed shape: code is written by harnesses (Devin, Claude,
ChatGPT) and the job here is judging it — jumping into unfamiliar code,
reading a diff, finding a root cause in whatever subsystem it turns out
to live in. Not authoring. The stack was audited against that.

What survived is what serves *reading*: nvim with LSP (`gd`, `gr`, `K` on
code nobody here wrote), treesitter, ripgrep and fd for hunting, delta
and lazygit for diffs, `gh` for PRs, `jq` for logs and APIs, and the
runtimes — because reviewing includes running the thing to see whether it
actually works.

What went: `direnv` (per-project env vars, an authoring convenience — no
`.envrc` existed on either machine) and `ruff` (a formatter and linter
for code you type yourself). `pyright` stays: reading unfamiliar Python
is now a daily act. The nvim annotation claiming `ruff` auto-ran on `:w`
had been false the whole time — there was never a `BufWritePre` autocmd
behind it.

**HandBrake** went too: never launched, and `ffmpeg` does the same job
from the terminal. `yazi` was cut in the same pass and put back, for
the honest reason rather than a constructed one: the overlap with
`oil.nvim` is real and it isn't load-bearing, but I like it. That's
allowed. Everything else here has to earn its place on the work it does;
this one earns it on preference, stated plainly so a future audit doesn't
"discover" the redundancy and cut it again.

`tree-sitter-cli` stays, and the reason is worth writing down because it
looks like pure build tooling: nvim-treesitter shells out to it every
time it installs a parser. Remove it and this machine looks fine — the
already-compiled parsers keep working — while a *fresh* Mac gets zero
parsers and no structural highlighting at all. Tested, not assumed:
without it on PATH, `tree-sitter build` fails.

Git tooling was deliberately left alone. Aliases and a structural diff
(difftastic) were proposed and declined; delta as pager is enough.

## Anywhere: macOS, a Linux server, WSL

"Works on whatever machine I'm sitting at" is a requirement, not a nice
to have. macOS and Ubuntu were already covered; WSL is Ubuntu for every
purpose here except one, so it gets a name (`is_wsl` in `lib/common.sh`)
rather than a platform directory.

The exception is the clipboard, and it's config rather than packages:

| Context | Clipboard route |
|---|---|
| macOS | native (nvim finds `pbcopy`) |
| WSL | `clip.exe` to copy, `powershell Get-Clipboard` to paste |
| SSH (Linux server) | OSC 52 — the terminal owns it |
| tmux, everywhere | OSC 52 (`set -s set-clipboard on`) |

WSL deliberately uses the two binaries Windows already ships rather than
`win32yank`, which is faster but means downloading an `.exe` and keeping
it current. `Get-Clipboard` returns CRLF, so the paste command strips
`\r` — without that every pasted line ends in a stray `^M`.

## PATH lives in .zshenv, and why .zprofile exists

`.zshrc` is read by interactive shells and nothing else. With PATH set
only there, `node` was v24 when typed by hand and v26 everywhere else —
scripts, cron, editor subprocesses, and the non-interactive shells that
Claude Code and Devin run builds in. Reviewing on one runtime while the
agent that wrote the code built on another is an invisible bug generator:
both shells report success.

So PATH moved to `configs/zshenv`, which every zsh reads. That alone was
not enough, and the failure is worth recording because it looks like it
should be:

| Shell | Before the fix | After |
|---|---|---|
| `zsh -c` (non-interactive) | node 26, python 3.9 | 24 / 3.12 |
| `zsh -i -c` (interactive) | node 24, python 3.12 | 24 / 3.12 |
| `zsh -l -c` (login) | **node 26, python 3.9.6** | 24 / 3.12 |

The login row is Apple's `path_helper`, run from `/etc/zprofile`. It
rebuilds PATH from `/etc/paths` with the system directories first and
everything else appended — silently undoing `.zshenv` and resolving
`python3` to macOS's system 3.9. Ghostty opens login shells, so this is
the common case.

`configs/zprofile` re-asserts PATH after `path_helper` has run;
`configs/zshrc` does the same for non-login interactive shells. Both are
one line sourcing `.zshenv`, and `typeset -U PATH` makes re-sourcing
idempotent — entries move to the front instead of accumulating. Verified
across all four invocation modes, with no duplicate PATH entries.

## bash 3.2 is the floor

macOS ships bash 3.2 and always will — bash went GPLv3 at 4.0, which
Apple won't ship — so `#!/usr/bin/env bash` means 3.2 on any Mac without
brew's bash, which is every fresh Mac since the Brewfile declares none.

`bin/ws-doctor` carried a `declare -A` for months and printed
`declare: -A: invalid option` on every run. Nobody saw it because brew's
bash was installed as an accidental dependency of `direnv` and shadowed
the system one. Removing direnv surfaced it immediately.
`tests/critical/script-syntax.test.sh` now fails on bash-4-only
constructs, so the floor is enforced rather than remembered.

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap (tap = Esc) | Hyperkey (user defaults) |
| Window management | macOS native + mouse |
| Launcher | Spotlight (`⌘Space`) — see [macos-defaults.md](macos-defaults.md) |
| Terminal multiplexing | tmux (`C-Space`) |
| Health check | ws-doctor · `bin/ws-doctor` (config source/deploy drift) |
| Package updates | `bin/update-system` (brew + mas + softwareupdate) |
| Runtimes (macOS) | brew — `node@24`, `python@3.12`, `neovim`, `tree-sitter-cli` |
| Runtimes (Ubuntu) | mise — apt's node is too far behind |
| Clipboard | terminal via OSC 52; WSL via clip.exe / Get-Clipboard |
| Shell floor | bash 3.2 (macOS ships no newer), enforced by tests |
| Run output | `lib/common.sh` — graded lines, `brew_quiet`/`apt_quiet`, `run_summary` |

No DriverKit kext, no scripting addition, no SIP modification, no
window-manager daemon.
