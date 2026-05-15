import CoreGraphics
import Foundation

/// Masonry packer for the cheatsheet HUD.
///
/// Distributes sections into N columns by **greedy shortest-column** —
/// each card lands in the column whose accumulated height is smallest at
/// the time we place it. Pinterest-style: no row alignment, no wasted
/// vertical space inside a column, density is the priority.
///
/// Organization is carried by family **color**, not by physical
/// adjacency. Sections of the same family share a hue (Catppuccin via
/// FamilyColors) so the eye groups them across columns regardless of
/// where they land. Same trick the existing LazyVGrid relied on, but
/// without LazyVGrid's row-alignment penalty (the whole row used to
/// stretch to the tallest card's height, leaving gaps under shorter
/// neighbors).
///
/// The packer is pure: same input → same output, no SwiftUI surface
/// area. CheatsheetView reads `columnize`'s result and lays out one
/// VStack per column inside an HStack.
enum Masonry {
    /// One column of the packed output. `sections` are in document order
    /// for the cards landed in this column (greedy + left-bias tiebreak
    /// preserves something close to document order top-to-bottom).
    struct Column: Identifiable {
        let id: Int
        let sections: [CheatsheetDocument.Section]
        /// Sum of estimated heights of every card in this column. The
        /// renderer doesn't need this — it's exposed so `--dump-layout`
        /// can print a balance diagnostic.
        let estimatedHeight: CGFloat
    }

    // MARK: - Adaptive column count

    /// Minimum visual width a card needs to remain readable. Below this
    /// the title line wraps awkwardly and key/desc rows lose room for the
    /// description column. 320pt matches the LazyVGrid `.adaptive(minimum:
    /// 300)` baseline the previous layout used (plus a small bump because
    /// we drop the gutter padding from the per-column width).
    static let minColumnWidth: CGFloat = 320

    /// Clamp the column count so a tiny window doesn't degenerate to one
    /// column (loses scannability) and a huge ultrawide doesn't fan out
    /// past 6 (titles become disconnected from their family band).
    static let columnBounds: ClosedRange<Int> = 2...6

    /// Pick a column count from the available width. Conservative: each
    /// column gets at least `minColumnWidth + spacing` worth of horizontal
    /// room. Falls back to `lowerBound` when the width is degenerate.
    static func columnCount(forWidth width: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return columnBounds.lowerBound }
        // Width fits N columns when: N × minColumnWidth + (N-1) × spacing ≤ width
        // → N ≤ (width + spacing) / (minColumnWidth + spacing)
        let raw = Int((width + spacing) / (minColumnWidth + spacing))
        return min(columnBounds.upperBound, max(columnBounds.lowerBound, raw))
    }

    // MARK: - Pack

    /// Distribute `sections` into `columnCount` columns by greedy
    /// shortest-column-first placement. Document order is the input order;
    /// within each column, cards remain in input-relative order because we
    /// always append to whichever column is currently shortest.
    ///
    /// Tiebreaker: if multiple columns are equally short, the leftmost
    /// wins. This preserves a hint of left-to-right reading order: cards
    /// in the first 4 input slots end up in columns 0..3 left-to-right.
    static func columnize(
        sections: [CheatsheetDocument.Section],
        columnCount: Int
    ) -> [Column] {
        let cols = max(1, columnCount)
        var buckets: [[CheatsheetDocument.Section]] =
            Array(repeating: [], count: cols)
        var heights: [CGFloat] = Array(repeating: 0, count: cols)

        for section in sections {
            let h = estimateHeight(section)
            // Pick the leftmost shortest column.
            var pick = 0
            for i in 1..<cols where heights[i] < heights[pick] {
                pick = i
            }
            buckets[pick].append(section)
            heights[pick] += h
        }

        return (0..<cols).map { i in
            Column(id: i, sections: buckets[i], estimatedHeight: heights[i])
        }
    }

    // MARK: - Estimation

    /// Approximate rendered height of one card. Numbers come from the
    /// SectionCard view in CheatsheetView.swift:
    ///
    ///   - 32pt padding (16pt top + 16pt bottom)
    ///   - Title row: ~22pt
    ///   - Subtitle row: ~16pt (omitted if `sub` is empty)
    ///   - Idea (optional): ~18pt per wrapped line + 4pt bottom pad
    ///   - Custom layout "keyboard": ~150pt block
    ///   - Each table row: ~30pt
    ///
    /// The numbers slightly overestimate on purpose. Overestimating means
    /// the packer assigns less aggressively to "small-looking" columns,
    /// which keeps a tall card from creating a deeply-imbalanced tail
    /// where one column dwarfs the others.
    static func estimateHeight(_ s: CheatsheetDocument.Section) -> CGFloat {
        var h: CGFloat = 32                // padding
        h += 22                            // title
        h += s.sub.isEmpty ? 0 : 16        // subtitle
        if let idea = s.idea, !idea.isEmpty {
            // Rough wrap: ~60 chars per line at the column's typical width.
            let lines = max(1, Int(ceil(Double(idea.count) / 60.0)))
            h += CGFloat(lines) * 18 + 4
        }
        if s.customLayout?.lowercased() == "keyboard" {
            h += 150
        }
        h += CGFloat(s.rows.count) * 30
        return h
    }
}
