import Foundation

/// Wire shape of ~/.config/workspace/cheatsheet.json. The file is GENERATED
/// by `lib/cheatsheet-gen.py` from `@cs` annotations in the upstream
/// config files (skhdrc, tmux.conf, nvim-init.lua, …) plus a layout
/// description at `configs/workspace/cheatsheet-layout.json`. The
/// renderer treats it as static input — column count, column ordering,
/// and section assignments are all decided at generation time.
///
/// The decoder is permissive about extra keys (anything starting with
/// `_` is ignored) so the layout file's `_doc` annotations and any
/// future per-column metadata don't blow up older binaries.
struct CheatsheetDocument: Decodable {
    let banner: [BannerItem]
    let columns: [Column]

    // Memberwise init kept explicit so the in-code fallback in main.swift
    // (the "couldn't load cheatsheet.json" error card) can construct a
    // document directly without round-tripping through JSON.
    init(banner: [BannerItem], columns: [Column]) {
        self.banner = banner
        self.columns = columns
    }

    struct BannerItem: Decodable {
        let k: String
        let v: String

        init(k: String, v: String) {
            self.k = k
            self.v = v
        }
    }

    /// One vertical column in the family-column mosaic. The generator
    /// produces these from `cheatsheet-layout.json`'s `columns` array:
    /// each entry concatenates the sections of one or more families,
    /// in family-then-source-order.
    struct Column: Decodable, Identifiable {
        let sections: [Section]
        /// Identity for `ForEach`. Stable across rebuilds: the first
        /// section's title doubles as the column ID (titles are unique
        /// across the document by construction). Falls back to a UUID
        /// only for genuinely empty columns, which shouldn't happen on
        /// the production layout but is safe defensive code.
        var id: String { sections.first?.title ?? UUID().uuidString }

        init(sections: [Section]) {
            self.sections = sections
        }
    }

    struct Section: Decodable, Identifiable {
        let title: String
        let rows: [[String]]      // wire is [["key", "desc"], ...]

        /// Optional `color` (legacy hex per-section) and `family`
        /// (preferred Catppuccin token). `family` wins via
        /// `FamilyColors.resolve`; `color` is the v1-back-compat fallback.
        /// The current generator emits `family` for every section, but
        /// the decoder keeps `color` decodable so a hand-edited fixture
        /// for tests doesn't have to follow the generator's conventions.
        let color: String?
        let family: String?

        /// Small subtitle line under the title (e.g. "yabai · skhd").
        let sub: String?

        /// Optional one-line "mental model" caption — italicized below
        /// the subtitle. Sweller's worked-example move: tell the reader
        /// what the section is about before showing the keys.
        let idea: String?

        /// Opt-in to a non-table body. Currently the only recognized
        /// value is `"keyboard"`, routed through `SpatialKeyboardView`
        /// (vim motion section).
        let customLayout: String?

        var id: String { title }

        // Memberwise init kept for tests / fallbacks built in code.
        init(
            title: String,
            rows: [[String]],
            color: String? = nil,
            family: String? = nil,
            sub: String? = nil,
            idea: String? = nil,
            customLayout: String? = nil
        ) {
            self.title = title
            self.rows = rows
            self.color = color
            self.family = family
            self.sub = sub
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
