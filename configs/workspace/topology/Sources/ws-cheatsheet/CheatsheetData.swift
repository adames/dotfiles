import Foundation

/// Wire shape of ~/.config/workspace/cheatsheet.json. The file is hand-edited
/// (and synced from `dotfiles/configs/workspace/cheatsheet.json`), so the
/// decoder is intentionally permissive about extra keys (anything starting
/// with `_` is ignored).
struct CheatsheetDocument: Decodable {
    let banner: [BannerItem]
    let sections: [Section]

    struct BannerItem: Decodable {
        let k: String
        let v: String
    }

    struct Section: Decodable, Identifiable {
        let title: String
        let color: String         // hex, e.g. "#60a5fa"
        let sub: String
        let rows: [[String]]      // wire is [["key", "desc"], ...]

        var id: String { title }
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
