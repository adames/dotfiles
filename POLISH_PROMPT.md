# Dotfiles polish + cross-Mac env mirroring

You're rooted at `~/dotfiles`. This is **my custom bash bootstrap system — NOT chezmoi, NOT nix-darwin, NOT mackup.** `chezmoi` isn't installed; the only artifact is a dead `~/.config/chezmoi/chezmoistate.boltdb` (delete it). **Do not introduce any dotfile framework.** Work in the bash model: edit tracked source under `~/dotfiles/`, then re-run the bootstrap to deploy.

## The mirror philosophy (read this — it shapes every decision)
I run two Macs: this **M3** (more memory) and an **M1 MacBook Air**. I'm about to travel and want them to feel identical.
- **Environment = identical on both.** Dotfiles, shell, CLI tooling, keybindings, and **macOS *defaults* (appearance/Dark mode, keyboard, Dock, Finder, trackpad)** must match. No more "dark on one, light on the other."
- **Don't assume one machine is right.** The M3's current values are the *starting baseline* (captured in Goal D), but the **M1/Air may have settings I prefer** and want on both. The canonical set is decided by **reconciling both machines and asking me** — never by blindly overwriting the other.
- **Apps = NOT forced identical.** The Air has less memory; it should NOT be made to install heavy apps (e.g. OrbStack). Heavy/per-machine apps live in an **untracked `Brewfile.local`** per machine.
- **Data = per-machine.** I choose what files live where; nothing about data is synced by this repo.
- The Air is **signed out of Apple ID**; this M3 is signed in (`adames.hodelin@gmail.com`). This is irrelevant to env parity — `AppleInterfaceStyle` (Dark mode) and the other defaults are **local**, set by script, not by iCloud. The signed-out Air mirrors fine.

## How this repo actually works (verify as you go)
- `~/dotfiles/bootstrap.sh` — OS dispatcher → `macos/bootstrap.sh` (Darwin) / `ubuntu/bootstrap.sh`.
- `~/dotfiles/macos/bootstrap.sh` — 4 phases: `phase_sudo`, `phase_packages` (inline `brew install`, **no Brewfile**), `phase_apply` (titled *"deploy configs & defaults"* but applies **zero** defaults beyond the broken Hyperkey lines), `phase_wizard` (TCC Accessibility).
- `~/dotfiles/lib/common.sh` — reuse: `section/step/ok/warn/err`, `have`, `has_tty`, `install_file <src> <dst> [mode]` (idempotent **byte-compare copy**, not symlink). Source via `. "$DOTFILES_DIR/lib/common.sh"`.
- `~/dotfiles/lib/platform-manifest.sh`, `~/dotfiles/lib/macos-tcc.sh` (TCC probe pattern), `~/dotfiles/macos/permissions-wizard.sh` (the one System-Settings pane I script — keep the hardened posture, no scripted Settings clicking).
- `~/dotfiles/configs/` — deployed source. `~/dotfiles/bin/` — tracked scripts (`ws-doctor`…). `~/dotfiles/docs/` — `architecture.md`, `keymap.md`, `wizard.md`.

**Safety:** branch off `main`; one logical change per commit. Edit **tracked source**, never the deployed `~/.config` copy. Re-running bootstrap is safe (byte-compare); after each change run the phase and `cmp` the deployed file against source. Gate risk behind env escape hatches (repo already uses `BOOTSTRAP_SKIP_CASKS`). Never leave a machine worse than found.

---

## ⏱ TODAY / FAST PATH (I travel in a couple hours — get the Air mirrored first)
Do these in order; this is the minimum to make the Air match this M3's environment before I leave. The deeper hardening (Goal C update flow, hidutil research) can come after.
1. **Fix the caps remap** on this M3 (Goal B) — verify caps+t / caps+b fire.
2. **Reconcile defaults + build `macos/macos-defaults.sh`** (Goal D): read the M1/Air's current settings, diff against this M3's baseline, **ask me which value wins for each difference**, then codify the agreed set and wire it into `phase_apply`.
3. **Create the core `macos/Brewfile`** (Goal C step 1) so the Air installs the env apps — make sure the **browser that caps+b opens (Helium)** is in core, or caps+b fails on the Air.
4. **Commit + push** these to `main`.
5. **On the Air:** `cd ~/dotfiles && git pull && ./bootstrap.sh` → it gets the same dotfiles, the Dark-mode + keyboard/Dock/Finder defaults, the working caps remap, and the core apps. Heavy apps stay off it (no `Brewfile.local`).
6. Sanity-check the Air against the verification checklist (appearance is Dark, caps chords work).

