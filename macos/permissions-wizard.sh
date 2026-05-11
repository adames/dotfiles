#!/usr/bin/env bash
# macos/permissions-wizard.sh — proactive permission-grant wizard.
#
# Walks the user through each macOS TCC gate the Hyper-key stack needs:
#   1. Pre-flight probes (skip everything already green)
#   2. Register apps so they appear in TCC lists (launch them once)
#   3. Accessibility batch: yabai → skhd → Hammerspoon → Karabiner-Elements
#   4. Input Monitoring batch: Karabiner-Elements, Karabiner-DriverKit
#   5. System Extension approval: Karabiner-DriverKit
#   6. Karabiner grabber re-kick
#   7. Final logout prompt (spans-displays requires fresh login)
#
# Each step polls its probe at 2 Hz with a 60s budget. On green, the
# AppleScript dialog auto-dismisses and the wizard advances. The user can
# Skip any individual gate; re-running the wizard picks up where they left off
# because state is derived from TCC probes, not a sentinel.
#
# Usage:
#   permissions-wizard.sh                  # full run
#   permissions-wizard.sh --step <name>    # single gate (see step names below)
#   permissions-wizard.sh --list           # print gate names

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
. "$DOTFILES_DIR/lib/common.sh"
. "$DOTFILES_DIR/lib/macos-tcc.sh"

WIZARD_LOG="$HOME/.local/state/hyper-bootstrap/wizard.log"
mkdir -p "$(dirname "$WIZARD_LOG")"
wlog() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$WIZARD_LOG"; }

# ---- gate definitions -------------------------------------------------------
# Each gate: name | human label | pane key | probe function
# Order matters — this is the sequence the wizard walks.
GATES=(
  "accessibility-yabai|yabai (Accessibility)|Privacy_Accessibility|mac_yabai_status_ok"
  "accessibility-skhd|skhd (Accessibility)|Privacy_Accessibility|mac_skhd_status_ok"
  "accessibility-hammerspoon|Hammerspoon (Accessibility)|Privacy_Accessibility|mac_hammerspoon_accessibility_ok"
  "accessibility-karabiner|Karabiner-Elements (Accessibility)|Privacy_Accessibility|mac_karabiner_accessibility_ok"
  "input-monitoring-karabiner|Karabiner-Elements (Input Monitoring)|Privacy_ListenEvent|mac_karabiner_input_monitoring_ok"
  "input-monitoring-driverkit|Karabiner-DriverKit-VirtualHIDDevice (Input Monitoring)|Privacy_ListenEvent|mac_driverkit_activated_ok"
  "system-extension-driverkit|Karabiner-DriverKit system extension|Privacy_SystemServices|mac_driverkit_activated_ok"
)

# Probe wrappers that return 0/non-zero (the lib's mac_*_status functions
# return enriched codes; we want a plain truthy result for the loop).
mac_yabai_status_ok() { mac_yabai_status; [[ $? -eq 0 ]]; }
mac_skhd_status_ok()  { mac_skhd_status;  [[ $? -eq 0 ]]; }

# ---- AppleScript dialog -----------------------------------------------------
# Shows a blocking modal with a 30-second timeout, so the outer poll loop
# re-renders the dialog about every half-minute (calm, not spammy). The
# background "Skip — already granted" button is for cases where the wizard's
# probe is broken but the user has confirmed the grant in Settings.
ws_dialog() {
  local title="$1" body="$2"
  osascript <<EOF 2>/dev/null || true
try
  set theResult to display dialog "$body" \
    with title "$title" \
    buttons {"Skip — already granted", "Open Pane Again"} \
    default button "Skip — already granted" \
    giving up after 30
  if gave up of theResult then
    return ""
  else
    return button returned of theResult
  end if
on error
  return ""
end try
EOF
}

