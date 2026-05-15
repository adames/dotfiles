#!/usr/bin/env bash
# ws-launch-inbox — open the user's "Inbox" note for quick capture.
#
# Bound to Caps+Shift+q in skhdrc. Same auto-detect-with-override
# philosophy as ws-launch-terminal / ws-launch-notes — the keymap layer
# stays free of app-specific assumptions.
#
# Detection order:
#   1. $WS_INBOX_APP env var — explicit override.
#        - If it contains '://' it's treated as a URL.
#        - Otherwise it's `open -a "$WS_INBOX_APP"`.
#   2. Obsidian: discover the vault from
#      ~/Library/Application Support/obsidian/obsidian.json (vault dir
#      basename), then `open obsidian://new?vault=<NAME>&file=Inbox&append`.
#      $WS_INBOX_VAULT overrides vault auto-detection.
#      $WS_INBOX_NOTE overrides the note name (default: "Inbox").
#   3. Apple Notes — `open notes://`.
#
# No <VAULT> placeholders — every reachable path is fully resolved at run
# time. Loud failure (osascript notification) if nothing is reachable.

set -u

note="${WS_INBOX_NOTE:-Inbox}"

# 1. Explicit override.
if [[ -n "${WS_INBOX_APP:-}" ]]; then
  app="$WS_INBOX_APP"
  if [[ "$app" == *"://"* ]]; then
    open "$app" >/dev/null 2>&1 && exit 0
  else
    open -a "$app" >/dev/null 2>&1 && exit 0
  fi
  osascript -e "display notification \"WS_INBOX_APP set but '$app' didn't open\" with title \"ws-launch-inbox\"" >/dev/null 2>&1 || true
  exit 1
fi

# 2. Obsidian path: app present, vault resolvable.
obsidian_installed=false
if [[ -d "/Applications/Obsidian.app" || -d "$HOME/Applications/Obsidian.app" ]]; then
  obsidian_installed=true
fi

if $obsidian_installed; then
  vault="${WS_INBOX_VAULT:-}"

  # Auto-detect: read the first vault path from obsidian.json. The
  # config file shape is {"vaults": {"<id>": {"path": "...", "ts": ...}}}.
  # We extract the first path's basename — that's the vault name
  # Obsidian uses in its URL scheme.
  if [[ -z "$vault" ]]; then
    cfg="$HOME/Library/Application Support/obsidian/obsidian.json"
    if [[ -r "$cfg" ]] && command -v python3 >/dev/null 2>&1; then
      vault=$(python3 - "$cfg" <<'PY' 2>/dev/null
import json, os, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
vaults = data.get("vaults") or {}
# Open vaults are flagged with "open": true. Prefer those; otherwise
# fall back to the first listed vault.
chosen = next(
    (v for v in vaults.values() if v.get("open")),
    next(iter(vaults.values()), None)
)
if chosen and chosen.get("path"):
    print(os.path.basename(chosen["path"].rstrip("/")))
PY
      )
    fi
  fi

  if [[ -n "$vault" ]]; then
    # URL-encode the vault and note names. Spaces and most special
    # chars need escaping in the obsidian:// URL.
    enc_vault=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$vault")
    enc_note=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$note")
    open "obsidian://new?vault=$enc_vault&file=$enc_note&append=true" >/dev/null 2>&1 && exit 0
  fi
fi

# 3. Apple Notes fallback. `notes://` activates the app; macOS opens the
# last-viewed note. Not perfect ("Inbox" semantics are lost) but the
# user always has somewhere to capture.
if open "notes://" >/dev/null 2>&1; then
  exit 0
fi

osascript -e 'display notification "no inbox app reachable (try setting $WS_INBOX_APP or $WS_INBOX_VAULT)" with title "ws-launch-inbox"' >/dev/null 2>&1 || true
exit 1