---

## Goal A — Verify both devices work as intended
Run `~/dotfiles/bin/ws-doctor` and read it. Walk the checklist (bottom) on this M3. Flag any spot the bootstrap assumes Apple Silicon (`/opt/homebrew/bin/brew`) so the Air path is safe (the Air is also Apple Silicon, but keep it host-agnostic).

## Goal B — FIX caps+t and caps+b (priority)
caps+t (Ghostty) and caps+b (**Helium**) stopped firing. The AeroSpace bindings are **correct** — grep `~/.config/aerospace/aerospace.toml` for `cmd-alt-ctrl-shift-t` / `-b` (≈ lines 166–167; caps+b runs `open -a Helium`). The failure is upstream: **Caps isn't being remapped to hyper at all**, so *every* caps chord (h/j/k/l focus, digits) is dead.

**Root cause to verify — grep, don't trust line numbers:** `macos/bootstrap.sh` (comment ≈ line 74, writes ≈ 76–77) does `defaults write Hyperkey enableHyperKey -bool true` / `tapForEscape -bool true`. But installed Hyperkey is **v1.56, bundle id `com.knollsoft.Hyperkey`**, and that domain uses **different keys**: `capsLockRemapped=2`, `keyRemap=1`, `hyperFlags=1966080`, `quickHyperKeycode=53` — with **no `enableHyperKey`/`tapForEscape` in either domain.** This is a **key-schema mismatch, not just a wrong domain** — writing the old keys to the new domain still does nothing.

Steps:
1. Ground truth: `defaults read com.knollsoft.Hyperkey`, `defaults read Hyperkey`, and bundle id/version in `/Applications/Hyperkey.app/Contents/Info.plist`. Capture this M3's **currently-working values** as the restore baseline (expected `capsLockRemapped=2`, `keyRemap=1`, `hyperFlags=1966080`, `quickHyperKeycode=53`).
2. Rewrite the bootstrap seeding to write **the keys/values v1.56 actually reads** into `com.knollsoft.Hyperkey` (derive from step 1; do **not** reuse `enableHyperKey`/`tapForEscape`). Detect domain/version rather than hard-coding one assumption again.
3. **Ordering hazard:** Hyperkey rewrites its prefs on quit, so a write while it's running gets clobbered. Order: **quit Hyperkey → `defaults write` → relaunch → verify the values survive the restart.**
4. Fix the comment and `docs/keymap.md`. Before rewriting the comment, **reconstruct the real intent of commit `f17cf62` from its diff** — its message is about service-stop ordering / cask name / dequarantine and does NOT claim "newer Hyperkey uses the plain domain," so don't assert that motive.
5. Verify **live, observed** (not assumed): caps+t→Ghostty, caps+b→Helium (confirm Helium is installed, else the binding fails regardless), plus a focus chord. Reload AeroSpace with caps+Enter.
6. Regression guard (in `ws-doctor` and/or `tests/`): assert the bootstrap writes the keys the **installed** Hyperkey version reads, pinned to bundle id `com.knollsoft.Hyperkey`.
7. **hidutil fallback — RESEARCH ONLY, report back, do NOT ship yet (my decision):** the keymap rides entirely on Hyperkey (a DriverKit virtual-HID remapper). Investigate the current status of reported macOS DriverKit-HID breakage on **built-in** MacBook keyboards (external unaffected) and whether a `hidutil` LaunchAgent fallback for basic Caps→Esc/Ctrl is warranted. Summarize findings + a recommendation; I'll decide whether to add it.

