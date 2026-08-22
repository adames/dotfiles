# Keymap

Chord inventory. Narrative in [architecture.md](architecture.md).
Source of truth: `configs/`. Apply edits with `./macos/bootstrap.sh`.

AeroSpace (and its whole Hyper chord layer, the cheatsheet HUD, and the
tmux mode) is retired — window management is mouse + native macOS now.
What survives:

- **Caps** (Hyperkey): tap = `Esc` · hold = `Hyper` (`⌃⌥⌘⇧`) — the Hyper
  layer currently has **no bindings**; it's held in reserve for any
  future global hotkeys
- **Stack**: app → tmux → zsh / nvim

## tmux

Prefix = `C-Space`, everywhere (local and SSH).

| Chord | Action |
|---|---|
| `C-Space  h/j/k/l` | pane focus |
| `C-Space  v` / `s` (or `-` / `|`) | split right / below |
| `C-Space  z` | zoom pane |
| `C-Space  d` / `r` | detach / reload config |
| `C-Space  [` | copy / scroll mode |
| `C-Space  x` | kill pane (no confirm) |
| `C-Space  f` | tmux-sessionizer fzf popup |
| `C-Space  c` / `n` / `p` | new window / previous / next |
| `C-Space  1..9` | go to window N |
| `C-Space  C-Space` | send literal `C-Space` to inner program |

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
| Caps-tap `Esc` vs Ghostty option-as-alt | `escape-time 10` in tmux.conf gives ESC time |
| tmux prefix `C-Space` vs inner program wanting literal `C-Space` | `C-Space C-Space` (`send-prefix` binding) |

## Add a chord

1. Edit tmux.conf, zshrc, or nvim-keymaps.lua in `configs/`.
2. Update the adjacent doc comment (`# @cs row` blocks are plain docs
   now — keep them truthful or delete them with the binding).
3. Redeploy: `./macos/bootstrap.sh` (or copy the file by hand and let
   `ws-doctor`'s drift check confirm).
