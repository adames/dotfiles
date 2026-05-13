import Foundation

public enum MigrationError: Error, CustomStringConvertible {
    case malformedJSON
    case missingSpaces
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .malformedJSON:           return "spaces.json is not valid JSON"
        case .missingSpaces:           return "spaces.json has no `spaces` object"
        case .unsupportedVersion(let v): return "unsupported spaces.json version: \(v)"
        }
    }
}

public struct MigrationResult: Equatable {
    public let alreadyV2: Bool
    public let slotsTouched: Int
    public let outputJSON: String

    public init(alreadyV2: Bool, slotsTouched: Int, outputJSON: String) {
        self.alreadyV2 = alreadyV2
        self.slotsTouched = slotsTouched
        self.outputJSON = outputJSON
    }
}

/// v1 → v2 migration. Preserves all unknown top-level keys (e.g. `_doc_*`
/// comments) and all unknown slot-level fields. Idempotent: running on a v2
/// file with no missing pieces produces an unchanged result.
public enum Migration {
    public static let currentVersion = 2
    public static let defaultNerdFontFamily = "JetBrainsMono Nerd Font"

    public static func migrate(jsonData: Data) throws -> MigrationResult {
        guard let raw = try JSONSerialization.jsonObject(
            with: jsonData,
            options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw MigrationError.malformedJSON
        }

        var root = raw
        let version = (root["version"] as? Int) ?? 1
        guard version == 1 || version == 2 else {
            throw MigrationError.unsupportedVersion(version)
        }

        guard let spaces = root["spaces"] as? [String: Any] else {
            throw MigrationError.missingSpaces
        }

        var migratedSpaces: [String: Any] = [:]
        var touched = 0
        let orderedKeys = spaces.keys.sorted { lhs, rhs in
            (Int(lhs) ?? .max) < (Int(rhs) ?? .max)
        }

        for key in orderedKeys {
            guard let slot = spaces[key] as? [String: Any] else { continue }
            let result = migrateSlot(key: key, slot: slot, alreadyV2: version == 2)
            migratedSpaces[key] = result.slot
            if result.touched { touched += 1 }
        }

        root["spaces"] = migratedSpaces
        root["version"] = currentVersion

        let outputJSON = render(root: root)
        return MigrationResult(
            alreadyV2: version == 2 && touched == 0,
            slotsTouched: touched,
            outputJSON: outputJSON
        )
    }

    struct SlotMigration {
        let slot: [String: Any]
        let touched: Bool
    }

    static func migrateSlot(key: String, slot: [String: Any], alreadyV2: Bool) -> SlotMigration {
        var out = slot
        var touched = false

        let name  = (out["name"] as? String) ?? "ws\(key)"
        let color = (out["color"] as? String) ?? "#cdd6f4"

        if out["iconSpec"] == nil {
            let legacy = (out["icon"] as? String) ?? ""
            let spec = deriveIconSpec(fromLegacy: legacy, name: name)
            out["iconSpec"] = encode(spec: spec)
            touched = true
        }

        if out["stableLogicalLabel"] == nil {
            out["stableLogicalLabel"] = name
            touched = true
        }

        out["name"]  = name
        out["color"] = color

        if !alreadyV2 { out.removeValue(forKey: "icon") }

        return SlotMigration(slot: out, touched: touched)
    }

    public static func deriveIconSpec(fromLegacy legacy: String, name: String) -> IconSpec {
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackText = SfSymbolFallbacks.textFallback(forSlotName: name)
        let fallbackSf   = SfSymbolFallbacks.symbol(forSlotName: name)

        if trimmed.isEmpty {
            return IconSpec(
                kind: .none,
                fallbackSfSymbol: fallbackSf,
                fallbackText: fallbackText,
                userOverridden: false
            )
        }

        let scalars = Array(trimmed.unicodeScalars)
        if scalars.count == 1, IconCodepoint.isPrivateUseArea(scalars[0]) {
            return IconSpec(
                kind: .nerdFont,
                codepoint: IconCodepoint.encode(scalars[0]),
                fontFamily: defaultNerdFontFamily,
                fallbackSfSymbol: fallbackSf,
                fallbackText: fallbackText,
                userOverridden: false
            )
        }

        return IconSpec(
            kind: .text,
            fallbackText: trimmed,
            userOverridden: false
        )
    }

    public static func encode(spec: IconSpec) -> [String: Any] {
        var dict: [String: Any] = [
            "kind": spec.kind.rawValue,
            "userOverridden": spec.userOverridden,
        ]
        if let v = spec.symbolName        { dict["symbolName"]       = v }
        if let v = spec.codepoint         { dict["codepoint"]        = v }
        if let v = spec.fontFamily        { dict["fontFamily"]       = v }
        if let v = spec.fallbackSfSymbol  { dict["fallbackSfSymbol"] = v }
        if let v = spec.fallbackText      { dict["fallbackText"]     = v }
        return dict
    }

    // MARK: - Deterministic pretty-printer
    //
    // JSONSerialization with .sortedKeys would alpha-sort everything, which puts
    // "10" before "2" inside `.spaces`. We need numerical ordering for slot keys
    // and alpha ordering everywhere else, so we render by hand.

    public static func render(root: [String: Any]) -> String {
        renderObject(root, indent: 0, isSpacesMap: false) + "\n"
    }

    static func renderObject(
        _ obj: [String: Any],
        indent: Int,
        isSpacesMap: Bool
    ) -> String {
        if obj.isEmpty { return "{}" }
        let keys = isSpacesMap
            ? obj.keys.sorted { (Int($0) ?? .max) < (Int($1) ?? .max) }
            : obj.keys.sorted()
        let pad   = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        var lines: [String] = []
        for (i, key) in keys.enumerated() {
            let value = obj[key] ?? NSNull()
            let isLast = (i == keys.count - 1)
            let valueStr = renderValue(value, indent: indent + 2, currentKey: key)
            lines.append("\(pad)\"\(escape(key))\": \(valueStr)\(isLast ? "" : ",")")
        }
        return "{\n" + lines.joined(separator: "\n") + "\n\(close)}"
    }

    static func renderArray(_ arr: [Any], indent: Int) -> String {
        if arr.isEmpty { return "[]" }
        let pad   = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        var lines: [String] = []
        for (i, value) in arr.enumerated() {
            let isLast = (i == arr.count - 1)
            let valueStr = renderValue(value, indent: indent + 2, currentKey: nil)
            lines.append("\(pad)\(valueStr)\(isLast ? "" : ",")")
        }
        return "[\n" + lines.joined(separator: "\n") + "\n\(close)]"
    }

    static func renderValue(_ value: Any, indent: Int, currentKey: String?) -> String {
        if value is NSNull { return "null" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? NSNumber {
            // Distinguish booleans from numbers — NSNumber bridges Bool, but the
            // `value as? Bool` check above already caught true Bool instances.
            return numberString(n)
        }
        if let s = value as? String { return "\"\(escape(s))\"" }
        if let a = value as? [Any]  { return renderArray(a, indent: indent) }
        if let o = value as? [String: Any] {
            let isSpaces = (currentKey == "spaces")
            return renderObject(o, indent: indent, isSpacesMap: isSpaces)
        }
        return "null"
    }

    static func numberString(_ n: NSNumber) -> String {
        // CFNumber type detection: integer-looking values render without trailing .0.
        let str = n.stringValue
        return str
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out += String(ch)
                }
            }
        }
        return out
    }
}
