import SwiftUI
import WsUI   // re-exports `Color(hex:)`

/// The HUD view, redesigned as a *learning aid* rather than a haystack:
///
/// - Sections sit inside **family bands** (system · terminal · editor · git)
///   so spatial neighbors are stable across display widths. The mental
///   model "which world am I in" is carried by the band, not by 12 unique
///   per-section colors.
/// - Each section has a one-line **idea caption** under its title — the
///   worked-example move from Sweller's cognitive-load work, translated to
///   "tell the learner what the section is *about* before showing the keys".
/// - Each key chord gets a leading **ModifierBadge** dot — Gestalt similarity
///   reinforcing the proximity grouping of the band.
/// - The vim-motion section opts in to a spatial **keyboard diagram** via
///   `customLayout: "keyboard"` — dual coding (Paivio) where it reinforces
///   the concept ("h is left because it's the leftmost arrow key").
///
/// Layout (v3 — span-aware shelf packing):
/// - 4 fixed columns. Each card occupies 1 or 2 columns based on its
///   `allowedSpans` hint. The packer (`ShelfLayout.pack`) pre-splits
///   tall cards (TMUX, WORKSPACE) by their declared subsections and
///   bin-packs the result into shelves, rebalancing spans inside each
///   shelf for height + utilization. See ShelfLayout.swift for the
///   pipeline.
struct CheatsheetView: View {
    let document: CheatsheetDocument
    let timestamp: String

    private let outerHPadding: CGFloat = 40
    private let outerTopPadding: CGFloat = 36
    private let outerBottomPadding: CGFloat = 22
    private let columnSpacing: CGFloat = 14
    private let shelfSpacing: CGFloat = 14
    private let maxPageWidth: CGFloat = 1720

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)

            VStack(spacing: 16) {
                bannerStrip
                sectionGrid
                footer
            }
            .padding(.horizontal, outerHPadding)
            .padding(.top, outerTopPadding)
            .padding(.bottom, outerBottomPadding)
            .frame(maxWidth: maxPageWidth, maxHeight: .infinity)
        }
    }

    /// Shelf-packed body. GeometryReader gives us the inner width so we
    /// can compute exact column widths; everything below it is sized in
    /// concrete pt values, which means ScrollView's intrinsic content
    /// size is well-defined.
    private var sectionGrid: some View {
        GeometryReader { geo in
            let usableWidth = min(geo.size.width, maxPageWidth - 2 * outerHPadding)
            let columns = ShelfLayout.columns
            let totalSpacing = columnSpacing * CGFloat(columns - 1)
            let columnWidth = (usableWidth - totalSpacing) / CGFloat(columns)
            let shelves = ShelfLayout.pack(
                sections: document.sections,
                pageWidth: usableWidth,
                pageHeight: geo.size.height
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: shelfSpacing) {
                    ForEach(shelves) { shelf in
                        ShelfRow(
                            shelf: shelf,
                            columnWidth: columnWidth,
                            columnSpacing: columnSpacing
                        )
                    }
                }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Banner (legend for the modifier badges below)

    private var bannerStrip: some View {
        HStack(spacing: 22) {
            ForEach(Array(document.banner.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 8) {
                    ModifierBadge(forChord: item.k)
                    KeyCap(text: item.k)
                    Text(item.v)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }
                if idx < document.banner.count - 1 {
                    Text("·").foregroundColor(.white.opacity(0.18))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Text("CAPS + ; (or Esc) TO CLOSE  ·  \(timestamp)")
                .font(.system(size: 11))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }
}

// MARK: - ShelfRow

private struct ShelfRow: View {
    let shelf: ShelfLayout.Shelf
    let columnWidth: CGFloat
    let columnSpacing: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in
                SectionCard(section: item.section)
                    .frame(
                        width: cardWidth(span: item.span),
                        alignment: .topLeading
                    )
            }
            Spacer(minLength: 0)
        }
    }

    /// One column wide = `columnWidth`. Two columns wide = two columns
    /// plus the spacer between them (so the card crosses the gutter that
    /// would otherwise sit between its two host columns).
    private func cardWidth(span: Int) -> CGFloat {
        let s = CGFloat(max(1, span))
        return columnWidth * s + columnSpacing * (s - 1)
    }
}

// MARK: - SectionCard

private struct SectionCard: View {
    let section: CheatsheetDocument.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.9)
                    .foregroundColor(accentColor)
                    .padding(.bottom, 3)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !section.sub.isEmpty {
                    Text(section.sub)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.bottom, section.idea == nil ? 12 : 8)
                }

                if let idea = section.idea, !idea.isEmpty {
                    Text(idea)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundColor(accentColor.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }

                // Custom-layout sections (currently only "keyboard") render
                // a diagram above the row table.
                if section.customLayout?.lowercased() == "keyboard" {
                    SpatialKeyboardView()
                        .padding(.bottom, hasRenderableRows ? 10 : 0)
                }

                ForEach(Array(renderableRows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Filtered rows: `[":sub", "..."]` markers are layout metadata, not
    /// rendered content. The packer consumes them; the renderer skips
    /// them. (Chunks emitted by `splitIntoChunks` don't contain `:sub`
    /// rows at all, but we filter defensively in case a section opts
    /// out of `splitAfter` but still has `:sub` markers for the future.)
    private var renderableRows: [[String]] {
        section.rows.filter { $0.first != ":sub" }
    }

    private var hasRenderableRows: Bool { !renderableRows.isEmpty }

    private func rowView(_ row: [String]) -> some View {
        let key = row.indices.contains(0) ? row[0] : ""
        let desc = row.indices.contains(1) ? row[1] : ""

        return HStack(alignment: .top, spacing: 10) {
            if key == "—" {
                // Footnote row: italic muted prose, no badge, no keycap.
                Text("—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .frame(width: 78, alignment: .leading)
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.50))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ModifierBadge(forChord: key)
                    .padding(.top, 6)
                KeyCap(text: key)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933).opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var accentColor: Color {
        FamilyColors.resolve(family: section.family, fallbackHex: section.color)
    }
}

// MARK: - KeyCap

/// Visual rendering of a key chord. Looks like a keycap with a faint border.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}
