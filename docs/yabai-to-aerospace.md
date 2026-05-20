# Yabai → Aerospace: Difficulty Assessment

## Context

You asked how hard it would be to retire the yabai+skhd dependency in favor
of nikitabobko/AeroSpace. The ricer-lens motivation (from the prior turn):
yabai requires partial SIP disable for its scripting addition, which makes
every macOS point release a potential breakage and prevents fully
idempotent bootstrap on a stock machine. Aerospace is pure userspace and
ships its own keybinding daemon, so a successful migration retires *both*
yabai and skhd in one move.

This file sizes the work, names the single architectural decision that
dominates the cost, and sketches the migration shape — but doesn't commit
to implementing anything yet.

## Verdict

**Medium-to-large.** Not 80% done, not a weekend either. The
`window-manager.sh` abstraction looks reassuringly complete (10 stubbed
functions, ready to fill in) — but that abstraction is only honored by the
shell layer. The Swift layer is leakier than the WindowManager protocol
suggests, and underneath it there is a **fundamental semantic mismatch**
about what a "space" is.

The honest sizing depends almost entirely on how you resolve that
mismatch (the fork in §3 below). Pick (A) and it's ~1 weekend. Pick (B)
and it's a multi-week refactor of the workspace data model. There is no
third option that preserves current behavior unchanged.

## 1. Shell layer — easy

Cost: **~half a day.**

- [lib/window-manager.sh:39-208](lib/window-manager.sh:39) has 10 TODO
  stubs, one per function. Each is a 5-15 line `aerospace ...` invocation.
- Only one direct yabai leak outside the abstraction:
  [cli/test-cascade.sh:336-337](cli/test-cascade.sh:336) — route through
  `wm_query_spaces` / `wm_space_count`.
- `install.sh`, all three `launchd/*.plist` files, and CI workflows have
  **zero** yabai/skhd dependencies. No SIP instructions to remove, no
  `yabai --install-sa` to delete.
- No `skhdrc` shipped in the repo — users bring their own, so there's no
  ricer-side keybinding file to translate. Just docs updates.

## 2. Swift layer — the actual cost

Cost: **most of the effort lives here.** The `WindowManager` protocol at
[Sources/WorkspaceState/WindowManager.swift](Sources/WorkspaceState/WindowManager.swift)
exists, but the following call-sites bypass it and shell to yabai
directly. Each needs to be routed through the protocol (or the protocol
extended) *before* the AerospaceWindowManager can be a complete swap-in:

- [Sources/ws-topology/main.swift:308,314](Sources/ws-topology/main.swift:308)
  — emits **hardcoded skhd fragments** containing `yabai -m space --focus`.
  Has to be rewritten to emit Aerospace's TOML keybinding format (different
  file, different syntax, different daemon).
- [Sources/ws-statusbar/main.swift:348-361,561](Sources/ws-statusbar/main.swift:348)
  — direct `/bin/sh -c "yabai ..."` for focused-space query and
  fallback-focus on menu click.
- [Sources/ws-picker/WindowSource.swift:32,44](Sources/ws-picker/WindowSource.swift:32)
  — direct `Process()` for `query --windows` and `window --focus`.
- [Sources/ws-prompt/ProductionWorkspaceService.swift:54-73,130-202](Sources/ws-prompt/ProductionWorkspaceService.swift:54)
  — parses yabai's `query --spaces` `[{index, display}]` shape; composes
  a three-step `space --create` → `name` → `icon` atomic add; embeds yabai
  display indices into sketchybar trigger env vars.
- [Sources/ws-prompt/ManageController.swift:374-375](Sources/ws-prompt/ManageController.swift:374)
  — relies on yabai's `space_destroyed` *signal* firing a cascade (i.e.,
  you depend on yabai's signal subsystem, not just its CLI). Aerospace
  has no equivalent.
- [Sources/ws-autohide/main.swift:193,290](Sources/ws-autohide/main.swift:193)
  — direct `Process()` for `query --displays`.

`Migration.swift` is pure JSON schema migration and unaffected.

## 3. The architectural fork — pick before estimating

This is the real question, and it dominates the effort estimate.

**Yabai model:** spaces have a **global 1-based index** (slot 1..N across
all displays). `spaces.json` is keyed on this. Slot 5 might be on the
external display today and the laptop display tomorrow. Mission Control
sees them. Yabai can `space --create` / `space --destroy` at runtime.

**Aerospace model:** workspaces are **per-monitor, named** (typically `1,
2, 3, A, B, C…`), sticky to a display, with no Mission Control bridge.
You don't create or destroy them at runtime — you declare them in
`aerospace.toml` and assign them to monitors.

