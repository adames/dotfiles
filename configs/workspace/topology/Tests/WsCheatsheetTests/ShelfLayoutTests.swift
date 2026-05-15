import CoreGraphics
import Foundation
import Testing
@testable import ws_cheatsheet

/// Tests for `ShelfLayout.pack` and `ShelfLayout.estimateHeight` — the
/// span-aware shelf packer that owns the cheatsheet's visual rhythm.
///
/// Bash unit tests (`tests/unit/ws-cheatsheet.test.sh`) cover the same
/// behavior end-to-end via the `--dump-layout` CLI. These Swift tests
/// drill into the pure function for fast iteration and assertions on
/// numbers that aren't worth round-tripping through stdout (estimated
/// heights, intermediate shelf shapes).
@Suite("ShelfLayout")
struct ShelfLayoutTests {

    typealias Section = CheatsheetDocument.Section

    // MARK: - estimateHeight

    @Suite("estimateHeight")
    struct EstimateHeight {

        @Test func minimal_section() {
            // padding(32) + title(22) + subtitle(16) + 0 rows = 70
            let s = Section(title: "X", color: "#fff", sub: "y", rows: [])
            #expect(ShelfLayout.estimateHeight(s) == 70)
        }

        @Test func empty_subtitle_omits_16pt() {
            let s = Section(title: "X", color: "#fff", sub: "", rows: [])
            #expect(ShelfLayout.estimateHeight(s) == 54)
        }

        @Test func each_row_adds_thirty_points() {
            // 5 rows × 30pt = 150 on top of the 70pt minimum.
            let rows = (1...5).map { ["k\($0)", "d\($0)"] }
            let s = Section(title: "X", color: "#fff", sub: "y", rows: rows)
            #expect(ShelfLayout.estimateHeight(s) == 70 + 150)
        }

        @Test func subsection_markers_do_not_count_as_rows() {
            // :sub rows are metadata — they don't render, so they don't
            // contribute height.
            let rows: [[String]] = [
                [":sub", "Section A"],
                ["k1", "d1"],
                [":sub", "Section B"],
                ["k2", "d2"]
            ]
            let s = Section(title: "X", color: "#fff", sub: "y", rows: rows)
            // 70 (base) + 2 × 30 (two real rows) = 130
            #expect(ShelfLayout.estimateHeight(s) == 130)
        }

        @Test func idea_adds_one_line_when_short() {
            // Short idea (< 60 chars) wraps to 1 line: 18 + 4 = 22 added.
            let s = Section(
                title: "X", color: "#fff", sub: "y", rows: [],
                idea: "short idea"
            )
            #expect(ShelfLayout.estimateHeight(s) == 70 + 22)
        }

        @Test func idea_wraps_to_two_lines_past_sixty_chars() {
            // ~75 chars → 2 lines (ceil(75/60) = 2). 2 × 18 + 4 = 40.
            let idea = String(repeating: "x", count: 75)
            let s = Section(
                title: "X", color: "#fff", sub: "y", rows: [],
                idea: idea
            )
            #expect(ShelfLayout.estimateHeight(s) == 70 + 40)
        }

        @Test func keyboard_custom_layout_adds_one_fifty() {
            let s = Section(
                title: "X", color: "#fff", sub: "y", rows: [],
                customLayout: "keyboard"
            )
            #expect(ShelfLayout.estimateHeight(s) == 70 + 150)
        }
    }

    // MARK: - pack: structural invariants

    private static let pageWidth: CGFloat = 1640
    private static let pageHeight: CGFloat = 1000

    private static func pack(_ sections: [Section]) -> [ShelfLayout.Shelf] {
        ShelfLayout.pack(
            sections: sections, pageWidth: pageWidth, pageHeight: pageHeight
        )
    }

    @Test func empty_input_produces_no_shelves() {
        #expect(Self.pack([]).isEmpty)
    }

    @Test func single_section_lands_on_one_shelf() {
        let s = Section(title: "A", color: "#fff", sub: "", rows: [["k", "d"]])
        let shelves = Self.pack([s])
        #expect(shelves.count == 1)
        #expect(shelves[0].items.count == 1)
        #expect(shelves[0].items[0].span == 1)
        #expect(shelves[0].items[0].section.title == "A")
    }

    @Test func four_narrows_fit_on_one_shelf_and_fifth_overflows() {
        let secs = (1...5).map { i in
            Section(title: "S\(i)", color: "#fff", sub: "", rows: [["k","d"]])
        }
        let shelves = Self.pack(secs)
        #expect(shelves.count == 2)
        #expect(shelves[0].items.count == 4)
        #expect(shelves[1].items.count == 1)
        #expect(shelves[1].items[0].section.title == "S5")
    }

    @Test func document_order_preserved_within_and_across_shelves() {
        let secs = ["A", "B", "C", "D", "E", "F"].map { t in
            Section(title: t, color: "#fff", sub: "", rows: [["k","d"]])
        }
        let shelves = Self.pack(secs)
        let titles = shelves.flatMap { $0.items.map(\.section.title) }
        #expect(titles == ["A", "B", "C", "D", "E", "F"])
    }

