import SwiftUI
import WsUI   // re-exports `Color(hex:)`

/// The HUD view, a *learning aid* shaped as a category mosaic:
///
/// - Each **column** is one family (system / terminal / vim / nvim+git).
///   Family color carries the categorical cue; physical adjacency
///   reinforces it.
/// - Within a column, cards stack tightly (no row alignment, no algorithm).
/// - Card layout is **declared** by `cheatsheet-layout.json` and produced
///   by `lib/cheatsheet-gen.py` from `@cs` annotations in the upstream
///   config files. The renderer just iterates the columns the JSON gave
///   it — no computation.
///
/// Within a card:
///   - section header → idea caption → row table.
///   - The vim-motion card opts into `customLayout: "keyboard"` and
///     renders a spatial keyboard above the table (Paivio dual-coding).
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
            VStack(spacing: 16) {
                bannerStrip
                columnGrid
                footer
            }
            .padding(.horizontal, outerHPadding)
            .padding(.top, outerTopPadding)
            .padding(.bottom, outerBottomPadding)
            .frame(maxWidth: maxPageWidth, maxHeight: .infinity)
        }
    }

    /// Static family columns. Each column gets an equal share of the
    /// available width via `.frame(maxWidth: .infinity)`; SwiftUI's
    /// `HStack` splits leftover space evenly across its children.
    private var columnGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(document.columns) { column in
                    VStack(spacing: cardSpacing) {
                        ForEach(column.sections) { section in
                            SectionCard(section: section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.bottom, 6)
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
                        .font(.system(size: 10))
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
                .font(.system(size: 10))
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
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(0.9)
                    .foregroundColor(accentColor)
                    .padding(.bottom, 3)

                if let sub = section.sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.bottom, section.idea == nil ? 12 : 8)
                }

                if let idea = section.idea, !idea.isEmpty {
                    Text(idea)
                        .font(.system(size: 13))
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
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .frame(width: 78, alignment: .leading)
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.50))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ModifierBadge(forChord: key)
                    .padding(.top, 8)
                KeyCap(text: key)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933).opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var accentColor: Color {
        FamilyColors.resolve(family: section.family, fallbackHex: section.color ?? "")
    }
}

// MARK: - KeyCap

/// Visual rendering of a key chord. Looks like a keycap with a faint border.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
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
