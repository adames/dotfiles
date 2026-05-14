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

struct PromptView: View {
    @ObservedObject var vm: PromptViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
            VStack(spacing: 14) {
                Spacer().frame(height: 80)
                card
                Spacer()
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if vm.mode == .manage {
                manageRows
            } else {
                queryField
                listRows
            }
            hint
        }
        .padding(20)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
            Spacer()
            Text(modeChipLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: chipColor) ?? .blue)
                )
        }
    }

    private var title: String {
        switch vm.mode {
        case .focus:  return "Focus workspace"
        case .send:   return "Send window to workspace"
        case .manage: return "Manage workspaces"
        }
    }
    private var modeChipLabel: String {
        switch vm.mode {
        case .focus:  return "FOCUS"
        case .send:   return "SEND"
        case .manage: return "MANAGE"
        }
    }
    private var chipColor: String {
        switch vm.mode {
        case .focus:  return "#60a5fa"
        case .send:   return "#34d399"
        case .manage: return "#fb7185"
        }
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Text(vm.query.isEmpty ? "1–9 / 0 commits · letters fuzzy-match" : vm.query)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(vm.query.isEmpty ? .white.opacity(0.35) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("↵")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(vm.matches.enumerated()), id: \.offset) { (idx, ws) in
                    workspaceRow(ws: ws, selected: idx == vm.selection)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func workspaceRow(ws: Workspace, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%2d", ws.index))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.black.opacity(0.78))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: ws.color) ?? .gray)
                )
            if let icon = ws.icon, ws.iconKind == .sfSymbol {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(width: 18)
            } else if let icon = ws.icon {
                Text(icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(width: 18)
            } else {
                Spacer().frame(width: 18)
            }
            Text(ws.name)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.94))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.white.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    selected ? (Color(hex: ws.color) ?? .blue).opacity(0.8) : .clear,
                    lineWidth: 1
                )
        )
    }

    private var manageRows: some View {
        VStack(spacing: 6) {
            manageRow(key: "a",  desc: "add workspace")
            manageRow(key: "r",  desc: "rename current")
            manageRow(key: "i",  desc: "info")
            manageRow(key: "l",  desc: "list (cheatsheet)")
            manageRow(key: "⇧D", desc: "destroy current")
        }
    }

    private func manageRow(key: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 32, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.12))
                )
            Text(desc)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.94))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var hint: some View {
        Text(vm.mode == .manage
             ? "Esc cancels · click-elsewhere cancels"
             : "1–0 commits · letters fuzzy-match · ↵ commits · Tab cycles · Esc cancels")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.42))
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
