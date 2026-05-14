import Foundation

/// Read-side model for the focus / send prompts and the manage overlay's
/// target picker. Names mirror the v2 spaces.json schema
/// (see configs/workspace/spaces.default.json), but only carry the
/// fields the overlay needs to render a list and resolve a typed query.
///
/// Sourcing the workspace list — joining yabai's slot count with
/// spaces.json's identity entries — lives in `WorkspaceService`, not
/// here. This file is just the data shape.
struct Workspace: Equatable {
    let index: Int          // yabai's 1-based slot index
    let display: Int        // yabai's display index this slot lives on
    let name: String        // user-given name or "ws<index>" fallback
    let color: String       // "#RRGGBB"
    let icon: String?       // resolved glyph (Nerd Font codepoint or SF Symbol name)
    let iconKind: IconKind  // disambiguates how to render `icon`

    enum IconKind { case none, sfSymbol, nerdFont }
}
