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
bundles and the ExpressVPN daemon are torn down by `phase_apply`;
browser profiles and editor settings are deliberately left alone.

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
