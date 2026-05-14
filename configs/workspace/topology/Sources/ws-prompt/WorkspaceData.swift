import Foundation

/// Read-side model for the focus / send prompts. Names mirror the v2
/// spaces.json schema (see configs/workspace/spaces.default.json) but
/// only carry the fields the prompt needs to render a list and resolve
/// a typed query.
struct Workspace: Equatable {
    let index: Int          // yabai's 1-based slot index
    let name: String        // user-given name or "ws<index>" fallback
    let color: String       // "#RRGGBB"
    let icon: String?       // resolved glyph (Nerd Font codepoint or SF Symbol name), nil if unset
    let iconKind: IconKind  // disambiguates how to render `icon`

    enum IconKind { case none, sfSymbol, nerdFont }
}

enum WorkspaceLoader {
    /// Builds the slot list by joining yabai's space count with
    /// spaces.json metadata. Slots that yabai reports but spaces.json
    /// doesn't name get the conventional `ws<N>` fallback and a neutral
    /// gray color, matching SketchyBar's bare-pill rendering.
    ///
    /// `yabaiBinary` and `wsConfig` are overridable so tests can point at
    /// the yabai-stub fixture without monkeypatching.
    static func load(
        yabaiBinary: String = "/opt/homebrew/bin/yabai",
        wsConfig: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/workspace/spaces.json")
    ) -> [Workspace] {
        let count = querySpaceCount(yabaiBinary: yabaiBinary)
        let identities = readIdentities(from: wsConfig)
        return (1...max(count, 0)).map { idx in
            if let id = identities[idx] {
                return Workspace(
                    index: idx,
                    name: id.name ?? "ws\(idx)",
                    color: id.color ?? "#7f8c8d",
                    icon: id.icon,
                    iconKind: id.iconKind
                )
            }
            return Workspace(
                index: idx,
                name: "ws\(idx)",
                color: "#7f8c8d",
                icon: nil,
                iconKind: .none
            )
        }
    }

    // MARK: - yabai

    static func querySpaceCount(yabaiBinary: String) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabaiBinary)
        task.arguments = ["-m", "query", "--spaces"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // yabai missing — fall back to "no spaces", which renders an
            // empty list and lets Esc dismiss. Loud failures live in the
            // bash helpers; the overlay just doesn't pretend.
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return 0
        }
        return arr.count
    }

    /// Currently-focused space index (1-based). Nil if yabai isn't
    /// responding. Used by the manage overlay to default rename/destroy
    /// pickers onto "this workspace" so Enter-without-typing is the
    /// fast path for "act on what I'm looking at".
    static func queryFocusedSpaceIndex(yabaiBinary: String? = nil) -> Int? {
        let binary = yabaiBinary ?? resolveYabaiBinary()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["-m", "query", "--spaces", "--space"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idx = obj["index"] as? Int
        else { return nil }
        return idx
    }

    // Locating yabai: skhd dispatches via /opt/homebrew/bin/yabai but the
    // ws-prompt binary inherits the launchd-agent PATH, which is minimal.
    // Probe the well-known install paths so the overlay works on both
    // Apple-Silicon Homebrew and Intel Homebrew without env wiring.
    // `YABAI_BIN` env var wins when set — used by the test harness to
    // point at tests/fixtures/yabai-stub.
    static func resolveYabaiBinary() -> String {
        if let override = ProcessInfo.processInfo.environment["YABAI_BIN"],
           !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let candidates = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "yabai"  // last resort: rely on PATH
    }

    // MARK: - spaces.json

    private struct IdentityRaw: Decodable {
        let name: String?
        let color: String?
        let iconSpec: IconSpec?
    }
    private struct IconSpec: Decodable {
        let kind: String?
        let codepoint: String?
        let symbolName: String?
        let fallbackSfSymbol: String?
    }
    struct Identity {
        let name: String?
        let color: String?
        let icon: String?
        let iconKind: Workspace.IconKind
    }

    static func readIdentities(from url: URL) -> [Int: Identity] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        struct Root: Decodable { let spaces: [String: IdentityRaw]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let raw = root.spaces else { return [:] }

        var out: [Int: Identity] = [:]
        for (key, value) in raw {
            guard let idx = Int(key) else { continue }
            let kind: Workspace.IconKind
            let glyph: String?
            switch value.iconSpec?.kind {
            case "nerdFont":
                kind = .nerdFont
                glyph = decodeCodepoint(value.iconSpec?.codepoint)
                    ?? value.iconSpec?.fallbackSfSymbol
            case "sfSymbol":
                kind = .sfSymbol
                glyph = value.iconSpec?.symbolName
                    ?? value.iconSpec?.fallbackSfSymbol
            default:
                kind = .none
                glyph = nil
            }
            out[idx] = Identity(
                name: value.name,
                color: value.color,
                icon: glyph,
                iconKind: glyph == nil ? .none : kind
            )
        }
        return out
    }

    /// spaces.json stores Nerd Font glyphs as escape strings — either
    /// `""` (BMP) or `"\u{F0009}"` (private-use plane). Both
    /// already come through JSONDecoder as a literal scalar, but if a
    /// theme file ships an unprocessed `"\u{XXXXX}"` we accept that
    /// shape too as a defensive fallback.
    private static func decodeCodepoint(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.unicodeScalars.count == 1 { return raw }
        // Try parsing "\u{HEX}" -> Scalar
        if raw.hasPrefix("\\u{"), raw.hasSuffix("}") {
            let hex = String(raw.dropFirst(3).dropLast())
            if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                return String(scalar)
            }
        }
        // Try parsing "\uHEX"
        if raw.hasPrefix("\\u"), raw.count >= 6 {
            let hex = String(raw.dropFirst(2).prefix(4))
            if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                return String(scalar)
            }
        }
        return raw
    }
}
