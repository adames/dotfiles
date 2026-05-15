import Foundation

/// Wire shape of ~/.config/workspace/cheatsheet.json. The file is hand-edited
/// (and synced from `dotfiles/configs/workspace/cheatsheet.json`), so the
/// decoder is intentionally permissive about extra keys (anything starting
/// with `_` is ignored).
///
/// Schema v2 (back-compat): `family`, `idea`, and `customLayout` are all
/// optional. An older JSON without them still decodes; the renderer falls
/// back to the legacy per-section `color`.
struct CheatsheetDocument: Decodable {
    let banner: [BannerItem]
    let sections: [Section]

    struct BannerItem: Decodable {
        let k: String
        let v: String
    }

    struct Section: Decodable, Identifiable {
        let title: String
        let color: String         // hex, e.g. "#60a5fa" (legacy / per-section override)
        let sub: String
        let rows: [[String]]      // wire is [["key", "desc"], ...]

        /// One of the family tokens (system, terminal, vim, nvim, git). When
        /// set, the renderer prefers `FamilyColors[family]` over `color`.
        let family: String?

        /// Optional one-line "mental model" caption rendered between the
        /// subtitle and the rows.
        let idea: String?

        /// Opt-in to a non-table body. Currently the only recognized value is
        /// `"keyboard"`, which routes the rendering through `SpatialKeyboardView`.
        let customLayout: String?

        var id: String { title }

        // Memberwise init kept explicit so the fallback in main.swift continues
        // to compile with only the required fields.
        init(
            title: String,
            color: String,
            sub: String,
            rows: [[String]],
            family: String? = nil,
            idea: String? = nil,
            customLayout: String? = nil
        ) {
            self.title = title
            self.color = color
            self.sub = sub
            self.rows = rows
            self.family = family
            self.idea = idea
            self.customLayout = customLayout
        }
    }
}

enum CheatsheetLoader {
    static let defaultPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/workspace/cheatsheet.json")

    static func load(from url: URL = defaultPath) throws -> CheatsheetDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(CheatsheetDocument.self, from: data)
    }
}
