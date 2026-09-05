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
would have deployed nvim's config with no nvim: `neovim`, `mise`, `jq`,
`htop`, `ffmpeg`.

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

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap (tap = Esc) | Hyperkey (user defaults) |
| Window management | macOS native + mouse |
| Launcher | Spotlight (`⌘Space`) — see [macos-defaults.md](macos-defaults.md) |
| Terminal multiplexing | tmux (`C-Space`) |
| Health check | ws-doctor · `bin/ws-doctor` (config source/deploy drift) |
| Package updates | `bin/update-system` (brew + mise + softwareupdate) |
| Run output | `lib/common.sh` — graded lines, `brew_quiet`/`apt_quiet`, `run_summary` |

No DriverKit kext, no scripting addition, no SIP modification, no
window-manager daemon.
