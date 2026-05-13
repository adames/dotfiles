# Permission Wizard

`macos/permissions-wizard.sh` walks the three System Settings panes the
Hyper-key stack needs — but only the ones that actually need attention.
On a re-bootstrap of a working machine it finishes in ~2 seconds without
opening anything. On a first install it opens whichever panes still have
ungranted toggles, listing **only the missing items** rather than the
full default set.

## Flow

1. **Probe.** [`lib/macos-tcc.sh`](../lib/macos-tcc.sh) asks each tool
   whether its TCC bit is on — no prompts, no side effects, no Full Disk
   Access required. Sources:

   | Tool | Probe |
   |---|---|
   | yabai · skhd                | `launchctl list` PID > 0 (services refuse to start without Accessibility); error-log fallback parses `"could not access accessibility"` / `"must be run with accessibility access"` |
   | ws-snap                     | binary present on PATH; first AX call triggers the TCC prompt, after which the toggle survives across reboots. |
   | Karabiner (Acc + Input Mon) | `Karabiner-Core-Service-rev2` agent PID — the service refuses to start without both bits granted, so a live PID is strong evidence of both. |
   | DriverKit System Extension  | `systemextensionsctl list` for `Karabiner.*activated enabled`. |

2. **Register if needed.** If any probe failed, launch the apps so they
   appear in TCC lists (`yabai --start-service`, `skhd --start-service`,
   `open -ga Karabiner-Elements`, plus a no-op `ws-snap` invocation),
   then re-probe. A freshly-installed app sometimes passes the second
   probe where it failed the first.

3. **Per pane, skip or open:**

   | Pane | Toggle ON |
   |---|---|
   | Accessibility       | yabai · skhd · ws-snap · Karabiner-Elements |
   | Input Monitoring    | Karabiner-Elements · Karabiner-DriverKit-VirtualHIDDevice |
   | System Extensions   | approve Karabiner-DriverKit-VirtualHIDDevice (banner near top) |

   If a pane's missing list is empty, it's skipped with `✓ already granted`.
   Otherwise the pane opens and the wizard lists only the still-missing
   items so you're not re-toggling things that are already on.

4. **Kick services.** Only runs if at least one pane was opened.
   `karabiner_grabber` and `karabiner_console_user_server` are
   re-launched so Karabiner picks up new grants.

5. **Logout offer.** If `com.apple.spaces spans-displays` is set but
   yabai isn't running, prompts to log out (yabai re-reads the value on
   fresh login only).

## Run

```sh
~/dotfiles/macos/permissions-wizard.sh           # probe-gated walk-through (idempotent)
~/dotfiles/macos/permissions-wizard.sh --force   # bypass probes, open every pane
```

Use `--force` when you suspect a probe is lying (false positive → pane
silently skipped when grant is actually missing) or for manual
re-verification.

If you only need to fix one pane, open it directly:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_SystemServices"
```

## What this does NOT do

- Doesn't write to TCC.db (Apple invalidates direct writes).
- Doesn't install signed `.mobileconfig` profiles (paid Developer ID required).
- Doesn't synthesise clicks in System Settings (UI is hardened).
- Doesn't reboot — the logout offer is the closest it comes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Wizard reports a pane "already granted" but a binding doesn't work | Probe false positive. Re-run with `--force` to walk every pane manually. |
| Wizard opens a pane whose toggles already look on | Probe false negative — the app probably wasn't running when probed. Harmless; press ↵ to advance. |
| Toggle exists but is greyed out | Some macOS versions require unlocking the pane (click the lock at the bottom). |
| Karabiner-DriverKit System Extension never goes green | Open Privacy & Security and scroll for the "Allow" banner near the top. |
| `osascript: not authorized` errors | The terminal hosting the script needs Accessibility once. Grant it, re-run. |
| `display has separate spaces is disabled` after running wizard | `spans-displays` was set but you haven't logged out yet. |
