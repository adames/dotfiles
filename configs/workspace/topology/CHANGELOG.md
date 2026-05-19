# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Window manager abstraction layer supporting yabai and future aerospace integration
- Configurable bundle prefix via `WORKSPACE_BUNDLE_PREFIX` environment variable
- XDG-compliant path configuration
- Template-based LaunchAgent plist generation
- MIT License
- Contributing guidelines

### Changed
- Deprecated hardcoded `com.adames.workspace.*` identifiers in favor of configurable prefixes
- Moved window manager operations to abstraction layer (`lib/window-manager.sh`)
- Updated all yabai calls to use new abstraction

### Fixed
- Made project de-personalized for open source distribution

## [0.1.0] - 2024-XX-XX

### Added
- Initial release
- Swift-based menu bar status (`ws-statusbar`)
- SwiftUI overlays (`ws-prompt`, `ws-picker`, `ws-cheatsheet`)
- Bash CLI (`ws`)
- Display topology detection (`ws-topologyd`)
- SF Symbols support for icons
- Per-host workspace overlays
- Theme system (Catppuccin)
