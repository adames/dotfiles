import SwiftUI

/// Dual-coded vim motion diagram — a stylized QWERTY where motion-bearing
/// keys are highlighted *in place*. This is the canonical vi/vim cheatsheet
/// pattern (viemu.com) and the highest-leverage learning aid for raw vim
/// motion: instead of memorizing "h is left", you see h occupy the leftmost
/// slot of the arrow cluster.
///
/// Role colors are deliberately a small set — proximity (key position) does
/// most of the work; color just tags the role.
struct SpatialKeyboardView: View {
    /// Roughly: arrows · word-motion · char-find · search-jump · neutral.
    enum Role {
        case arrow, word, find, jump, neutral, dim

        // The `.jump` accent was previously FamilyColors.nvim. After the
        // nvim cheatsheet sections were pruned, FamilyColors.nvim went
        // with them; the spatial keyboard is the last consumer of that
        // particular pink, so the hex is inlined here. Search/jump keys
        // (/, n, N, *, #) stay visually distinct from word-motion (b, w,
        // e) and char-find (f, F, t, T) which both use the vim orange.
        private static let jumpAccent = Color(hex: "#f472b6") ?? .pink

        var bg: Color {
            switch self {
            case .arrow:   return FamilyColors.vim.opacity(0.85)
            case .word:    return FamilyColors.vim.opacity(0.50)
            case .find:    return FamilyColors.vim.opacity(0.32)
            case .jump:    return Self.jumpAccent.opacity(0.55)
            case .neutral: return Color.white.opacity(0.06)
            case .dim:     return Color.white.opacity(0.025)
            }
        }
        var fg: Color {
            switch self {
            case .arrow, .word, .find, .jump: return .white.opacity(0.95)
            case .neutral:                    return .white.opacity(0.55)
            case .dim:                        return .white.opacity(0.22)
            }
        }
    }

    struct Cap: Identifiable {
        let id = UUID()
        let letter: String
        let role: Role
        let hint: String?    // small subscript drawn under the letter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Three rows — stylized QWERTY. Indent each row slightly so the
            // staircase reads as a keyboard.
            row(offset: 0,  caps: row1)
            row(offset: 10, caps: row2)
            row(offset: 22, caps: row3)

            // Legend — tiny color key for the four highlighted roles.
            HStack(spacing: 10) {
                legendChip(color: Role.arrow.bg, label: "arrows")
                legendChip(color: Role.word.bg,  label: "word")
                legendChip(color: Role.find.bg,  label: "find char")
                legendChip(color: Role.jump.bg,  label: "search/jump")
            }
            .padding(.top, 2)
        }
    }

    private func row(offset: CGFloat, caps: [Cap]) -> some View {
        HStack(spacing: 4) {
            Spacer().frame(width: offset)
            ForEach(caps) { cap in
                keyCapView(cap)
            }
            Spacer(minLength: 0)
        }
    }

    private func keyCapView(_ cap: Cap) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(cap.role.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .frame(width: 22, height: 24)

            VStack(spacing: 0) {
                Text(cap.letter)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(cap.role.fg)
                if let hint = cap.hint {
                    Text(hint)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(cap.role.fg.opacity(0.75))
                        .padding(.bottom, 1)
                } else {
                    Spacer().frame(height: 0)
                }
            }
            .frame(width: 22, height: 24)
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.50))
        }
    }

    // MARK: - Keyboard rows
    //
    // Letters not bound to a motion are kept (greyed out) so the eye reads
    // the layout as a keyboard, not as scattered tokens. Hints are 1–2 chars
    // shown under the letter.

    private var row1: [Cap] = [
        .init(letter: "q", role: .neutral, hint: "rec"),
        .init(letter: "w", role: .word,    hint: "→w"),
        .init(letter: "e", role: .word,    hint: "→e"),
        .init(letter: "r", role: .dim,     hint: nil),
        .init(letter: "t", role: .find,    hint: "→t"),
        .init(letter: "y", role: .dim,     hint: nil),
        .init(letter: "u", role: .dim,     hint: nil),
        .init(letter: "i", role: .dim,     hint: nil),
        .init(letter: "o", role: .dim,     hint: nil),
        .init(letter: "p", role: .dim,     hint: nil),
    ]

    private var row2: [Cap] = [
        .init(letter: "a", role: .dim,     hint: nil),
        .init(letter: "s", role: .dim,     hint: nil),
        .init(letter: "d", role: .dim,     hint: nil),
        .init(letter: "f", role: .find,    hint: "→f"),
        .init(letter: "g", role: .jump,    hint: "gg"),
        .init(letter: "h", role: .arrow,   hint: "←"),
        .init(letter: "j", role: .arrow,   hint: "↓"),
        .init(letter: "k", role: .arrow,   hint: "↑"),
        .init(letter: "l", role: .arrow,   hint: "→"),
    ]

    private var row3: [Cap] = [
        .init(letter: "z", role: .dim,     hint: nil),
        .init(letter: "x", role: .dim,     hint: nil),
        .init(letter: "c", role: .dim,     hint: nil),
        .init(letter: "v", role: .dim,     hint: nil),
        .init(letter: "b", role: .word,    hint: "←w"),
        .init(letter: "n", role: .jump,    hint: "next"),
        .init(letter: "m", role: .neutral, hint: "mark"),
    ]
}
