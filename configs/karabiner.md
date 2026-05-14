# Karabiner configuration

Companion to `karabiner.json` — JSON doesn't allow comments, so the
explanation lives here.

The config has **two complex modifications**, ordered intentionally:

## Rule 1 — Caps Lock + Shift → Mod

```
from: caps_lock with mandatory shift
to:   left_control + left_option + left_command   (NO shift)
```

This rule fires when the user holds **Caps Lock together with Shift**. The
`mandatory: ["shift"]` clause tells Karabiner to *consume* the shift modifier
(remove it from the output), so the emitted combo is exactly
`Ctrl+Opt+Cmd` — three modifiers. We call this the **Mod** key.

**Why?** The whole Hyper scheme wants two distinct hotkey layers:

- `Hyper + H` → focus window left
- `Hyper + Shift + H` → swap window left

If Hyper itself already includes Shift (the literal "4-mod Hyper"), then
adding physical Shift is a no-op — `Hyper+H` and `Hyper+Shift+H` are
indistinguishable to skhd. By making `Caps + Shift` emit a *different*
3-mod combo, skhd can bind:

```
cmd + alt + ctrl + shift - h : yabai -m window --focus west
cmd + alt + ctrl         - h : yabai -m window --swap  west
```

Two different bindings, both intuitive ("Caps+H" vs "Caps+Shift+H").

## Rule 2 — Caps Lock alone → Hyper, or Esc on tap

```
from: caps_lock (with any optional modifiers)
to:   left_control + left_shift + left_option + left_command   (Hyper)
to_if_alone: escape
```

When **Caps Lock is held**, it emits the full 4-mod Hyper. When **Caps Lock
is tapped alone** (pressed and released without any other key), it emits
**Escape** instead. This is the standard Karabiner idiom for "make Caps Lock
useful for everything" — vim users get a cheap Esc, the rest of us get Hyper.

`optional: ["any"]` means: don't be picky about other modifiers being held
at press-time; just remap Caps Lock itself. (Rule 1 fires first when Shift
is present, so this rule covers all other cases.)

## Order matters

Karabiner evaluates rules top-to-bottom. Rule 1 (with `mandatory shift`)
must come first; otherwise Rule 2's `optional any` would consume the
Shift+Caps case and the 3-mod Mod would never fire.

## What this implies for tooling downstream

- **skhd** sees keystrokes with modifier sets `cmd+alt+ctrl+shift` (Hyper)
  or `cmd+alt+ctrl` (Mod) depending on whether Shift was held.
- **macOS shortcut conflicts** — Cmd+Q, Cmd+W, etc. still work normally
  because the user is pressing them without Caps Lock.

## App launchers live in skhd, not here

The Karabiner config has only the two rules above. Everything else
that fires on a Hyper chord — including `Caps + B` (browser),
`Caps + C` (Claude), `Caps + M` (Spotify), `Caps + S` (System
Settings), `Caps + T` (terminal), `Caps + F` (Finder), and `Caps + ;`
(cheatsheet HUD) — is bound in [`skhdrc`](skhdrc). Karabiner's job
ends at re-emitting the Hyper/Mod modifier set; skhd does the
dispatch.

`Caps + g` and `Caps + v` are currently unbound (in either layer)
and available for future use; `Caps + v` was historically reserved
for a clipboard manager (Maccy, Raycast clipboard) if one ever lands.

## Layer semantic: Hyper = navigate, Mod = modify

The two layers carry a consistent split — useful when adding new bindings:

- **Hyper** (Caps held)        — navigate / non-destructive
  (focus window/space, launch app, new terminal, open cheatsheet)
- **Mod**   (Caps+Shift held)  — modify / destructive
  (swap window, manage workspaces, manual snap)

When in doubt about where a new binding belongs, ask: does it *move* state
(Mod) or *show* state (Hyper)?

## Workspace control prompts (lives in ws-prompt, dispatched by skhd)

Karabiner doesn't grab any of these keys. skhd binds the two chords
directly to `ws-prompt <mode>`, a SwiftUI overlay that captures
keystrokes itself and exits on commit / cancel / blur. There are no
sticky skhd modes anywhere in the system anymore.

- `Caps + space`          (Hyper+Space)    → focus prompt (digit commits · letters fuzzy-match name + ↵)
- `Caps + return`         (Hyper+Return)   → send prompt  (digit commits + follow · letters fuzzy-match name + ↵)
- `Esc` / click-elsewhere (inside overlay) → cancel
- `Caps + Esc`            (Hyper+Esc)      → no-op (preserved for muscle memory; nothing to escape)

Workspace lifecycle (add / rename / destroy) is CLI-only: `ws add`,
`ws name N <new>`, `ws remove N`. There used to be a
`Caps + Shift + return` manage palette wired to in-overlay dispatch,
but its add / info / list / destroy paths were unreliable enough that
the whole chord was retired in favour of typing the explicit CLI.
