#!/usr/bin/env bash
# Idempotent Ubuntu bootstrap (VPS / VM). No Hyperkey — shell + nvim only.
# Override dotfiles repo with DOTFILES_REPO=...

set -euo pipefail

# Default to the repo this script lives in, so a clone outside ~/dotfiles
# still finds itself; explicit DOTFILES_DIR wins.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$DOTFILES_DIR/lib/common.sh"

# ─── phase 0 · sparse-checkout (idempotent, runs first) ─────────────────────
# Prune the working tree of macOS-only paths (ghostty, the macos/
# scripts, etc.) so a Linux clone only contains
# files this host actually uses. Manifest at lib/platform-manifest.sh
# is the single source of truth — see ubuntu/sparse-checkout.sh.
# Safe to run every bootstrap; no-ops when patterns are already current.
phase_sparse_checkout() {
  phase "sparse-checkout (prune macOS-only paths)"
  if [[ -x "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" ]]; then
    "$DOTFILES_DIR/ubuntu/sparse-checkout.sh" 2>&1 | sed 's/^/    /' \
      || warn "sparse-checkout failed; continuing with full tree"
  else
    warn "ubuntu/sparse-checkout.sh missing or not executable — skipping prune"
  fi
}

# ─── phase 1 · terminfo (idempotent, runs first) ────────────────────────────
# When SSH'ing in from Ghostty, TERM=xterm-ghostty is forwarded. Ubuntu's
# default terminfo database doesn't ship that entry, so zsh's line editor
# falls back to a stub — typing duplicates characters, backspace inserts
# spaces, the REPL is unusable. Compile the bundled source to ~/.terminfo
# so any user-level shell finds it. Runs first so the heavier apt/git work
# below isn't done through a broken REPL on the first-ever bootstrap from
# a Ghostty SSH session.
phase_terminfo() {
  phase "terminfo (xterm-ghostty)"
  if ! have tic; then
    step "installing ncurses-bin (provides tic)"
    sudo apt-get update -qq && sudo apt-get install -y ncurses-bin >/dev/null
  fi
  if [[ -f "$HOME/.terminfo/x/xterm-ghostty" ]]; then
    ok "xterm-ghostty already in ~/.terminfo — skipping"
  else
    step "compiling configs/xterm-ghostty.terminfo → ~/.terminfo"
    # run_quiet: tic emits an "older tic versions may treat the description
    # field as an alias" advisory on every single run. It's noise when the
    # compile succeeds and the whole story when it doesn't.
    if run_quiet "tic" tic -x -o "$HOME/.terminfo" "$CONFIGS_DIR/xterm-ghostty.terminfo"; then
      ok "xterm-ghostty installed (reconnect SSH or 'exec zsh' to pick up)"
    else
      warn "tic returned non-zero — entry may still be usable"
    fi
  fi
}

# ─── phase 2 · system packages ──────────────────────────────────────────────
phase_system() {
  phase "system packages"
  # `sudo apt-get update && sudo apt-get upgrade -y >/dev/null` bound the
  # redirect to `upgrade` only, so every run dumped ~19 raw "Get:" lines from
  # `update` and then hid the one line worth reading — how many packages
  # actually moved. Both now go through apt_quiet, which does the reverse.
  local upgrade_out held
  step "apt update + upgrade"
  sudo apt-get update 2>&1 | apt_quiet
  upgrade_out="$(sudo apt-get upgrade -y 2>&1)"
  printf '%s\n' "$upgrade_out" | apt_quiet
  ok "system packages upgraded"

  # "and N not upgraded" means apt held packages back (phased rollouts, or a
  # dependency it won't resolve automatically). That's a true, useful,
  # not-a-failure fact — exactly what note() is for. Zero maintenance: the
  # number comes from apt's own summary line.
  held="$(sed -nE 's/.*and ([0-9]+) not upgraded.*/\1/p' <<<"$upgrade_out" | head -1)"
  if [[ -n "${held:-}" ]] && (( held > 0 )); then
    note "$held package(s) held back by apt (see: apt list --upgradable)"
  fi

  # neovim deliberately absent: noble's 0.9.5 can't run configs/nvim-init.lua
  # (vim.lsp.config()/vim.uv are 0.11+ APIs) — phase_runtimes installs the
  # pinned release tarball instead. gnupg: NodeSource's signing key ships
  # ASCII-armored and needs `gpg --dearmor` (gh's arrives binary, hence no
  # gpg there); present on any real Ubuntu, declared for containers/WSL.
  step "installing apt packages"
  sudo apt-get install -y \
    git curl zsh build-essential tmux htop jq gnupg \
    ripgrep fd-find git-delta zoxide 2>&1 | apt_quiet
  ok "git zsh tmux jq ripgrep fd zoxide …"

  # Debian/Ubuntu calls fd "fdfind"; symlink for cross-OS parity.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "symlinked fdfind → ~/.local/bin/fd"
  fi

  if ! have gh; then
    step "adding GitHub CLI apt repo"
    curl --proto '=https' --tlsv1.2 -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq 2>&1 | apt_quiet
    sudo apt-get install -y gh 2>&1 | apt_quiet
    ok "gh installed"
  fi
}

