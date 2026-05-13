import Foundation

public enum WorkspaceStateError: Error, CustomStringConvertible {
    case configNotFound(URL)
    case readFailed(URL, underlying: Error)
    case decodeFailed(URL, underlying: Error)
    case writeFailed(URL, underlying: Error)

    public var description: String {
        switch self {
        case .configNotFound(let url):
            return "spaces.json not found at \(url.path)"
        case .readFailed(let url, let err):
            return "failed reading \(url.path): \(err)"
        case .decodeFailed(let url, let err):
            return "failed decoding \(url.path): \(err)"
        case .writeFailed(let url, let err):
            return "failed writing \(url.path): \(err)"
        }
    }
}

/// Reads and writes the user's `spaces.json`. The store understands both v1 and
/// v2 on read (v1 is auto-promoted in memory via the same logic the Migration
/// uses). Writes always produce v2.
///
/// Atomic-mv contract matches `on-space-changed.sh:84-93`: write to a sibling
/// temp file in the same directory, then `rename` over the target so readers
/// never observe a half-written file.
public final class WorkspaceStateStore {
    public let configURL: URL

    public init(configURL: URL) {
        self.configURL = configURL
    }

    public convenience init(homeRelativePath: String = ".config/workspace/spaces.json") {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(configURL: home.appendingPathComponent(homeRelativePath))
    }

    public func load() throws -> WorkspaceConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw WorkspaceStateError.configNotFound(configURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw WorkspaceStateError.readFailed(configURL, underlying: error)
        }

        do {
            return try decode(data: data)
        } catch let err as WorkspaceStateError {
            throw err
        } catch {
            throw WorkspaceStateError.decodeFailed(configURL, underlying: error)
        }
    }

    public func decode(data: Data) throws -> WorkspaceConfig {
        guard let raw = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw WorkspaceStateError.decodeFailed(
                configURL,
                underlying: MigrationError.malformedJSON
            )
        }

        let version = (raw["version"] as? Int) ?? 1
        let palette = raw["palette"] as? String
        let theme   = raw["theme"] as? String
        let spaces  = (raw["spaces"] as? [String: Any]) ?? [:]

        let orderedKeys = spaces.keys.sorted { (Int($0) ?? .max) < (Int($1) ?? .max) }
        var slots: [WorkspaceSlot] = []
        for key in orderedKeys {
            guard let dict = spaces[key] as? [String: Any] else { continue }
            guard let id   = Int(key) else { continue }
            let name  = (dict["name"] as? String) ?? "ws\(key)"
            let color = (dict["color"] as? String) ?? "#cdd6f4"
            let stableLabel = (dict["stableLogicalLabel"] as? String) ?? name

            let iconSpec: IconSpec
            if let iconDict = dict["iconSpec"] as? [String: Any] {
                iconSpec = WorkspaceStateStore.decodeSpec(from: iconDict)
            } else {
                let legacy = (dict["icon"] as? String) ?? ""
                iconSpec = Migration.deriveIconSpec(fromLegacy: legacy, name: name)
            }

            slots.append(WorkspaceSlot(
                id: id,
                name: name,
                color: color,
                iconSpec: iconSpec,
                stableLogicalLabel: stableLabel
            ))
        }

        return WorkspaceConfig(version: version, palette: palette, theme: theme, slots: slots)
    }

    public static func decodeSpec(from dict: [String: Any]) -> IconSpec {
        let kindRaw = (dict["kind"] as? String) ?? "none"
        let kind    = IconKind(rawValue: kindRaw) ?? .none
        return IconSpec(
            kind: kind,
            symbolName:       dict["symbolName"]       as? String,
            codepoint:        dict["codepoint"]        as? String,
            fontFamily:       dict["fontFamily"]       as? String,
            fallbackSfSymbol: dict["fallbackSfSymbol"] as? String,
            fallbackText:     dict["fallbackText"]     as? String,
            userOverridden:   (dict["userOverridden"]  as? Bool) ?? false
        )
    }

    /// Atomic write: temp file in the same directory, then `rename`.
    public func save(_ config: WorkspaceConfig) throws {
        let payload = encodeJSON(config)
        let dir = configURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".spaces.json.\(UUID().uuidString)")

        do {
            try Data(payload.utf8).write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(configURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw WorkspaceStateError.writeFailed(configURL, underlying: error)
        }
    }

    public func encodeJSON(_ config: WorkspaceConfig) -> String {
        var root: [String: Any] = [
            "version": Migration.currentVersion,
        ]
        if let palette = config.palette { root["palette"] = palette }
        if let theme   = config.theme   { root["theme"]   = theme }

        var spacesObj: [String: Any] = [:]
        for slot in config.slots {
            spacesObj["\(slot.id)"] = [
                "name":               slot.name,
                "color":              slot.color,
                "iconSpec":           Migration.encode(spec: slot.iconSpec),
                "stableLogicalLabel": slot.stableLogicalLabel,
            ] as [String: Any]
        }
        root["spaces"] = spacesObj

        return Migration.render(root: root)
    }
}
