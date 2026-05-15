import Foundation

/// Wire shape of ~/.config/workspace/cheatsheet.json. The file is hand-edited
/// (and synced from `dotfiles/configs/workspace/cheatsheet.json`), so the
/// decoder is intentionally permissive about extra keys (anything starting
/// with `_` is ignored).
///
/// Schema v3 (back-compat with v2): `priority`, `allowedSpans`, `preferredSpan`,
/// and `splitAfter` are all optional layout hints consumed by the shelf packer
/// (see ShelfLayout.swift). Older JSON without them still decodes; the packer
/// treats absence as "span 1, no priority, no splits."
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

        /// Lower = packed earlier. Absent → treated as 100 (i.e. after any
        /// explicit priorities). The packer reorders within a shelf only;
        /// shelves themselves stay in document order so family bands
        /// (system → terminal → vim → nvim → git) read top-to-bottom.
        let priority: Int?

        /// Allowed column widths for this card in the 4-column shelf grid.
        /// Default `[1]` — most cards are slim. Wide visual cards (the
        /// vim-motion keyboard) can declare `[1, 2]` to let the packer
        /// promote them to a 2-column span when shelf balance is improved
        /// by doing so.
        let allowedSpans: [Int]?

        /// When `allowedSpans` admits multiple widths, the packer prefers
        /// this one and only falls back to alternatives when shelf
        /// balancing demands it.
        let preferredSpan: Int?

        /// Subsection labels at which the packer should split this card
        /// into multiple sibling cards. Each label must match a
        /// `[":sub", "Label"]` row in `rows`. Used to break tall cards
        /// (TMUX, WORKSPACE) into shelf-friendly chunks while keeping
        /// the source-of-truth JSON in one place per topic.
        let splitAfter: [String]?

        var id: String { title }

        // Memberwise init kept explicit so the fallback in main.swift
        // continues to compile with only the required fields.
        init(
            title: String,
            color: String,
            sub: String,
            rows: [[String]],
            family: String? = nil,
            idea: String? = nil,
            customLayout: String? = nil,
            priority: Int? = nil,
            allowedSpans: [Int]? = nil,
            preferredSpan: Int? = nil,
            splitAfter: [String]? = nil
        ) {
            self.title = title
            self.color = color
            self.sub = sub
            self.rows = rows
            self.family = family
            self.idea = idea
            self.customLayout = customLayout
            self.priority = priority
            self.allowedSpans = allowedSpans
            self.preferredSpan = preferredSpan
            self.splitAfter = splitAfter
        }

        // MARK: - Derived layout hints (queried by the packer)

        /// Resolved allowed-span set with defaults applied: cards with no
        /// declaration are slim (1 column).
        var resolvedAllowedSpans: [Int] {
            (allowedSpans?.isEmpty == false) ? allowedSpans! : [1]
        }

        /// Resolved preferred span, clamped to allowed set.
        var resolvedPreferredSpan: Int {
            let allowed = resolvedAllowedSpans
            if let p = preferredSpan, allowed.contains(p) { return p }
            return allowed.first ?? 1
        }

        // MARK: - Subsection split

        /// Split this section into one card per subsection block defined by
        /// `splitAfter`. Rows are walked; a `[":sub", "Label"]` row starts a
        /// new chunk iff `Label` is named in `splitAfter`. The title of each
        /// chunk after the first gets the subsection label appended ("TMUX
        /// · Panes"). `idea` and `customLayout` carry to the first chunk
        /// only — subsequent chunks inherit the band color but render
        /// without those decorations to keep their height predictable.
        func splitIntoChunks() -> [Section] {
            guard let splits = splitAfter, !splits.isEmpty else { return [self] }
            let splitSet = Set(splits)

            var chunks: [Section] = []
            var pendingLabel: String? = nil
            var pendingRows: [[String]] = []
            var emittedAny = false

            func emit() {
                let chunkTitle: String = {
                    guard let label = pendingLabel else { return title }
                    return "\(title) · \(label)"
                }()
                let chunk = Section(
                    title: chunkTitle,
                    color: color,
                    sub: pendingLabel == nil ? sub : "",
                    rows: pendingRows,
                    family: family,
                    idea: emittedAny ? nil : idea,
                    customLayout: emittedAny ? nil : customLayout,
                    priority: priority,
                    allowedSpans: allowedSpans,
                    preferredSpan: preferredSpan,
                    splitAfter: nil
                )
                chunks.append(chunk)
                emittedAny = true
                pendingLabel = nil
                pendingRows = []
            }

            for row in rows {
                if row.count >= 2 && row[0] == ":sub", splitSet.contains(row[1]) {
                    // Flush whatever was accumulating before this split point.
                    if !pendingRows.isEmpty || emittedAny { emit() }
                    pendingLabel = row[1]
                    continue
                }
                // Skip non-split subsection markers entirely — they would
                // render as junk. (If we wanted in-card subsections later we
                // could render them, but the design here splits-or-omits.)
                if row.count >= 2 && row[0] == ":sub" { continue }
                pendingRows.append(row)
            }
            if !pendingRows.isEmpty || pendingLabel != nil { emit() }
            return chunks.isEmpty ? [self] : chunks
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