# ─── phase 3 · shell layer ──────────────────────────────────────────────────
phase_shell() {
  phase "shell layer"
  if ! have starship; then
    step "installing Starship"
    # --proto '=https' --tlsv1.2: refuse any non-HTTPS redirect and any TLS
    # below 1.2. This is still pipe-to-shell — we trust starship.rs — but it
    # closes the downgrade path, and costs nothing to keep.
    run_quiet "starship installer" bash -c \
      "curl --proto '=https' --tlsv1.2 -sSf https://starship.rs/install.sh | sh -s -- --yes"
    ok "Starship installed"
  fi

  step "installing zsh plugins (git clones into ~/.zsh)"
  [[ -d ~/.zsh/zsh-autosuggestions ]] || \
    git clone -q https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
  [[ -d ~/.zsh/zsh-syntax-highlighting ]] || \
    git clone -q https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
  ok "zsh-autosuggestions + zsh-syntax-highlighting"

  if [[ ! -d ~/.fzf ]]; then
    step "installing fzf (binary only)"
    git clone --depth 1 -q https://github.com/junegunn/fzf.git ~/.fzf
    # --bin, not --all: the installer's rc edits get overwritten by
    # phase_configs anyway. The shared zshrc gates on `command -v fzf`,
    # so all we owe it is the binary on PATH.
    # The installer downloads a release tarball with curl, whose progress
    # meter goes to stderr — `>/dev/null` never caught it.
    run_quiet "fzf installer" "$HOME/.fzf/install" --bin
    ok "fzf binary built"
  fi
  # Outside the clone gate so a re-run heals installs from the --all era.
  mkdir -p "$HOME/.local/bin"
  ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
}

# ─── phase 4 · runtimes ─────────────────────────────────────────────────────
# Docker intentionally NOT installed: on macOS, OrbStack covers containers.
# On Ubuntu (this script) containers aren't a typical workload for the VPS /
# VM use cases — develop locally with OrbStack, ship from there. If you ever
# need a container runtime on the server: `curl -fsSL https://get.docker.com | sh`.
#
# mise is retired here too (macOS dropped it 2026-09 — see docs/architecture.md,
# "Dropping mise"). On macOS that was pure subtraction: brew already carried
# byte-identical runtimes. Here every tool needed its own source, and the
# honest tally is three:
#   node 24          — NodeSource apt repo (noble's own nodejs is 18). The
#                      node_24.x repo only ever carries 24.x, so a plain
#                      `apt upgrade` tracks patches while pinning the major,
#                      exactly like brew's node@24.
#   neovim           — official release tarball, pinned via NVIM_VERSION.
#                      noble's 0.9.5 predates vim.lsp.config()/vim.uv (0.11+),
#                      which configs/nvim-init.lua depends on.
#   tree-sitter-cli, pyright, typescript — npm -g into ~/.local. noble's
#                      tree-sitter-cli (0.20) is below nvim-treesitter's
#                      0.25 floor; the LSP servers have no apt package at all.
# python is the fourth runtime and cost nothing: noble's system python3 IS
# 3.12, and uv covers per-project versions.
NVIM_VERSION="v0.12.5"

