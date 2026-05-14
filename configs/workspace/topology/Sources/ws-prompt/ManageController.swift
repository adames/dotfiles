import Foundation

/// Where the manage overlay is in its multi-step flow. Each stage owns
/// the data it needs to render and to transition forward. Esc always
/// drops back one stage; from `verbPicker` Esc cancels the overlay.
enum ManageStage: Equatable {
    case verbPicker
    case addName(buffer: String)
    case addIcon(name: String, buffer: String)
    case renameTarget(filter: String, selection: Int)
    case renameNewName(slot: Int, slotName: String, buffer: String)
    case destroyTarget(filter: String, selection: Int)
    case destroyConfirm(slot: Int, slotName: String)
    case layoutVerb
    case layoutSaveName(buffer: String)
    case layoutLoadPick(snapshots: [String], filter: String, selection: Int)
    case layoutDeletePick(snapshots: [String], filter: String, selection: Int)
    case layoutDeleteConfirm(name: String)
    case running(verb: String)
    case result(title: String, body: String, success: Bool)
}

/// What ManageController.handle returns. The caller (main.swift) executes
/// `.runCommand` side-effects, captures the result, and feeds it back
/// into the controller via `applyCommandResult(...)`. `.idle` means
/// the view should re-render but no side effect runs. `.terminate`
/// closes the overlay.
enum ManageAction: Equatable {
    case idle
    case runCommand(verb: String, args: [String], capture: Bool)
    case terminate
}

/// Multi-stage state machine for the manage overlay. The actual command
/// dispatch (Process.run) lives in main.swift so this stays unit-testable
/// and side-effect-free.
final class ManageController {
    private(set) var stage: ManageStage = .verbPicker
    private(set) var workspaces: [Workspace]
    private let wsBinary: String

    /// Layout-snapshot list is loaded on demand the first time the user
    /// enters the layout sub-flow; cached after that.
    private var snapshotCache: [String]?

