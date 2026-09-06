#!/usr/bin/env bash
# Critical test: Hyperkey seeding writes the v1.56 schema to the right
# defaults domain.
#
# Guards against the broken `defaults write Hyperkey enableHyperKey` era:
# bootstrap was writing to the wrong domain with keys the installed app
# doesn't read, so every caps chord silently died on a fresh install
# until the user re-toggled the switches by hand in the Hyperkey GUI.
#
# Static checks against macos/bootstrap.sh — no live system probing.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/macos/bootstrap.sh"

pass=0; fail=0

echo "=== hyperkey-defaults.test.sh ==="

# Every check here reads macos/bootstrap.sh, which a Linux clone prunes via
# sparse-checkout (lib/platform-manifest.sh). Skip only when the prune is the
# reason it's gone — a full clone (CI, any Mac) missing the file must still
# fail all seven ways.
if [[ ! -f "$BOOTSTRAP" ]] \
   && [[ "$(git -C "$REPO_ROOT" config --type=bool core.sparsecheckout 2>/dev/null)" == "true" ]]; then
  echo "SKIP: macos/bootstrap.sh pruned by sparse-checkout on this clone"
  echo ""
  echo "hyperkey-defaults: 0 passed, 0 failed"
  exit 0
fi

# 1. Writes the bundle-id domain (com.knollsoft.Hyperkey)
if grep -qE 'defaults write[[:space:]]+"?(com\.knollsoft\.Hyperkey|\$domain)"?' "$BOOTSTRAP" \
   && grep -qE 'domain="com\.knollsoft\.Hyperkey"' "$BOOTSTRAP"; then
  echo "PASS: bootstrap writes com.knollsoft.Hyperkey domain"
  ((pass++))
else
  echo "FAIL: bootstrap does not write com.knollsoft.Hyperkey domain"
  ((fail++))
fi

# 2. No obsolete Hyperkey/enableHyperKey writes leak back in
if grep -qE 'defaults write[[:space:]]+Hyperkey[[:space:]]+(enableHyperKey|tapForEscape)' "$BOOTSTRAP"; then
  echo "FAIL: bootstrap still writes obsolete Hyperkey/{enableHyperKey,tapForEscape} schema"
  ((fail++))
else
  echo "PASS: no obsolete Hyperkey domain writes"
  ((pass++))
fi

# 3. v1.56 schema keys all present
for key in capsLockRemapped keyRemap hyperFlags quickHyperKeycode executeQuickHyperKey; do
  if grep -qE "defaults write[[:space:]]+\"?\\\$?(domain|com\\.knollsoft\\.Hyperkey)\"?[[:space:]]+$key" "$BOOTSTRAP"; then
    echo "PASS: writes $key"
    ((pass++))
  else
    echo "FAIL: missing $key write"
    ((fail++))
  fi
done

# 4. Quit-before-write ordering — v1.56 rewrites prefs on quit, so a
#    write while it's running gets clobbered.
if awk '
  /tell application "Hyperkey" to quit/   { saw_quit = NR }
  /defaults write[[:space:]]+"?\$?(domain|com\.knollsoft\.Hyperkey)/ && !saw_write { saw_write = NR }
  END { exit (saw_quit && saw_write && saw_quit < saw_write) ? 0 : 1 }
' "$BOOTSTRAP"; then
  echo "PASS: Hyperkey quit precedes defaults write"
  ((pass++))
else
  echo "FAIL: Hyperkey not quit before defaults write (v1.56 will clobber)"
  ((fail++))
fi

echo ""
printf "hyperkey-defaults: %d passed, %d failed\n" "$pass" "$fail"
[[ $fail -eq 0 ]]
