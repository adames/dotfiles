import SwiftUI
import WsUI

/// Binds directly to `ManageController`'s `@Published var stage`. No
/// separate view-model — the controller is the model. Workspace list is
/// a snapshot taken at overlay open (the controller's `workspaces` is a
/// `let`), so the view reads it directly through the controller.
struct ManageView: View {
    @ObservedObject var controller: ManageController

    var body: some View {
        // Fill the full hosting view so the VStack's default `.center`
        // alignment centers the card horizontally on screen — see
        // PromptView.swift for the same call.
        ZStack {
            // No background scrim — the card floats over the live desktop.
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
            stageBody
            hint
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 560)
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

    // MARK: - Header (title + breadcrumb chip)

    private var header: some View {
        HStack(spacing: 10) {
            Text("edit workspace")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            Spacer()
            breadcrumb
        }
    }

    /// Tiny chip that names the current stage. Acts as a breadcrumb so
    /// the user always sees where they are in the flow.
    private var breadcrumb: some View {
        Text(stageLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(stageColor)
            )
    }

    private var stageLabel: String {
        switch controller.stage {
        case .verbPicker:         return "MENU"
        case .addName, .addIcon:  return "ADD"
        case .renameTarget, .renameNewName: return "RENAME"
        case .destroyTarget, .destroyConfirm: return "DESTROY"
        case .iconTarget:         return "ICON"
        case .iconPick:           return "ICON · PICK"
        case .layoutVerb:         return "LAYOUT"
        case .layoutSaveName:     return "LAYOUT · SAVE"
        case .layoutLoadPick:     return "LAYOUT · LOAD"
        case .layoutDeletePick, .layoutDeleteConfirm: return "LAYOUT · DELETE"
        case .running(let v):     return v.uppercased() + "…"
        case .result(_, _, let ok): return ok ? "OK" : "ERROR"
        }
    }

    private var stageColor: Color {
        switch controller.stage {
        case .verbPicker, .layoutVerb:        return Catppuccin.blue
        case .addName, .addIcon:               return Catppuccin.green
        case .renameTarget, .renameNewName:    return Catppuccin.blue
        case .destroyTarget, .destroyConfirm,
             .layoutDeleteConfirm:             return Catppuccin.maroon
        case .iconTarget, .iconPick:           return Catppuccin.blue
        case .layoutSaveName, .layoutLoadPick, .layoutDeletePick: return Catppuccin.blue
        case .running:                         return Catppuccin.overlay1
        case .result(_, _, let ok):            return ok ? Catppuccin.green : Catppuccin.maroon
        }
    }

    // MARK: - Stage body

    @ViewBuilder
    private var stageBody: some View {
        switch controller.stage {
        case .verbPicker:                              verbPickerView
        case .addName(let buf):
            // Show the spelled-out default for the next slot so ↵ on an
            // empty buffer has an obvious effect ("ok, that one's named
            // `one`/`two`/…").
            let defaultName = ManageController.defaultName(forSlot: controller.workspaces.count + 1)
            textEntry(prompt: "new workspace name (default: \(defaultName))", buffer: buf)
        case .addIcon(_, let buf):                     textEntry(prompt: "icon (empty = stop.fill · type to filter SF Symbols)", buffer: buf)
        case .renameTarget(let f, let s, _):           targetPicker(filter: f, sel: s)
        case .renameNewName(_, let nm, let buf):       textEntry(prompt: "rename \"\(nm)\" →", buffer: buf)
        case .destroyTarget(let f, let s, _):          targetPicker(filter: f, sel: s)
        case .destroyConfirm(let i, let nm):           destroyConfirmView(slot: i, name: nm)
        case .iconTarget(let f, let s, _):             targetPicker(filter: f, sel: s)
        case .iconPick(_, let nm, let f, let s):       iconPicker(slotName: nm, filter: f, sel: s)
        case .layoutVerb:                              layoutVerbView
        case .layoutSaveName(let buf):                 textEntry(prompt: "layout name (letters / digits / . _ -)", buffer: buf)
        case .layoutLoadPick(let snaps, let f, let s): snapshotPicker(snaps: snaps, filter: f, sel: s, verb: "load")
        case .layoutDeletePick(let snaps, let f, let s): snapshotPicker(snaps: snaps, filter: f, sel: s, verb: "delete")
        case .layoutDeleteConfirm(let name):           snapshotDeleteConfirm(name: name)
        case .running(let v):                          runningView(verb: v)
        case .result(let t, let body, let ok):         resultView(title: t, body: body, success: ok)
        }
    }

    // MARK: - Verb picker

    private var verbPickerView: some View {
        VStack(spacing: 6) {
            verbRow(key: "a",  desc: "add workspace",         color: Catppuccin.green)
            verbRow(key: "r",  desc: "rename workspace",      color: Catppuccin.blue)
            verbRow(key: "i",  desc: "set workspace icon",    color: Catppuccin.blue)
            verbRow(key: "d",  desc: "destroy workspace",     color: Catppuccin.maroon)
            verbRow(key: "⇧L", desc: "layout — save / load / delete", color: Catppuccin.blue)
            verbRow(key: "v",  desc: "verify cascade (ws verify)",    color: Catppuccin.subtext0)
            verbRow(key: "?",  desc: "doctor schema (ws doctor)",     color: Catppuccin.subtext0)
        }
    }

    private var layoutVerbView: some View {
        VStack(spacing: 6) {
            verbRow(key: "s", desc: "save current state as a layout", color: Catppuccin.green)
            verbRow(key: "l", desc: "load a saved layout",            color: Catppuccin.blue)
            verbRow(key: "x", desc: "delete a saved layout",          color: Catppuccin.maroon)
        }
    }

    private func verbRow(key: String, desc: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 12))
                .foregroundColor(Catppuccin.base)
                .frame(width: 40, height: PromptStyle.pillHeight)
                .background(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .fill(color)
                )
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(Catppuccin.text)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Text entry

