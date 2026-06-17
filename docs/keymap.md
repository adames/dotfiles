# Keymap

Chord inventory. Narrative in [architecture.md](architecture.md).
Source of truth: `configs/`. Apply edits with `./macos/bootstrap.sh`.

- **Stack**: Hyperkey → AeroSpace → app → tmux → zsh / nvim
- **Caps**: tap = `Esc` · hold = `Hyper` (`⌃⌥⌘⇧`)
- **One layer**: Hyperkey can't reproduce Caps+Shift→separate-Mod,
  so swap chords live on Caps+yuio not Caps+Shift+hjkl

## AeroSpace (Hyper = `cmd-alt-ctrl-shift`)

### Windows

| Chord | Action |
|---|---|
| `h j k l` | focus neighbour ← ↓ ↑ → (native `focus`) |
| `a` | alternate — bounce to the last focused window (crosses workspaces) |
| `y u i o` | swap window ← ↓ ↑ → |
| `d` | move window to next display (wraps) |
| `v` | float ↔ tile |
| `r` | toggle tile orientation (horizontal ↔ vertical, native `layout`) |
| `x` | close focused window |
| `z` | fullscreen toggle |

AeroSpace tiles new windows natively — the old `ws-grid` auto-grid and
its `Caps+g` / `Caps+r`-rotate were dropped with the sigil teardown (see
[sigil-teardown.md](sigil-teardown.md)). `Caps+c` (the `ws-picker` fuzzy
window switcher) is gone too; the chord is free for a native rebuild.

The pointer follows focus (`on-focus-changed = ['move-mouse
window-lazy-center']`) — lazy, so the mouse only jumps when it's outside
the window the focus landed in. Delete the `on-focus-changed` line in
aerospace.toml to opt back out.

### Layout ops (direct chords — the service drawer is retired)

| Chord | Action |
|---|---|
| `-` / `=` | resize -50 / +50 (hold Caps, tap to repeat) |
| `e` | equalize window sizes |
| `⌫` | close all windows but current |
| `⏎` | reload aerospace config |

Why no drawer: every op was one key deep behind a mode-enter — a drawer
earns its keystroke tax only when chords run out, and they haven't.

### Workspaces

| Chord | Action |
|---|---|
| `n` / `p` | prev / next workspace, wraps (native `workspace --wrap-around`) |
| `tab` | last / recent workspace (native `workspace-back-and-forth`) |
| `1..9, 0` | go to workspace N — `0` → 10 (native `workspace N`, hand-written) |

All native now. The digit block is hand-written in aerospace.toml (was
sigil-generated; the generator's lexical slot sort once mapped `Caps+2`
→ workspace 10). `Caps+f` (the `ws-prompt` send-and-follow overlay) was
dropped — no native send picker; the chord is free to rebuild as direct
`move-node-to-workspace N` bindings or a native picker later.

### Launchers

| Chord | Action |
|---|---|
| `t` | terminal — `open -a Ghostty` |
| `b` | browser — `open -a Helium` |
| `.` | Finder (AppleScript) |
| `,` | System Settings |
| `;` | notes — `open -a Obsidian` |
| `'` | inbox — `open -a Raycast` |
| `/` | cheatsheet HUD toggle (`ws-cheatsheet`) |
| `space` | enter AeroSpace tmux mode (`mode.tmux` — direct commands, no keystroke injection) |

Launchers are bare `open -a` now (was `ws-launch-here`, which snapshotted
the focused workspace so the window landed where you triggered the chord).
`open -a` activates the app's existing window if one exists — accepted
regression from the teardown; revisit if it annoys.

## tmux

`tmux.conf` + AeroSpace `mode.tmux`. Caps+Space enters the AeroSpace tmux
mode; the next key fires a direct tmux command and exits. Press `esc` or
`space` to abort without doing anything. `C-Space` is kept as the physical
tmux prefix for SSH sessions and environments without AeroSpace.