install_node24() {
  if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    step "adding NodeSource apt repo (node 24)"
    curl --proto '=https' --tlsv1.2 -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor \
      | sudo dd of=/usr/share/keyrings/nodesource.gpg status=none
    sudo chmod go+r /usr/share/keyrings/nodesource.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
      | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    sudo apt-get update -qq 2>&1 | apt_quiet
  fi
  # Probe /usr/bin/node, not `node` on PATH: during the one transitional run
  # on a mise-era box, PATH still resolves node to mise's copy, which would
  # skip this install and then retire_mise would leave the box node-less.
  if [[ -x /usr/bin/node && "$(/usr/bin/node -v)" == v24.* ]]; then
    ok "node $(/usr/bin/node -v) (NodeSource apt)"
  else
    step "installing nodejs 24 (NodeSource)"
    sudo apt-get install -y nodejs 2>&1 | apt_quiet
    ok "node $(/usr/bin/node -v 2>/dev/null || echo '?') installed"
  fi
}

check_system_python() {
  # Deliberately installs nothing. If the OS python ever stops being 3.12
  # (the next LTS will), this note is the tripwire — decide then between
  # riding the new version and adding a real source, rather than silently
  # drifting.
  local pv
  pv="$(/usr/bin/python3 -V 2>/dev/null | awk '{print $2}')"
  case "$pv" in
    3.12.*) ok "python3 $pv (system — uv covers per-project versions)" ;;
    *) note "system python3 is ${pv:-absent}, expected 3.12 — phase_runtimes needs a decision" ;;
  esac
}

install_nvim() {
  # Pinned, not "latest": bump NVIM_VERSION and re-run bootstrap to upgrade.
  # This is the one runtime `apt upgrade` won't maintain — the price of an
  # editor whose config wants APIs two years ahead of noble's package.
  local current="" asset tmp
  [[ -x "$HOME/.local/opt/nvim/bin/nvim" ]] && \
    current="$("$HOME/.local/opt/nvim/bin/nvim" --version | sed -n '1s/^NVIM //p')"
  if [[ "$current" == "$NVIM_VERSION" ]]; then
    ok "nvim $NVIM_VERSION (pinned tarball)"
  else
    case "$(uname -m)" in
      aarch64) asset="nvim-linux-arm64" ;;
      x86_64)  asset="nvim-linux-x86_64" ;;
      *) warn "no official neovim build for $(uname -m) — nvim not installed"
         return 0 ;;
    esac
    step "installing neovim $NVIM_VERSION ($asset → ~/.local/opt/nvim)"
    tmp="$(mktemp -d)"
    if curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/nvim.tar.gz" \
         "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/$asset.tar.gz" \
       && tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"; then
      mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
      rm -rf "$HOME/.local/opt/nvim"
      mv "$tmp/$asset" "$HOME/.local/opt/nvim"
      ln -sf "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
      ok "nvim $NVIM_VERSION → ~/.local/bin/nvim"
    else
      warn "neovim $NVIM_VERSION download/extract failed"
    fi
    rm -rf "$tmp"
  fi
  # The apt neovim earlier bootstraps installed is 0.9.5 — superseded by the
  # tarball and one PATH mishap away from opening the wrong editor. Remove it
  # so `which nvim` has exactly one honest answer.
  if dpkg -s neovim >/dev/null 2>&1; then
    step "removing apt neovim (superseded by pinned tarball)"
    sudo apt-get remove -y neovim 2>&1 | apt_quiet
  fi
}

