# Architecture

Caps Lock is king of the dev surface. Chord lookups + collisions live in
[keymap.md](keymap.md).

## Stack

```
Caps Lock → Hyperkey ─┬─ tap → Esc
                      └─ hold → Hyper (⌃⌥⌘⇧) → AeroSpace
                                                  ├─ tiles windows (native)
                                                  ├─ launchers (open -a)
                                                  └─ cheatsheet HUD (ws-cheatsheet)

Ghostty → tmux (C-Space) → zsh (vi-mode) → Neovim (Space leader)
```

One Hyper layer. Hyperkey can't reproduce Karabiner's
Caps+Shift→separate-Mod, so swap chords live on `Caps + y/u/i/o` rather
than Caps+Shift+hjkl. Modifier sets the scope: bare `h` moves the vim
cursor, `Caps+␣ h` moves the tmux pane, `Caps + h` moves the OS window.
Same letter, no overlap.

## The sigil teardown

The sigil workspace-management layer was removed — see
[sigil-teardown.md](sigil-teardown.md). `aerospace.toml` is now fully
hand-written (no `# >>> sigil generated >>>` fences, no
`ws-topology emit-aerospace`), `spaces.json` is gone, and the workspace
binaries (ws-topology, ws-picker, ws-prompt, ws-focus, ws-grid, ws-dir,
ws-launch-here, ws-mouse-follow, ws-snap) were dropped in favor of native
AeroSpace commands. Only the cheatsheet HUD survives.

## Who owns what

| Concern | Owner |
|---|---|
| Caps remap | Hyperkey (user defaults) |
| Window tiling + chord dispatch | AeroSpace · `aerospace.toml` (hand-written) |
| Workspace nav / focus / move | AeroSpace native (`workspace`, `focus`, `move`, …) |
| Pointer-follows-focus | AeroSpace native (`on-focus-changed = move-mouse`) |
| Launchers | `open -a` in `aerospace.toml` |
| Cheatsheet HUD (Caps+/) | ws-cheatsheet · [sigil](https://github.com/adames/sigil)/Sources/ws-cheatsheet/ |
| Health check | ws-doctor · `bin/ws-doctor` |

## Why AeroSpace plus a single Swift CLI

AeroSpace has a built-in keybinding engine and runs entirely in
userspace. Each `[mode.main.binding]` entry maps a chord to a native
command or an `exec-and-forget`. Native commands now cover the workspace,
focus, move, resize, layout, and pointer-follow concerns that previously
shelled out to sigil binaries. The one remaining Swift binary is the
cheatsheet HUD (a SwiftUI overlay reading `cheatsheet.json`); it builds
from the sigil clone but has no dependency on the workspace code. No
DriverKit kext, no scripting addition, no SIP modification, no Lua runtime.

## Workspace existence is config-time

Aerospace declares workspaces statically in
`[workspace-to-monitor-force-assignment]` (hand-written, all pinned to
monitor 1). There's no runtime add/destroy — to add a workspace, edit the
toml, add a `cmd-alt-ctrl-shift-N = 'workspace N'` binding, and
`aerospace reload-config`.

`outer.top = 26` in `aerospace.toml` reserves the menu-bar strip.
`[[on-window-detected]]` rules pick float-vs-tile by bundle ID at
window-open time; `Caps+v` toggles manually.
