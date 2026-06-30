# lib/macos-tcc.sh — macOS TCC (Transparency, Consent, Control) probes.
#
# Detection-only. No prompts, no side effects. Every function returns 0 on
# "granted / running" and non-zero otherwise. Probes are cheap so callers can
# poll them in a tight loop without worrying about overhead.
#
# References:
#   - pgrep for AeroSpace.app + Hyperkey.app liveness
#   - TCC.db reads via sqlite3 for generic auth-value lookups (reads are
#     safe — Apple invalidates writes, not reads). Requires Terminal/iTerm
#     to have Full Disk Access; falls back to a behavioral probe when the
#     read fails.
#
# Source it: `. "$DOTFILES_DIR/lib/macos-tcc.sh"`

set -u

# ---- TCC.db read helper -----------------------------------------------------
# Internal. Returns auth_value (0=denied, 1=unknown, 2=allowed) for a given
# service+client query. Empty string on failure (no Full Disk Access, etc.).
_tcc_auth() {
  local service="$1" client_like="$2"
  # System-scoped services (Accessibility, screen capture, HID event taps)
  # are stored in the ROOT-owned system TCC.db; per-app services live in the
  # per-user db. Reading EITHER needs the calling terminal to have Full Disk
  # Access — callers fall back to a behavioral probe on an empty/failed read.
  local db
  case "$service" in
    kTCCServiceAccessibility|kTCCServiceScreenCapture|kTCCServiceListenEvent|kTCCServicePostEvent)
      db="/Library/Application Support/com.apple.TCC/TCC.db" ;;
    *)
      db="$HOME/Library/Application Support/com.apple.TCC/TCC.db" ;;
  esac
  [[ -r "$db" ]] || return 1
  sqlite3 "$db" \
    "SELECT auth_value FROM access WHERE service='$service' AND client LIKE '$client_like' LIMIT 1;" \
    2>/dev/null
}

# ---- Hyperkey ---------------------------------------------------------------
# Hyperkey is a regular GUI app (no daemon split, no kext). The
# Accessibility grant is the only thing that matters; behavior is a live
# process + a non-zero TCC.db auth_value, with the process check as the
# fallback when Full Disk Access isn't granted to the terminal.
mac_hyperkey_accessibility_ok() {
  [[ "$(_tcc_auth kTCCServiceAccessibility '%Hyperkey%' 2>/dev/null)" == "2" ]] \
    && return 0
  pgrep -x Hyperkey >/dev/null 2>&1
}

# ---- AeroSpace --------------------------------------------------------------
# AeroSpace's Accessibility grant is what lets it move / focus windows; the
# process runs fine without it, so liveness alone is a false proxy. Probe the
# TCC grant (bundle id bobko.aerospace) with a live-process fallback for when
# the system db isn't readable.
mac_aerospace_accessibility_ok() {
  [[ "$(_tcc_auth kTCCServiceAccessibility '%aerospace%' 2>/dev/null)" == "2" ]] \
    && return 0
  pgrep -x AeroSpace >/dev/null 2>&1
}

# ---- generic "is this app's bundle in Accessibility?" probe -----------------
# Used by the wizard to decide which gates remain. Pass a TCC.db LIKE pattern
# for the client (e.g. '%karabiner%').
mac_tcc_granted() {
  local service="$1" client_like="$2"
  [[ "$(_tcc_auth "$service" "$client_like")" == "2" ]]
}
