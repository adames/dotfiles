# Workspace Extraction from Dotfiles

This document describes how to extract the workspace project from the dotfiles repository into its own standalone repository.

## Overview

The workspace project has evolved from personal configuration into a standalone macOS workspace management tool. Extraction creates:

1. A **clean repository** for the workspace project
2. **Professional open source presentation**
3. **Independent releases** and versioning
4. A **simplified dotfiles** that references workspace as a dependency

## Step-by-Step Extraction

### Phase 1: Create the New Repository

```bash
# 1. Run the extraction script
cd ~/dotfiles
./configs/workspace/extract-workspace.sh ~/projects/workspace

# 2. Navigate to the new repo
cd ~/projects/workspace

# 3. Review the extracted files
ls -la
# Should see:
#   Package.swift
#   Sources/
#   Tests/
#   cli/
#   lib/
#   launchd/
#   install.sh
#   README.md
#   LICENSE
#   ...

# 4. Initialize git
git add -A
git commit -m "Initial commit: Extract workspace from dotfiles

Features:
- SwiftUI overlays (ws-prompt, ws-picker, ws-cheatsheet)
- Menu bar status (ws-statusbar)
- Display topology daemon (ws-topologyd)
- Bash CLI (ws)
- Window manager abstraction (yabai support, aerospace stub)
- SF Symbol icons with Nerd Font fallback
- Configurable bundle prefix and XDG paths

Extracted from: https://github.com/adamesh/dotfiles"

# 5. Create GitHub repository (via web or gh CLI)
gh repo create workspace --private --push --source .
# Or: git remote add origin https://github.com/adamesh/workspace.git
#     git push -u origin main
```

### Phase 2: Verify the Extraction

```bash
cd ~/projects/workspace

# Test 1: Swift build
swift build -c release

# Test 2: Run install (dry run first to check paths)
./install.sh

# Test 3: Check binaries exist
ls ~/.local/bin/ws-*

# Test 4: Verify LaunchAgents generated
ls ~/Library/LaunchAgents/com.user.workspace.*.plist

# Test 5: Test CLI
ws doctor
```

### Phase 3: Update Dotfiles

Once workspace is confirmed working in its new home:

```bash
cd ~/dotfiles

# 1. Create a branch for the removal
git checkout -b remove-workspace-extraction

# 2. Remove workspace files
rm -rf configs/workspace/

# 3. Update bootstrap.sh to install workspace from new repo
cat >> macos/bootstrap.sh << 'EOF'

# Install workspace (separate repo)
install_workspace() {
  if [[ ! -d ~/.config/workspace ]]; then
    step "Installing workspace"
    local tmpdir=$(mktemp -d)
    git clone https://github.com/adamesh/workspace.git "$tmpdir/workspace"
    "$tmpdir/workspace/install.sh"
    rm -rf "$tmpdir"
  else
    step "workspace already installed"
  fi
}
install_workspace
EOF

# 4. Update documentation in dotfiles README
# (Remove workspace-specific docs, add reference to new repo)

# 5. Commit
git add -A
git commit -m "Remove workspace - now maintained in separate repository

Workspace has been extracted to: https://github.com/adamesh/workspace

This commit:
- Removes configs/workspace/ directory
- Adds workspace installation to bootstrap.sh
- Updates documentation

The workspace project is now a standalone open source project."

# 6. Push and merge
git push origin remove-workspace-extraction
```

### Phase 4: Polish the New Repository

Before making the workspace repo public:

```bash
cd ~/projects/workspace

# 1. Update README with real content
# - Add screenshots/GIFs of overlays
# - Write proper usage examples
# - Document configuration options

# 2. Add CI/CD (GitHub Actions)
mkdir -p .github/workflows
cat > .github/workflows/build.yml << 'EOF'
name: Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: swift build -c release
      - name: Test
        run: swift test || true  # Tests may need Xcode
EOF

# 3. Create initial release tag
git tag -a v0.1.0 -m "Initial release - extracted from dotfiles"
git push origin v0.1.0

# 4. Make repository public (when ready)
gh repo edit --visibility=public
```

## Post-Extraction Maintenance

### For Workspace Development

```bash
cd ~/projects/workspace
# Work on workspace features
# Commit and push to workspace repo
```

### For Dotfiles Development

```bash
cd ~/dotfiles
# Dotfiles now treats workspace as external dependency
# Update bootstrap.sh if workspace install method changes
```

### Cross-Repository Changes

If a change spans both (rare):
1. Make workspace change first, release new version
2. Update dotfiles bootstrap.sh to reference new version

## Rollback Plan

If extraction fails:

```bash
# 1. Revert dotfiles
cd ~/dotfiles
git checkout main
git branch -D remove-workspace-extraction

# 2. Clean up new repo
rm -rf ~/projects/workspace

# 3. Continue using embedded workspace
# Workspace remains in dotfiles as before
```

## Benefits After Extraction

| Aspect | Before | After |
|--------|--------|-------|
| **Cloning** | Clone entire dotfiles | Clone just workspace |
| **Issues** | Mixed with dotfiles issues | Focused workspace issues |
| **Releases** | None | Versioned releases |
| **Contributors** | Personal project | Open to contributions |
| **Stars** | Hidden in dotfiles | Standalone recognition |
| **Install** | Run bootstrap.sh | Run install.sh |
| **Scope** | Part of personal config | Product for all macOS users |

## Checklist

- [ ] Extraction script runs successfully
- [ ] New repo builds with `swift build -c release`
- [ ] Install script works on clean machine
- [ ] All binaries present in `~/.local/bin/`
- [ ] LaunchAgents generated correctly
- [ ] Dotfiles bootstrap.sh updated
- [ ] Documentation updated
- [ ] CI/CD configured (optional)
- [ ] Initial release tagged
- [ ] Repository made public (when ready)

## Questions?

If issues arise during extraction, check:
1. Did all files copy? Compare `find configs/workspace -type f | wc -l` vs new repo
2. Are paths correct? Check `lib/config.sh` and `install.sh`
3. Does Swift build? Check for missing `Sources/` directories
4. Are templates processed? Check LaunchAgent plists for `{{VAR}}` placeholders
