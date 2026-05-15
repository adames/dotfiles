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
/// Layout: **masonry** (see Masonry.swift). Cards drop into the shortest
/// column at the time of placement — same trick CSS column-count gives
/// you for free. This trades the previous LazyVGrid's row-alignment
/// (which forced every card in a row to match the tallest one's height,
/// wasting vertical room under shorter neighbors) for tight Pinterest-
/// style packing. Family color carries the organizational cue: same hue
/// = same world, regardless of which column the card landed in.
struct CheatsheetView: View {
    let document: CheatsheetDocument
    let timestamp: String

    private let outerHPadding: CGFloat = 40
    private let outerTopPadding: CGFloat = 36
    private let outerBottomPadding: CGFloat = 22
    private let columnSpacing: CGFloat = 14
    private let cardSpacing: CGFloat = 14
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

    /// Masonry grid. GeometryReader gives us the inner width so we can
    /// adapt the column count to the screen (2..6 columns) and compute an
    /// exact column width. ScrollView keeps each column independently
    /// scrollable when the tallest column exceeds the page.
    private var sectionGrid: some View {
        GeometryReader { geo in
            let usableWidth = min(geo.size.width, maxPageWidth - 2 * outerHPadding)
            let cols = Masonry.columnCount(forWidth: usableWidth, spacing: columnSpacing)
            let totalSpacing = columnSpacing * CGFloat(cols - 1)
            let columnWidth = (usableWidth - totalSpacing) / CGFloat(cols)
            let columns = Masonry.columnize(
                sections: document.sections,
                columnCount: cols
            )

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns) { column in
                        VStack(spacing: cardSpacing) {
                            ForEach(column.sections) { section in
                                SectionCard(section: section)
                            }
                        }
                        .frame(width: columnWidth, alignment: .top)
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

                Text(section.sub)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.bottom, section.idea == nil ? 12 : 8)

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
                        .padding(.bottom, section.rows.isEmpty ? 0 : 10)
                }

                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
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
