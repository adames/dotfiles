#!/usr/bin/env bash
# yabai scripting-addition installer + sudoers entry.
#
# Run this AFTER you have disabled SIP from Recovery Mode. The script:
#   1. Verifies SIP is sufficiently disabled for SA to load
#   2. `sudo yabai --load-sa` (yabai 7.x merged install + load into one
#      command; writes the SA bundle into Dock.app and loads it now)
#   3. Writes /etc/sudoers.d/yabai so yabai can `--load-sa` at login
#      without a password prompt (hash-pinned to the current yabai binary)
#   4. Restarts yabai
#   5. Verifies the SA actually loaded by attempting a space create/destroy
#
# Re-run any time yabai is upgraded by brew — the sudoers hash needs to
# match the new binary, otherwise the SA won't auto-load and you'll lose
# `--space --create`, fullscreen, sticky, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

# --force re-runs the install even when the SA is already loaded. Use it
# after a yabai upgrade so the sudoers hash gets re-pinned to the new
# binary; without --force the idempotency gate below skips the work.
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

section "yabai SA installer (Apple Silicon · macOS Sequoia · run AFTER SIP disable in Recovery)"

# ── 1. Prerequisite checks ────────────────────────────────────────────────
section "1. Preflight"

have yabai || { err "yabai not found in PATH"; exit 1; }
YABAI_BIN="$(which yabai)"
YABAI_HASH="$(shasum -a 256 "$YABAI_BIN" | awk '{print $1}')"
USER_NAME="$(whoami)"
step "yabai     : $YABAI_BIN"
step "version   : $(yabai --version)"
step "hash      : $YABAI_HASH"
step "user      : $USER_NAME"

SIP_STATUS="$(csrutil status 2>&1 || true)"
step "SIP       : ${SIP_STATUS#System Integrity Protection status: }"

# SA load needs at minimum: filesystem protection off (--without fs) or
# full disable. Catch the obvious "still fully enabled" case before
# letting `yabai --load-sa` fail noisily.
if grep -q 'enabled.$' <<<"$SIP_STATUS"; then
  err "SIP is still fully enabled. The SA cannot be installed."
  cat <<EOF >&2

  To disable SIP on Apple Silicon:
    1. shut down: 'sudo shutdown -h now'
    2. hold the power button until "Loading startup options"
    3. Options → Continue → admin login
    4. menu bar: Utilities → Terminal
    5. 'csrutil disable'   → 'y' → admin password
    6. reboot
    7. open Terminal in normal session and re-run this script

EOF
  exit 1
fi

# Apple Silicon: yabai is arm64, Dock.app is arm64e. Cross-ABI mach
# injection requires the arm64e_preview_abi boot-arg. Without it, the
# --load-sa call succeeds but Dock silently rejects the SA and every
# --create / --destroy / fullscreen call fails. Detect and offer to set.
ARCH="$(uname -m)"
step "arch      : $ARCH"
if [[ "$ARCH" == "arm64" ]]; then
  BOOT_ARGS="$(nvram boot-args 2>/dev/null | awk '{$1=""; print $0}' | xargs || true)"
  step "boot-args : ${BOOT_ARGS:-<unset>}"
  if [[ "$BOOT_ARGS" != *"-arm64e_preview_abi"* ]]; then
    warn "missing nvram boot-arg '-arm64e_preview_abi' (required on Apple Silicon)"
    cat <<EOF >&2

  Set it and reboot:
    sudo nvram boot-args="-arm64e_preview_abi"
    sudo reboot

  Then re-run this script.

EOF
    exit 1
  fi
fi

