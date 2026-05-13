import SwiftUI

/// The HUD view. Mirrors the catppuccin/cyberpunk feel of the Lua original:
/// transparent backdrop, blurred cards with a colored top accent, dense rows
/// of (key, description). Layout is an adaptive grid that flows naturally
/// across display widths.
struct CheatsheetView: View {
    let document: CheatsheetDocument
    let timestamp: String

    var body: some View {
        ZStack {
            // Backdrop: subtle dim. Cards provide their own blur.
            Color.black.opacity(0.35)

            VStack(spacing: 14) {
                bannerStrip
                sectionGrid
                footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .frame(maxWidth: 1720, maxHeight: .infinity)
        }
    }

    private var bannerStrip: some View {
        HStack(spacing: 22) {
            ForEach(Array(document.banner.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 8) {
                    KeyCap(text: item.k)
                    Text(item.v)
                        .font(.system(size: 11.5, design: .default))
                        .foregroundColor(.white.opacity(0.55))
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
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var sectionGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 290), spacing: 14, alignment: .top)],
                spacing: 14
            ) {
                ForEach(document.sections) { section in
                    SectionCard(section: section)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("CAPS LOCK + ; (or Esc) TO CLOSE  ·  \(timestamp)")
                .font(.system(size: 11, design: .default))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }
}

private struct SectionCard: View {
    let section: CheatsheetDocument.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent top-bar
            Rectangle()
                .fill(accentColor)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(section.title.uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(accentColor)
                    .padding(.bottom, 3)

                Text(section.sub)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.32))
                    .padding(.bottom, 12)

                ForEach(Array(section.rows.enumerated()), id: \.offset) { idx, row in
                    rowView(row)
                    if idx < section.rows.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.045))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rowView(_ row: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            let key = row.indices.contains(0) ? row[0] : ""
            let desc = row.indices.contains(1) ? row[1] : ""
            if key == "—" {
                Text("—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .frame(width: 80, alignment: .leading)
                Text(desc)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.55))
                    .italic()
            } else {
                KeyCap(text: key)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933).opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var accentColor: Color {
        Color(hex: section.color) ?? .accentColor
    }
}

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

extension Color {
    /// Initialize from a "#RRGGBB" string. Returns nil on parse failure.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
