# macOS defaults

`macos/macos-defaults.sh` is run by `phase_apply` so both Macs (M3 + Air)
converge on the same appearance / keyboard / Dock / Finder / trackpad
posture. Encoded values live in the script — edit there, re-run
`./macos/bootstrap.sh` to apply (idempotent).

## What's covered

| Category | Setting | Value | Notes |
|---|---|---|---|
| Appearance | `AppleInterfaceStyle` | `Dark` | |
| Appearance | `AppleAccentColor` | `-1` | graphite |
| Keyboard | `KeyRepeat` | `2` | very fast |
| Keyboard | `InitialKeyRepeat` | `15` | |
| Keyboard | `ApplePressAndHoldEnabled` | `false` | vim posture — hjkl repeats |
| Keyboard | `AppleShowAllExtensions` | `true` | |
| Dock | `autohide` | `true` | |
| Dock | `tilesize` | `44` | |
| Dock | `show-recents` | `false` | |
| Dock | `mru-spaces` | `false` | spaces stay in fixed order |
| Dock | `orientation` | `bottom` | |
| Finder | `FXPreferredViewStyle` | `Nlsv` | list view |
| Finder | `FXDefaultSearchScope` | `SCcf` | search current folder |
| Trackpad | `Clicking` (built-in) | `false` | |
| Trackpad | `Clicking` (bluetooth) | `false` | |
| Trackpad | `com.apple.mouse.tapBehavior` | `0` | global tap-to-click off |

## What's NOT scriptable

Hard limits — don't try to drive these from `defaults`:

- **Wallpaper.** Historically iCloud-coupled and brittle to script. The
  Air is signed out of Apple ID, so wallpaper has no sync path either
  way — set it once manually on each Mac after first login.
- **Display arrangement** (multi-monitor layout). No `defaults` surface.
- **pmset** items that touch the SMC. Use `sudo pmset -a …` directly.
- **sqlite-backed Settings panes** (Privacy & Security, Login Items,
  some Sound prefs). Privacy/Accessibility goes through
  `macos/permissions-wizard.sh`.

## Apply timing

- **Dark mode** applies fully at next login. The script forces it live
  via `osascript … set dark mode to true`, which works most of the time;
  a fresh login is the only guaranteed apply path.
- **Some keyboard / trackpad** changes need a logout to fully apply.
- All changes need `killall Dock Finder SystemUIServer` to show without
  logout — already in the script.

## Adding a setting

1. Edit `macos/macos-defaults.sh`. Pin to a domain/key — no GUI clicks.
2. Re-run `./macos/bootstrap.sh` (or `bash macos/macos-defaults.sh`
   standalone).
3. Verify: `defaults read <domain> <key>`.
4. Update this table.

## Cross-machine reconciliation

The encoded values are the **live M3 baseline** as of branch
`polish/cross-mac-mirror`. Three differed from the working prompt's
recollection at capture time — live won (it's the actual user-set state):

| Setting | Doc | Live (M3) | Encoded |
|---|---|---|---|
| `ApplePressAndHoldEnabled` | `true` | `false` | `false` |
| Dock `tilesize` | `42` | `44` | `44` |
| Finder `FXPreferredViewStyle` | `clmv` (column) | `Nlsv` (list) | `Nlsv` |

When the Air is live-readable, diff against this script and reconcile:
read the Air's current values, diff each against this table, **ask
before overwriting either machine**, then codify the agreed set here
and in `macos/macos-defaults.sh`. (This was "Goal D" in the one-shot
working prompt that drove the original cross-Mac mirror — completed
and removed; see git history for the full checklist if needed.)

## App-pref parity

For per-app prefs (Ghostty, Raycast, etc.), prefer per-app
`defaults export <domain> <file>` checked into `configs/`. We don't use
mackup — its symlink mode is broken on macOS 14+.
