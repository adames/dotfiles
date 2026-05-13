import Foundation

public enum SfSymbolFallbacks {
    /// Best-effort SF Symbol mapping for the user's current 10 slot names.
    /// Used during v1 → v2 migration when no explicit fallback exists. Names
    /// not in the map fall through to `defaultSymbol`.
    static let table: [String: String] = [
        "stream":  "play.fill",
        "hub":     "square.grid.2x2",
        "grid":    "square.grid.3x3",
        "vault":   "lock.fill",
        "oracle":  "sparkles",
        "sandbox": "cube.box",
        "arena":   "gamecontroller",
        "deck":    "rectangle.stack",
        "shell":   "terminal",
        "daemon":  "cpu",
    ]

    static let defaultSymbol = "circle.fill"

    public static func symbol(forSlotName name: String) -> String {
        table[name.lowercased()] ?? defaultSymbol
    }

    /// Two-letter uppercase abbreviation: first two letters of the name, or
    /// the first letter doubled if the name is single-character.
    public static func textFallback(forSlotName name: String) -> String {
        let upper = name.uppercased()
        if upper.count >= 2 {
            return String(upper.prefix(2))
        }
        if let first = upper.first { return String([first, first]) }
        return "??"
    }
}
