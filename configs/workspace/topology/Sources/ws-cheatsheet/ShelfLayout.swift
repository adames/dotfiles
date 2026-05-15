import CoreGraphics
import Foundation

/// Shelf-packing layout for the cheatsheet HUD.
///
/// Pipeline (matches the `layoutCheatsheet` pseudocode in the design note):
///
///   1. `estimateCards`      — predict each card's rendered height from its
///                             content so the packer has something to balance
///                             against. Approximate but stable: layout
///                             decisions are deterministic across runs.
///   2. `splitBySubsections` — break cards taller than the page-height
///                             threshold into their declared subsection
///                             chunks (TMUX → Panes / Windows / Sessions).
///   3. `groupIntoShelves`   — greedy fill: accumulate cards into a shelf
///                             until its column budget (4) is exhausted,
///                             then start the next one. Cards stay in
///                             document order so family bands read
///                             top-to-bottom.
///   4. `generateShelfLayouts`/`scoreLayout` — for shelves whose cards
///                             admit multiple spans, enumerate the
///                             span combinations and pick the one with
///                             the best height-balance + utilization.
///
/// The output is a list of shelves, each shelf a list of `(section, span)`
/// pairs. The renderer (CheatsheetView) just walks shelves top-to-bottom,
/// laying each one out as an HStack of fixed-width cards.
enum ShelfLayout {
    /// Result of packing — one entry per shelf, in vertical order.
    struct Shelf: Identifiable {
        let id: Int
        let items: [Item]
        /// Estimated max card height inside this shelf — used by the
        /// renderer to fix the shelf's row height (preventing GeometryReader
        /// from collapsing it during ScrollView measurement).
        let estimatedHeight: CGFloat
    }

    struct Item {
        let section: CheatsheetDocument.Section
        let span: Int          // 1..columns
        let estimatedHeight: CGFloat
    }

    // MARK: - Tunables (kept central so a layout tweak is one place to read)

    /// 4 columns is the design call (see the design note: "shelves with
    /// 4 fixed columns + shelf-aware balancing"). Cards take 1 or 2
    /// columns of this 4-track grid.
    static let columns: Int = 4

    /// Fraction of the page height above which a card is forcibly split
    /// by its declared subsections. Cards beyond this threshold dominate
    /// any shelf they land on, regardless of their neighbors.
    static let splitThreshold: CGFloat = 0.38

    // MARK: - Pipeline entry

    /// Pack `sections` into ordered shelves sized for a page of the given
    /// width and height. `pageWidth` is the inner width available to the
    /// shelf strip (already minus outer padding); `pageHeight` is the
    /// inner height (used as the splitting threshold reference).
    static func pack(
        sections: [CheatsheetDocument.Section],
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) -> [Shelf] {
        // Phase 1: pre-split tall cards into subsection chunks. The
        // `splitIntoChunks()` helper on Section is data-shape-only —
        // height comparison is the responsibility of THIS phase, so
        // splits don't trigger on short cards that happen to declare
        // splitAfter for future-proofing.
        let prepped: [CheatsheetDocument.Section] = sections.flatMap { sec -> [CheatsheetDocument.Section] in
            let estimated = estimateHeight(sec)
            let oversize = estimated > pageHeight * splitThreshold
            if oversize, sec.splitAfter?.isEmpty == false {
                return sec.splitIntoChunks()
            }
            return [sec]
        }

        // Phase 2: pre-measure all chunks.
        let measured: [(section: CheatsheetDocument.Section, height: CGFloat)] =
            prepped.map { ($0, estimateHeight($0)) }

        // Phase 3: greedy bin-pack into shelves of `columns` slots.
        // Each card takes its preferred span — we don't yet try
        // alternatives. (Phase 4 below adjusts spans within a shelf.)
        // `WIP` is a tuple alias so `rebalance` can take + return it
        // without needing a file-scope struct.
        var wipShelves: [WIP] = []
        var current: WIP = (items: [], used: 0)
        for (sec, h) in measured {
            let span = sec.resolvedPreferredSpan.clamped(to: 1...columns)
            // Card doesn't fit on current shelf — flush and start a new one.
            if current.used + span > columns {
                wipShelves.append(current)
                current = (items: [], used: 0)
            }
            current.items.append((sec, span, h))
            current.used += span
        }
        if !current.items.isEmpty { wipShelves.append(current) }

        // Phase 4: rebalance each shelf's spans. If any card on the shelf
        // admits more than one span, try each combination and pick the
        // one with the best score (low height-variance + low empty-slot
        // count). This is what turns wide visual cards into 2-wide cards
        // on a shelf that has the budget for them.
        let balanced: [WIP] = wipShelves.map { rebalance(shelf: $0) }

        // Phase 5: emit Shelf values for the renderer.
        return balanced.enumerated().map { (idx, w) in
            let items = w.items.map {
                Item(section: $0.section, span: $0.span, estimatedHeight: $0.height)
            }
            let maxH = items.map(\.estimatedHeight).max() ?? 0
            return Shelf(id: idx, items: items, estimatedHeight: maxH)
        }
    }

    /// Internal "work-in-progress shelf" alias used by phases 3 and 4.
    /// Tuple shape (not a struct) so it interoperates cleanly with
    /// `rebalance`'s signature without dragging WIPShelf into file scope.
    private typealias WIP = (
        items: [(section: CheatsheetDocument.Section, span: Int, height: CGFloat)],
        used: Int
    )

    // MARK: - Estimation