Three ways to bridge this:

- **(A) Single-display slot mapping.** Project all N "slots" onto one
  display's aerospace workspaces. Multi-monitor workspace topology
  collapses to single-monitor. Effort: ~1 weekend. Loses the marquee
  feature of the current system.
- **(B) Per-display workspace data model.** Refactor `spaces.json`,
  `WorkspaceData`, `ManageController`, `ws-topology`, and all consumers
  to think in `(displayID, workspaceName)` pairs instead of global slot
  indices. Effort: ~2-3 weeks. Preserves multi-monitor behavior. Requires
  bumping spaces.json to v3 and writing a v2→v3 migrator.
- **(C) Hybrid: keep slot indexing at the UI/config layer.** Slot N maps
  deterministically to `(display, aerospaceWorkspace)` via a lookup
  table. Adds indirection but preserves config shape and most call-sites.
  Lose runtime create/destroy (declare workspaces statically in
  `aerospace.toml`, hide UI affordances for add/remove). Effort: ~1 week.

My read: **(C) is the right ricer answer.** It lets you delete the
runtime space-lifecycle code (`ws-prompt`'s add/remove flow), which is
also the part that most relies on yabai's signal subsystem. Static
declaration in `aerospace.toml` is more "ricer" anyway — versionable,
reproducible, no runtime mutation.

But this is your call. (A) is fastest if you've decided multi-monitor
isn't worth it. (B) is right if you treat the multi-monitor model as
load-bearing.

## 4. Migration shape (if you pick (C))

Critical files to add/modify:

1. **New:** `Sources/WorkspaceState/AerospaceWindowManager.swift` implementing
   `WindowManager`. Plan for stub methods on space lifecycle (return
   `notImplemented`) — those calls go away in step 5.
2. **Extend** [Sources/WorkspaceState/WindowManager.swift](Sources/WorkspaceState/WindowManager.swift)
   with `queryDisplays() -> [DisplayInfo]` and `querySpaces() -> [SpaceInfo]`
   so the protocol covers what `ws-statusbar`, `ws-autohide`, `ws-picker`,
   and `ws-prompt` shell out for today.
3. **Reroute** all six leaky call-sites in §2 through the protocol. Use
   `WindowManagerFactory` (already exists at
   [Sources/WorkspaceState/WindowManagerFactory.swift](Sources/WorkspaceState/WindowManagerFactory.swift))
   to dispatch.
4. **Rewrite** [Sources/ws-topology/main.swift:308](Sources/ws-topology/main.swift:308)'s
   keybinding emitter to produce `aerospace.toml` `[mode.main.binding]`
   blocks, not skhd fragments. Split into two emitters behind the
   `WindowManagerKind` enum so yabai users keep the existing skhd path.
5. **Delete** the runtime space-create/destroy paths in
   [ws-prompt/ManageController.swift:374](Sources/ws-prompt/ManageController.swift:374)
   and [ws-prompt/ProductionWorkspaceService.swift:130-177](Sources/ws-prompt/ProductionWorkspaceService.swift:130)
   when running under aerospace. Wire UI to hide the add/remove
   affordances.
6. **Fill in** the 10 stubs in [lib/window-manager.sh:39-208](lib/window-manager.sh:39).
7. **Route** [cli/test-cascade.sh:336-337](cli/test-cascade.sh:336) through
   `wm_query_spaces`.
8. **Docs:** README.md requirements section, MANUAL_TEST_MATRIX.md
   (lines 47-48, 72-73), cheatsheet.json strings ("yabai · skhd" → conditional).

## 5. Verification

End-to-end checks before declaring done:

- Fresh-machine bootstrap on a SIP-enabled stock macOS (the whole point):
  `~/dotfiles/bootstrap.sh` completes without Recovery Mode interaction,
  and `ws-prompt` overlays render + focus-switching works.
- `WORKSPACE_WINDOW_MANAGER=yabai` still passes existing tests (don't
  regress the yabai path while adding aerospace).
- `WORKSPACE_WINDOW_MANAGER=aerospace` passes the same MANUAL_TEST_MATRIX
  rows that don't involve runtime space creation.
- `ws-topology dump` returns valid JSON under aerospace.
- `ws-topology` keybinding emitter produces a TOML block that
  `aerospace --config-path /tmp/test.toml reload-config` accepts without
  error.
- `current.env` and `layout.env` still emit the same field set
  ([LayoutEnvRenderer at ws-topologyd](Sources/ws-topologyd/))
  — these are consumed by tmux and starship out of repo, so the shape
  must not change.
