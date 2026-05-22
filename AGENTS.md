# AGENTS.md

Persona: ricer — infrastructure, configs, shell, deploy idempotency,
window-managers in `~/dotfiles`.

This repo is public (`adames/dotfiles` on GitHub). No `Co-Authored-By:`
trailers, no "🤖 Generated" footers, no agent self-references in
commits, PR titles, or PR bodies — strip the default attribution your
tooling emits before submission. Branches are `feat/fix/chore/refactor/
docs/ci/`, never `claude/` / `ai/` / `agent/`. Author and committer
stay as the human's identity. If naming an installed helper would
reveal the assistant, find another framing or omit it.

Per-agent workspace dirs (`.claude/`, `.windsurf/`, `.devin/`,
`.cursor/`) and live settings stay out of the tracked tree — they
live under `~/personas/.<agent>/`. This file (`AGENTS.md`) and
`.settings.json` are the only agent-facing artifacts that ship in
the repo.

## What this is

Keyboard-first macOS (+ Ubuntu) dev environment. Caps Lock is the
centre — every layer below uses the same modifier-sets-scope model.
Layered on purpose: any one tool should be swappable without touching
the others. Migration history (yabai → AeroSpace, Karabiner →
Hyperkey) in [docs/archive/yabai-to-aerospace.md](docs/archive/yabai-to-aerospace.md).

## Read first

| When | Doc |
|---|---|
| Editing any chord — collision matrix, free-key register, file:line for every binding | [docs/keymap.md](docs/keymap.md) |
| Why the stack is shaped this way — cascade, sentinel-subscriber, ownership boundaries | [docs/architecture.md](docs/architecture.md) |
| TCC / Accessibility troubleshooting | [docs/wizard.md](docs/wizard.md) |
| User-facing setup + keymap cheatsheet + troubleshooting | [README.md](README.md) |
| Diagnosing a misfiring chord / drifted launcher / broken menu ref | `ws-doctor` ([bin/ws-doctor](bin/ws-doctor)) — run it first |

## Invariants (load-bearing)

- **Edit `configs/`, never the deployed copy.** Bootstrap is the deployer.
- **`nvim-init.lua` is COPIED, not symlinked** — edits to `configs/nvim-init.lua` need either re-running bootstrap or `cp` to `~/.config/nvim/init.lua` to take effect.
- **Bootstrap is idempotent.** Every install step is a no-op on a clean machine. Re-running is the supported way to apply edits.
- **`aerospace.toml` is sentinel-fenced.** Sigil owns the digit binding block between `# >>> sigil generated >>>` / `# <<< sigil generated <<<` via `ws-topology emit-aerospace --write`. User owns gaps, modes, on-window-detected, every binding outside the fence. Hand-edits inside the fence are clobbered on next regeneration.
- **`escape-time 10` in [configs/tmux.conf](configs/tmux.conf)** protects Caps-tap-Esc from being mis-interpreted as an Option chord.
- **One Hyper layer, no Mod.** Hyperkey emits `cmd-alt-ctrl-shift` regardless of whether Shift is held — Caps+Shift+letter is indistinguishable from Caps+letter at AeroSpace. Swap chords live on Caps+yuio for this reason; inbox is Caps+x.
- **`ws` CLI mutations are atomic** (mktemp + jq + mv) and fire the cascade via `on-space-changed.sh`. Don't write `spaces.json` directly.
- **`aerospace.toml` owns workspace EXISTENCE; `spaces.json` owns IDENTITY** (name/color/icon/displayUUID/workspaceName). Add/destroy is config-time: edit aerospace.toml + `aerospace reload-config && ws-topology emit-aerospace --write`. `ws-prompt manage`'s add/destroy verbs surface the help text instead of mutating.
- **App-specific URLs / bundle IDs don't belong in `aerospace.toml`** — abstract via `~/.local/bin/ws-launch-*` helpers with `$WS_*_APP` env-var overrides.
- **`~/.local/bin/` is the `ws-*` binary prefix.** New CLI helpers go there via one `install_file` line in `macos/bootstrap.sh`.

## Things that will bite you

- **`aerospace reload-config` is synchronous** — bad TOML hangs subsequent writes. `ws-topology emit-aerospace --write --validate` parses the candidate against `aerospace reload-config --dry-run` before committing; don't bypass.
- **AeroSpace monitor ordinals shift on hot-plug.** Stable display identity is the CG UUID in `spaces.json` keys (`CGDisplayCreateUUIDFromDisplayID`). Never key on aerospace's `monitor-id` across hot-plug events.
- **Held-Caps + injected keystroke.** `osascript … keystroke "X" using …` in a launcher gets OR'd with the live Hyper modifier state. If Caps is still held when the script fires, `Cmd+N` becomes `Hyper+N` and aerospace intercepts it (e.g. `ws-focus next`, not `new_window`). Drive apps via `click menu item` (AX, bypasses aerospace) or the app's AppleScript dictionary — not synthetic keystrokes. Lint: `ws-doctor`.
- **Two parallel cache lines** in `~/.cache/workspace/`: `current.env` (keyed on focused workspace; consumed by tmux/starship/`paint-all.sh`) vs `layout.env` (keyed on display; consumed by sketchybar layout plugins). They never overlap — don't merge them.
- **SketchyBar coexistence is a load-bearing pair**: `topmost=off` + `y_offset=7` in sketchybar, and `outer.top = 26` in aerospace.toml `[gaps]`. Changing one without the other clips.
- **Pure-bash unit tests** under `tests/critical/*.test.sh`. Don't add bats or shellspec.
- **`workspace_changed` is a sentinel-subscriber event** — fired by aerospace's `exec-on-workspace-change` hook (declared inside the sigil-fenced block of aerospace.toml), delivered to one hidden item (`workspace.paint`). Per-pill scripts would re-introduce N-staggered redraws.
- **`mini.icons` is `lazy = false`** because it has to mock `nvim-web-devicons` BEFORE fzf-lua / which-key / oil load. Don't add `event = ...` to it.
- **Workspace names must start with a non-digit** so all-numeric queries unambiguously address a slot index — the path to slot 11+ via numeric input.
- **macOS green-button fullscreen** hides a window from `aerospace list-windows`, which means it's invisible to ws-picker. Use `Caps+G → digit` to send the window to its own workspace instead.
- **Source/deploy drift for launchers.** `configs/workspace/launch-*.sh` is *copied* to `~/.local/bin/ws-launch-*` by bootstrap. Patch only one side and either the fix gets clobbered or the running system stays broken. `ws-doctor source-deploy-drift` catches both.
- **Stale aerospace.toml after edit.** `aerospace reload-config` is in-process; `ps lstart` still shows the original AeroSpace.app launch time. If a chord does nothing, the toml may have been edited without a reload — reload is idempotent.

