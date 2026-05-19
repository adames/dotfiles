import SwiftUI
import WsUI

// Visual vocabulary (palette, typography, pill geometry) lives in
// WsUI/DesignSystem.swift — see `Catppuccin` and `PromptStyle`. The
// overlay borrows its language from `configs/sketchybar/colors.sh` so
// switching between the bar and the prompt feels like one app.

/// Binds directly to `PromptController`'s `@Published` state — no
/// separate view-model. The view re-renders whenever query / selection
/// changes; `currentMatches()` recomputes the filter on each render
/// (cheap for <20 workspaces).
struct PromptView: View {
    @ObservedObject var controller: PromptController

    /// Match list pulled lazily — controllers don't store this, the
    /// view just asks for it each render via the fuzzy filter.
    private var matches: [Workspace] { controller.currentMatches() }

    var body: some View {
        // Fill the full hosting view so the VStack's default `.center`
        // alignment centers the card horizontally on screen. Without
        // maxWidth/maxHeight the ZStack shrinks to the card's 520pt and
        // NSHostingView pins it to the top-leading corner.
        ZStack {
            // No background scrim. The borderless window is transparent
            // (isOpaque=false in WsPromptApp); the card's own opaque
            // catppuccin background carries the visual weight so the
            // prompt floats above the live desktop instead of dimming it.
            VStack(spacing: 14) {
                Spacer().frame(height: PromptStyle.topInset)
                card
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            Spacer()
            modeChip
        }
    }

    private var title: String {
        // PromptView is only instantiated for focus/send; manage uses
        // ManageView. The .manage arms here exist only to satisfy
        // exhaustiveness — they're never rendered.
        switch controller.mode {
        case .focus:  return "focus workspace"
        case .send:   return "send window"
        case .manage: return ""
        }
    }

    /// Same shape as a sketchybar workspace.name chip — fixed corner,
    /// 22pt tall, full-color fill, dark catppuccin text.
    private var modeChip: some View {
        Text(modeChipLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(modeChipColor)
            )
    }

    private var modeChipLabel: String {
        switch controller.mode {
        case .focus:  return "FOCUS"
        case .send:   return "SEND"
        case .manage: return ""
        }
    }
    private var modeChipColor: Color {
        switch controller.mode {
        case .focus:  return Catppuccin.blue   // navigate → blue (matches Hyper family)
        case .send:   return Catppuccin.green  // move-and-follow → green
        case .manage: return Catppuccin.maroon // unused (ManageView renders manage)
        }
    }

    // MARK: - Query field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.mode == .focus ? "arrow.right" : "paperplane.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(modeChipColor)
                .frame(width: 14)
            Text(displayQuery)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(controller.query.isEmpty ? Catppuccin.overlay0 : Catppuccin.text)
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
        if controller.query.isEmpty {
            return "1–9 / 0 commits · letters search · ↵"
        }
        return controller.query
    }

    // MARK: - Workspace list

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(matches.enumerated()), id: \.offset) { (idx, ws) in
                    workspaceRow(ws: ws, selected: idx == controller.selection)
                }
                if matches.isEmpty {
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(glyphColor)
                if let icon = ws.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(glyphColor)
                }
            }
            .frame(width: 56, alignment: .leading)

            Text(ws.name)
                .font(.system(size: 12))
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
        Text(hintText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Catppuccin.overlay0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hintText: String {
        switch controller.mode {
        case .focus:
            return "1–0 focuses · letters fuzzy-match · ↵ commits · tab cycles · esc cancels"
        case .send:
            return "1–0 sends + follows · letters fuzzy-match · ↵ commits · tab cycles · esc cancels"
        case .manage:
            return ""  // unreachable — ManageView owns the manage rendering
        }
    }
}
