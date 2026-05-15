import Foundation
import Testing
@testable import ws_cheatsheet

/// Tests for `CheatsheetDocument.Section.splitIntoChunks()` — pre-split
/// logic that runs in the layout pipeline (ShelfLayout.pack phase 1).
///
/// The packer calls this only when the source section's estimated height
/// exceeds the page-height threshold; these tests verify the pure
/// data-shape transformation independent of that gating.
@Suite("Section.splitIntoChunks")
struct SplitIntoChunksTests {

    typealias Section = CheatsheetDocument.Section

    private func makeSection(
        title: String = "Demo",
        sub: String = "subtitle",
        idea: String? = "the idea",
        customLayout: String? = nil,
        splitAfter: [String]? = nil,
        rows: [[String]]
    ) -> Section {
        Section(
            title: title, color: "#fff", sub: sub, rows: rows,
            family: "system", idea: idea, customLayout: customLayout,
            splitAfter: splitAfter
        )
    }

    @Test func no_splitAfter_returns_self_unchanged() {
        let s = makeSection(splitAfter: nil, rows: [["k", "d"]])
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 1)
        #expect(chunks[0].title == "Demo")
        #expect(chunks[0].rows.count == 1)
    }

    @Test func empty_splitAfter_returns_self_unchanged() {
        let s = makeSection(splitAfter: [], rows: [["k", "d"]])
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 1)
        #expect(chunks[0].title == "Demo")
    }

    @Test func splitAfter_with_no_matching_markers_emits_one_chunk() {
        let s = makeSection(
            splitAfter: ["Ghost"],
            rows: [["k1", "d1"], ["k2", "d2"]]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 1)
        #expect(chunks[0].title == "Demo")
        #expect(chunks[0].rows.count == 2)
    }

    @Test func single_split_partitions_rows_and_labels_titles() {
        let s = makeSection(
            splitAfter: ["B"],
            rows: [
                ["k1", "d1"],
                [":sub", "B"],
                ["k2", "d2"]
            ]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 2)
        #expect(chunks[0].title == "Demo")
        #expect(chunks[0].rows.map(\.first) == ["k1"])
        #expect(chunks[1].title == "Demo · B")
        #expect(chunks[1].rows.map(\.first) == ["k2"])
    }

    @Test func multiple_splits_emit_one_chunk_per_section() {
        let s = makeSection(
            splitAfter: ["First", "Second", "Third"],
            rows: [
                [":sub", "First"],
                ["k1", "d1"],
                [":sub", "Second"],
                ["k2", "d2"],
                [":sub", "Third"],
                ["k3", "d3"]
            ]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 3)
        #expect(chunks.map(\.title) == ["Demo · First", "Demo · Second", "Demo · Third"])
        #expect(chunks.map { $0.rows.count } == [1, 1, 1])
    }

    @Test func idea_and_customLayout_only_on_first_chunk() {
        let s = makeSection(
            idea: "an idea",
            customLayout: "keyboard",
            splitAfter: ["B", "C"],
            rows: [
                [":sub", "B"],
                ["k1", "d1"],
                [":sub", "C"],
                ["k2", "d2"]
            ]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 2)
        // First chunk gets the idea + keyboard layout (its title has the
        // first split's label suffix).
        #expect(chunks[0].idea == "an idea")
        #expect(chunks[0].customLayout == "keyboard")
        // Second chunk inherits the band color but drops decoration.
        #expect(chunks[1].idea == nil)
        #expect(chunks[1].customLayout == nil)
    }

    @Test func subsection_marker_not_in_splitAfter_is_dropped() {
        // ":sub" rows that the packer didn't ask to split on are layout
        // metadata only — they must never reach the renderer's row list.
        let s = makeSection(
            splitAfter: ["A"],
            rows: [
                ["k1", "d1"],
                [":sub", "A"],
                [":sub", "B"],    // unrelated marker; should disappear
                ["k2", "d2"]
            ]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 2)
        let allRows = chunks.flatMap(\.rows)
        #expect(!allRows.contains(where: { $0.first == ":sub" }))
    }

    @Test func splitAfter_field_dropped_from_emitted_chunks() {
        // Chunks shouldn't carry the original splitAfter forward — they
        // already have no `:sub` rows, so re-splitting them is a no-op,
        // but the cleanest invariant is "splitAfter is consumed."
        let s = makeSection(
            splitAfter: ["A"],
            rows: [
                ["k1", "d1"],
                [":sub", "A"],
                ["k2", "d2"]
            ]
        )
        let chunks = s.splitIntoChunks()
        for chunk in chunks {
            #expect(chunk.splitAfter == nil)
        }
    }

    @Test func leading_split_marker_collapses_empty_first_chunk() {
        // First row is a split marker → there's no pre-marker chunk to
        // emit. The implementation skips emit() in that case and just
        // sets the pending label, so the first emitted chunk is "Demo · A".
        let s = makeSection(
            splitAfter: ["A"],
            rows: [
                [":sub", "A"],
                ["k1", "d1"]
            ]
        )
        let chunks = s.splitIntoChunks()
        #expect(chunks.count == 1)
        #expect(chunks[0].title == "Demo · A")
        #expect(chunks[0].rows.map(\.first) == ["k1"])
    }
}
