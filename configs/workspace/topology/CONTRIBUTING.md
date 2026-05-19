# Contributing to Workspace

Thank you for your interest in contributing! This document outlines the process and guidelines for contributing to the workspace project.

## Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/workspace.git
cd workspace

# Build the Swift package
./install.sh

# Or manually:
cd configs/workspace/topology
swift build -c release
```

## Architecture Overview

The workspace system is organized into layers:

| Layer | Language | Purpose |
|-------|----------|---------|
| **Swift Package** | Swift 5.10+ | Native UI, display topology, window management |
| **CLI** | Bash | User-facing commands, JSON manipulation |
| **Configuration** | JSON/YAML | Workspace identity, theming |

### Key Components

- **`ws-topology`** - Display detection and layout policy
- **`ws-topologyd`** - LaunchAgent for display change monitoring
- **`ws-prompt`** - SwiftUI overlay for focus/send operations
- **`ws-picker`** - Window-based workspace switching
- **`ws-statusbar`** - Menu bar status item
- **`ws`** - Bash CLI for workspace mutation

## Making Changes

### Swift Code

1. Follow Swift API Design Guidelines
2. Add tests for new functionality (see `Tests/` directory)
3. Ensure `swift build -c release` compiles without warnings
4. Use `WorkspaceConfig` for any new paths or identifiers

### Bash Code

1. Use `shellcheck` to validate scripts: `shellcheck cli/ws`
2. Source `lib/config.sh` for configuration values
3. Use `lib/window-manager.sh` for window manager operations
4. Maintain idempotency: running twice should produce the same result

### Configuration

- Default values belong in `lib/config.sh`
- User overrides go in `~/.config/workspace/config.env`
- Never hardcode personal paths or identifiers

## Testing

```bash
# Run Swift tests (requires full Xcode)
swift test

# Validate bash scripts
shellcheck cli/ws
shellcheck install.sh

# Manual test matrix
./install.sh
ws doctor
ws verify
```

## Submitting Changes

1. **Fork** the repository
2. **Branch** - Create a feature branch: `git checkout -b feature/my-feature`
3. **Commit** - Make focused commits with clear messages
4. **Test** - Ensure everything works on your machine
5. **Push** - Push to your fork: `git push origin feature/my-feature`
6. **Pull Request** - Open a PR against `main`

### Commit Message Format

```
component: Brief summary

Longer explanation if needed. Wrap at 72 characters.

Fixes #123
```

Examples:
- `ws-prompt: Add support for Aerospace window manager`
- `cli: Fix race condition in ws add`
- `topology: Optimize display change detection`

## Code Style

### Swift
- 4 spaces for indentation
- Max line length: 100 characters
- Explicit `self.` in closures and initializers
- Protocol names: `WindowManager`, not `IWindowManager`

### Bash
- 2 spaces for indentation
- Quote all variable expansions: `"$VAR"`
- Use `[[ ]]` for conditionals
- Functions: `cmd_` prefix for CLI commands, `_` prefix for private

## Window Manager Support

When adding support for a new window manager:

1. Add case to `WindowManagerKind` in `WorkspaceState/WindowManager.swift`
2. Implement `WindowManager` protocol in new file
3. Update `WindowManagerFactory` to detect and create it
4. Add bash functions to `lib/window-manager.sh`
5. Update `lib/config.sh` with binary paths
6. Test all operations: focus, send, create, destroy

## Questions?

- Open an issue for discussion
- Check existing issues and PRs first
- For security issues, email directly (see security policy)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