## Locked-in choices (don't re-propose)

| Choice | Why | Rejected |
|---|---|---|
| AeroSpace (i3-style tiling) | Pure userspace · built-in keybinding daemon · per-monitor workspace model | Rectangle (no tiling), Amethyst (no signal subsystem) |
| Hyperkey (Caps → Hyper) | Single-purpose, no kext, only needs Accessibility | Karabiner-Elements (DriverKit + extra TCC gates), hidutil (single modifier only; no tap-Esc) |
| Ghostty | Native, fast, well-maintained | iTerm, kitty |
| SketchyBar | Per-display items, native, scriptable | macOS menu bar extras (no per-display) |
| SwiftUI overlays | One-shot binaries, share `WsUI/` tokens, no daemon | Hammerspoon panels, AppleScript dialogs |
| Mason + mason-tool-installer | Reproducible LSP/DAP installs, pinned via `lazy-lock.json` | Manual `npm i -g`, system packages |
| pyright + ruff | Types from pyright; lint+format from ruff (one tool replaces black+isort+flake8) | Black + isort + flake8 + mypy |
| mise | Fast, single tool for python/node/neovim/etc | asdf (slower), pyenv (single-language) |
| pure-bash tests + fixture stubs | Zero dep, ~1.5s suite, CI-portable | bats, shellspec |
| Catppuccin Mocha | Used everywhere (nvim, sketchybar, starship, ws-* overlays) | Tokyo Night, Nord — would require six retunes |
| oil.nvim | File explorer as a buffer; editable | nvim-tree, neo-tree |
| harpoon2 | Pinned-file jumps with `<leader>1..4` | bookmarks plugins |
| mini.icons | Mocks `nvim-web-devicons`; one dep covers fzf/which-key/oil | nvim-web-devicons (separate plugin) |

## Where to add things

| Adding | Steps |
|---|---|
| New chord | Follow [docs/keymap.md](docs/keymap.md) → Editing protocol. Pick layer, grep collisions, edit `configs/aerospace.toml` (outside the fence), `aerospace reload-config`, fire chord. |
| New workspace | Edit `~/.config/aerospace/aerospace.toml` `[workspace-to-monitor-force-assignment]`; `aerospace reload-config && ws-topology emit-aerospace --write`; then `ws name <slot> <name>` for identity. |
| New nvim plugin | Add block in `configs/nvim-init.lua`; sync to `~/.config/nvim/init.lua`; `nvim --headless "+Lazy! sync" +qa`; commit updated `configs/nvim-lazy-lock.json`. |
| New Swift overlay | New target in sigil's `Package.swift` + `Sources/<name>/` dir; share UI via `Sources/WsUI/`; install via sigil's `install.sh` (bootstrap calls it). |
| New `ws` subcommand | Edit sigil's `cli/ws`; add test under sigil's `Tests/` or `tests/`; ensure atomic mutation (mktemp + jq + mv); fire the cascade via `on-space-changed.sh`. |
| New `~/.local/bin/` helper | Drop in `configs/workspace/` (or appropriate subdir); add one `install_file` line in `macos/bootstrap.sh`. |
| New permission gate | Add probe in `lib/macos-tcc.sh`; add pane to `macos/permissions-wizard.sh`; document in `docs/wizard.md`. |
| New launcher (terminal/browser/notes) | Extend `configs/workspace/launch-*.sh` with auto-detect logic, or add `$WS_*_APP` env-var override. Never put bundle IDs in `aerospace.toml`. Drive the app via `click menu item` or its AppleScript dictionary — never `keystroke "X" using …`. Run `ws-doctor` after. |

## Verification (before claiming X works)

```sh
aerospace list-windows --all --json | jq '.[]."app-name"'   # tiler is live
pgrep -x Hyperkey                                           # Hyperkey running
tmux show -gv prefix                                        # → C-a
zsh -ic 'type z' | head -1                                  # zoxide function
nvim --headless +'lua print(#vim.lsp.get_clients({bufnr=0}))' +qa  # LSP attaches
tests/run-all.sh                                            # ~1.5s; critical suite
ws verify                                                   # end-to-end cascade harness
ws-doctor                                                   # keymap/launcher health (collisions, drift, menu refs)
defaults read com.knollsoft.Hyperkey 2>/dev/null            # Hyperkey config persisted (bundle id may differ)
```

Cheatsheet (live overlay, nothing on disk): `Caps + ;`.