# ---- one step ---------------------------------------------------------------
# wizard_step <step-index> <total> <gate-spec>
# Runs the dialog + poll loop for one gate. Returns:
#   0 = granted (probe went green)
#   1 = user skipped
#   2 = timeout / max retries
wizard_step() {
  local idx="$1" total="$2" gate="$3"
  local name=${gate%%|*}; rest=${gate#*|}
  local label=${rest%%|*}; rest=${rest#*|}
  local pane=${rest%%|*}; rest=${rest#*|}
  local probe=${rest}

  # Fast path: already granted.
  if "$probe"; then
    log "[$idx/$total] $label — already granted ✓"
    wlog "step $name already green"
    return 0
  fi

  wlog "step $name START"
  mac_open_privacy_pane "$pane"

  # Up to 8 dialog rounds (30s each = ~4 min total budget). The wizard
  # auto-advances the moment the probe goes green — the dialog is just a
  # visible cue while waiting.
  local budget=8
  local body="Step $idx of $total

Enable $label.

System Settings has been opened to the right pane. Toggle the entry ON and the wizard will detect it within ~30 seconds.

If you've already granted it but the wizard isn't picking it up, click \"Skip — already granted\"."

  while (( budget > 0 )); do
    if "$probe"; then
      log "[$idx/$total] $label — granted ✓"
      osascript -e 'tell application "System Events" to display notification "Granted ✓" with title "Hyper Bootstrap"' >/dev/null 2>&1 || true
      wlog "step $name GRANTED"
      return 0
    fi
    local button
    button=$(ws_dialog "Hyper Bootstrap Wizard" "$body")
    case "$button" in
      "Skip — already granted")
        warn "[$idx/$total] $label — skipped (user-confirmed)"
        wlog "step $name SKIPPED-USER"
        return 1
        ;;
      "Open Pane Again")
        mac_open_privacy_pane "$pane"
        ;;
      "")
        # 30s timeout elapsed without click — re-probe and loop
        :
        ;;
    esac
    budget=$((budget - 1))
  done
  warn "[$idx/$total] $label — timed out without grant"
  wlog "step $name TIMEOUT"
  return 2
}

# ---- phases -----------------------------------------------------------------
phase_register_apps() {
  log "registering apps in TCC lists (launch attempts, no prompts yet)"
  # Launching/attempting these causes macOS to add them to the relevant TCC
  # panes with toggles OFF, so the user just flips ON later — no dragging.
  have yabai && yabai --start-service >/dev/null 2>&1 || true
  have skhd  && skhd  --start-service >/dev/null 2>&1 || true
  [[ -d /Applications/Hammerspoon.app        ]] && open -ga Hammerspoon       2>/dev/null || true
  [[ -d /Applications/Karabiner-Elements.app ]] && open -ga Karabiner-Elements 2>/dev/null || true

  # If Hammerspoon was already running with a stale init.lua (e.g. fresh
  # bootstrap that just deployed our new init.lua), the pathwatcher inside
  # the OLD init.lua should reload — but the AppleScript bridge probe races
  # against that reload. Force a reload here and give it 3 seconds to settle
  # before the wizard probes.
  if pgrep -x Hammerspoon >/dev/null 2>&1; then
    osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' \
      >/dev/null 2>&1 || true
  fi
  sleep 3
}

