# CLAUDE.md

Pointer notes for Claude Code sessions in this repo.

## Before editing keybindings

Read [`docs/keymap.md`](docs/keymap.md) first. It's the binding inventory +
collision matrix + free-key register for every layer (Karabiner → skhd → yabai
→ Ghostty → tmux → zsh → nvim), with file:line pointers to every binding's
source. Use it to grep for collisions before claiming a chord. The narrative
counterpart is [`docs/architecture.md`](docs/architecture.md).

## Source layout

- **`configs/`** is the source of truth. Bootstrap installs from here.
- **`configs/workspace/`** — workspace-management subsystem. Bash launchers
  (`launch-*.sh`) and CLI helpers (`cli/ws*`) live here.
- **`configs/workspace/topology/`** — Swift package (`swift build`). Houses
  every SwiftUI overlay binary: `ws-prompt`, `ws-picker`, `ws-cheatsheet`,
  `ws-snap`, plus the LaunchAgent daemons `ws-topologyd` and `ws-autohide`.
  Shared UI tokens live in `Sources/WsUI/` (Catppuccin palette, fuzzy matcher,
  pill geometry).
- **`macos/bootstrap.sh`** — the canonical apply path. Idempotent. Adding a
  new bash helper to `~/.local/bin/` means appending one `install_file` line
  here.

## Design principles

- **Layered, not bundled.** Any one tool should be swappable without touching
  the others. App-specific URLs and bundle IDs do not belong in `skhdrc` —
  abstract via a helper script (see `launch-terminal.sh` / `launch-notes.sh`).
- **Idempotent.** Re-running `./macos/bootstrap.sh` is the supported way to
  apply edits. Every install step should be a no-op on a clean machine.
- **Drift-resistant.** What's in `configs/` is what gets deployed. Avoid
  placeholders, hand-edited files outside `configs/`, or anything that
  requires "remember to also update X."
