import SwiftUI

/// View-model that mirrors `PromptController`'s state for the SwiftUI
/// renderer. The controller is the source of truth; this just exposes
/// `@Published`-shaped properties for the view to bind against.
final class PromptViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var matches: [Workspace] = []
    @Published var selection: Int = 0
    let mode: PromptMode

    init(mode: PromptMode, workspaces: [Workspace]) {
        self.mode = mode
        self.matches = workspaces
    }
}

// MARK: - Visual vocabulary (Catppuccin Mocha, matches sketchybar)
//
// The overlay borrows its color, typography, and shape language from
// `configs/sketchybar/colors.sh` + `plugins/per-display-pills.sh` so
// switching between the bar and the prompt doesn't feel like crossing
// into a different app. Pill height 22pt, corner radius 6pt, font
// `JetBrainsMono Nerd Font:Bold:12pt`. Focused row uses the slot color
// as a full fill with dark text (catppuccin base) — same as the
// workspace.name.<D> chip on the focused display. Unfocused rows mirror
// the unfocused chip: transparent fill, slot-color border + label.

enum Catppuccin {
    static let crust    = Color(hex: "#11111b") ?? .black
    static let mantle   = Color(hex: "#181825") ?? .black
    static let base     = Color(hex: "#1e1e2e") ?? .black
    static let surface0 = Color(hex: "#313244") ?? .gray
    static let surface1 = Color(hex: "#45475a") ?? .gray
    static let overlay0 = Color(hex: "#6c7086") ?? .gray
    static let overlay1 = Color(hex: "#7f849c") ?? .gray
    static let subtext0 = Color(hex: "#a6adc8") ?? .white
    static let text     = Color(hex: "#cdd6f4") ?? .white
    static let blue     = Color(hex: "#89b4fa") ?? .blue
    static let green    = Color(hex: "#a6e3a1") ?? .green
    static let maroon   = Color(hex: "#eba0ac") ?? .pink
}

enum PromptStyle {
    /// `JetBrainsMono Nerd Font:Bold` — same family the sketchybar pill
    /// strip uses. Custom font means the Nerd Font private-use glyphs
    /// render correctly; default `.system(design: .monospaced)` is
    /// SF Mono, which doesn't ship the workspace icons.
    static let nerdFontFamily = "JetBrainsMono Nerd Font"

    static func nerd(_ size: CGFloat) -> Font {
        .custom(nerdFontFamily, size: size).weight(.bold)
    }

    static let pillCorner: CGFloat = 6
    static let pillHeight: CGFloat = 22
    static let cardCorner: CGFloat = 10
}

struct PromptView: View {
    @ObservedObject var vm: PromptViewModel

    var body: some View {
        ZStack {
            // Scrim: same darken-everything-else cue as ws-cheatsheet, a
            // touch lighter so the catppuccin card's `mantle` background
            // reads as the focused surface.
            Color.black.opacity(0.45)

            VStack(spacing: 14) {
                Spacer().frame(height: 96)
                card
                Spacer()
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            queryField
            listRows
            hint
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                .fill(Catppuccin.mantle.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                        .strokeBorder(Catppuccin.surface0.opacity(0.85), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(PromptStyle.nerd(13))
                .foregroundColor(Catppuccin.text)
            Spacer()
            modeChip
        }
    }

    private var title: String {
        // PromptView is only instantiated for focus/send; manage uses
        // ManageView. The .manage arms here exist only to satisfy
        // exhaustiveness — they're never rendered.
        switch vm.mode {
        case .focus:  return "focus workspace"
        case .send:   return "send window"
        case .manage: return ""
        }
    }

    /// Same shape as a sketchybar workspace.name chip — fixed corner,
    /// 22pt tall, full-color fill, dark catppuccin text.
    private var modeChip: some View {
        Text(modeChipLabel)
            .font(PromptStyle.nerd(11))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(modeChipColor)
            )
    }

    private var modeChipLabel: String {
        switch vm.mode {
        case .focus:  return "FOCUS"
        case .send:   return "SEND"
        case .manage: return ""
        }
    }
    private var modeChipColor: Color {
        switch vm.mode {
        case .focus:  return Catppuccin.blue   // navigate → blue (matches Hyper family)
        case .send:   return Catppuccin.green  // move-and-follow → green
        case .manage: return Catppuccin.maroon // unused (ManageView renders manage)
        }
    }

    // MARK: - Query field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.mode == .focus ? "arrow.right" : "paperplane.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(modeChipColor)
                .frame(width: 14)
            Text(displayQuery)
                .font(PromptStyle.nerd(13))
                .foregroundColor(vm.query.isEmpty ? Catppuccin.overlay0 : Catppuccin.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("↵")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Catppuccin.overlay0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(Catppuccin.base.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(Catppuccin.surface0.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var displayQuery: String {
        if vm.query.isEmpty {
            return "1–9 / 0 commits · letters search · ↵"
        }
        return vm.query
    }

    // MARK: - Workspace list

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(vm.matches.enumerated()), id: \.offset) { (idx, ws) in
                    workspaceRow(ws: ws, selected: idx == vm.selection)
                }
                if vm.matches.isEmpty {
                    Text("no matching workspaces")
                        .font(.system(size: 11))
                        .foregroundColor(Catppuccin.overlay0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    /// One row = one sketchybar pill. We mirror the chip's
    /// focused/unfocused visual contract directly:
    ///   - Selected row → filled with slot color, dark catppuccin text.
    ///     This is exactly what `workspace.name.<D>` looks like on the
    ///     focused display.
    ///   - Unselected row → transparent fill, slot-color border + text.
    ///     Same as the unfocused-display chip.
    private func workspaceRow(ws: Workspace, selected: Bool) -> some View {
        let slot = Color(hex: ws.color) ?? Catppuccin.overlay1
        let textColor: Color = selected ? Catppuccin.base : Catppuccin.text
        let glyphColor: Color = selected ? Catppuccin.base : slot
        return HStack(spacing: 10) {
            // Pill identity zone: "<digit> <glyph>" — same single-string
            // shape paint-all.sh writes to a real pill (`icon_text`).
            HStack(spacing: 6) {
                Text(String(ws.index))
                    .font(PromptStyle.nerd(12))
                    .foregroundColor(glyphColor)
                if let icon = ws.icon, ws.iconKind == .sfSymbol {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(glyphColor)
                } else if let icon = ws.icon {
                    Text(icon)
                        .font(PromptStyle.nerd(12))
                        .foregroundColor(glyphColor)
                }
            }
            .frame(width: 56, alignment: .leading)

            Text(ws.name)
                .font(PromptStyle.nerd(12))
                .foregroundColor(textColor)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? slot : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(slot.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Hint

    private var hint: some View {
        Text("1–0 commits · letters fuzzy-match · ↵ commits · tab cycles · esc cancels")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Catppuccin.overlay0)
            .frame(maxWidth: .infinity, alignment: .leading)
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