    private func textEntry(prompt: String, buffer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Catppuccin.overlay1)
            HStack(spacing: 8) {
                Text(buffer.isEmpty ? "" : buffer)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Catppuccin.text)
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
    }

    // MARK: - Target picker (workspace list with fuzzy filter)
    //
    // Shape mirrors PromptView's listRows: same pill rows, selected row
    // gets the slot-color fill. The filter behaves like focus/send.

    private func targetPicker(filter: String, sel: Int) -> some View {
        let matches = FuzzyMatch.filter(controller.workspaces, query: filter, keyPath: { $0.name })
        let clampedSel = max(0, min(sel, max(0, matches.count - 1)))
        return VStack(alignment: .leading, spacing: 8) {
            textEntry(prompt: "filter by name (digit = slot), ↵ picks", buffer: filter)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { (idx, ws) in
                        workspaceRow(ws: ws, selected: idx == clampedSel)
                    }
                    if matches.isEmpty {
                        Text("no matching workspaces")
                            .font(.system(size: 11))
                            .foregroundColor(Catppuccin.overlay0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func workspaceRow(ws: Workspace, selected: Bool) -> some View {
        let slot = Color(hex: ws.color) ?? Catppuccin.overlay1
        let textColor: Color = selected ? Catppuccin.base : Catppuccin.text
        let glyphColor: Color = selected ? Catppuccin.base : slot
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(String(ws.index))
                    .font(.system(size: 12))
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

    // MARK: - Destroy confirm

    private func destroyConfirmView(slot: Int, name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("destroy slot \(slot) — \"\(name)\"?")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            Text("Windows on this space will reparent to a neighbouring space.\nHigher-numbered slots shift down by one.")
                .font(.system(size: 11))
                .foregroundColor(Catppuccin.overlay1)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                confirmChip(text: "press d again to destroy", color: Catppuccin.maroon)
                confirmChip(text: "esc to back out",          color: Catppuccin.overlay1)
            }
        }
    }

    private func snapshotDeleteConfirm(name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("delete layout \"\(name)\"?")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            HStack(spacing: 10) {
                confirmChip(text: "press d again to delete", color: Catppuccin.maroon)
                confirmChip(text: "esc to back out",         color: Catppuccin.overlay1)
            }
        }
    }

    private func confirmChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner).fill(color)
            )
    }

    // MARK: - Snapshot picker

    private func snapshotPicker(snaps: [String], filter: String,
                                sel: Int, verb: String) -> some View {
        let matches = FuzzyMatch.filter(snaps, query: filter, keyPath: { $0 })
        let clampedSel = max(0, min(sel, max(0, matches.count - 1)))
        return VStack(alignment: .leading, spacing: 8) {
            textEntry(prompt: "filter layouts to \(verb), ↵ picks", buffer: filter)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { (idx, name) in
                        snapshotRow(name: name, selected: idx == clampedSel)
                    }
                    if matches.isEmpty {
                        Text("no matching layouts")
                            .font(.system(size: 11))
                            .foregroundColor(Catppuccin.overlay0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func snapshotRow(name: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundColor(selected ? Catppuccin.base : Catppuccin.subtext0)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(selected ? Catppuccin.base : Catppuccin.text)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? Catppuccin.blue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(Catppuccin.blue.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Icon picker

    /// Fuzzy-filter list of SF Symbol entries. Each row previews
    /// the SF Symbol icon alongside its name; the selection writes
    /// `ws icon SLOT <sf-name>`. Catalog comes from the ws CLI.
    private func iconPicker(slotName: String, filter: String,
                            sel: Int) -> some View {
        let matches = FuzzyMatch.filter(controller.iconCatalogCached,
                                        query: filter,
                                        keyPath: { $0.sfName })
        let clampedSel = max(0, min(sel, max(0, matches.count - 1)))
        return VStack(alignment: .leading, spacing: 8) {
            textEntry(prompt: "icon for \"\(slotName)\" — fuzzy-filter, ↵ commits",
                      buffer: filter)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { (idx, entry) in
                        iconRow(entry: entry, selected: idx == clampedSel)
                    }
                    if matches.isEmpty {
                        Text("no matching icons")
                            .font(.system(size: 11))
                            .foregroundColor(Catppuccin.overlay0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func iconRow(entry: IconCatalogEntry, selected: Bool) -> some View {
        HStack(spacing: 12) {
            // SF Symbol preview
            Image(systemName: entry.sfName)
                .font(.system(size: 14))
                .foregroundColor(selected ? Catppuccin.base : Catppuccin.subtext0)
                .frame(width: 28, alignment: .center)
            Text(entry.sfName)
                .font(.system(size: 12))
                .foregroundColor(selected ? Catppuccin.base : Catppuccin.text)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? Catppuccin.blue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(Catppuccin.blue.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Running + result

    private func runningView(verb: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("running `ws \(verb)`…")
                .font(.system(size: 12))
                .foregroundColor(Catppuccin.text)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultView(title: String, body: String, success: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(success ? Catppuccin.green : Catppuccin.maroon)
            ScrollView {
                Text(body.isEmpty ? (success ? "(no output)" : "(no error message)") : body)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Catppuccin.subtext0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
        }
    }

    // MARK: - Hint strip

    private var hint: some View {
        Text(hintText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Catppuccin.overlay0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hintText: String {
        switch controller.stage {
        case .verbPicker:        return "pick a verb · esc cancels"
        case .addName:           return "type a name or ↵ to accept the default · no leading digit · esc backs out"
        case .addIcon:           return "type one glyph (Nerd Font / SF Symbol) or ↵ to skip (defaults to stop.fill) · esc backs out"
        case .renameTarget:      return "↵ renames focused · digit = slot · letters fuzzy-match · tab cycles · esc backs out"
        case .renameNewName:     return "type a new name · ↵ commits · esc backs out"
        case .destroyTarget:     return "↵ destroys focused · digit = slot · letters fuzzy-match · esc backs out"
        case .destroyConfirm:    return "press d / y / ↵ to confirm · esc backs out"
        case .iconTarget:        return "↵ picks focused · digit = slot · letters fuzzy-match · esc backs out"
        case .iconPick:          return "letters fuzzy-match · tab cycles · ↵ commits · esc backs out"
        case .layoutVerb:        return "s save · l load · x delete · esc backs out"
        case .layoutSaveName:    return "name your snapshot · ↵ commits · esc backs out"
        case .layoutLoadPick, .layoutDeletePick: return "letters filter · tab cycles · ↵ picks · esc backs out"
        case .layoutDeleteConfirm: return "press d / y / ↵ to confirm · esc backs out"
        case .running:           return "…"
        case .result:            return "any key to dismiss"
        }
    }
}