Why mode over shim: `tmux send-keys C-Space` writes bytes to the pane's
stdin, bypassing tmux's key-binding layer — the prefix is never entered.
Direct commands sidestep the problem entirely.

| Chord | Action |
|---|---|
| `Caps+␣` | enter AeroSpace `tmux` mode (`esc` / `space` to abort) |
| `Caps+␣  h/j/k/l` | pane focus |
| `Caps+␣  v` / `s` (or `-`) | split right / below |
| `Caps+␣  z` | zoom pane |
| `Caps+␣  d` / `r` | detach / reload config |
| `Caps+␣  [` | copy / scroll mode |
| `Caps+␣  x` | kill pane (no confirm) |
| `Caps+␣  f` | tmux-sessionizer fzf popup |
| `Caps+␣  c` / `n` / `p` | new window / next / prev |
| `Caps+␣  1..9` | go to window N |

No `Option/M-*` bindings — collides with Ghostty's left-Alt bytes.

## zsh + nvim

| Layer | Chord | Action |
|---|---|---|
| zsh | `Esc` | enter vi normal |
| zsh | `Ctrl-R` / `Ctrl-T` / `Alt-C` | fzf history / file / cd |
| zsh | `z <pat>` | zoxide jump |
| nvim | `gd` / `gr` / `K` | LSP definition / references / hover |
| nvim | `<leader>ff` / `fg` / `fb` | fzf files / live-grep / buffers |
| nvim | `<leader>rn` / `=` | LSP rename / format |
| nvim | `-` | oil (parent dir as buffer) |
| nvim | `<leader>m{a-z}` / `'{a-z}` | set / jump mark |

Leader = Space. Full mappings in
[nvim-keymaps.lua](../configs/nvim-keymaps.lua).

## Collisions

| Collision | Resolution |
|---|---|
| `Caps + 1..0` vs `Caps + Shift + 1..0` | Hyperkey collapses Shift; the two are the same chord |
| `Caps + T` (launcher) vs Ghostty `Cmd + T` | Different modifier sets |
| Caps-tap `Esc` vs Ghostty option-as-alt | `escape-time 10` in tmux.conf gives ESC time |
| tmux prefix `C-Space` vs inner program wanting literal `C-Space` | Physical `C-Space C-Space` in terminal (`send-prefix` binding) — AeroSpace mode path doesn't inject `C-Space` |
| Held-Caps + injected `Cmd+X` in a launcher | Use AX `click menu item` (bypasses aerospace); `ws-doctor` lints for this |

## Free Hyper letters

`c f g m q s w` (`c`/`f`/`g` freed by the sigil teardown). Re-derive:
`grep -nE '^cmd-alt-ctrl-shift-' ~/.config/aerospace/aerospace.toml`.

## Add a chord

1. Edit `configs/aerospace.toml` `[mode.main.binding]` (or tmux.conf,
   zshrc, nvim-keymaps.lua).
2. Update the adjacent `# @cs row` — the HUD (`Caps + /`) is generated
   from these blocks, so the cheatsheet stays truthful only if the row
   changes with the binding. Regenerate via `./macos/bootstrap.sh` or
   `rune -c configs/workspace/rune.toml build -o configs/workspace/cheatsheet.json`
   ([rune](https://github.com/adames/rune)).
3. `aerospace reload-config` (or Caps+Space → `r` for tmux).
4. `ws-doctor` — catches stale toml, keystroke contamination,
   source/deploy drift, menu-item rename, aerospace casing.

## Gotchas

- **Keystroke contamination.** `osascript … keystroke "X" using …` in a
  launcher fires as `Hyper+X` if Caps is still held. Drive via
  `click menu item` (AX, bypasses aerospace) or pick an unbound letter.
- **Aerospace monitor ordinals drift on hot-plug.** The
  `[workspace-to-monitor-force-assignment]` table pins every workspace
  to monitor 1; revisit if you run a fixed multi-monitor layout.
- **Stale aerospace.toml.** `aerospace reload-config` after edits;
  it's idempotent.
