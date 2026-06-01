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
| `h j k l` | focus neighbour (tiled) · snap (floating: h/l halves, j center, k fill) — `ws-dir` |
| `y u i o` | swap window ← ↓ ↑ → |
| `d` | move window to next display (wraps) |
| `v` | float ↔ tile |
| `r` | flatten + rotate workspace tree |
| `c` | change application (`ws-picker` — fuzzy by app + title; tab cycles; ↵ jumps) |
| `x` | close focused window |
| `z` | fullscreen toggle |

### Service drawer (`Caps + s` enters)

| Chord | Action |
|---|---|
| `-` / `=` | resize -50 / +50 (stays in mode) |
| `b` | balance sizes |
| `⌫` | close all windows but current |
| `⏎` | reload aerospace config |
| `esc` | exit |

### Workspaces

| Chord | Action |
|---|---|
| `n` / `p` | prev / next workspace (wraps) |
| `tab` | last / recent workspace |
| `1..9, 0` | go to workspace N (sigil-fenced; regenerate with `ws-topology emit-aerospace --write`) |
| `c` | change application (covers windows in other spaces too) |
| `e` | edit workspace (`ws-prompt edit` — rename / icon / color / verify / doctor) |
| `f` | follow — send focused window + travel with it (`ws-prompt send`) |
| `g` | go to workspace (`ws-prompt focus`) |

Send-window digit chords (Caps+Shift+N) **not bound** — Hyperkey collapses
Caps+Shift+N onto Caps+N (same modifier set). Use `Caps + f` instead.

### Launchers

| Chord | Action |
|---|---|
| `t` | terminal — `ws-launch-here terminal` · `$WS_TERMINAL_APP` |
| `b` | browser — `ws-launch-here browser` · `$WS_BROWSER_APP` |
| `.` | Finder (AppleScript) |
| `,` | System Settings |
| `;` | notes — `ws-launch-here notes` · `$WS_NOTES_APP` |
| `'` | inbox — `ws-launch-here inbox` · `$WS_INBOX_APP` · `$WS_INBOX_VAULT` |
| `/` | cheatsheet HUD toggle (`ws-cheatsheet`) |
| `space` | tmux prefix — `ws-tmux-prefix` (gates on live tmux server) |

`ws-launch-here` snapshots the focused workspace before launching so the
new window lands where you triggered the chord, not wherever the app
already had a window.

## tmux

`tmux.conf`. Prefix is `C-Space`, user-facing chord `Caps+␣`.

| Chord | Action |
|---|---|
| `Caps+␣` | prefix |
| `Caps+␣  Caps+␣` | literal `C-Space` to inner program |
| `Caps+␣  h/j/k/l` | pane focus |
| `Caps+␣  v` / `s` (or `|` / `-`) | split right / below |
| `Caps+␣  z` | zoom pane |
| `Caps+␣  d` / `r` | detach / reload |
| `Caps+␣  x` / `&` | kill pane / window (no confirm) |
| `Caps+␣  f` | tmux-sessionizer fzf popup |

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
| `Caps + 1..0` vs `Caps + Shift + 1..0` | Hyperkey collapses Shift; use `Caps + f` to send |
| `Caps + T` (launcher) vs Ghostty `Cmd + T` | Different modifier sets |
| Caps-tap `Esc` vs Ghostty option-as-alt | `escape-time 10` in tmux.conf gives ESC time |
| tmux prefix `C-Space` vs inner program wanting literal `C-Space` | Double-tap Caps+Space (`send-prefix`) |
| Held-Caps + injected `Cmd+X` in a launcher | Use AX `click menu item` (bypasses aerospace); `ws-doctor` lints for this |

## Free Hyper letters

`a m q w`. Re-derive:
`grep -nE '^cmd-alt-ctrl-shift-' ~/.config/aerospace/aerospace.toml`.

## Add a chord

1. Edit `configs/aerospace.toml` `[mode.main.binding]` (or tmux.conf,
   zshrc, nvim-keymaps.lua).
2. `aerospace reload-config` (or `prefix r` for tmux).
3. `ws-doctor` — catches stale toml, keystroke contamination,
   source/deploy drift, menu-item rename, aerospace casing.

## Gotchas

- **Keystroke contamination.** `osascript … keystroke "X" using …` in a
  launcher fires as `Hyper+X` if Caps is still held. Drive via
  `click menu item` (AX, bypasses aerospace) or pick an unbound letter.
- **Aerospace monitor ordinals drift on hot-plug.** Sigil keys
  `spaces.json` on `CGDisplayCreateUUIDFromDisplayID` for this reason.
- **Stale aerospace.toml.** `aerospace reload-config` after edits;
  it's idempotent.
