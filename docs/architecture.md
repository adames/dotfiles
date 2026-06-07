# Architecture

Caps Lock is king of the dev surface. Chord lookups + collisions live in
[keymap.md](keymap.md).

## Stack

```
Caps Lock → Hyperkey ─┬─ tap → Esc
                      └─ hold → Hyper (⌃⌥⌘⇧) → AeroSpace
                                                  ├─ tiles windows
                                                  ├─ launchers (ws-launch-*)
                                                  ├─ ws-prompt overlays
                                                  └─ ws-picker overlay

Ghostty → tmux (C-Space) → zsh (vi-mode) → Neovim (Space leader)
```

One Hyper layer. Hyperkey can't reproduce Karabiner's
Caps+Shift→separate-Mod, so swap chords live on `Caps + y/u/i/o` rather
than Caps+Shift+hjkl. Modifier sets the scope: bare `h` moves the vim
cursor, `Caps+␣ h` moves the tmux pane, `Caps + h` moves the OS window.
Same letter, no overlap.

## Three contracts

1. **`current.env`** — `MACOS_WORKSPACE_NAME`, `_COLOR`, `_ICON`, `_ANSI`.
   Written by `on-space-changed.sh`, read by tmux + starship.
2. **`aerospace.toml`** — sentinel-fenced. User owns everything outside
   `# >>> sigil generated >>>`. `ws-topology emit-aerospace` writes
   the fenced block atomically and validates first; hand-edits inside
   are clobbered.
3. **`spaces.json` v3** — keyed on `<displayUUID>:<workspaceName>`,
   UUID from `CGDisplayCreateUUIDFromDisplayID` (stable across hot-plug
   where aerospace's ordinal isn't). Only schema supported.

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap | Hyperkey (user defaults) |
| Window tiling + chord dispatch | AeroSpace · `aerospace.toml` |
| Send (follow) overlay | ws-prompt · [sigil](https://github.com/adames/sigil)/Sources/ws-prompt/ |
| Window picker (Caps+c) | ws-picker · sigil/Sources/ws-picker/ |
| Cheatsheet HUD (Caps+/) | ws-cheatsheet · sigil/Sources/ws-cheatsheet/ |
| Pill strip | ws-statusbar · sigil/Sources/ws-statusbar/ |
| Display topology + notch | ws-topologyd · sigil/Sources/ws-topologyd/ |
| Float snap on Caps+hjkl | ws-snap · sigil/Sources/ws-snap/ |
| Direction-aware Caps+hjkl | ws-dir · `bin/ws-dir` |
| Launcher window placement | ws-launch-here · `bin/ws-launch-here` |
| Health check | ws-doctor · `bin/ws-doctor` |

## Why AeroSpace plus small Swift CLIs

AeroSpace has a built-in keybinding engine and runs entirely in
userspace. Each `[mode.main.binding]` entry maps a chord to a native
command or an `exec-and-forget`. Anything that needs macOS APIs
aerospace doesn't cover ships as a one-shot Swift binary out of sigil
— SwiftUI overlays, AX snap, NSStatusItem pill row, display-reconfig
LaunchAgent. No DriverKit kext, no scripting addition, no SIP
modification, no Lua runtime.

## Workspace existence is config-time

Aerospace declares workspaces statically in
`[workspace-to-monitor-force-assignment]`. There's no runtime
add/destroy. The edit overlay's `add`/`destroy` verbs surface an
"edit aerospace.toml + reload" help message rather than mutate
anything. To add a workspace: edit the toml, `aerospace reload-config`,
then `ws-topology emit-aerospace --write` to refresh the sigil-fenced
digit bindings.

`outer.top = 26` in `aerospace.toml` reserves the menu-bar strip for
ws-statusbar. `[[on-window-detected]]` rules pick float-vs-tile by
bundle ID at window-open time; `Caps+v` toggles manually.
