import CoreGraphics
import Foundation
import Testing
@testable import ws_cheatsheet

/// Tests for `Masonry.columnize`, `Masonry.columnCount`, and
/// `Masonry.estimateHeight` — the cheatsheet's layout primitives.
///
/// Bash unit tests (`tests/unit/ws-cheatsheet.test.sh`) cover the same
/// behavior end-to-end via `--dump-layout`. These Swift tests drill
/// into the pure functions for numeric assertions that aren't worth
/// round-tripping through stdout.
@Suite("Masonry")
struct MasonryTests {

    typealias Section = CheatsheetDocument.Section

    private func makeSection(
        title: String = "Demo",
        sub: String = "",
        idea: String? = nil,
        customLayout: String? = nil,
        rows: [[String]] = [["k", "d"]]
    ) -> Section {
        Section(
            title: title, color: "#fff", sub: sub, rows: rows,
            family: nil, idea: idea, customLayout: customLayout
        )
    }

    // MARK: - estimateHeight

    @Suite("estimateHeight")
    struct EstimateHeight {

        @Test func no_rows_no_subtitle() {
            // padding(32) + title(22) = 54
            let s = Section(title: "X", color: "#fff", sub: "", rows: [])
            #expect(Masonry.estimateHeight(s) == 54)
        }

        @Test func subtitle_adds_sixteen() {
            // padding(32) + title(22) + subtitle(16) = 70
            let s = Section(title: "X", color: "#fff", sub: "y", rows: [])
            #expect(Masonry.estimateHeight(s) == 70)
        }

        @Test func each_row_adds_thirty() {
            // base(54) + 5 × 30 = 204
            let rows = (1...5).map { ["k\($0)", "d\($0)"] }
            let s = Section(title: "X", color: "#fff", sub: "", rows: rows)
            #expect(Masonry.estimateHeight(s) == 54 + 150)
        }

        @Test func idea_adds_one_line_when_short() {
            // base(54) + idea(18+4=22)
            let s = Section(
                title: "X", color: "#fff", sub: "", rows: [],
                idea: "short"
            )
            #expect(Masonry.estimateHeight(s) == 54 + 22)
        }

        @Test func idea_wraps_to_two_lines_past_sixty_chars() {
            // 75 chars wraps to 2 lines (ceil(75/60)=2). 2×18+4=40 added.
            let idea = String(repeating: "x", count: 75)
            let s = Section(
                title: "X", color: "#fff", sub: "", rows: [],
                idea: idea
            )
            #expect(Masonry.estimateHeight(s) == 54 + 40)
        }

        @Test func keyboard_custom_layout_adds_one_fifty() {
            let s = Section(
                title: "X", color: "#fff", sub: "", rows: [],
                customLayout: "keyboard"
            )
            #expect(Masonry.estimateHeight(s) == 54 + 150)
        }
    }

    // MARK: - columnCount derivation

    @Suite("columnCount")
    struct ColumnCount {

        @Test func zero_or_negative_width_falls_back_to_lower_bound() {
            #expect(Masonry.columnCount(forWidth: 0, spacing: 14) == 2)
            #expect(Masonry.columnCount(forWidth: -100, spacing: 14) == 2)
        }

        @Test func tiny_width_clamps_up_to_minimum_two() {
            // ⌊(100+14)/(320+14)⌋ = 0, clamped to 2.
            #expect(Masonry.columnCount(forWidth: 100, spacing: 14) == 2)
        }

        @Test func medium_width_derives_three_columns() {
            // ⌊(1024+14)/334⌋ = 3.
            #expect(Masonry.columnCount(forWidth: 1024, spacing: 14) == 3)
        }

        @Test func typical_width_derives_four_columns() {
            // ⌊(1640+14)/334⌋ = 4.
            #expect(Masonry.columnCount(forWidth: 1640, spacing: 14) == 4)
        }

        @Test func wide_width_derives_five_columns() {
            // ⌊(1900+14)/334⌋ = 5.
            #expect(Masonry.columnCount(forWidth: 1900, spacing: 14) == 5)
        }

        @Test func ultrawide_width_clamps_down_to_upper_bound_six() {
            // ⌊(2560+14)/334⌋ = 7, clamped to 6.
            #expect(Masonry.columnCount(forWidth: 2560, spacing: 14) == 6)
            #expect(Masonry.columnCount(forWidth: 5000, spacing: 14) == 6)
        }
    }

    // MARK: - columnize: structural invariants

    @Test func empty_input_returns_empty_columns_of_requested_count() {
        let columns = Masonry.columnize(sections: [], columnCount: 4)
        #expect(columns.count == 4)
        #expect(columns.allSatisfy { $0.sections.isEmpty })
        #expect(columns.allSatisfy { $0.estimatedHeight == 0 })
    }

