import CoreGraphics
import Foundation

/// Column-major layout for the cheatsheet HUD.
///
/// Walks sections in **document order** and fills column 0 to roughly
/// `total_height / column_count` before advancing to column 1, etc.
/// Because the source JSON is family-ordered (system → terminal → vim →
/// nvim → git), family clustering happens as a *side effect*: a family
/// flows top-to-bottom inside a single column, occasionally wrapping
/// to the next column at a natural boundary. No explicit "family band"
/// logic — the document order does the work.
///
/// Advance rule: before placing each card, if its **midpoint** would
/// cross this column's target line (`target × (col + 1)`), advance one
/// column. Midpoint instead of start/end means a tall card straddling
/// a target line gets assigned to whichever side has more of its mass —
/// the assignment that minimizes downstream imbalance.
///
/// Two guard rails:
///   - never advance out of an empty column (a tall first card stays
///     in col 0 even if its midpoint nominally exceeds the target);
///   - **single-step only** — even a card 4× target wide can only push
///     the cursor forward by one column, so each subsequent placement
///     walks the cursor along instead of skipping. Result: no empty
///     trailing columns when there are enough cards to fill them.
///
/// Variance is acceptable, not optimal. Linear-partition with binary
/// search would minimize max-column-height to within ~1pt, but at the
/// cost of breaking the "advance at most one per card" invariant
/// (and the resulting ordering can put adjacent cards in non-adjacent
/// columns, defeating the family-flow side effect). The simple rule
/// here keeps the visual model legible and the code under 30 lines.
enum Masonry {
    struct Column: Identifiable {
        let id: Int
        let sections: [CheatsheetDocument.Section]
        /// Sum of estimated heights of cards in this column. Exposed for
        /// `--dump-layout` diagnostics; the renderer doesn't need it.
        let estimatedHeight: CGFloat
    }

    // MARK: - Adaptive column count

    /// Minimum visual width a card needs to remain readable. Below this
    /// the title line wraps awkwardly and the key/desc rows lose room
    /// for the description column. 320pt matches the prior LazyVGrid
    /// `.adaptive(minimum: 300)` baseline plus a small bump for the
    /// per-column gutter we account for explicitly.
    static let minColumnWidth: CGFloat = 320

    /// Clamp the column count so a tiny window doesn't degenerate to
    /// one column (loses scannability) and an ultrawide doesn't fan out
    /// past 6 (titles disconnect from their family band).
    static let columnBounds: ClosedRange<Int> = 2...6

    /// Derive a column count from the available width. Conservative —
    /// each column needs at least `minColumnWidth + spacing` worth of
    /// horizontal room. Falls back to the lower bound when width is
    /// degenerate (≤ 0).
    static func columnCount(forWidth width: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return columnBounds.lowerBound }
        // N columns fit when N × minColumnWidth + (N-1) × spacing ≤ width
        // → N ≤ (width + spacing) / (minColumnWidth + spacing)
        let raw = Int((width + spacing) / (minColumnWidth + spacing))
        return min(columnBounds.upperBound, max(columnBounds.lowerBound, raw))
    }

    // MARK: - Pack

    /// Distribute `sections` into `columnCount` columns by column-major
    /// document-order fill. Each card is placed in the current column;
    /// after placement, the cursor advances by at most one column if
    /// the cumulative height has crossed a target line.
    ///
    /// The result preserves input order absolutely — for any two
    /// sections i < j, section i is in an earlier or same column as
    /// section j.
    static func columnize(
        sections: [CheatsheetDocument.Section],
        columnCount: Int
    ) -> [Column] {
        let cols = max(1, columnCount)
        guard !sections.isEmpty else {
            return (0..<cols).map { Column(id: $0, sections: [], estimatedHeight: 0) }
        }

        let weights = sections.map(estimateHeight)
        let total = weights.reduce(0, +)
        let target = total / CGFloat(cols)

        var buckets: [[CheatsheetDocument.Section]] = Array(repeating: [], count: cols)
        var heights: [CGFloat] = Array(repeating: 0, count: cols)
        var col = 0
        var cumsum: CGFloat = 0

        for (i, section) in sections.enumerated() {
            let h = weights[i]
            let midpoint = cumsum + h / 2
            // Advance one column if: (a) we have more columns left,
            // (b) the current column isn't empty (a tall first card
            // stays in col 0), and (c) this card's midpoint has
            // crossed the next target line.
            if col < cols - 1
               && heights[col] > 0
               && midpoint >= target * CGFloat(col + 1) {
                col += 1
            }
            buckets[col].append(section)
            heights[col] += h
            cumsum += h
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
    /// Slight overestimate on purpose. Overestimating means the packer
    /// hits target lines slightly early, which keeps any single column
    /// from being dominated by an underestimated tall card.
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
