import SwiftUI

// MARK: - Catppuccin Mocha palette
//
// Hex values match `configs/sketchybar/colors.sh` so the overlay reads
// as the same surface as the sketchybar pill strip. Caseless struct
// (vs enum) follows the Swift convention for "namespace for constants" —
// `enum` is conventionally for tagged unions.

struct Catppuccin {
    static let crust    = Color(hex: "#11111b") ?? .black
    static let mantle   = Color(hex: "#181825") ?? .black
    static let base     = Color(hex: "#1e1e2e") ?? .black
    static let surface0 = Color(hex: "#313244") ?? .gray
    static let surface1 = Color(hex: "#45475a") ?? .gray
    static let overlay0 = Color(hex: "#6c7086") ?? .gray
    static let overlay1 = Color(hex: "#7f849c") ?? .gray
    static let subtext0 = Color(hex: "#a6adc8") ?? .white
    static let text     = Color(hex: "#cdd6f4") ?? .white
    static let blue     = Color(hex: "#89b4fa") ?? .blue
    static let green    = Color(hex: "#a6e3a1") ?? .green
    static let maroon   = Color(hex: "#eba0ac") ?? .pink
    private init() {}
}

// MARK: - Shape + typography tokens

struct PromptStyle {
    /// `JetBrainsMono Nerd Font:Bold` — same family the sketchybar pill
    /// strip uses. Custom font means the Nerd Font private-use glyphs
    /// render correctly; `.system(design: .monospaced)` is SF Mono,
    /// which doesn't ship the workspace icons.
    static let nerdFontFamily = "JetBrainsMono Nerd Font"

    static func nerd(_ size: CGFloat) -> Font {
        .custom(nerdFontFamily, size: size).weight(.bold)
    }

    static let pillCorner: CGFloat = 6
    static let pillHeight: CGFloat = 22
    static let cardCorner: CGFloat = 10

    private init() {}
}

// MARK: - Color from hex

extension Color {
    /// Initialize from a "#RRGGBB" string. Returns nil on parse failure.
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

// MARK: - Comparable.clamped

extension Comparable {
    /// Clamp `self` to a closed range. Used in target / snapshot pickers
    /// where the SwiftUI selection index can briefly outlive the
    /// filtered list during a refilter.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
