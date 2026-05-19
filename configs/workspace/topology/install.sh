#!/usr/bin/env bash
# install.sh — build the topology package and lay down the system pieces.
#
# Idempotent. Steps:
#   1. Source workspace configuration (bundle prefix, paths)
#   2. swift build -c release (with WORKSPACE_BUNDLE_PREFIX if set)
#   3. re-sign each binary ad-hoc with a stable identifier (so TCC grants
#      survive rebuilds — see codesign block below)
#   4. symlink built binaries into ~/.local/bin/
#   5. generate LaunchAgent plists from templates into ~/Library/LaunchAgents/
#   6. launchctl load each agent
#
# Configuration: Set WORKSPACE_BUNDLE_PREFIX env var before running to customize.
# Default: com.user.workspace

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source workspace configuration
source "$HERE/../lib/config.sh" 2>/dev/null || {
  # Fallback if config.sh not available (first run)
  WORKSPACE_BUNDLE_PREFIX="${WORKSPACE_BUNDLE_PREFIX:-com.user.workspace}"
  WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workspace"
  WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
}

LOCAL_BIN="$WORKSPACE_BIN_DIR"
LAUNCH_AGENTS="$WORKSPACE_LAUNCH_AGENTS_DIR"

# Binaries we build + symlink. CLIs come first (no LaunchAgent), daemons
# follow with their matching plist files.
BINARIES=(ws-topology ws-topologyd ws-cheatsheet ws-prompt ws-picker ws-snap ws-statusbar)

# Template names and their generated plist names
TEMPLATES=(topologyd autohide statusbar)
AGENT_LABELS=("$WORKSPACE_BUNDLE_PREFIX.topologyd" "$WORKSPACE_BUNDLE_PREFIX.autohide" "$WORKSPACE_BUNDLE_PREFIX.statusbar")

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n'   "$*" >&2; }

# Detect a version-skewed Command Line Tools install. Symptom: `swift build`
# can compile the manifest but the linker rejects PackageDescription symbols
# because the bundled libPackageDescription.dylib was built for a different
# swift major than the active swiftc. Common after a macOS major upgrade
# where CLT lingered from the previous OS. Caught here so the user sees a
# fixable instruction instead of a wall of "Undefined symbols" output.
#
# Exit code 2 = version skew (distinct from a generic build failure).
check_swift_pm_health() {
  command -v swift >/dev/null 2>&1 || return 0  # bootstrap.sh handles the absent case

  # `/usr/bin/swift` is a shim that delegates to xcode-select. After
  # `sudo rm -rf /Library/Developer/CommandLineTools`, the shim still
  # exists but `swift --version` fails and re-pops the install dialog.
  # Catch that mid-install state explicitly — otherwise `swift build`
  # below prints the same noisy "No developer tools were found" message
  # and the user thinks the script is broken.
  local active iface_path iface_ver active_major iface_major dev_dir version_out
  if ! version_out=$(swift --version 2>/dev/null); then
    err "Swift toolchain not ready (Command Line Tools installer hasn't finished)."
    printf '  The macOS installer dialog should still be open — let it finish,\n'  >&2
    printf '  then re-run ./bootstrap.sh (or this install.sh).\n\n'                >&2
    printf '  If no dialog is visible: re-trigger with `xcode-select --install`.\n\n' >&2
    return 2
  fi
  active=$(printf '%s\n' "$version_out" \
    | sed -n 's/.*Apple Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' \
    | head -n1)
  [[ -n "$active" ]] || return 0  # unknown swift flavor — let the build try

  dev_dir=$(xcode-select -p 2>/dev/null)
  [[ -n "$dev_dir" ]] || return 0
  iface_path=$(ls "$dev_dir"/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.swiftinterface 2>/dev/null | head -n1)
  [[ -n "$iface_path" && -r "$iface_path" ]] || return 0
  iface_ver=$(sed -n 's|.*swift-compiler-version: Apple Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*|\1|p' "$iface_path" | head -n1)
  [[ -n "$iface_ver" ]] || return 0

  active_major=${active%%.*}
  iface_major=${iface_ver%%.*}
  [[ "$active_major" == "$iface_major" ]] && return 0

  err "Command Line Tools are version-skewed and can't link Swift packages."
  printf '    active swift:                 %s\n' "$active"           >&2
  printf '    PackageDescription built with: %s\n\n' "$iface_ver"     >&2
  printf '  Fix one of these, then re-run ./bootstrap.sh:\n\n'        >&2
  printf '    A. Reinstall CLT (fast; recommended):\n'                >&2
  printf '         sudo rm -rf /Library/Developer/CommandLineTools\n' >&2
  printf '         xcode-select --install\n\n'                        >&2
  printf '    B. Install full Xcode (larger; only needed if you build other Swift apps):\n' >&2
  printf '         https://apps.apple.com/app/xcode/id497799835\n\n'  >&2
  return 2
}

