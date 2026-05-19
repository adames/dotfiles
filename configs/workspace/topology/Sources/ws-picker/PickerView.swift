import AppKit
import SwiftUI
import WsUI

/// SwiftUI overlay for the **change workspace** prompt (binary: ws-picker).
/// Lists every visible window across every space; selecting one focuses
/// that window, which yabai follows by jumping to its space. Visual
/// contract matches ws-prompt's PromptView so the workspace-prompt suite
/// feels like one tool: same card geometry, Catppuccin palette, pill style.
struct PickerView: View {
    @ObservedObject var controller: PickerController

    private var matches: [WindowItem] { controller.currentMatches() }

    var body: some View {
        // Fill the full hosting view so the VStack's default `.center`
        // alignment centers the card horizontally on screen — without
        // maxWidth/maxHeight the ZStack shrinks to the card's 520pt and
        // NSHostingView pins it to the top-leading corner. Mirrors the
        // ws-prompt PromptView body for visual parity across overlays.
        ZStack {
            // No background scrim — the card floats over the live desktop.
            // Borderless window is already transparent (WsPickerApp).
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
            Text("change workspace")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            Spacer()
            modeChip
        }
    }

    private var modeChip: some View {
        Text("CHANGE")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(Catppuccin.blue)
            )
    }

    // MARK: - Query field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Catppuccin.blue)
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
        controller.query.isEmpty
            ? "type app or title · ↵ jumps to that window's workspace · esc cancels"
            : controller.query
    }

    // MARK: - List

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { (idx, item) in
                    windowRow(item: item, selected: idx == controller.selection)
                }
                if matches.isEmpty {
                    Text("no matching windows")
                        .font(.system(size: 11))
                        .foregroundColor(Catppuccin.overlay0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    /// One row mirrors a workspace pill from PromptView: app icon + name
    /// on the left, window title on the right, space-index pill at the
    /// far end. Selected row fills with Catppuccin.blue (the same color
    /// the focus prompt uses for its navigate-action chip).
    private func windowRow(item: WindowItem, selected: Bool) -> some View {
        let accent = Catppuccin.blue
        let textColor: Color = selected ? Catppuccin.base : Catppuccin.text
        let subColor:  Color = selected ? Catppuccin.base.opacity(0.75) : Catppuccin.overlay1
        return HStack(spacing: 10) {
            iconView(for: item.app, tinted: selected)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayLabel)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !item.title.isEmpty {
                    Text(item.app)
                        .font(.system(size: 10))
                        .foregroundColor(subColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("ws\(item.space)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(selected ? Catppuccin.base : accent)
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 12)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(accent.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
    }

    /// App icon rendered at row height. NSWorkspace's icon cache means
    /// repeated lookups are cheap — fine to resolve inline per row.
    @ViewBuilder
    private func iconView(for app: String, tinted selected: Bool) -> some View {
        if let nsImage = AppIconResolver.icon(forAppName: app) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .opacity(selected ? 0.95 : 1.0)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selected ? Catppuccin.base : Catppuccin.overlay1)
        }
    }

    private var hint: some View {
        Text("letters fuzzy-match · ↵ jumps to that workspace · tab/⇧tab cycles · esc cancels")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Catppuccin.overlay0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Resolve an app's icon by its display name. Caches NSImage instances
/// because the picker re-asks for the same icon on every keystroke.
enum AppIconResolver {
    private static var cache: [String: NSImage] = [:]

    static func icon(forAppName name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            let img = workspace.icon(forFile: url.path)
            cache[name] = img
            return img
        }
        // Fall back to a running-app lookup by localized name. Many apps
        // expose a display name that doesn't match their bundle identifier.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: name) {
            if let img = app.icon {
                cache[name] = img
                return img
            }
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "")
            .first(where: { $0.localizedName == name }),
           let img = app.icon {
            cache[name] = img
            return img
        }
        // Last resort — scan running apps by display name. Slower than
        // a bundle-ID lookup but only runs on a cache miss.
        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == name }),
           let img = app.icon {
            cache[name] = img
            return img
        }
        return nil
    }
}
