# Notch padding — how to nudge the pill strip on a notched MacBook

On a MacBook with a camera notch (14"/16" since 2021), the SketchyBar
workspace pill strip is split symmetrically around the notch: half the
pills sit right-anchored against the notch in the left aux area, half
left-anchored in the right aux area. The split point is driven by
`NSScreen.safeAreaInsets` reported by macOS, published to
`~/.cache/workspace/layout.env` by `ws-topologyd`.

The OS-reported safe-area rectangle is sometimes a few points wider or
narrower than the visible camera housing, or shifted by a point or two.
Three user-tunable variables nudge the strip without rebuilding
anything.

## Variables

| Variable | Effect | Default |
|---|---|---|
| `WS_NOTCH_PADDING_PT` | symmetric — applied equally to both sides of the notch | `16` |
| `WS_NOTCH_PAD_LEFT_PT` | left-side override; pushes the left pill chain further left as it grows | falls back to `WS_NOTCH_PADDING_PT` |
| `WS_NOTCH_PAD_RIGHT_PT` | right-side override; pushes the right pill chain further right as it grows | falls back to `WS_NOTCH_PADDING_PT` |

Precedence per variable: shell environment > config file > default.

A side-specific override beats the symmetric default. Use
`WS_NOTCH_PAD_LEFT_PT` / `WS_NOTCH_PAD_RIGHT_PT` when the housing is
shifted off-center, not just slightly wider — the symmetric variable is
the right knob for "everything's evenly tight" cases.

## Where it lives

The file is at `~/.config/workspace/sketchybar-tuning.env`. Bootstrap
seeds it from `configs/workspace/sketchybar-tuning.env` only when
missing; your edits survive `bootstrap.sh` re-runs.

```
# ~/.config/workspace/sketchybar-tuning.env
WS_NOTCH_PADDING_PT=16
# WS_NOTCH_PAD_LEFT_PT=18
# WS_NOTCH_PAD_RIGHT_PT=14
```

## How a tweak flows to the bar

1. You edit `~/.config/workspace/sketchybar-tuning.env`.
2. `configs/sketchybar/plugins/recenter.sh` sources the file (lines
   54–63 of that script). If any of the three variables are unset, it
   sources the config; existing env vars are preserved.
3. The math at `recenter.sh:175–176` applies:
   ```
   eff_notch_x = notch_x − WS_NOTCH_PAD_LEFT_PT
   eff_notch_w = notch_w + WS_NOTCH_PAD_LEFT_PT + WS_NOTCH_PAD_RIGHT_PT
   ```
   Larger `_LEFT_PT` widens the perceived notch to the left → the left
   pill chain anchors further left. Larger `_RIGHT_PT` widens it to the
   right → the right chain anchors further right.
4. Each pill's `padding_left` is computed once and committed in one
   `sketchybar` invocation (`recenter.sh:220–221`) — no intermediate
   flicker.

## Copy-paste tuning recipe

```bash
# 1) Edit
"$EDITOR" ~/.config/workspace/sketchybar-tuning.env
# nudge WS_NOTCH_PAD_LEFT_PT or WS_NOTCH_PAD_RIGHT_PT (signed int, points)

# 2) Live-reload (no sketchybar --reload, no logout)
~/.config/sketchybar/plugins/recenter.sh
```

The recenter plugin re-sources the env file on every invocation, so
running it directly is the canonical apply. A full `sketchybar
--reload` works too but it isn't necessary — only `recenter.sh` reads
these variables.

## Direction reference

| Observation | Adjustment |
|---|---|
| Right-side pills crowd into the notch | `WS_NOTCH_PAD_RIGHT_PT` larger |
| Right-side pills leave a gap to the right of the notch | `WS_NOTCH_PAD_RIGHT_PT` smaller |
| Left-side pills crowd into the notch | `WS_NOTCH_PAD_LEFT_PT` larger |
| Left-side pills sit too far from the notch | `WS_NOTCH_PAD_LEFT_PT` smaller |
| Both sides off by the same amount | `WS_NOTCH_PADDING_PT` (symmetric) |

Half-an-icon (~8–16pt) is a typical nudge. Move in increments and run
`recenter.sh` between each.

## Non-notched displays: the math is bypassed

Non-notched displays — external monitors, MacBook Airs, the 13" Pro
built-in — use a different branch:

`configs/sketchybar/plugins/recenter.sh:201–214` runs when the
display's `is_laptop` flag is false (line 159). That branch:

- Computes `chain_w = visible_count × pill_w + (visible_count − 1) × gap`.
- Computes `pad_anchor = (usable − chain_w) / 2` — pure center.
- Applies `pad_anchor` only to the first pill; subsequent pills use the
  inter-pill gap.

It never reads `WS_NOTCH_*` and never invokes `eff_notch_x` / `eff_notch_w`.
The tuning variables can be set, ignored, or removed — they have no effect
on a display without a notch. There is no per-display escape hatch needed.

## Slot count and visible cap on a notched display

`per-display-pills.sh:28` keeps a `LEGACY_NOTCH_MAX_VISIBLE=10` cap for
notched displays where `ws-topologyd` hasn't yet published a per-display
`WS_MAX_VISIBLE_SLOTS_<id>`. The cap is on *rendered* pills, not on the
slot count — slots past the cap exist (yabai knows about them, the
workspace CLI can address them) but draw=off on the notched bar.

A practical consequence: if you add slots past index 10, they're visible
only on external monitors and they render with a subtle `•` in place of
the digit (slots past 10 have no Hyper+1..0 hotkey, so the dot signals
"reachable by name only").

The system supports up to whatever yabai's per-monitor cap allows
(currently 16). The navbar code reads the live count from yabai or
`spaces.json` — there is no hardcoded upper bound in the bar.