install_npm_tools() {
  # The npm prefix (~/.local) is a declared config, deployed here rather
  # than in phase_configs because the npm installs just below need it and
  # runtimes run before configs. Not `npm config set`: that writes an
  # untracked ~/.npmrc with the literal expanded path, which the drift
  # check could never reconcile with a source file.
  install_file "$CONFIGS_DIR/npmrc" "$HOME/.npmrc"
  # tree-sitter-cli is load-bearing, not build sugar: nvim-treesitter's main
  # branch shells out to it for every parser it installs. Without it a fresh
  # box compiles zero parsers and gets zero structural highlighting. (And the
  # C-library package is NOT the CLI — that confusion cost an hour on macOS.)
  # pyright + typescript are the two servers nvim-init.lua gates on
  # (`pyright-langserver`, `tsc --lsp`); brew owns them on macOS.
  # Probe ~/.local/bin, not PATH — same mise-shadow trap as /usr/bin/node.
  local missing=()
  [[ -x "$HOME/.local/bin/tree-sitter" ]]        || missing+=(tree-sitter-cli)
  [[ -x "$HOME/.local/bin/pyright-langserver" ]] || missing+=(pyright)
  [[ -x "$HOME/.local/bin/tsc" ]]                || missing+=(typescript)
  if (( ${#missing[@]} > 0 )); then
    step "npm install -g ${missing[*]}"
    # Soft-fail: a missing server degrades nvim to plain editing (every
    # server is gated on its binary); it shouldn't abort the whole run.
    if run_quiet "npm install -g" npm install -g "${missing[@]}"; then
      ok "npm tools: ${missing[*]}"
    else
      warn "npm tools failed to install: ${missing[*]}"
    fi
  else
    ok "tree-sitter-cli, pyright, typescript present"
  fi
}

# Mirrors retire_mise in macos/bootstrap.sh. Order matters the same way:
# phase_runtimes has installed node, nvim and the npm tools by the time this
# runs, so the box is never without a runtime between the sweep and the next
# shell. Idempotent — every path here may already be gone.
retire_mise() {
  if [[ ! -e "$HOME/.local/bin/mise" && ! -d "$HOME/.local/share/mise" ]]; then
    return 0
  fi
  if [[ ! -x /usr/bin/node ]]; then
    warn "node 24 not installed — keeping mise so the box still has a node"
    return 0
  fi
  step "retiring mise (runtimes come from real install paths now)"
  rm -f "$HOME/.local/bin/mise"
  # The install tree is the part that bites: ~/.local/share/mise held every
  # runtime the shims served. ~/.config/mise carried the version pins.
  rm -rf "$HOME/.local/share/mise" "$HOME/.local/state/mise" \
         "$HOME/.cache/mise" "$HOME/.config/mise"
  ok "mise binary + install tree swept"
  note "shells opened before this run will complain about _mise_hook — stale state; exec zsh"
}

phase_runtimes() {
  phase "runtimes"
  install_node24
  check_system_python
  install_nvim
  install_npm_tools
  retire_mise
}

# ─── phase 5 · configs ──────────────────────────────────────────────────────
phase_configs() {
  phase "configs"
  install_file "$CONFIGS_DIR/tmux.conf"           "$HOME/.tmux.conf"
  install_file "$CONFIGS_DIR/ripgreprc"           "$HOME/.ripgreprc"
  install_file "$CONFIGS_DIR/tmux-sessionizer"    "$HOME/.local/bin/tmux-sessionizer" 755
  install_file "$CONFIGS_DIR/starship.toml"       "$HOME/.config/starship.toml"
  install_file "$CONFIGS_DIR/zshenv"               "$HOME/.zshenv"
  install_file "$CONFIGS_DIR/zprofile"               "$HOME/.zprofile"
  install_file "$CONFIGS_DIR/zshrc"               "$HOME/.zshrc"
  install_file "$CONFIGS_DIR/gitconfig"           "$HOME/.gitconfig"
  install_file "$CONFIGS_DIR/CLAUDE.md"           "$HOME/.claude/CLAUDE.md"
  install_file "$CONFIGS_DIR/claude-settings.json" "$HOME/.claude/settings.json"
  install_file "$DOTFILES_DIR/bin/backup-claude-memory" "$HOME/.local/bin/backup-claude-memory.sh" 755
  # update-sys was a dangling alias on Ubuntu until 2026-09: the shared
  # zshrc promised update-system on both platforms and only macOS
  # delivered it. It now carries the apt + npm -g @latest sweep — the
  # only thing keeping the npm globals from freezing at install time.
  install_file "$DOTFILES_DIR/bin/update-system" "$HOME/.local/bin/update-system" 755
  ensure_claude_skills

  mkdir -p "$HOME/.config/nvim/after/plugin"
  install_file "$CONFIGS_DIR/nvim-init.lua"       "$HOME/.config/nvim/init.lua"
  install_file "$CONFIGS_DIR/nvim-lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  install_file "$CONFIGS_DIR/nvim-keymaps.lua"    "$HOME/.config/nvim/after/plugin/keymaps.lua"

  # Retired surfaces: the ws CLI was macOS-only all along (sigil), so the
  # old install block here shipped a binary and completions for a command
  # that can't work on Linux. Sweep the orphans off machines bootstrapped
  # from those versions (same convention as macos/bootstrap.sh).
  rm -f "$HOME/.local/bin/ws" "$HOME/.local/bin/workspace"
  rm -f "$HOME/.config/zsh/completions/_ws"
  rm -f "$HOME/.config/bash/completions/ws.bash"
  rm -f "$HOME/.config/workspace/cli/test-cascade.sh"

  ensure_gitconfig_local
}

# ─── phase 6 · default shell ────────────────────────────────────────────────
phase_default_shell() {
  phase "default shell"
  # ${VAR:-} guards: minimal environments (containers, cloud-init) run
  # without USER/SHELL exported, and set -u would abort right here.
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    step "setting login shell to zsh"
    sudo chsh -s "$(command -v zsh)" "${USER:-$(id -un)}" || warn "chsh failed; run manually"
    ok "default shell → zsh"
    note "log out / log in for the zsh shell change to apply"
  else
    ok "zsh already default shell"
  fi
}

# ─── entry ──────────────────────────────────────────────────────────────────
main() {
  if is_wsl; then
    section "Hyper-key dotfiles bootstrap (Ubuntu on WSL)"
  else
    section "Hyper-key dotfiles bootstrap (Ubuntu · minerva dev env)"
  fi
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

  # Without this, tzdata's postinst opens an interactive "select your
  # geographic area" menu mid-install. In a container it auto-answered and
  # merely printed the menu; on a real VPS an unattended run can sit there
  # waiting for input forever. noninteractive takes the package defaults.
  export DEBIAN_FRONTEND=noninteractive

  # Configs-only mode — same contract as macos/bootstrap.sh: the portable
  # core, no apt, no chsh, no installers. For a box this repo doesn't own.
  if [[ -n "${BOOTSTRAP_CONFIGS_ONLY:-}" ]]; then
    PHASE_TOTAL=1
    phase_configs
    run_summary
    return
  fi

  # Authenticate sudo up front, loudly. Without this, the first sudo lives
  # inside an `| apt_quiet` pipeline: run without a usable tty (a harness,
  # a pipe), sudo's "a password is required" is exactly the kind of
  # unrecognized line apt_quiet drops, and set -e -o pipefail aborts the
  # run with no visible reason. Measured, not theorized — that silent
  # death is how this line got here. (macos/bootstrap.sh has phase_sudo
  # for the same job; this is the one-line version, no keepalive.)
  if ! sudo -v; then
    err "sudo could not authenticate — run from an interactive terminal"
    run_summary
    exit 1
  fi

  # The list is the source of truth for both order and count — phase() reads
  # PHASE_TOTAL from it, so adding or reordering a phase needs no edits
  # anywhere else.
  local phases=(
    phase_sparse_checkout
    phase_terminfo
    phase_system
    phase_shell
    phase_runtimes
    phase_configs
    phase_default_shell
  )
  PHASE_TOTAL=${#phases[@]}
  local p
  for p in "${phases[@]}"; do "$p"; done

  # Ubuntu drops this file when a kernel or libc upgrade needs a restart to
  # take effect. On a VPS that's the difference between "patched" and
  # "patched after you reboot", and nothing else in the run would tell you.
  # WSL is Ubuntu for every purpose here except the clipboard, which has
  # to cross into Windows — nvim routes through clip.exe / Get-Clipboard,
  # tmux through OSC 52. Both are config, not packages, so there is
  # nothing to install; say so, because a silent success is
  # indistinguishable from an untested platform.
  if is_wsl; then
    note "WSL detected — clipboard routed to Windows (nvim: clip.exe, tmux: OSC 52)"
  fi

  if [[ -f /var/run/reboot-required ]]; then
    note "reboot required to finish applying updates$(
      [[ -f /var/run/reboot-required.pkgs ]] &&
        printf ' (%s)' "$(tr '\n' ' ' < /var/run/reboot-required.pkgs | sed 's/ $//')"
    )"
  fi
  run_summary
}

main "$@"
