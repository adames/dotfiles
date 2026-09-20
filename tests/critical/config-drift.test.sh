#!/usr/bin/env bash
# Critical test: the deploy manifest and the drift check that reads it.
#
# Was two files grepping each other's source for keywords — "does ws-doctor
# contain the string check_source_deploy_drift", "does bootstrap contain
# install_file". Tests like that pass while the thing they name is broken,
# which is exactly what happened: the suite reported three healthy checks
# while two of them scanned for AppleScript the repo no longer contained.
# These assert behaviour instead — deploy into a throwaway HOME and look at
# what lands.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"

pass=0; fail=0

echo "=== config-drift.test.sh ==="

DOTFILES_DIR="$REPO_ROOT"
. "$REPO_ROOT/lib/common.sh" 2>/dev/null || {
  echo "FAIL: cannot source lib/common.sh"
  echo ""
  echo "0 passed, 1 failed"
  exit 1
}

# 1. Every source in the manifest exists. A manifest entry pointing at a
#    file that was renamed or deleted deploys nothing and warns forever.
test_manifest_sources_exist() {
  local n=0 gone=0 src
  while IFS='|' read -r src _; do
    [[ -n "$src" ]] || continue
    n=$((n + 1))
    [[ -f "$src" ]] || { echo "FAIL: manifest source missing: ${src#"$REPO_ROOT"/}"; gone=$((gone + 1)); }
  done < <(config_manifest)

  # >= 10: the count is the coverage. A regression to a hand-kept list is
  # what this floor catches — the last one covered 2 of 13 files.
  if (( n >= 10 && gone == 0 )); then
    echo "PASS: all $n manifest sources present"
    ((pass++))
  else
    echo "FAIL: manifest has $n entries ($gone missing sources; expected >= 10, 0 missing)"
    ((fail++))
  fi
}

# 2. deploy_configs actually deploys the manifest — into a throwaway HOME,
#    so this is the real code path and not a grep for its name.
test_deploy_configs_deploys_manifest() {
  local tmp; tmp="$(mktemp -d)"
  # The two network/identity helpers deploy_configs calls are not under
  # test: one clones a repo, the other writes a stub.
  ensure_claude_skills() { :; }
  ensure_gitconfig_local() { :; }

  local expected=0 landed=0 dst
  ( HOME="$tmp" deploy_configs ) >/dev/null 2>&1
  while IFS='|' read -r src dst _; do
    [[ -n "$src" ]] || continue
    expected=$((expected + 1))
    [[ -f "$dst" ]] && landed=$((landed + 1))
  done < <(HOME="$tmp" config_manifest)
  rm -rf "$tmp"

  if (( expected > 0 && landed == expected )); then
    echo "PASS: deploy_configs deployed $landed/$expected manifest entries"
    ((pass++))
  else
    echo "FAIL: deploy_configs deployed $landed/$expected manifest entries"
    ((fail++))
  fi
}

# 3. ws-doctor reports on the whole manifest, not a subset of it.
test_doctor_covers_manifest() {
  if [[ ! -x "$DOCTOR" ]]; then
    echo "FAIL: ws-doctor missing or not executable"
    ((fail++))
    return
  fi
  local manifest_n doctor_n out
  manifest_n=$(config_manifest | grep -c .)
  out=$("$DOCTOR" 2>&1)
  # Every closing line carries "<total> configs" — "17 configs in sync",
  # "17 configs: 2 not deployed", "1 of 17 configs drifted" — so this reads
  # coverage whether the machine is clean, drifted, or (as on CI) has
  # nothing deployed at all.
  doctor_n=$(sed -nE 's/.*[^0-9]([0-9]+) configs.*/\1/p' <<<"$out" | tail -1)

  if [[ "$doctor_n" == "$manifest_n" ]] && (( manifest_n >= 10 )); then
    echo "PASS: ws-doctor covers all $doctor_n manifest entries"
    ((pass++))
  else
    echo "FAIL: ws-doctor covered '${doctor_n:-?}' of $manifest_n manifest entries"
    echo "$out" | sed 's/^/       /'
    ((fail++))
  fi
}

# 4. ws-doctor's own contract: --help works, and a run exits with the
#    drift count rather than crashing.
test_doctor_runs() {
  [[ -x "$DOCTOR" ]] || return

  if "$DOCTOR" --help 2>/dev/null | grep -q 'ws-doctor'; then
    echo "PASS: ws-doctor --help prints usage"
    ((pass++))
  else
    echo "FAIL: ws-doctor --help prints nothing useful"
    ((fail++))
  fi

  local out exit_code
  out=$("$DOCTOR" --quiet 2>&1); exit_code=$?
  # Exit code IS the drift count, so anything above the manifest size means
  # it died rather than counted.
  if (( exit_code <= $(config_manifest | grep -c .) )); then
    echo "PASS: ws-doctor --quiet exited $exit_code (drift count)"
    ((pass++))
  else
    echo "FAIL: ws-doctor --quiet exited $exit_code"
    echo "$out" | sed 's/^/       /'
    ((fail++))
  fi
}

test_manifest_sources_exist
test_deploy_configs_deploys_manifest
test_doctor_covers_manifest
test_doctor_runs

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