if ! check_swift_pm_health; then
  exit 2
fi

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

# Re-sign each binary ad-hoc with a stable identifier and a custom
# Designated Requirement that omits cdhash. Why: `swift build` produces
# ad-hoc signatures whose default DR pins the build's cdhash, so TCC
# treats every rebuild as a new entity and asks you to flip the
# Accessibility toggle again. Stamping a stable DR (`identifier "X"`,
# no cdhash) lets TCC carry an existing grant across rebuilds — `ws-snap`
# is the practical beneficiary, but signing all of them keeps the bundle
# identity tidy and lets future binaries reuse the pattern.
step "ad-hoc codesigning with stable identifiers"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  if [[ ! -x "$src" ]]; then
    warn "missing build product: $src"
    exit 1
  fi
  identifier="$WORKSPACE_BUNDLE_PREFIX.$bin"
  if ! codesign --force --sign - \
        --identifier "$identifier" \
        --requirements "=designated => identifier \"$identifier\"" \
        "$src" 2>/dev/null; then
    warn "codesign $bin failed — TCC may re-prompt after rebuilds"
  fi
done

mkdir -p "$LOCAL_BIN"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  dst="$LOCAL_BIN/$bin"
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

mkdir -p "$LAUNCH_AGENTS"
mkdir -p "$WORKSPACE_CACHE_DIR"

# Generate plists from templates
for template in "${TEMPLATES[@]}"; do
  label="$WORKSPACE_BUNDLE_PREFIX.${template}"
  template_file="$HERE/launchd/com.template.workspace.${template}.plist"
  dst="$LAUNCH_AGENTS/${label}.plist"

  if [[ ! -f "$template_file" ]]; then
    warn "missing template: $template_file"
    continue
  fi

  # Generate plist with substitutions
  sed -e "s|{{BUNDLE_PREFIX}}|$WORKSPACE_BUNDLE_PREFIX|g" \
      -e "s|{{HOME}}|$HOME|g" \
      -e "s|{{CACHE_DIR}}|$WORKSPACE_CACHE_DIR|g" \
      "$template_file" > "$dst"

  step "generated $dst"

  # Unload old agent if running (with old name)
  if [[ "$template" == "topologyd" ]]; then
    old_label="com.adames.workspace.topologyd"
    if launchctl print "gui/$(id -u)/$old_label" >/dev/null 2>&1; then
      step "unloading old agent: $old_label"
      launchctl bootout "gui/$(id -u)/$old_label" 2>/dev/null || true
    fi
  elif [[ "$template" == "statusbar" ]]; then
    old_label="com.user.ws-statusbar"
    if launchctl print "gui/$(id -u)/$old_label" >/dev/null 2>&1; then
      step "unloading old agent: $old_label"
      launchctl bootout "gui/$(id -u)/$old_label" 2>/dev/null || true
    fi
  fi

  # Unload current agent if running
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    step "reloading $label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  fi

  launchctl bootstrap "gui/$(id -u)" "$dst"
done

step "agents loaded; logs under $WORKSPACE_CACHE_DIR/"

cat <<NOTE

Configuration:
  Bundle prefix: $WORKSPACE_BUNDLE_PREFIX
  Window manager: ${WORKSPACE_WINDOW_MANAGER:-yabai}
  Bar: ${WORKSPACE_BAR:-ws-statusbar}

To uninstall:
  for L in ${AGENT_LABELS[*]}; do launchctl bootout "gui/$(id -u)/\$L" 2>/dev/null || true; rm -f "$LAUNCH_AGENTS/\$L.plist"; done
  for B in ${BINARIES[*]}; do rm -f "$LOCAL_BIN/\$B"; done
NOTE
