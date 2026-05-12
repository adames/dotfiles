# Permission Wizard

`macos/permissions-wizard.sh` walks the three System Settings panes the
Hyper-key stack needs. No probing, no polling — opens a pane, lists the
toggles, waits for ↵. Three panes, ~5 minutes.

## Flow

1. **Register apps in TCC lists.** `yabai/skhd --start-service`,
   `open -ga Hammerspoon/Karabiner-Elements`. Once an app has been
   launched, it appears in the relevant TCC pane with its toggle OFF.
   You just flip it — no dragging through Finder's `+` dialog.

2. **Three panes:**

   | Pane | Toggle ON |
   |---|---|
   | Accessibility | yabai · skhd · Hammerspoon · Karabiner-Elements |
   | Input Monitoring | Karabiner-Elements · Karabiner-DriverKit-VirtualHIDDevice |
   | System Extensions | approve Karabiner-DriverKit-VirtualHIDDevice (banner near top) |

3. **Kick services.** `karabiner_grabber` and `karabiner_console_user_server`
   re-launched so Karabiner picks up the new grants; Hammerspoon reloaded.

4. **Logout offer.** If `com.apple.spaces spans-displays` is set but yabai
   isn't running, prompts to log out (yabai re-reads the value on fresh
   login only).

## Run

```sh
~/dotfiles/macos/permissions-wizard.sh   # full walk-through (idempotent)
```

There's no `--step` option: if you only need to fix one pane, open it
directly:

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
| Toggle exists but is greyed out | Some macOS versions require unlocking the pane (click the lock at the bottom). |
| Karabiner-DriverKit System Extension never goes green | Open Privacy & Security and scroll for the "Allow" banner near the top. |
| `osascript: not authorized` errors | The terminal hosting the script needs Accessibility once. Grant it, re-run. |
| `display has separate spaces is disabled` after running wizard | `spans-displays` was set but you haven't logged out yet. |
