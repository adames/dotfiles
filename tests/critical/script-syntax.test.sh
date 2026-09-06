#!/usr/bin/env bash
# Critical test: every shell script in the repo parses (bash -n).
#
# The bin/ tools (ws-doctor, update-system) and
# several configs/ helpers have no .sh extension, so an extension-only
# lint glob silently skipped the most complex scripts in the tree. This
# test selects scripts by content (bash/sh shebang) plus the known
# extensionless dotfiles, then parse-checks each one — so a syntax error
# in any script fails the suite locally, not just in CI.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

pass=0; fail=0

echo "=== script-syntax.test.sh ==="

# Collect candidate scripts: *.sh / zshrc / bashrc by name, plus any
# file whose first line is a bash/sh shebang. Skip VCS + build dirs.
scripts=()
while IFS= read -r -d '' f; do
  case "$f" in
    *.sh|*/zshrc|*/bashrc) scripts+=("$f") ;;
    *)
      IFS= read -r first < "$f" || first=""
      [[ "$first" == '#!'* ]] || continue
      [[ "$first" =~ (^|[^[:alnum:]])(ba)?sh([^[:alnum:]]|$) ]] && scripts+=("$f")
      ;;
  esac
done < <(find "$REPO_ROOT" -type f \
              -not -path '*/.git/*' -not -path '*/.build/*' -print0)

if (( ${#scripts[@]} == 0 )); then
  echo "FAIL: no shell scripts discovered (find/selection broke)"
  ((fail++))
fi

# Sanity floor: the four bin/ tools must be among the discovered set —
# guards against a future refactor that re-hides them from the linter.
for must in bin/update-system bin/ws-doctor; do
  found=
  for s in "${scripts[@]}"; do [[ "$s" == "$REPO_ROOT/$must" ]] && found=1 && break; done
  if [[ -n "$found" ]]; then
    echo "PASS: discovered $must"
    ((pass++))
  else
    echo "FAIL: $must not discovered by syntax linter"
    ((fail++))
  fi
done

for s in "${scripts[@]}"; do
  rel="${s#"$REPO_ROOT"/}"
  if bash -n "$s" 2>/tmp/syntax-err.$$; then
    ((pass++))
  else
    echo "FAIL: bash -n $rel"
    sed 's/^/    /' /tmp/syntax-err.$$
    ((fail++))
  fi
done
rm -f /tmp/syntax-err.$$

echo "PASS: parse-checked ${#scripts[@]} shell script(s)"
((pass++))

# macOS ships bash 3.2 and always will (bash went GPLv3 in 4.0, which
# Apple won't ship), so `#!/usr/bin/env bash` resolves to 3.2 on any Mac
# without brew's bash — which is every fresh Mac, since the Brewfile
# deliberately declares none. ws-doctor carried a `declare -A` for months,
# printing an error on every run, masked by brew's bash arriving as an
# accidental dependency of direnv. When direnv went, the error surfaced.
# --exclude this file: it names the constructs it is looking for, both in
# the pattern and in the comment above, and would otherwise flag itself.
bash4_hits="$(grep -rnE 'declare -A|local -A|mapfile |readarray ' \
  --include='*.sh' --include='ws-doctor' --include='update-system' \
  --include='backup-claude-memory' --include='tmux-sessionizer' \
  --exclude='script-syntax.test.sh' \
  "$REPO_ROOT" 2>/dev/null \
  | grep -v '/\.git/' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [[ -z "$bash4_hits" ]]; then
  echo "PASS: no bash-4-only constructs (macOS ships 3.2)"
  ((pass++))
else
  echo "FAIL: bash-4-only construct(s) — these break on stock macOS bash:"
  printf '%s\n' "$bash4_hits" | sed 's/^/       /'
  ((fail++))
fi

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
