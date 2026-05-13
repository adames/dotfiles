import Foundation

public enum IconKind: String, Codable, Sendable, CaseIterable {
    case sfSymbol
    case nerdFont
    case text
    case none
}

public struct IconSpec: Codable, Equatable, Sendable {
    public var kind: IconKind
    public var symbolName: String?
    public var codepoint: String?
    public var fontFamily: String?
    public var fallbackSfSymbol: String?
    public var fallbackText: String?
    public var userOverridden: Bool

    public init(
        kind: IconKind,
        symbolName: String? = nil,
        codepoint: String? = nil,
        fontFamily: String? = nil,
        fallbackSfSymbol: String? = nil,
        fallbackText: String? = nil,
        userOverridden: Bool = false
    ) {
        self.kind = kind
        self.symbolName = symbolName
        self.codepoint = codepoint
        self.fontFamily = fontFamily
        self.fallbackSfSymbol = fallbackSfSymbol
        self.fallbackText = fallbackText
        self.userOverridden = userOverridden
    }

    public static let none = IconSpec(kind: .none)
}

public enum IconCodepoint {
    /// Decode a persisted escape like `"\\uf0b1"` or `"\\u{F0001}"` into a Unicode scalar.
    /// Returns nil on any malformed input. The string `""` (already a literal) is
    /// NOT supported here — persistence is always escaped.
    public static func decode(_ escaped: String) -> Unicode.Scalar? {
        let bracedPrefix = "\\u{"
        let bracedSuffix = "}"
        let shortPrefix  = "\\u"

        let hex: String
        if escaped.hasPrefix(bracedPrefix), escaped.hasSuffix(bracedSuffix) {
            let inside = escaped.dropFirst(bracedPrefix.count).dropLast(bracedSuffix.count)
            hex = String(inside)
        } else if escaped.hasPrefix(shortPrefix) {
            hex = String(escaped.dropFirst(shortPrefix.count))
        } else {
            return nil
        }

        guard !hex.isEmpty,
              let value = UInt32(hex, radix: 16),
              let scalar = Unicode.Scalar(value) else {
            return nil
        }
        return scalar
    }

    /// Encode a single Unicode scalar into ASCII-escaped persistence form.
    /// Uses `\uXXXX` for BMP, `\u{XXXXX}` for supplementary planes.
    public static func encode(_ scalar: Unicode.Scalar) -> String {
        let value = scalar.value
        if value <= 0xFFFF {
            return String(format: "\\u%04x", value)
        }
        return String(format: "\\u{%X}", value)
    }

    /// Is the scalar in a Nerd Font / Private Use Area range?
    /// Covers BMP PUA (U+E000..U+F8FF) and Supplementary PUA-A (U+F0000..U+FFFFD).
    public static func isPrivateUseArea(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0xE000...0xF8FF).contains(v) || (0xF0000...0xFFFFD).contains(v)
    }
}
