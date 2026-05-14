#!/usr/bin/env bash
# Configure git sparse-checkout so a Linux clone only carries files it
# actually uses. Reads lib/platform-manifest.sh; excludes every path
# listed in MACOS_ONLY_PATHS from the working tree.
#
# Idempotent: re-running refreshes the pattern file from the current
# manifest, then re-applies sparse-checkout. Safe to run on every
# bootstrap; cheap when nothing changed.
#
# To opt out for a single clone:
#   git -C ~/dotfiles sparse-checkout disable
#
# To inspect the active rule set:
#   cat ~/dotfiles/.git/info/sparse-checkout

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# Only meaningful inside a git working tree.
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
  echo "sparse-checkout: $DOTFILES_DIR is not a git working tree — skipping"
  exit 0
fi

# macOS clones want the full repo (they build the Swift package, run
# karabiner, etc.). Bail out early so this never accidentally narrows a
# Mac checkout.
case "$(uname -s)" in
  Darwin) echo "sparse-checkout: macOS clone — full tree retained, skipping"; exit 0 ;;
esac

# Pull the manifest. Fail loudly if it's missing — the manifest is the
# entire contract.
manifest="$DOTFILES_DIR/lib/platform-manifest.sh"
if [[ ! -r "$manifest" ]]; then
  echo "sparse-checkout: manifest not found at $manifest" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$manifest"

cd "$DOTFILES_DIR"

# Use non-cone mode so we can subtract nested paths (e.g. configs/
# workspace/topology/ while still keeping configs/workspace/cli/).
git sparse-checkout init --no-cone >/dev/null

# Build the pattern file:
#   /*              — include everything at the root, recursively (the
#                     default in non-cone mode with `*` patterns)
#   !/<path>        — exclude an individual file
#   !/<path>/       — exclude a directory and its contents
sparse_file=".git/info/sparse-checkout"
tmp_file="$(mktemp)"
{
  echo "/*"
  for p in "${MACOS_ONLY_PATHS[@]}"; do
    echo "!/$p"
  done
} > "$tmp_file"

# Only re-apply if the pattern set actually changed (avoids the working-
# tree refresh on every bootstrap).
if [[ -r "$sparse_file" ]] && cmp -s "$tmp_file" "$sparse_file"; then
  rm -f "$tmp_file"
  echo "sparse-checkout: patterns already current ($(wc -l < "$sparse_file" | tr -d ' ') rules)"
  exit 0
fi

mv -f "$tmp_file" "$sparse_file"

# Re-materialize the working tree. `git sparse-checkout reapply` is the
# idiomatic refresh — it re-evaluates the pattern file and prunes/
# restores files accordingly.
git sparse-checkout reapply >/dev/null

echo "sparse-checkout: applied. Excluded paths:"
for p in "${MACOS_ONLY_PATHS[@]}"; do
  echo "  - $p"
done
