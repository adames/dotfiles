# Permission Wizard

`~/dotfiles/macos/permissions-wizard.sh` is the proactive permission flow.
It probes every TCC gate the Hyper-key stack needs, opens the right System
Settings pane, and auto-advances when each grant is detected.

## What it does

Seven gates, in order:

1. **Accessibility / yabai**
2. **Accessibility / skhd**
3. **Accessibility / Hammerspoon**
4. **Accessibility / Karabiner-Elements**
5. **Input Monitoring / Karabiner-Elements**
6. **Input Monitoring / Karabiner-DriverKit-VirtualHIDDevice**
7. **System Extension approval / Karabiner-DriverKit**

Before any prompt, the wizard launches each app once (`yabai/skhd
--start-service`, `open -a Hammerspoon`, `open -a Karabiner-Elements`).
This causes macOS to **add them to the relevant TCC lists with toggles
OFF** — so the user just has to flip a toggle ON, never drag a binary
through Finder's `+` dialog. That's the single biggest UX win.

For each gate the wizard:

1. **Probes first.** If already granted, prints `✓` and skips.
2. **Opens the System Settings pane** via the
   `x-apple.systempreferences:com.apple.preference.security?Privacy_…`
   URL scheme.
3. **Shows a blocking AppleScript dialog** with two buttons:
   - `Skip — already granted` (default; for cases where the wizard's
     probe is broken but you've confirmed the grant in Settings)
   - `Open Pane Again` (re-opens the System Settings pane if you
     navigated away)
   The dialog has a 30-second `giving up after` timeout, so it re-renders
   roughly twice a minute as the outer poll loop re-probes the gate.
4. **Auto-advances** the moment the probe goes green — usually within a
   few seconds of you toggling the switch ON.
5. **Total budget**: 8 dialog rounds (~4 minutes per gate) before timing out.

After all gates: a final dialog asks whether to log out *now* to apply the
`com.apple.spaces spans-displays` change. The default button is "Later" —
the user has to actively choose "Log out now" to trigger it (and macOS
still asks them to confirm once more).

## How to run it

### Full wizard

```sh
~/dotfiles/macos/permissions-wizard.sh
```

Idempotent — re-running picks up any newly-revoked grants and re-prompts
just for those.

### Single step

```sh
~/dotfiles/macos/permissions-wizard.sh --step accessibility-hammerspoon
```

Available step names (also: `--list`):

| Step name | What it grants |
|---|---|
| `accessibility-yabai` | Accessibility for yabai |
| `accessibility-skhd` | Accessibility for skhd |
| `accessibility-hammerspoon` | Accessibility for Hammerspoon |
| `accessibility-karabiner` | Accessibility for Karabiner-Elements |
| `input-monitoring-karabiner` | Input Monitoring for Karabiner-Elements |
| `input-monitoring-driverkit` | Input Monitoring for Karabiner-DriverKit |
| `system-extension-driverkit` | System Extension approval for Karabiner-DriverKit |

## Troubleshooting

| Symptom | Probable cause | Fix |
|---|---|---|
| "Karabiner accessibility: no" but Karabiner works | Terminal lacks Full Disk Access, so the TCC.db read fails | Either grant Terminal FDA, or rely on the behavioral fallback (Karabiner-Core-Service-rev2 has live PID) — wizard does this automatically |
| Dialog doesn't dismiss after I flip the toggle | Probe is wrong for this macOS version | Click "Open Pane Again" — wizard re-probes. If still stuck, click "Skip this step" and file an issue |
| Wizard prompts for a permission already granted | App was removed and re-added to TCC list; old entry stale | Click the toggle off and on; the new entry should grant. Or run `tccutil reset Accessibility` and re-run wizard |
| Karabiner-DriverKit never goes green | System extension blocked at OS level | Open System Settings → Privacy & Security, scroll to the bottom — there's a banner asking to approve the extension. Click "Allow" |
| `osascript` errors about "not authorized" | Accessibility prompts not yet granted to whatever script-runner is hosting this shell | Standard catch-22; grant Accessibility to your terminal app once, then re-run |
| `display has separate spaces is disabled` after running wizard | `spans-displays` was set but you haven't logged out yet | Log out and log back in. yabai re-reads the value on fresh login |

## What the wizard does NOT do

- Doesn't write to TCC.db. Apple invalidates direct writes; only reads are safe.
- Doesn't install signed `.mobileconfig` profiles. That would require a paid
  Apple Developer ID. PPPC payloads from unsigned profiles are ignored by
  macOS on non-MDM machines.
- Doesn't synthesize clicks in System Settings. The app's UI is hardened
  against synthetic events.
- Doesn't reboot. The final logout prompt is the closest it comes — and
  even that defaults to "Later."

## Logs

Every wizard run appends to `~/.local/state/hyper-bootstrap/wizard.log`
(append-only, never read by the wizard, never gates anything). Useful for
debugging "why did the wizard re-prompt for X?" after the fact.
