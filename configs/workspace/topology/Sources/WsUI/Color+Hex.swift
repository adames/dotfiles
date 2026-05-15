import SwiftUI

/// Shared SwiftUI helpers + design tokens used by every workspace
/// overlay binary in this package (ws-prompt, ws-cheatsheet, ws-picker,
/// future). Anything that lives here should be (a) UI-shaped — depends
/// on SwiftUI — and (b) generic enough that two-or-more targets benefit
/// from sharing it. The Catppuccin palette + PromptStyle tokens are
/// shared because two overlays already key off the same visual contract;
/// app-specific colors (FamilyColors in ws-cheatsheet) stay in their
/// respective targets.

public extension Color {
    /// Initialize from a "#RRGGBB" string. Returns nil on parse failure.
    /// Both overlays paint their UI from hex strings that live in user-
    /// editable JSON (sketchybar colors, spaces.json), so a forgiving
    /// parser at the boundary is convenient.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
