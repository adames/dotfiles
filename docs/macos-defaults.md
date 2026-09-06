# macOS defaults

`macos/macos-defaults.sh` is run by `phase_apply` so both Macs (`m3` + `m1`)
converge on the same appearance / keyboard / Dock / Finder / Spotlight /
trackpad posture. Encoded values live in the script — edit there, re-run
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
| Spotlight | `AppleSymbolicHotKeys` 64 | enabled | Cmd+Space — Spotlight search |
| Spotlight | `AppleSymbolicHotKeys` 65 | enabled | Cmd+Opt+Space — Finder search window |
| Spotlight | `EnabledPreferenceRules` | related content + Dictionary | app-content sources; see below |
| Spotlight | `DisabledUTTypes` | `()` | Hidden File Types — nothing suppressed |
| Trackpad | `Clicking` (built-in) | `false` | |
| Trackpad | `Clicking` (bluetooth) | `false` | |
| Trackpad | `com.apple.mouse.tapBehavior` | `0` | global tap-to-click off |

## Spotlight

Cmd+Space was switched off when Raycast became the launcher, and retiring
Raycast (see `macos/bootstrap.sh`) left it off — Spotlight had no hotkey at
all. Hotkeys 64/65 are nested dicts under `AppleSymbolicHotKeys`, so `dw()`
can't drive them; the script compares `:<id>:enabled` by hand and calls
`activateSettings -u` on change so the binding takes effect without a logout.

Tahoe's Spotlight pane splits results in two:

- **Always on, not listed anywhere** — apps, files, folders, and the
  calculator. `EnabledPreferenceRules` does not govern these. The only way
  to suppress on-disk results is Hidden File Types (`DisabledUTTypes`),
  which we deliberately keep empty.
- **`EnabledPreferenceRules`** — opt-in *app-content* sources. This is the
  "search inside my apps" layer, and we want a launcher instead. Trimmed to
  `Custom.relatedContents` (on-device related content) and
  `com.apple.Dictionary` (definitions — same quick-utility class as the
  calculator).

Dropped from the stock list: Mail, Messages, Notes, Contacts, Calendar,
Reminders, Photos, Books, Pages, Podcasts, Voice Memos, Phone, Shortcuts,
Tips, plus `System.menuItems` (frontmost app's menu commands) and
`System.iphoneApps` (iPhone Mirroring). Re-enable any of them by adding the
identifier back to `SPOT_RULES`.

Spotlight caches its prefs, so the script `killall Spotlight` on change.

## What's NOT scriptable

Hard limits — don't try to drive these from `defaults`:

- **Wallpaper.** Historically iCloud-coupled and brittle to script. The
  m1 is signed out of Apple ID, so wallpaper has no sync path either
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

The encoded values are the **live M3 baseline**. Three were reconciled
against an earlier recollection — live won (it's the actual user-set state):

| Setting | Earlier note | Live (M3) | Encoded |
|---|---|---|---|
| `ApplePressAndHoldEnabled` | `true` | `false` | `false` |
| Dock `tilesize` | `42` | `44` | `44` |
| Finder `FXPreferredViewStyle` | `clmv` (column) | `Nlsv` (list) | `Nlsv` |

To bring the second Mac (`m1`) into parity, don't assume either machine
is canonical:

1. On the other Mac, read its live value for every domain/key in the script.
2. Diff against the encoded baseline and build a table of every *difference*
   (setting · M3 value · other value · recommendation). Settings that
   already match need no decision.
3. Pick the winner per difference, update `macos/macos-defaults.sh` to the
   agreed set, and re-run on both. Never silently overwrite the other
   machine. Dark mode is the one given — both machines stay Dark.

## App-pref parity

For per-app prefs (Ghostty, etc.), prefer per-app
`defaults export <domain> <file>` checked into `configs/`. We don't use
mackup — its symlink mode is broken on macOS 14+.
