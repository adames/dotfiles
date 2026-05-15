# Manual test matrix

Scenarios that need actual hardware changes (plug, unplug, mirror) or
system settings to toggle. Re-run when validating a release.

## Display topology + layout

| # | Scenario | Setup | Expected `ws-topology dump` | Expected SketchyBar |
|---|---|---|---|---|
| 1 | M3 only | unplug external from M3 Max | One display, `isBuiltIn=true`, `safeAreaInsets.top > 0`, `auxiliaryTopLeftArea` + `auxiliaryTopRightArea` non-nil | Left-aligned strip in the left aux region; visible-pill cap of 10 applied |
| 2 | M3 + external, external is primary | System Settings → Displays → drag white menu-bar bar to external | Both displays present; external has `isPrimaryMenuBarDisplay=true`; M3 keeps `isBuiltIn=true` | Each display has its own left-aligned strip with its `workspace.name.<D>` chip leftmost |
| 3 | M3 + external, unplug external | Plug then unplug | Exactly one snapshot diff (debounced); `fallbackScreenIDOnDisconnect` resolves to M3's id | All pills migrate to M3; chip for the removed display is cleaned up |
| 4 | M1 only | Use the M1 13" alone | One display, `isBuiltIn=true`, `safeAreaInsets.top == 0`, no aux areas | Left-aligned strip across the top; chip leftmost; no visible cap |
| 5 | M1 + external | Plug monitor into M1 | Two displays, compact built-in + external rectangular | Each display has its own left-aligned strip + chip; identical slot identity |
| 6 | Mirrored mode | System Settings → Displays → mirror to external | Two displays; secondary has `mirrorMasterID != nil`; policy marks it `isCollapsedMirrorSecondary=true` | Only one logical bar (master); secondary repaints suppressed |
| 7 | Lid closed (clamshell) on M3 with external | Close lid with external attached | Single display (external); fallback resolves to external | Bar continues on external; no orphaned slot indices |
| 8 | "Other people's monitor" | Plug into an unfamiliar display | Unknown `stableUUID` appears; policy still classifies as `externalRectangular` | Left-aligned strip appears immediately with its chip; no pre-configuration |
| 9 | Display reconfig callback storm | Hot-plug external twice in quick succession | OSLog shows one debounced publish per physical event; `topology.json` mtime advances once | No duplicate sketchybar repaints |

## Icons + identity

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 10 | Missing Nerd Font | Temporarily disable `JetBrainsMono Nerd Font` in Font Book | `ws-topology resolve-icon 1 --surface=font` returns `kind=text`; SketchyBar shows the text fallback (`ST`, `HU`, …) |
| 11 | Override survives rename | `workspace icon 1 ` then `workspace name 1 broadcast` | `iconSpec.codepoint` stays as ``, `iconSpec.userOverridden=true`; name updates to `broadcast` |
| 12 | Legacy v1 config import | Paste a v1 spaces.json on top of `~/.config/workspace/spaces.json` | `ws-topology migrate` dry-run prints expected v2 shape; `--apply` rewrites in place. Readers do NOT fall back to legacy `.icon`, so always `--apply` before reloading. |

## Per-host overlay

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 13 | Fork host config | `workspace host init` on m3 | `~/.config/workspace/spaces.m3.json` created from `spaces.json`; `workspace host status` shows it as active |
| 14 | Reset overlay | `workspace host reset` | Per-host file deleted; cascade falls back to shared `spaces.json` |
| 15 | Different config per machine | Edit `spaces.m1.json` independently of `spaces.m3.json` | Each machine reads its own; shared file unchanged |

## Accessibility

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 16 | Reduce Motion enabled | System Settings → Accessibility → Display → Reduce motion | `layout.env` shows `WS_REDUCE_MOTION=1`; consumers can damp animations (configure sketchybar `animation_curve` if desired) |
| 17 | Increase Contrast enabled | System Settings → Accessibility → Display → Increase contrast | `layout.env` shows `WS_INCREASE_CONTRAST=1` |

## Hotkeys

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 18 | Slot count > 10 overflow | `ws add` until 11 slots | Inside `Caps+f` focus overlay, digits `1..0` address slots 1..10 directly; reach slot 11+ via name typing + ↵ (all-numeric query addresses slot index) or `yabai -m space --focus 11`. |
| 19 | New slot is reachable immediately | Run `ws add foo` | Sketchybar pill appears (post-mutate hook → per-display-pills.sh); `Caps+f` focus overlay can target the new slot without a reload (skhdrc bindings are static, not generated). |

## Performance

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 20 | Space switch latency | `Caps+f → 1..0` in rapid succession | No "paint to right then snap" pulse on pills; single `sketchybar --set` transaction per layout change. (ws-prompt captures keystrokes itself the moment the overlay opens, so the first digit after `Caps+f` is never dropped.) |
| 21 | Cascade fires once per event | `log stream --predicate 'subsystem == "com.adames.workspace.topology"'` while switching spaces | One emission per space switch (no duplicate cascades from stale signals) |

## Verification commands

```bash
# Topology snapshot
ws-topology dump | jq

# Per-display policy
ws-topology layout | jq '.policies[] | {displayID, layoutClass, maxVisibleSlots, topOrnamentRegion, auxiliaryTopRightRegion, notchRegion}'

# Streaming logs
log stream --predicate 'subsystem == "com.adames.workspace.topology"'

# Live env cache
cat ~/.cache/workspace/layout.env

# yabai signal sanity (should be lean: 1 per event family, no duplicates)
yabai -m signal --list | jq -r 'group_by(.event) | .[] | "\(.[0].event)  count=\(length)"'

# Live geometry — should match the math in the layout rules above
for n in 1 4 5 8 9 12; do
  printf 'space.%-2d  pad_left=%s\n' "$n" \
    "$(sketchybar --query space.$n | jq -r .geometry.padding_left)"
done
```