## Goal C — Machine COMPLETELY updated after every bootstrap, idempotently
Today macOS gets package *installs* but **zero updates** (Ubuntu runs `apt upgrade`; macOS runs nothing). **Decision: no `mas` / App Store apps — skip them.**
1. **Brewfile (core, tracked):** read the actual inline `brew install` block in `phase_packages` and capture its exact formulae + casks (use the **real** font cask name from the file, don't guess) into `~/dotfiles/macos/Brewfile`. This is the **shared env** set — it MUST include the browser caps+b opens (**Helium**) so the Air gets it. Replace the inline block with `brew bundle --file=…`. Keep `BOOTSTRAP_SKIP_CASKS`.
2. **`Brewfile.local` (untracked, per-machine heavy apps):** add `macos/Brewfile.local` to `.gitignore` (mirror the existing `~/.gitconfig.local` pattern). In `phase_packages`, after the core bundle, run `brew bundle --file=macos/Brewfile.local` **if it exists**. On this M3, seed `Brewfile.local` with the heavy apps (e.g. **OrbStack**) and REMOVE them from core. The Air simply has no `Brewfile.local`, so it stays lean. Document this in `docs/architecture.md`.
3. **Upgrades in-flow:** add `brew upgrade && brew cleanup`, and `mise install && mise upgrade` (macOS currently skips mise entirely; config `~/.config/mise/config.toml`). Idempotent, TTY-aware.
4. **System updates:** add an Xcode Command Line Tools **guard** before `phase_packages` (brew needs it), and a step that checks `softwareupdate -l` and, with a TTY, surfaces/applies updates — prompt, never force a silent reboot.
5. **Standalone entrypoint:** `~/dotfiles/bin/update-system` (sources `lib/common.sh`) running the full sweep — `brew update && upgrade && cleanup`, `mise upgrade`, `softwareupdate`. Add a `zshrc` alias `update-sys`. Bootstrap calls the same logic (one source of truth). Don't include global npm/pip refresh unless you find I actually rely on global packages beyond corepack/rune.
6. Update `docs/architecture.md` **and** the README for the new phases.

## Goal D — macOS env parity: RECONCILE both Macs, then codify (⚠️ ASK ME)
`phase_apply` is named "deploy configs & defaults" but applies no `defaults`. Add a curated, idempotent layer that gives both Macs the **same agreed-on defaults**. The M3 values below are the *starting baseline* — **do NOT assume M3 wins.** The M1/Air may have settings I prefer and want on both.

0. **Reconcile + ASK — do this BEFORE writing the script.** Read the **local machine's** current value for every domain/key in step 1, diff against the M3 baseline embedded below, and **present me a table of every DIFFERENCE** (setting · M3 value · M1/Air value · your recommendation). **Ask me which value becomes canonical for each difference** before codifying anything. Settings that already match need no question; never silently overwrite the other machine. This works whichever Mac you run on — the M3 baseline lives in this doc, so read the live machine and compare. (Appearance = Dark is the one safe assumption: I want Dark on both regardless.)
1. Create `~/dotfiles/macos/macos-defaults.sh` (`set -euo pipefail`, sources `lib/common.sh`, idempotent, safe to re-run unconditionally). Call it from `phase_apply`. Encode the **agreed canonical values from step 0**. The M3 baseline (starting point — confirm or override per step 0; re-read live to verify `AppleHighlightColor` and the correct trackpad domain):

   - **Appearance (the drift I care about):** `defaults write -g AppleInterfaceStyle Dark`; `defaults write -g AppleAccentColor -int -1` (graphite). Note: setting `AppleInterfaceStyle` fully applies after logout/login (or toggle via `osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'`).
   - **Keyboard:** `KeyRepeat=2`, `InitialKeyRepeat=15`, `ApplePressAndHoldEnabled=true` (this M3 has press-and-hold ON — mirror it, set explicit `true` so the Air matches), `AppleShowAllExtensions=true`. (All `-g` / `NSGlobalDomain`.)
   - **Dock (`com.apple.dock`):** `autohide=true`, `tilesize=42`, `show-recents=false`, `mru-spaces=false`, `orientation=bottom`.
   - **Finder (`com.apple.finder`):** `FXPreferredViewStyle=clmv` (column view), `FXDefaultSearchScope=SCcf` (search current folder).
   - **Trackpad:** tap-to-click is **OFF** on this M3 — mirror it: set `Clicking=false` on both `com.apple.AppleMultitouchTrackpad` and `com.apple.driver.AppleBluetoothMultitouch.trackpad`, and `-g com.apple.mouse.tapBehavior 0`.
   - **Screenshots:** this M3 uses macOS defaults — **do not** impose a custom location/format.
   - Finish: `killall Dock Finder SystemUIServer 2>/dev/null || true`.

2. **Document hard limits** in the script header and a new `docs/macos-defaults.md`: `defaults write` can't script display arrangement, some pmset items, or sqlite-backed/hardened Settings panes; some keyboard/trackpad changes need a logout; appearance applies on next login; changes need the `killall` to show. **Wallpaper is NOT reliably scriptable and historically leans on iCloud** — since the Air is signed out, treat wallpaper parity as a **manual one-time set on the Air**, not part of this script (note it in the doc).
3. App-pref parity (optional, later): prefer per-app `defaults export <domain> <file>` into `configs/`. Don't use mackup (symlink mode broken on macOS 14+).

## Cleanup (low-risk, alongside)
- Delete orphaned `~/.config/chezmoi/`.
- Delete stale backups after confirming nothing references them: `~/.skhdrc.osd-backup`, `~/.config/nvim.lazyvim-backup/`. Ask me if either looks load-bearing.
- **Untracked `~/.local/bin` scripts** — `ws-launch-terminal/browser/notes/inbox` and `rune` exist on disk but aren't in the repo. Determine if they're generated (sigil/rune) or hand-written, then **track them** so the Air gets them (they may be wired to caps chords!) or document why not. Don't lose them.
- `~/.gitconfig.local` (untracked name/email stub) — leave untracked; confirm the include resolves.

## Per-device verification checklist (run on M3 and Air)
- [ ] `ws-doctor` clean.
- [ ] caps+t→Ghostty, caps+b→Helium, a caps focus chord — **observed live**.
- [ ] `defaults read com.knollsoft.Hyperkey` shows working keys; regression guard passes; values survive a Hyperkey restart.
- [ ] **Appearance is Dark** on both machines.
- [ ] Keyboard, Dock, Finder, trackpad, accent — all match the **agreed canonical set** (Goal D step 0) on both machines.
- [ ] Re-run `macos/bootstrap.sh`: no-op for configs **and** `brew outdated`/`mise outdated` empty after.
- [ ] `update-system` runs end-to-end; `update-sys` alias works.
- [ ] `brew bundle check --file=~/dotfiles/macos/Brewfile` satisfied; Air has **no** `Brewfile.local` (stays lean); M3's heavy apps (OrbStack) come from its `Brewfile.local`.
- [ ] Every deployed config `cmp`-matches `configs/` source.
- [ ] No orphaned chezmoi dir / stale backups; `ws-launch-*` tracked-or-documented.

## Acceptance criteria
1. Caps chords (incl. t/b) work, with a committed regression guard; hidutil fallback **researched and reported** (not shipped).
2. Bootstrap idempotent for config **and** brings the machine fully current every run, with a standalone `update-system`. No `mas`.
3. `macos-defaults.sh` in `phase_apply` encodes the **agreed canonical defaults** (reconciled M3 + M1, my choices); both Macs converge (Dark mode synced).
4. Packages: core `macos/Brewfile` (shared env, incl. Helium) + per-machine untracked `Brewfile.local` (heavy apps); Air stays lean.
5. Cleanup done, nothing untracked lost; `architecture.md` + README + `macos-defaults.md` reflect reality.
6. One commit per change on a branch; no machine left worse.

## Decisions already made (don't re-ask)
- **Not chezmoi** — custom bash bootstrap; introduce no framework.
- **Env identical, apps & data per-machine.** Heavy apps → untracked `Brewfile.local`; OrbStack is M3-only.
- **macOS defaults = reconcile M3 + M1, then ASK me per difference.** The M3 values (above) are the starting baseline, not the final word — the M1/Air may have settings I want on both. Both machines converge to the agreed canonical set. (Dark mode on both is the one given.)
- **No `mas` / App Store sync.**
- **hidutil fallback = research only**, report back, don't ship.
- Air is signed out of Apple ID — fine; parity is script-driven, not iCloud. Wallpaper parity is manual on the Air.
