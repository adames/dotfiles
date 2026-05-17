# Karabiner configuration

Companion to `karabiner.json` — JSON doesn't allow comments, so the
explanation lives here.

The config has **three complex modifications**, ordered intentionally:

## Rule 1 — Hyper + Space → Ctrl + Space

```
from: spacebar with mandatory ctrl+opt+cmd+shift   (Hyper)
to:   spacebar with left_control
```

When Hyper is held (from Rule 3) and Space is pressed, Karabiner emits
`Ctrl+Space` — which is tmux's prefix. Net effect: **Caps + Space sends the
tmux prefix**.

**Why not just set tmux's prefix to something else?** Terminal emulators
can't reliably pass a 4-modifier chord (`Ctrl+Opt+Cmd+Shift+Space`) through
to tmux, and `Ctrl+Space` is already the well-trodden tmux default. Doing
the downgrade in Karabiner keeps tmux's config portable and lets the same
ergonomic chord (Caps+Space) reach tmux from any terminal.

This rule operates on `spacebar` input, not `caps_lock`, so it doesn't
conflict with Rules 2 or 3 — it fires on the *emitted* Hyper+Space event
that those rules produce.

## Rule 2 — Caps Lock + Shift → Mod

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

## Rule 3 — Caps Lock alone → Hyper, or Esc on tap

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
at press-time; just remap Caps Lock itself. (Rule 2 fires first when Shift
is present, so this rule covers all other cases.)

## Order matters

Karabiner evaluates rules top-to-bottom. Rule 2 (with `mandatory shift`)
must come before Rule 3; otherwise Rule 3's `optional any` would consume
the Shift+Caps case and the 3-mod Mod would never fire. Rule 1 operates on
a different input key (`spacebar`) so its position relative to Rules 2/3 is
not load-bearing, but the documented order — and the one enforced by
`.github/workflows/lint.yml` — is `Hyper+Space → Caps+Shift Mod → Caps
Hyper/Esc`.

## What this implies for tooling downstream

- **skhd** sees keystrokes with modifier sets `cmd+alt+ctrl+shift` (Hyper)
  or `cmd+alt+ctrl` (Mod) depending on whether Shift was held.
- **macOS shortcut conflicts** — Cmd+Q, Cmd+W, etc. still work normally
  because the user is pressing them without Caps Lock.

## App launchers live in skhd, not here

The Karabiner config has only the three rules above. Every Hyper chord
— `Caps + T` (terminal), `Caps + B` (browser), `Caps + O` (Finder),
`Caps + ,` (System Settings), `Caps + ;` (cheatsheet) — is bound in
[`skhdrc`](skhdrc). Karabiner's job ends at re-emitting the
Hyper/Mod modifier set; skhd dispatches.

**Free-key register** — chords currently unbound at each layer:

- Hyper (Caps held): `c`, `space`, most punctuation. (Caps+Space is
  consumed by Karabiner Rule 1 → tmux prefix.)
- Mod (Caps+Shift held): everything except `hjkl` and `q` (inbox).
  Notably free: `v`, `r`, `w`, `e`, `f`, `g`, `m`, `n`, `p`, `t`,
  `b`, `o` — the Hyper-layer counterparts pulled their Mod siblings
  with them when the manage prompt moved from Mod+W to Hyper+W. Verify
  before claiming with `grep -nE 'cmd \+ alt \+ ctrl - <key>' skhdrc`.

## Layer semantic: Hyper = navigate, Mod = modify

The two layers carry a consistent split — useful when adding new bindings:

- **Hyper** (Caps held)        — navigate / non-destructive
  (focus window/space, launch app, new terminal, open cheatsheet)
- **Mod**   (Caps+Shift held)  — modify / destructive
  (swap window, manual snap)

When in doubt about where a new binding belongs, ask: does it *move* state
(Mod) or *show* state (Hyper)?

## Workspace prompts (lives in ws-prompt + ws-picker, dispatched by skhd)

Karabiner doesn't grab any of these keys. skhd binds each chord to
either `ws-prompt <mode>` or `ws-picker` — SwiftUI overlays that
capture keystrokes themselves and exit on commit / cancel / blur.
There are no sticky skhd modes anywhere in the system.

Four overlays, one pattern: **digit commits · letters fuzzy-search ·
↵ accepts · esc cancels**. Pick by intent — change to *jump* to a
window's space, focus to *land* on a space, go to *send* a window,
edit to *modify* the space set.

- `Caps + e` (Hyper+E)        → change workspace (`ws-picker`; fuzzy-search every window in every space — ↵ jumps to its space)
- `Caps + f` (Hyper+F)        → focus workspace  (digit commits · letters fuzzy-match + ↵)
- `Caps + g` (Hyper+G)        → go (send window) (digit commits + follow · letters fuzzy-match + ↵)
- `Caps + m` (Hyper+M)        → go (send window) (alias for Caps+g; "m" for move)
- `Caps + w` (Hyper+W)        → edit workspace   (verb-picker → multi-stage flow):
                                  a add · r rename · i icon · d destroy
                                  ⇧L layout save/load/delete
                                  v verify · ? doctor
- `Esc` / click-elsewhere     → cancel (edit backs up one stage; verb-picker cancels)
- `Caps + Esc` (Hyper+Esc)    → no-op (preserved for muscle memory; nothing to escape)

The edit flow shells out to the `ws` CLI directly and surfaces
stdout + stderr in an in-overlay result panel — no AppleScript
dialogs, no helper shell shims.
