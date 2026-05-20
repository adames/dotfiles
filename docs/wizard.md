# Permission Wizard

`macos/permissions-wizard.sh` walks the one System Settings pane the
Hyper-key + tiling stack needs — but only if it actually needs attention.
On a re-bootstrap of a working machine it finishes in ~2 seconds without
opening anything. On a first install it opens the Accessibility pane and
lists **only the missing items** rather than the full default set.

Post-Phase-6 (yabai → AeroSpace, Karabiner → Hyperkey) the surface has
shrunk significantly: no more Input Monitoring pane (Karabiner's HID
event stream is gone), no more System Extensions pane (no DriverKit
dependency), no more logout-for-spans-displays prompt (AeroSpace doesn't
need it).

## Flow

1. **Probe.** [`lib/macos-tcc.sh`](../lib/macos-tcc.sh) asks each tool
   whether its Accessibility grant is in place — no prompts, no side
   effects, no Full Disk Access required. Sources:

   | Tool | Probe |
   |---|---|
   | AeroSpace | `pgrep -x AeroSpace` (the .app refuses to manage windows without Accessibility, so a live PID is strong evidence the bit is on) plus a CLI socket round-trip via `aerospace list-monitors --json`. |
   | Hyperkey  | `pgrep -x Hyperkey` plus an optional TCC.db read for `kTCCServiceAccessibility` + `%Hyperkey%`. |
   | ws-snap   | Binary present on PATH; first AX call triggers the TCC prompt, after which the toggle survives across reboots. |

2. **Register if needed.** If any probe failed, launch the apps so they
   appear in the Accessibility list (`open -ga AeroSpace`,
   `open -ga Hyperkey`, plus a no-op `ws-snap` invocation), then
   re-probe. A freshly-installed app sometimes passes the second probe
   where it failed the first.

3. **Open or skip.**

   | Pane | Toggle ON |
   |---|---|
   | Accessibility | AeroSpace · Hyperkey · ws-snap |

   If the missing list is empty, the pane is skipped with `✓ already
   granted`. Otherwise it opens and lists only the still-missing items
   so you're not re-toggling what's already on.

## Run

```sh
~/dotfiles/macos/permissions-wizard.sh           # probe-gated walk-through (idempotent)
~/dotfiles/macos/permissions-wizard.sh --force   # bypass probe, open the pane
```

Use `--force` when you suspect a probe is lying (false positive → pane
silently skipped when grant is actually missing) or for manual
re-verification.

If you only need to fix the Accessibility pane, open it directly:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

## What this does NOT do

- Doesn't write to TCC.db (Apple invalidates direct writes).
- Doesn't install signed `.mobileconfig` profiles (paid Developer ID required).
- Doesn't synthesise clicks in System Settings (UI is hardened).
- Doesn't reboot or log out — neither is needed under the aerospace stack.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Wizard reports the pane "already granted" but a binding doesn't work | Probe false positive. Re-run with `--force` to walk the pane manually. |
| Wizard opens the pane and items already look toggled on | Probe false negative — the app probably wasn't running when probed. Harmless; press ↵ to advance. |
| Toggle exists but is greyed out | Some macOS versions require unlocking the pane (click the lock at the bottom). |
| Hyperkey grants Accessibility but Caps still doesn't fire Hyper | The Hyperkey menu-bar toggle has to be ON. Open Hyperkey from the menu bar, ensure "Enable Hyper Key" + "Tap for Escape" are checked. |
| `osascript: not authorized` errors | The terminal hosting the script needs Accessibility once. Grant it, re-run. |
| AeroSpace not in the Accessibility list at all | `open -a AeroSpace` to launch it once. First launch surfaces the TCC prompt; granting the toggle persists across reboots. |