    @Test func single_card_lands_in_column_zero_with_others_empty() {
        let s = makeSection(title: "Solo")
        let columns = Masonry.columnize(sections: [s], columnCount: 4)
        #expect(columns[0].sections.map(\.title) == ["Solo"])
        for i in 1..<4 {
            #expect(columns[i].sections.isEmpty)
        }
    }

    @Test func every_input_section_appears_in_exactly_one_column() {
        let sections = (1...10).map { makeSection(title: "S\($0)") }
        let columns = Masonry.columnize(sections: sections, columnCount: 3)
        let placed = columns.flatMap { $0.sections.map(\.title) }
        #expect(placed.sorted() == sections.map(\.title).sorted())
        #expect(placed.count == sections.count)
    }

    @Test func column_count_matches_requested_count() {
        let s = makeSection()
        for n in [1, 2, 3, 4, 5, 6, 10] {
            let columns = Masonry.columnize(sections: [s], columnCount: n)
            #expect(columns.count == n, "expected \(n) columns")
        }
    }

    @Test func column_ids_match_their_index() {
        let s = makeSection()
        let columns = Masonry.columnize(sections: [s], columnCount: 5)
        for (i, c) in columns.enumerated() {
            #expect(c.id == i)
        }
    }

    // MARK: - columnize: distribution rules

    @Test func equal_height_cards_round_robin_left_to_right() {
        // Three identical 84pt cards into 3 columns → one per column,
        // in document order (because leftmost-tiebreak picks col 0
        // first, then col 1, then col 2).
        let a = makeSection(title: "A")
        let b = makeSection(title: "B")
        let c = makeSection(title: "C")
        let columns = Masonry.columnize(sections: [a, b, c], columnCount: 3)
        #expect(columns[0].sections.map(\.title) == ["A"])
        #expect(columns[1].sections.map(\.title) == ["B"])
        #expect(columns[2].sections.map(\.title) == ["C"])
    }

    @Test func tall_card_pushes_subsequent_siblings_to_other_columns() {
        // Tall card (10 rows → 32+22+10×30 = 354) lands in col 0.
        // Heights become [354, 0]. Three short cards (84pt each) all
        // land in col 1 (each iteration col 1 is shorter).
        let tall = makeSection(
            title: "Tall",
            rows: (1...10).map { ["k\($0)", "d"] }
        )
        let s1 = makeSection(title: "S1")
        let s2 = makeSection(title: "S2")
        let s3 = makeSection(title: "S3")
        let columns = Masonry.columnize(
            sections: [tall, s1, s2, s3],
            columnCount: 2
        )
        #expect(columns[0].sections.map(\.title) == ["Tall"])
        #expect(columns[1].sections.map(\.title) == ["S1", "S2", "S3"])
    }

    @Test func eight_equal_cards_into_four_columns_pair_up() {
        // Eight equal-height cards into 4 columns: after the first 4
        // round-robin, heights are uniform again, so the next 4 also
        // round-robin into the same columns in document order.
        // Col 0 = [A, E], col 1 = [B, F], etc.
        let titles = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let sections = titles.map { makeSection(title: $0) }
        let columns = Masonry.columnize(sections: sections, columnCount: 4)
        #expect(columns[0].sections.map(\.title) == ["A", "E"])
        #expect(columns[1].sections.map(\.title) == ["B", "F"])
        #expect(columns[2].sections.map(\.title) == ["C", "G"])
        #expect(columns[3].sections.map(\.title) == ["D", "H"])
    }

    @Test func column_estimated_height_sums_member_heights() {
        // Three 84pt cards in col 0 — total should be 252.
        let a = makeSection(title: "A")
        let columns = Masonry.columnize(
            sections: [a, a, a],
            columnCount: 1
        )
        #expect(columns[0].sections.count == 3)
        #expect(columns[0].estimatedHeight == 84 * 3)
    }

    @Test func columnize_with_zero_or_negative_count_defaults_to_one_column() {
        // Defensive: a caller passing 0 or -1 shouldn't crash; the
        // implementation clamps to one column.
        let s = makeSection(title: "Solo")
        let zero = Masonry.columnize(sections: [s], columnCount: 0)
        let neg  = Masonry.columnize(sections: [s], columnCount: -1)
        #expect(zero.count == 1)
        #expect(neg.count == 1)
        #expect(zero[0].sections.map(\.title) == ["Solo"])
        #expect(neg[0].sections.map(\.title) == ["Solo"])
    }
}
