# Permission wizard

`macos/permissions-wizard.sh` walks the one System Settings pane the
stack needs — but only if it actually needs attention. On a working
machine: ~2 seconds, opens nothing. On first install: opens
Accessibility, lists only what's missing.

One pane: **Accessibility** for AeroSpace · Hyperkey. No
Input Monitoring (Karabiner's gone), no System Extensions (no
DriverKit), no logout (AeroSpace doesn't need it).

## Run

```sh
~/dotfiles/macos/permissions-wizard.sh           # probe-gated, idempotent
~/dotfiles/macos/permissions-wizard.sh --force   # bypass probe, walk the pane
```

Use `--force` when a probe lies (false positive: pane silently skipped
when grant is missing).

Direct pane:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Probes live in [`lib/macos-tcc.sh`](../lib/macos-tcc.sh): `pgrep` +
socket round-trip for AeroSpace, `pgrep` + optional TCC.db read for
Hyperkey. No TCC.db writes — Apple invalidates direct writes. No
signed `.mobileconfig` — paid Developer ID required. No synthetic
clicks — System Settings is hardened.

## Troubleshoot

| Symptom | Fix |
|---|---|
| "Already granted" but a binding doesn't work | `--force` to walk manually |
| Toggle greyed out | Click the lock at the bottom of the pane |
| Hyperkey granted but Caps stays inert | Open Hyperkey from the menu bar; toggle "Enable Hyper Key" + "Tap for Escape" ON |
| `osascript: not authorized` | The terminal hosting the script needs Accessibility too |
| AeroSpace not in the list | `open -a AeroSpace` once to surface the prompt |