    init(workspaces: [Workspace],
         wsBinary: String = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".local/bin/ws").path) {
        self.workspaces = workspaces
        self.wsBinary = wsBinary
    }

    // MARK: - Event handling

    /// Drive the state machine. One key in, one Action out.
    func handle(_ key: PromptKey) -> ManageAction {
        switch stage {
        case .verbPicker:                       return atVerbPicker(key)
        case .addName(let buf):                 return atAddName(key, buf: buf)
        case .addIcon(let n, let buf):          return atAddIcon(key, name: n, buf: buf)
        case .renameTarget(let f, let s):       return atRenameTarget(key, filter: f, sel: s)
        case .renameNewName(let i, let nm, let buf):
            return atRenameNewName(key, slot: i, slotName: nm, buf: buf)
        case .destroyTarget(let f, let s):      return atDestroyTarget(key, filter: f, sel: s)
        case .destroyConfirm(let i, let nm):    return atDestroyConfirm(key, slot: i, slotName: nm)
        case .layoutVerb:                       return atLayoutVerb(key)
        case .layoutSaveName(let buf):          return atLayoutSaveName(key, buf: buf)
        case .layoutLoadPick(let snaps, let f, let s):
            return atLayoutPick(key, snapshots: snaps, filter: f, sel: s, mode: .load)
        case .layoutDeletePick(let snaps, let f, let s):
            return atLayoutPick(key, snapshots: snaps, filter: f, sel: s, mode: .delete)
        case .layoutDeleteConfirm(let name):    return atLayoutDeleteConfirm(key, name: name)
        case .running:                          return .idle    // ignore input while command in flight
        case .result:                           return .terminate   // any key dismisses
        }
    }

    /// main.swift calls this after running a `.runCommand` to surface the
    /// result. Transitions the stage to `.result(...)`. The view re-renders;
    /// the next keystroke (handled in `.result`) terminates the overlay.
    func applyCommandResult(verb: String, success: Bool, output: String) {
        let title = success ? "\(verb): ok" : "\(verb): failed"
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        stage = .result(title: title, body: body, success: success)
    }

    /// Read the layout-snapshot list lazily. main.swift calls this when
    /// entering layout load/delete so the picker has names to show.
    func loadSnapshots() -> [String] {
        if let cached = snapshotCache { return cached }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: wsBinary)
        task.arguments = ["layout", "list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        let snaps = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        snapshotCache = snaps
        return snaps
    }

    // MARK: - Stage handlers

    private func atVerbPicker(_ key: PromptKey) -> ManageAction {
        switch key {
        case .escape:        return .terminate
        case .char("a"), .char("A"):  stage = .addName(buffer: "");        return .idle
        case .char("r"), .char("R"):  stage = .renameTarget(filter: "", selection: 0);  return .idle
        case .char("d"), .char("D"):  stage = .destroyTarget(filter: "", selection: 0); return .idle
        case .char("L"):              // capital L only (Shift+L), avoids clashing with destroy 'd'
            stage = .layoutVerb;       return .idle
        case .char("v"), .char("V"):
            stage = .running(verb: "verify")
            return .runCommand(verb: "verify", args: ["verify"], capture: true)
        case .char("?"):
            stage = .running(verb: "doctor")
            return .runCommand(verb: "doctor", args: ["doctor"], capture: true)
        default:             return .idle
        }
    }

    private func atAddName(_ key: PromptKey, buf: String) -> ManageAction {
        switch key {
        case .escape:                stage = .verbPicker; return .idle
        case .backspace:             stage = .addName(buffer: String(buf.dropLast())); return .idle
        case .enter:
            let name = buf.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .idle }
            guard !name.first!.isNumber else {
                stage = .result(title: "add: rejected",
                                body: "name cannot start with a digit (reserved for slot indices)",
                                success: false)
                return .idle
            }
            stage = .addIcon(name: name, buffer: "")
            return .idle
        case .char(let c):
            // Refuse the first digit explicitly — `ws name` would reject
            // it on commit anyway, but stopping it here makes the
            // restriction visible while typing.
            if buf.isEmpty, c.isNumber {
                stage = .result(title: "add: rejected",
                                body: "name cannot start with a digit",
                                success: false)
                return .idle
            }
            stage = .addName(buffer: buf + String(c))
            return .idle
        case .tab, .backTab:         return .idle
        }
    }

    private func atAddIcon(_ key: PromptKey, name: String, buf: String) -> ManageAction {
        switch key {
        case .escape:        stage = .addName(buffer: name); return .idle
        case .backspace:     stage = .addIcon(name: name, buffer: String(buf.dropLast())); return .idle
        case .enter:
            // Empty icon → ws CLI uses its seeded default (kind=none).
            // Non-empty → pass through as the icon arg.
            var args = ["add", name, ""]
            if !buf.isEmpty { args.append(buf) }
            stage = .running(verb: "add")
            return .runCommand(verb: "add", args: args, capture: true)
        case .char(let c):
            stage = .addIcon(name: name, buffer: buf + String(c))
            return .idle
        case .tab, .backTab: return .idle
        }
    }

    private func atRenameTarget(_ key: PromptKey, filter: String, sel: Int) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            let matches = filteredWorkspaces(filter: filter)
            // Digit fast-path: empty filter, just numeric — commit the
            // explicit slot if it exists.
            if let target = digitTarget(filter: filter) {
                guard let ws = workspaces.first(where: { $0.index == target }) else {
                    stage = .result(title: "rename: rejected",
                                    body: "slot \(target) does not exist",
                                    success: false)
                    return .idle
                }
                stage = .renameNewName(slot: ws.index, slotName: ws.name, buffer: "")
                return .idle
            }
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            stage = .renameNewName(slot: pick.index, slotName: pick.name, buffer: "")
            return .idle
        case .tab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .renameTarget(filter: filter,
                                  selection: cycle(sel, count: matches.count, by: +1))
            return .idle
        case .backTab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .renameTarget(filter: filter,
                                  selection: cycle(sel, count: matches.count, by: -1))
            return .idle
        case .backspace:
            stage = .renameTarget(filter: String(filter.dropLast()), selection: 0); return .idle
        case .char(let c):
            stage = .renameTarget(filter: filter + String(c).lowercased(), selection: 0)
            return .idle
        }
    }

    private func atRenameNewName(_ key: PromptKey, slot: Int, slotName: String,
                                 buf: String) -> ManageAction {
        switch key {
        case .escape:        stage = .renameTarget(filter: "", selection: 0); return .idle
        case .backspace:     stage = .renameNewName(slot: slot, slotName: slotName,
                                                   buffer: String(buf.dropLast())); return .idle
        case .enter:
            let new = buf.trimmingCharacters(in: .whitespaces)
            guard !new.isEmpty else { return .idle }
            guard !new.first!.isNumber else {
                stage = .result(title: "rename: rejected",
                                body: "name cannot start with a digit", success: false)
                return .idle
            }
            stage = .running(verb: "name")
            return .runCommand(verb: "name", args: ["name", String(slot), new], capture: true)
        case .char(let c):
            stage = .renameNewName(slot: slot, slotName: slotName, buffer: buf + String(c))
            return .idle
        case .tab, .backTab: return .idle
        }
    }

    private func atDestroyTarget(_ key: PromptKey, filter: String, sel: Int) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            if let target = digitTarget(filter: filter) {
                guard let ws = workspaces.first(where: { $0.index == target }) else {
                    stage = .result(title: "destroy: rejected",
                                    body: "slot \(target) does not exist", success: false)
                    return .idle
                }
                stage = .destroyConfirm(slot: ws.index, slotName: ws.name)
                return .idle
            }
            let matches = filteredWorkspaces(filter: filter)
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            stage = .destroyConfirm(slot: pick.index, slotName: pick.name)
            return .idle
        case .tab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .destroyTarget(filter: filter,
                                   selection: cycle(sel, count: matches.count, by: +1))
            return .idle
        case .backTab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .destroyTarget(filter: filter,
                                   selection: cycle(sel, count: matches.count, by: -1))
            return .idle
        case .backspace:
            stage = .destroyTarget(filter: String(filter.dropLast()), selection: 0); return .idle
        case .char(let c):
            stage = .destroyTarget(filter: filter + String(c).lowercased(), selection: 0)
            return .idle
        }
    }

    private func atDestroyConfirm(_ key: PromptKey, slot: Int,
                                  slotName: String) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("d"), .char("D"), .char("y"), .char("Y"), .enter:
            stage = .running(verb: "remove")
            return .runCommand(verb: "remove", args: ["remove", String(slot), "-y"], capture: true)
        default:
            stage = .destroyTarget(filter: "", selection: 0)
            return .idle
        }
    }

    private func atLayoutVerb(_ key: PromptKey) -> ManageAction {
        switch key {
        case .escape:        stage = .verbPicker; return .idle
        case .char("s"), .char("S"): stage = .layoutSaveName(buffer: ""); return .idle
        case .char("l"), .char("L"):
            let snaps = loadSnapshots()
            guard !snaps.isEmpty else {
                stage = .result(title: "layout load",
                                body: "no saved layouts (use `s` to save the current state)",
                                success: false)
                return .idle
            }
            stage = .layoutLoadPick(snapshots: snaps, filter: "", selection: 0)
            return .idle
        case .char("x"), .char("X"), .char("d"), .char("D"):
            let snaps = loadSnapshots()
            guard !snaps.isEmpty else {
                stage = .result(title: "layout delete",
                                body: "no saved layouts", success: false)
                return .idle
            }
            stage = .layoutDeletePick(snapshots: snaps, filter: "", selection: 0)
            return .idle
        default: return .idle
        }
    }

    private func atLayoutSaveName(_ key: PromptKey, buf: String) -> ManageAction {
        switch key {
        case .escape:        stage = .layoutVerb; return .idle
        case .backspace:     stage = .layoutSaveName(buffer: String(buf.dropLast())); return .idle
        case .enter:
            let name = buf.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .idle }
            stage = .running(verb: "layout save")
            return .runCommand(verb: "layout save", args: ["layout", "save", name], capture: true)
        case .char(let c):
            // Layout name validator (matches the CLI's [A-Za-z0-9._-]+).
            // Reject invalid chars early so the user sees the rule.
            let allowed = c.isLetter || c.isNumber || c == "." || c == "_" || c == "-"
            guard allowed else { return .idle }
            stage = .layoutSaveName(buffer: buf + String(c))
            return .idle
        case .tab, .backTab: return .idle
        }
    }

    enum LayoutPickMode { case load, delete }

    private func atLayoutPick(_ key: PromptKey, snapshots: [String], filter: String,
                              sel: Int, mode: LayoutPickMode) -> ManageAction {
        let matches = snapshots.filter { filter.isEmpty || $0.lowercased().contains(filter.lowercased()) }
        switch key {
        case .escape:        stage = .layoutVerb; return .idle
        case .enter:
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            switch mode {
            case .load:
                stage = .running(verb: "layout load")
                return .runCommand(verb: "layout load",
                                   args: ["layout", "load", pick, "-y"], capture: true)
            case .delete:
                stage = .layoutDeleteConfirm(name: pick)
                return .idle
            }
        case .tab:
            stage = layoutPickStage(mode: mode, snaps: snapshots, filter: filter,
                                    sel: cycle(sel, count: matches.count, by: +1))
            return .idle
        case .backTab:
            stage = layoutPickStage(mode: mode, snaps: snapshots, filter: filter,
                                    sel: cycle(sel, count: matches.count, by: -1))
            return .idle
        case .backspace:
            stage = layoutPickStage(mode: mode, snaps: snapshots,
                                    filter: String(filter.dropLast()), sel: 0)
            return .idle
        case .char(let c):
            stage = layoutPickStage(mode: mode, snaps: snapshots,
                                    filter: filter + String(c).lowercased(), sel: 0)
            return .idle
        }
    }

    private func atLayoutDeleteConfirm(_ key: PromptKey, name: String) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("d"), .char("D"), .char("y"), .char("Y"), .enter:
            stage = .running(verb: "layout delete")
            return .runCommand(verb: "layout delete",
                               args: ["layout", "delete", name, "-y"], capture: true)
        default:
            stage = .layoutVerb
            return .idle
        }
    }

    // MARK: - Helpers

    private func layoutPickStage(mode: LayoutPickMode, snaps: [String],
                                 filter: String, sel: Int) -> ManageStage {
        switch mode {
        case .load:   return .layoutLoadPick(snapshots: snaps, filter: filter, selection: sel)
        case .delete: return .layoutDeletePick(snapshots: snaps, filter: filter, selection: sel)
        }
    }

    func filteredWorkspaces(filter: String) -> [Workspace] {
        guard !filter.isEmpty else { return workspaces }
        let q = filter.lowercased()
        return workspaces.filter { $0.name.lowercased().contains(q) }
    }

    /// If `filter` is purely numeric, parse it as a slot index. Used by
    /// rename/destroy target pickers to keep the "digit = slot N" shortcut
    /// alive that focus/send already have.
    private func digitTarget(filter: String) -> Int? {
        guard !filter.isEmpty, filter.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(filter)
    }

    private func cycle(_ sel: Int, count: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((sel + delta) % count + count) % count
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
