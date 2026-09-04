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

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap (tap = Esc) | Hyperkey (user defaults) |
| Window management | macOS native + mouse |
| Launcher | Spotlight (`⌘Space`) — see [macos-defaults.md](macos-defaults.md) |
| Terminal multiplexing | tmux (`C-Space`) |
| Health check | ws-doctor · `bin/ws-doctor` (config source/deploy drift) |
| Package updates | `bin/update-system` (brew + mise + softwareupdate) |

No DriverKit kext, no scripting addition, no SIP modification, no
window-manager daemon.
