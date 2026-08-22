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

echo ""
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