phase_grant_permissions() {
  local total=${#GATES[@]}
  local idx=0 skipped=()
  for gate in "${GATES[@]}"; do
    idx=$((idx + 1))
    wizard_step "$idx" "$total" "$gate"
    case $? in
      1|2) skipped+=("${gate%%|*}") ;;
    esac
  done

  # Karabiner grabber re-kick now that the toggles are on.
  if launchctl list 2>/dev/null | grep -q "org.pqrs.service.daemon.karabiner_grabber"; then
    launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.daemon.karabiner_grabber" \
      >/dev/null 2>&1 || true
    log "karabiner_grabber kicked"
  fi
  # Karabiner console_user_server (note: label has ".agent." not ".service.")
  if launchctl list 2>/dev/null | grep -q "org.pqrs.service.agent.karabiner_console_user_server"; then
    launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server" \
      >/dev/null 2>&1 || true
    log "karabiner_console_user_server kicked"
  fi

  # Hammerspoon reload if running
  if pgrep -x Hammerspoon >/dev/null 2>&1; then
    osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' \
      >/dev/null 2>&1 || true
    log "Hammerspoon reloaded"
  fi

  if (( ${#skipped[@]} > 0 )); then
    warn "skipped gates: ${skipped[*]}"
    warn "re-run a single gate with:  ~/dotfiles/macos/permissions-wizard.sh --step <name>"
  fi
}

phase_finalize() {
  echo ""
  log "===== wizard summary ====="
  local total=${#GATES[@]} green=0 skipped=()
  for gate in "${GATES[@]}"; do
    local name=${gate%%|*}; rest=${gate#*|}
    local label=${rest%%|*}; rest=${rest#*|}
    local probe=${rest#*|}
    if "$probe"; then
      log "  ✓ $label"
      green=$((green + 1))
    else
      warn "  ✗ $label (skipped or not granted)"
      skipped+=("$name")
    fi
  done
  log "  $green / $total gates granted"

  # spans-displays logout gate
  if [[ "${HYPER_BOOTSTRAP_NEED_RELOGIN:-}" == "1" ]] \
     || [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" == "0" ]] \
     && ! mac_yabai_status; then
    if has_tty; then
      local choice
      choice=$(osascript <<'AS' 2>/dev/null || true
display dialog "Final step:

The 'Displays have separate Spaces' default was set, but macOS only re-reads it on a fresh login. yabai cannot start until you log out and back in.

Log out now? (Save your work first — macOS will ask you to confirm.)" \
  with title "Hyper Bootstrap Wizard" \
  buttons {"Later", "Log out now"} \
  default button "Later" \
  with icon caution
return button returned of the result
AS
)
      if [[ "$choice" == "Log out now" ]]; then
        log "logging out — see you on the other side"
        osascript -e 'tell application "System Events" to log out' || warn "log out canceled"
      else
        warn "remember: log out / log in to enable yabai's spans-displays change"
      fi
    else
      warn "log out / log in required to apply spans-displays change"
    fi
  fi

  cat <<EOF

================================================================
                       BOOTSTRAP COMPLETE
================================================================

  Cheatsheet:   press Caps+0 (Hammerspoon overlay), or open
                ~/Desktop/Hyper-Keys.html in any browser.

  Re-run wizard:
        ~/dotfiles/macos/permissions-wizard.sh
        ~/dotfiles/macos/permissions-wizard.sh --step <name>

  Verify the rest of the stack:
        tmux show -gv prefix                              # → C-a
        yabai -m query --windows | jq '.[].app'           # after login
        nvim --headless +'echo execute("nmap <Space>h")' +qa
================================================================
EOF
}

# ---- entry ------------------------------------------------------------------
list_steps() {
  for gate in "${GATES[@]}"; do
    printf '  %s\n' "${gate%%|*}"
  done
}

run_single_step() {
  local target="$1"
  local idx=0
  for gate in "${GATES[@]}"; do
    idx=$((idx + 1))
    if [[ "${gate%%|*}" == "$target" ]]; then
      wizard_step "$idx" "${#GATES[@]}" "$gate"
      return $?
    fi
  done
  err "unknown step: $target"
  echo "available steps:" >&2
  list_steps >&2
  return 64
}

main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "wizard is macOS-only"
    exit 1
  fi

  case "${1:-}" in
    --list)
      list_steps
      ;;
    --step)
      [[ -n "${2:-}" ]] || { err "--step requires a name (try --list)"; exit 64; }
      phase_register_apps
      run_single_step "$2"
      ;;
    "")
      phase_register_apps
      phase_grant_permissions
      phase_finalize
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--step <name> | --list]

Without args: runs the full wizard.

  --list           Show available step names.
  --step <name>    Run only the named step (after registering apps).
EOF
      ;;
    *)
      err "unknown arg: $1 (try --help)"
      exit 64
      ;;
  esac
}

main "$@"
