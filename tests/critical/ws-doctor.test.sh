#!/usr/bin/env bash
# Critical test: ws-doctor core functionality
# Health check must catch all known failure modes

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_ROOT/bin/ws-doctor"
# The check bodies live in lib/ws-doctor-checks.sh (sourced by ws-doctor);
# the keyword greps below scan both so a moved check still counts.
CHECKS_LIB="$REPO_ROOT/lib/ws-doctor-checks.sh"
DOCTOR_SRC=("$DOCTOR" "$CHECKS_LIB")

pass=0; fail=0

# Test 1: ws-doctor exists and is executable
test_doctor_exists() {
  if [[ -x "$DOCTOR" ]]; then
    echo "PASS: ws-doctor exists and is executable"
    ((pass++))
  else
    echo "FAIL: ws-doctor missing or not executable"
    ((fail++))
  fi
}

# Test 2: Doctor has --help
test_doctor_help() {
  if "$DOCTOR" --help &>/dev/null || "$DOCTOR" -h &>/dev/null; then
    echo "PASS: ws-doctor supports --help"
    ((pass++))
  else
    echo "FAIL: ws-doctor does not support --help/-h"
    ((fail++))
  fi
}

# Test 3: the drift check is registered AND actually covers every deployed
# config. The old version of this test grepped the source for check-name
# keywords, which is why it kept reporting three healthy checks while two
# of them had been scanning for AppleScript patterns the repo no longer
# contained. Assert observable behaviour instead: the check must appear in
# --list, and a real run must report a pair count in double digits (it
# derives them from macos/bootstrap.sh's install_file calls — a regression
# to a hand-maintained list would drop it back to 2).
test_doctor_drift_check_covers_all_configs() {
  if [[ ! -x "$DOCTOR" ]]; then
    echo "SKIP: ws-doctor not executable"
    return 0
  fi

  if ! "$DOCTOR" --list 2>/dev/null | grep -q '^source-deploy-drift'; then
    echo "FAIL: source-deploy-drift not registered in CHECKS"
    ((fail++))
    return 0
  fi

  local out count
  out=$("$DOCTOR" --only=source-deploy-drift 2>&1)
  # Every outcome leads with "<N> configs ...", so this reads the coverage
  # count whether the machine is clean, drifted, or (as on CI) has nothing
  # deployed at all.
  count=$(sed -nE 's/.*[[:space:]]([0-9]+) configs.*/\1/p' <<<"$out" | head -1)

  if [[ -n "$count" ]] && (( count >= 10 )); then
    echo "PASS: drift check covers $count deployed configs"
    ((pass++))
  else
    echo "FAIL: drift check covered '${count:-?}' configs (expected >= 10)"
    echo "$out" | sed 's/^/       /'
    ((fail++))
  fi
}

# Test 4: Doctor can run (may return non-zero if issues found, but shouldn't crash)
test_doctor_runs() {
  if [[ ! -x "$DOCTOR" ]]; then
    return 0
  fi

  # `timeout` is GNU coreutils; CI (ubuntu-latest) has it built in, but
  # plain macOS doesn't ship it (Homebrew's coreutils installs it as
  # `gtimeout` to avoid clobbering nothing — there just isn't a native
  # one). Prefer a real timeout binary; fall back to running untimed
  # rather than silently no-op'ing the hang guard the way the old
  # `timeout 10 ... || timeout 10 ... | grep -q .` fallback did (that
  # matched "bash: timeout: command not found" on stderr as "output").
  local timeout_bin=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin="gtimeout"
  fi

  local out exit_code
  if [[ -n "$timeout_bin" ]]; then
    out=$("$timeout_bin" 10 "$DOCTOR" 2>&1)
  else
    out=$("$DOCTOR" 2>&1)
  fi
  exit_code=$?

  # A real, non-hanging run exits 0 (clean) or 1 (a single check
  # legitimately FAILed) and prints its actual summary line. 2+ means
  # either multiple checks failed or `timeout` killed it (124/137) —
  # not "any output", which a stack trace also satisfies.
  # Require at least one check to have actually RUN. The old assertion took
  # any summary line as success, so a doctor that couldn't source its own
  # libs — every check undefined — still reported
  # "summary: 0 pass · 0 warn · 0 fail · 0 skip" and passed this test.
  # Sum all four buckets: on CI nothing is deployed, so the only check
  # legitimately WARNs and "pass" is 0. What must never happen is every
  # bucket reading 0 — that's the signature of a doctor that couldn't
  # source its checks yet still printed a summary.
  local ran
  # [^0-9]+ for the separators, not ".": the renderer joins them with "·",
  # which is two bytes in UTF-8, and CI runs under LC_ALL=C where "." matches
  # a single byte and the whole pattern silently fails to match.
  ran=$(sed -nE 's/.*summary: ([0-9]+) pass[^0-9]+([0-9]+) warn[^0-9]+([0-9]+) fail[^0-9]+([0-9]+) skip.*/\1+\2+\3+\4/p' <<<"$out" | head -1)
  ran=$(( ${ran:-0} ))
  if (( exit_code <= 1 )) && (( ran >= 1 )); then
    echo "PASS: ws-doctor executes cleanly and emits its summary line"
    ((pass++))
  else
    echo "FAIL: ws-doctor exited $exit_code or didn't emit a summary line"
    ((fail++))
  fi
}

# Run tests
echo "=== ws-doctor.test.sh ==="
test_doctor_exists
test_doctor_help
test_doctor_drift_check_covers_all_configs
test_doctor_runs

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