    /// Approximate rendered height of one card. Numbers come from the
    /// SectionCard view in CheatsheetView.swift:
    ///
    ///   - 16pt top padding, 16pt bottom padding (32pt fixed)
    ///   - Title row: ~13pt font, ~22pt total including the 3pt bottom pad
    ///   - Subtitle row: ~10pt font, ~16pt total with bottom pad
    ///   - Idea (optional): ~11pt italic, ~22pt with bottom pad
    ///   - Custom layout "keyboard": ~140pt block + 10pt pad
    ///   - Each table row: ~32pt (key + desc + 6pt vertical padding)
    ///
    /// The numbers are intentionally a bit generous — overestimating
    /// height makes shelf-balance choices conservative (it'll rarely
    /// pack a wide card next to a tall one), which is the right
    /// failure mode for a visual cheatsheet.
    static func estimateHeight(_ s: CheatsheetDocument.Section) -> CGFloat {
        var h: CGFloat = 32                // padding
        h += 22                            // title
        h += s.sub.isEmpty ? 0 : 16        // subtitle row
        if let idea = s.idea, !idea.isEmpty {
            // Rough wrap: 60 chars per line at the card's typical width.
            let lines = max(1, Int(ceil(Double(idea.count) / 60.0)))
            h += CGFloat(lines) * 18 + 4
        }
        if s.customLayout?.lowercased() == "keyboard" {
            h += 150
        }
        // Skip `:sub` markers when counting table rows — they don't render.
        let renderableRows = s.rows.filter { $0.first != ":sub" }
        h += CGFloat(renderableRows.count) * 30
        return h
    }

    // MARK: - Rebalance

    /// Try every span permutation that fits in `columns`, pick the one
    /// scoring best on (height-variance + unused-slot penalty).
    private static func rebalance(
        shelf: (items: [(section: CheatsheetDocument.Section, span: Int, height: CGFloat)], used: Int)
    ) -> (items: [(section: CheatsheetDocument.Section, span: Int, height: CGFloat)], used: Int) {
        // Build the per-card allowed-span list once.
        let allowedPerCard = shelf.items.map { $0.section.resolvedAllowedSpans.sorted() }

        // Quick-exit: every card is span-1 with no alternative — no work.
        let allFixed = allowedPerCard.allSatisfy { $0 == [1] }
        if allFixed { return shelf }

        // Enumerate cartesian product of span choices, keeping those whose
        // sum-of-spans ≤ columns. For 4 columns and ≤4 cards this is at
        // most 16 candidates — cheap to brute-force.
        var bestCombo: [Int]? = nil
        var bestScore: Double = .infinity
        cartesian(allowedPerCard) { combo in
            let totalSpan = combo.reduce(0, +)
            guard totalSpan <= columns else { return }
            let score = scoreSpans(
                combo: combo,
                items: shelf.items,
                totalColumns: columns
            )
            if score < bestScore {
                bestScore = score
                bestCombo = combo
            }
        }
        guard let combo = bestCombo else { return shelf }

        // Apply the winning combo.
        var newItems = shelf.items
        for i in 0..<newItems.count {
            newItems[i].span = combo[i]
        }
        let used = combo.reduce(0, +)
        return (items: newItems, used: used)
    }

    /// Score a candidate span assignment for one shelf. Lower = better.
    ///
    /// Two terms:
    ///   - **Empty-slot penalty**: each unused column adds a constant
    ///     cost. We don't WANT empty slots on shelves that could fill
    ///     them, but we accept them when balance demands it.
    ///   - **Height variance**: scaled down so balance doesn't dominate
    ///     a shelf with one tall card (which can't be helped).
    ///
    /// `combo` is parallel to `items`.
    private static func scoreSpans(
        combo: [Int],
        items: [(section: CheatsheetDocument.Section, span: Int, height: CGFloat)],
        totalColumns: Int
    ) -> Double {
        let used = combo.reduce(0, +)
        let empty = max(0, totalColumns - used)
        let emptyPenalty = Double(empty) * 40.0

        // Height variance, ignoring preferredSpan miss for now.
        let heights = items.map(\.height)
        let mean = heights.reduce(0, +) / CGFloat(max(1, heights.count))
        let variance = heights.reduce(CGFloat(0)) { acc, h in
            acc + pow(h - mean, 2)
        } / CGFloat(max(1, heights.count))
        let stddev = sqrt(variance)
        let balanceTerm = Double(stddev) * 0.1

        // Penalize deviating from preferredSpan, but only mildly — we
        // want the preferred span to win when balance is roughly equal.
        var preferredPenalty = 0.0
        for (idx, c) in combo.enumerated() {
            if c != items[idx].section.resolvedPreferredSpan {
                preferredPenalty += 5.0
            }
        }

        return emptyPenalty + balanceTerm + preferredPenalty
    }

    // MARK: - Cartesian helper

    /// Enumerate every combination of one choice per axis, calling
    /// `consume` with each fully-formed tuple. Pure recursion; no
    /// allocations beyond the working buffer. Caller is responsible
    /// for filtering invalid combos (we don't pre-prune by sum because
    /// the sum bound is cheap to check inline).
    private static func cartesian(_ axes: [[Int]], consume: ([Int]) -> Void) {
        var current = Array(repeating: 0, count: axes.count)
        func recurse(_ depth: Int) {
            if depth == axes.count {
                consume(current)
                return
            }
            for v in axes[depth] {
                current[depth] = v
                recurse(depth + 1)
            }
        }
        if !axes.isEmpty { recurse(0) }
    }
}

// MARK: - Comparable.clamped (local because WsUI's extension is consumed
// only by ws-prompt / ws-picker; ws-cheatsheet imports WsUI but the
// extension would also work if invoked here — kept as a local extension
// to keep the dependency surface explicit at the call site).

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