# ── 1b. Idempotency gate ──────────────────────────────────────────────────
# Skip the load-sa dance (and its sudo prompt) when the SA is already
# loaded. Canonical probe: `yabai -m space --create` only succeeds when
# Dock has accepted the SA injection — that's exactly the property we'd
# verify at the end anyway, so checking it up front is cheap and lets
# rerunning this script after a working install exit in <100ms.
#
# Bypass with --force to re-pin the sudoers hash after a yabai upgrade
# (the new binary hash won't match the pinned entry).
if (( FORCE == 0 )) && pgrep -x yabai >/dev/null 2>&1; then
  section "1b. idempotency check"
  PRE_COUNT="$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
  CREATE_OUT="$(yabai -m space --create 2>&1 || true)"
  if [[ -n "$CREATE_OUT" && "$CREATE_OUT" != *"scripting-addition"* \
        && "$CREATE_OUT" != *"cannot"* && "$CREATE_OUT" != *"could not"* ]] \
     || [[ -z "$CREATE_OUT" ]]; then
    POST_COUNT="$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
    if [[ "$POST_COUNT" -gt "$PRE_COUNT" ]]; then
      yabai -m space --destroy "$POST_COUNT" >/dev/null 2>&1 || true
    fi
    ok "yabai SA already loaded — nothing to do"
    printf "      rerun with --force after a yabai upgrade to re-pin the sudoers hash\n"
    exit 0
  fi
  step "SA not loaded yet — proceeding with full install"
fi

# ── 2. Install + load the scripting addition ──────────────────────────────
section "2. sudo yabai --load-sa"
printf "      yabai 7.x installs + loads the SA into Dock.app in one shot; SIP-disable required\n"
# Note: the sudoers entry doesn't exist yet, so this WILL prompt for password
# the first time. After the entry below is in place, future --load-sa runs
# (including yabai's auto-load at login) are passwordless.
sudo yabai --load-sa
ok "SA installed and loaded"

# ── 3. /etc/sudoers.d/yabai ───────────────────────────────────────────────
section "3. sudoers entry (hash-pinned)"

SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SUDOERS_TMP"' EXIT

cat >"$SUDOERS_TMP" <<EOF
# Generated by ~/dotfiles/macos/yabai-sa-install.sh
# Allows yabai to load its scripting-addition into Dock without a password
# prompt at login. Hash-pinned: re-run this script after any yabai upgrade.
$USER_NAME ALL=(root) NOPASSWD: sha256:$YABAI_HASH $YABAI_BIN --load-sa
EOF

# Validate before installing — visudo -c rejects bad syntax / wrong hash format.
if ! sudo visudo -c -q -f "$SUDOERS_TMP"; then
  err "generated sudoers file failed visudo validation; aborting"
  cat "$SUDOERS_TMP" >&2
  exit 1
fi

sudo install -o root -g wheel -m 0440 "$SUDOERS_TMP" /etc/sudoers.d/yabai
ok "/etc/sudoers.d/yabai installed"
printf "      user=$USER_NAME · sha256=${YABAI_HASH:0:12}…\n"

# ── 4. Restart yabai ──────────────────────────────────────────────────────
section "4. restart yabai"
yabai --restart-service
sleep 1
launchctl list | grep -q com.asmvik.yabai && ok "yabai is running" || warn "yabai not in launchctl list"

# ── 5. Verify SA loaded ───────────────────────────────────────────────────
section "5. verify SA loaded"
PRE_COUNT="$(yabai -m query --spaces | jq 'length')"
step "spaces before test: $PRE_COUNT"

CREATE_OUT="$(yabai -m space --create 2>&1 || true)"
if [[ "$CREATE_OUT" == *"scripting-addition"* ]]; then
  err "SA did not load. yabai still rejects --create."
  err "Output: $CREATE_OUT"
  cat <<EOF >&2

  Common causes:
   - Apple Silicon also needs: sudo nvram boot-args="-arm64e_preview_abi"
     followed by a reboot. Try that and re-run this script.
   - SIP was not disabled enough — full 'csrutil disable' is the safe option.
   - sudoers hash doesn't match (yabai got upgraded between SA install and now).

EOF
  exit 1
fi

POST_COUNT="$(yabai -m query --spaces | jq 'length')"
step "spaces after test:  $POST_COUNT"
# Roll back the test create so we don't leave a stray space behind.
if [ "$POST_COUNT" -gt "$PRE_COUNT" ]; then
  yabai -m space --destroy "$POST_COUNT" 2>/dev/null || true
  printf "      destroyed test space; back to $PRE_COUNT\n"
fi

ok "SA verified loaded · yabai can manage spaces"

section "done"
ok "log out / log in (or run 'yabai --restart-service') and the yabairc 5-space bootstrap will run"
