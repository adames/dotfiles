# lib/macos-tcc.sh — macOS TCC (Transparency, Consent, Control) probes.
#
# Detection-only. No prompts, no side effects. Every function returns 0 on
# "granted / running" and non-zero otherwise. Probes are cheap so callers can
# poll them in a tight loop without worrying about overhead.
#
# References:
#   - pgrep for AeroSpace.app liveness
#   - TCC.db reads via sqlite3 for Karabiner (reads are safe — Apple
#     invalidates writes, not reads). Requires Terminal/iTerm to have Full
#     Disk Access; falls back to alternative probes when not granted.
#   - systemextensionsctl list for Karabiner-DriverKit-VirtualHIDDevice
#
# Source it: `. "$DOTFILES_DIR/lib/macos-tcc.sh"`

set -u

# Deep-link to System Settings panes. Pane keys we use:
#   Privacy_Accessibility, Privacy_ListenEvent (Input Monitoring),
#   Privacy_SystemServices (system extensions)
mac_open_privacy_pane() {
  local pane="${1:-Privacy_Accessibility}"
  open "x-apple.systempreferences:com.apple.preference.security?$pane" 2>/dev/null || true
}

# ---- AeroSpace --------------------------------------------------------------
# Return codes:
#   0 = AeroSpace.app process exists AND the CLI socket responds
#   1 = process missing or daemon not reachable
mac_aerospace_status() {
  pgrep -x AeroSpace >/dev/null 2>&1 || return 1
  command -v aerospace >/dev/null 2>&1 || return 1
  aerospace list-monitors --json >/dev/null 2>&1
}

# ---- TCC.db read helper -----------------------------------------------------
# Internal. Returns auth_value (0=denied, 1=unknown, 2=allowed) for a given
# service+client query. Empty string on failure (no Full Disk Access, etc.).
_tcc_auth() {
  local service="$1" client_like="$2"
  local db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  [[ -r "$db" ]] || return 1
  sqlite3 "$db" \
    "SELECT auth_value FROM access WHERE service='$service' AND client LIKE '$client_like' LIMIT 1;" \
    2>/dev/null
}

# ---- Karabiner core service -------------------------------------------------
# Internal: returns 0 if Karabiner-Core-Service-rev2 agent has a live PID.
# This is the modern Karabiner architecture (post-rev1); the service refuses
# to start without both Accessibility AND Input Monitoring granted, so a live
# PID is strong behavioral evidence that both TCC bits are on.
_mac_karabiner_core_running() {
  local pid
  pid=$(launchctl list 2>/dev/null \
        | awk '/org.pqrs.service.agent.Karabiner-Core-Service-rev2/{print $1}')
  [[ "$pid" =~ ^[0-9]+$ && "$pid" != "0" ]]
}

# ---- Karabiner Accessibility ------------------------------------------------
# Preferred: TCC.db read (needs Terminal Full Disk Access). Fallback:
# behavioral — Core-Service-rev2 agent running implies grant.
mac_karabiner_accessibility_ok() {
  [[ "$(_tcc_auth kTCCServiceAccessibility '%karabiner%' 2>/dev/null)" == "2" ]] \
    && return 0
  _mac_karabiner_core_running
}

# ---- Karabiner Input Monitoring --------------------------------------------
mac_karabiner_input_monitoring_ok() {
  [[ "$(_tcc_auth kTCCServiceListenEvent '%karabiner%' 2>/dev/null)" == "2" ]] \
    && return 0
  _mac_karabiner_core_running
}

# ---- Karabiner-DriverKit-VirtualHIDDevice system extension ------------------
# Authoritative probe: systemextensionsctl list. Look for the Karabiner
# DriverKit identifier in the "activated enabled" state.
mac_driverkit_activated_ok() {
  systemextensionsctl list 2>/dev/null | grep -qE 'Karabiner.*activated enabled'
}

# ---- generic "is this app's bundle in Accessibility?" probe -----------------
# Used by the wizard to decide which gates remain. Pass a TCC.db LIKE pattern
# for the client (e.g. '%karabiner%').
mac_tcc_granted() {
  local service="$1" client_like="$2"
  [[ "$(_tcc_auth "$service" "$client_like")" == "2" ]]
}
