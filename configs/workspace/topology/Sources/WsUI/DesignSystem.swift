import SwiftUI

// MARK: - Catppuccin Mocha palette
//
// Hex values match `configs/sketchybar/colors.sh` so every overlay reads
// as the same surface as the sketchybar pill strip. Caseless struct
// (vs enum) follows the Swift convention for "namespace for constants" —
// `enum` is conventionally for tagged unions.

public struct Catppuccin {
    public static let crust    = Color(hex: "#11111b") ?? .black
    public static let mantle   = Color(hex: "#181825") ?? .black
    public static let base     = Color(hex: "#1e1e2e") ?? .black
    public static let surface0 = Color(hex: "#313244") ?? .gray
    public static let surface1 = Color(hex: "#45475a") ?? .gray
    public static let overlay0 = Color(hex: "#6c7086") ?? .gray
    public static let overlay1 = Color(hex: "#7f849c") ?? .gray
    public static let subtext0 = Color(hex: "#a6adc8") ?? .white
    public static let text     = Color(hex: "#cdd6f4") ?? .white
    public static let blue     = Color(hex: "#89b4fa") ?? .blue
    public static let green    = Color(hex: "#a6e3a1") ?? .green
    public static let maroon   = Color(hex: "#eba0ac") ?? .pink
    private init() {}
}

// MARK: - Shape + typography tokens

public struct PromptStyle {
    /// SF Symbols for all icons — native Apple icon system.
    /// Previously used JetBrainsMono Nerd Font for sketchybar compatibility,
    /// now standardized on SF Symbols for all surfaces.
    public static let iconFont: Font = .system(size: 16, weight: .medium)

    public static func icon(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    public static let pillCorner: CGFloat = 6
    public static let pillHeight: CGFloat = 22
    public static let cardCorner: CGFloat = 10

    /// Distance from the top of the screen to the top of the overlay
    /// card. Matches Raycast's search-box top so the two surfaces feel
    /// like part of the same launcher family.
    public static let topInset: CGFloat = 120

    private init() {}
}

// MARK: - Comparable.clamped

public extension Comparable {
    /// Clamp `self` to a closed range. Used in overlay pickers where the
    /// SwiftUI selection index can briefly outlive the filtered list during
    /// a refilter.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