    @Test func shelf_max_height_matches_tallest_card_inside_it() {
        // Tall card in row 1, short cards in row 2. max_height must
        // reflect the tallest in each shelf independently.
        let tall = Section(
            title: "Tall", color: "#fff", sub: "",
            rows: (1...8).map { ["k\($0)", "d\($0)"] }
        )
        let short = Section(title: "S", color: "#fff", sub: "", rows: [["k","d"]])
        let shelves = Self.pack([tall, short, short, short, short])
        // tall+3short fills shelf 0, last short overflows.
        let shelf0Max = shelves[0].items.map(\.estimatedHeight).max()!
        let shelf1Max = shelves[1].items.map(\.estimatedHeight).max()!
        #expect(shelves[0].estimatedHeight == shelf0Max)
        #expect(shelves[1].estimatedHeight == shelf1Max)
        #expect(shelf0Max > shelf1Max)
    }

    // MARK: - pack: span promotion

    @Test func wide_card_promotes_to_span_2_when_shelf_has_room() {
        // Two cards, Wide admits [1,2] preferred 2 → greedy fills with
        // span 2, then narrow takes 1. Shelf is full at 4 used columns.
        let wide = Section(
            title: "Wide", color: "#fff", sub: "", rows: [["k","d"]],
            allowedSpans: [1, 2], preferredSpan: 2
        )
        let narrow = Section(title: "N", color: "#fff", sub: "", rows: [["k","d"]])
        let shelves = Self.pack([wide, narrow])
        #expect(shelves.count == 1)
        #expect(shelves[0].items.map(\.span) == [2, 1])
    }

    @Test func wide_card_with_preferred_one_stays_narrow_amongst_three_others() {
        // Preferred=1 plus 3 single-span siblings: shelf packs [1,1,1,1]
        // (full at 4 used). Promoting Wide to 2 would push the shelf to
        // 5 — not allowed. So Wide stays span 1.
        let wide = Section(
            title: "Wide", color: "#fff", sub: "", rows: [["k","d"]],
            allowedSpans: [1, 2], preferredSpan: 1
        )
        let n = { (t: String) in
            Section(title: t, color: "#fff", sub: "", rows: [["k","d"]])
        }
        let shelves = Self.pack([n("A"), wide, n("C"), n("D")])
        #expect(shelves.count == 1)
        #expect(shelves[0].items.count == 4)
        #expect(shelves[0].items.map(\.span).allSatisfy { $0 == 1 })
    }

    // MARK: - pack: split

    @Test func tall_section_with_splitAfter_pre_splits_before_packing() {
        // 30 rows over 3 subsections, total estimated ≈ 950pt, well over
        // 0.38 × 1000 = 380 threshold. Should emit three sub-cards.
        let rows: [[String]] = (
            [[":sub", "A"]] as [[String]]
            + (1...10).map { ["k\($0)", "d\($0)"] }
            + [[":sub", "B"]]
            + (11...20).map { ["k\($0)", "d\($0)"] }
            + [[":sub", "C"]]
            + (21...30).map { ["k\($0)", "d\($0)"] }
        )
        let tall = Section(
            title: "Big", color: "#fff", sub: "", rows: rows,
            splitAfter: ["A", "B", "C"]
        )
        let shelves = Self.pack([tall])
        let titles = shelves.flatMap { $0.items.map(\.section.title) }
        #expect(titles == ["Big · A", "Big · B", "Big · C"])
    }

    @Test func short_section_with_splitAfter_is_not_split() {
        // Same shape as above but only 2 rows total → well under threshold.
        let rows: [[String]] = [
            [":sub", "A"], ["k", "d"], [":sub", "B"], ["k", "d"]
        ]
        let short = Section(
            title: "Tiny", color: "#fff", sub: "", rows: rows,
            splitAfter: ["A", "B"]
        )
        let shelves = Self.pack([short])
        #expect(shelves.count == 1)
        #expect(shelves[0].items.count == 1)
        #expect(shelves[0].items[0].section.title == "Tiny")
    }

    @Test func page_height_zero_disables_threshold_split() {
        // pageHeight=0 → splitThreshold × 0 = 0 → every card with declared
        // splitAfter splits regardless of height. Edge case but worth
        // pinning so a future refactor doesn't accidentally NaN-divide.
        let rows: [[String]] = [
            [":sub", "A"], ["k", "d"], [":sub", "B"], ["k", "d"]
        ]
        let short = Section(
            title: "Tiny", color: "#fff", sub: "", rows: rows,
            splitAfter: ["A", "B"]
        )
        let shelves = ShelfLayout.pack(
            sections: [short], pageWidth: 1640, pageHeight: 0
        )
        let titles = shelves.flatMap { $0.items.map(\.section.title) }
        #expect(titles == ["Tiny · A", "Tiny · B"])
    }
}
