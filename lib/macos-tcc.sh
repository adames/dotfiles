# lib/macos-tcc.sh — macOS TCC (Transparency, Consent, Control) probes.
#
# Detection-only. No prompts, no side effects. Every function returns 0 on
# "granted / running" and non-zero otherwise. Probes are cheap so callers can
# poll them in a tight loop without worrying about overhead.
#
# References:
#   - TCC.db reads via sqlite3 for generic auth-value lookups (reads are
#     safe — Apple invalidates writes, not reads). Accessibility rows live
#     in the SYSTEM db (/Library/Application Support/com.apple.TCC/TCC.db),
#     not the per-user one, so that's queried first. Either read requires
#     Terminal/iTerm to have Full Disk Access; when both reads fail the
#     probe returns non-zero and callers err toward prompting.
#
# Source it: `. "$DOTFILES_DIR/lib/macos-tcc.sh"`

set -u

# ---- TCC.db read helper -----------------------------------------------------
# Internal. Prints auth_value (0=denied, 1=unknown, 2=allowed) for a given
# service+client query. System db first (kTCCServiceAccessibility lives
# there), then the user db. Non-zero + no output on failure (no Full Disk
# Access, no matching row, etc.).
_tcc_auth() {
  local service="$1" client_like="$2" db val
  for db in "/Library/Application Support/com.apple.TCC/TCC.db" \
            "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; do
    [[ -r "$db" ]] || continue
    # Single-quotes doubled per SQL escaping. Both args are literals at
    # every call site today, so this is belt-and-braces — but a probe that
    # ever takes a bundle id from the environment shouldn't be the place we
    # discover string interpolation into SQL.
    val="$(sqlite3 "$db" \
      "SELECT auth_value FROM access WHERE service='${service//\'/\'\'}' AND client LIKE '${client_like//\'/\'\'}' LIMIT 1;" \
      2>/dev/null)" || continue
    [[ -n "$val" ]] && { printf '%s\n' "$val"; return 0; }
  done
  return 1
}

# ---- generic "is this app's bundle in Accessibility?" probe -----------------
# Used by the wizard to decide which gates remain. Pass a TCC.db LIKE pattern
# for the client (e.g. '%karabiner%').
mac_tcc_granted() {
  local service="$1" client_like="$2"
  [[ "$(_tcc_auth "$service" "$client_like")" == "2" ]]
}
