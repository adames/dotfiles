import Foundation

/// Where the manage overlay is in its multi-step flow. Each stage owns
/// the data it needs to render and to transition forward. Esc always
/// drops back one stage; from `verbPicker` Esc cancels the overlay.
///
/// `inQueryMode` on the rename/destroy target pickers tracks whether
/// the user has started typing letters. Off → the next digit commits
/// directly to that slot (fast path: open prompt, press `5`, you're
/// renaming slot 5). On → digits join the filter buffer so 11+ can be
/// reached after an initial letter or backspace-erasure.
enum ManageStage: Equatable {
    case verbPicker
    case addName(buffer: String)
    case addIcon(name: String, buffer: String)
    case renameTarget(filter: String, selection: Int, inQueryMode: Bool)
    case renameNewName(slot: Int, slotName: String, buffer: String)
    case destroyTarget(filter: String, selection: Int, inQueryMode: Bool)
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
/// the side-effect cases, captures the result, and feeds it back via
/// `applyCommandResult(...)`. `.idle` means the view should re-render
/// but no side effect runs. `.terminate` closes the overlay.
///
/// Two binaries get invoked from the manage flow:
///
///   ws    — identity layer over spaces.json (`ws name`, `ws layout`,
///           `ws verify`, `ws doctor`). Output goes to the result panel.
///   yabai — the actual macOS Space lifecycle (`--create`, `--destroy`).
///           Requires the scripting-addition to be loaded.
///
/// `runAdd` is a composite: create the yabai space first, then attach
/// identity via `ws name <new_index>`. main.swift drives the sequence so
/// the state machine doesn't have to model two-stage execution.
enum ManageAction: Equatable {
    case idle
    case runWs(verb: String, args: [String])
    case runYabai(verb: String, args: [String])
    case runAdd(name: String, icon: String?)
    case terminate
}

/// Multi-stage state machine for the manage overlay. The actual command
/// dispatch (Process.run) lives in main.swift so this stays unit-testable
/// and side-effect-free.
final class ManageController {
    private(set) var stage: ManageStage = .verbPicker
    private(set) var workspaces: [Workspace]
    private let wsBinary: String

    /// Yabai's currently-focused space index, captured once at overlay
    /// open. Used to default the rename/destroy target pickers to "act
    /// on the workspace I'm already on" so Enter-without-typing is the
    /// fast path. Nil → fall back to selection index 0.
    private let focusedIndex: Int?

    /// Layout-snapshot list is loaded on demand the first time the user
    /// enters the layout sub-flow; cached after that.
    private var snapshotCache: [String]?

    init(workspaces: [Workspace],
         focusedIndex: Int? = nil,
         wsBinary: String = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".local/bin/ws").path) {
        self.workspaces = workspaces
        self.focusedIndex = focusedIndex
        self.wsBinary = wsBinary
    }

    /// Position of the focused workspace within `workspaces` (0-based),
    /// or 0 if yabai didn't report a focus. Used as the initial
    /// selection when entering a target picker.
    private var focusedSelection: Int {
        guard let fi = focusedIndex,
              let pos = workspaces.firstIndex(where: { $0.index == fi })
        else { return 0 }
        return pos
    }

    // MARK: - Event handling

    /// Drive the state machine. One key in, one Action out.
    func handle(_ key: PromptKey) -> ManageAction {
        switch stage {
        case .verbPicker:                       return atVerbPicker(key)
        case .addName(let buf):                 return atAddName(key, buf: buf)
        case .addIcon(let n, let buf):          return atAddIcon(key, name: n, buf: buf)
        case .renameTarget(let f, let s, let q):
            return atRenameTarget(key, filter: f, sel: s, inQueryMode: q)
        case .renameNewName(let i, let nm, let buf):
            return atRenameNewName(key, slot: i, slotName: nm, buf: buf)
        case .destroyTarget(let f, let s, let q):
            return atDestroyTarget(key, filter: f, sel: s, inQueryMode: q)
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
        case .char("r"), .char("R"):
            stage = .renameTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .char("d"), .char("D"):
            stage = .destroyTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .char("L"):              // capital L only (Shift+L), avoids clashing with destroy 'd'
            stage = .layoutVerb;       return .idle
        case .char("v"), .char("V"):
            stage = .running(verb: "verify")
            return .runWs(verb: "verify", args: ["verify"])
        case .char("?"):
            stage = .running(verb: "doctor")
            return .runWs(verb: "doctor", args: ["doctor"])
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
            // Icon resolution policy: empty → no icon (CLI default).
            // Single character → assume the user typed a Nerd Font glyph
            // directly; pass through. Multi-char → must exist in the
            // SF Symbol → Nerd Font map, otherwise silently drop it so
            // the workspace is created cleanly rather than with a
            // placeholder glyph (which the CLI would warn about).
            //
            // Composite execution: main.swift runs `yabai space --create`
            // first to actually allocate the macOS Space, then attaches
            // identity via `ws name <new_index> NAME [ICON]`. Without
            // the yabai step the slot would be an orphan in spaces.json
            // (the failure mode the CLI's `ws add` had on its own).
            let icon: String? = (!buf.isEmpty && Self.iconResolvable(buf)) ? buf : nil
            stage = .running(verb: "add")
            return .runAdd(name: name, icon: icon)
        case .char(let c):
            stage = .addIcon(name: name, buffer: buf + String(c))
            return .idle
        case .tab, .backTab: return .idle
        }
    }

    // MARK: - Icon resolvability
    //
    // Pre-flight check against ~/.config/workspace/lib/sf-to-nerd.json so
    // the manage flow doesn't have to surface the CLI's "no mapping →
    // placeholder" warning. The map is loaded lazily once per overlay
    // session; small (~80 entries) and there's no point re-reading it on
    // every keystroke.

    private static var cachedIconMap: Set<String>?
    private static let iconMapPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/workspace/lib/sf-to-nerd.json")

    private static func iconMap() -> Set<String> {
        if let cached = cachedIconMap { return cached }
        guard let data = try? Data(contentsOf: iconMapPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            cachedIconMap = []
            return []
        }
        // Documentation keys start with `_` (e.g. `_doc`) — exclude them.
        let keys = Set(obj.keys.filter { !$0.hasPrefix("_") })
        cachedIconMap = keys
        return keys
    }

    /// True when `icon` is something the CLI can render without falling
    /// back to a placeholder: a single typed glyph, or a known SF Symbol
    /// name with a Nerd Font mapping.
    static func iconResolvable(_ icon: String) -> Bool {
        guard !icon.isEmpty else { return false }
        if icon.unicodeScalars.count == 1 { return true }
        return iconMap().contains(icon)
    }

    private func atRenameTarget(_ key: PromptKey, filter: String, sel: Int,
                                inQueryMode: Bool) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            // Enter on empty filter → commit the focused workspace (the
            // initial selection points at it). Otherwise pick the
            // currently-highlighted match. All-numeric query while in
            // query mode resolves to a literal slot (the path to 11+).
            if inQueryMode, let target = digitTarget(filter: filter) {
                return commitRename(slot: target)
            }
            let matches = filteredWorkspaces(filter: filter)
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            stage = .renameNewName(slot: pick.index, slotName: pick.name, buffer: "")
            return .idle
        case .tab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .renameTarget(filter: filter,
                                  selection: cycle(sel, count: matches.count, by: +1),
                                  inQueryMode: inQueryMode)
            return .idle
        case .backTab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .renameTarget(filter: filter,
                                  selection: cycle(sel, count: matches.count, by: -1),
                                  inQueryMode: inQueryMode)
            return .idle
        case .backspace:
            if filter.isEmpty { return .idle }
            stage = .renameTarget(filter: String(filter.dropLast()),
                                  selection: 0, inQueryMode: inQueryMode)
            return .idle
        case .char(let c):
            // First-keystroke digit → commit that slot directly. Slot 0
            // is a stand-in for 10, mirroring focus/send.
            if !inQueryMode, c.isASCII, c.isNumber {
                let slot: Int = (c == "0") ? 10 : Int(String(c)) ?? -1
                return commitRename(slot: slot)
            }
            stage = .renameTarget(filter: filter + String(c).lowercased(),
                                  selection: 0, inQueryMode: true)
            return .idle
        }
    }

    /// Helper for the digit + all-numeric-query paths. Validates the slot
    /// exists; if not, transitions to a result panel so the failure is
    /// visible rather than silently dropping the keystroke.
    private func commitRename(slot: Int) -> ManageAction {
        guard let ws = workspaces.first(where: { $0.index == slot }) else {
            stage = .result(title: "rename: rejected",
                            body: "slot \(slot) does not exist", success: false)
            return .idle
        }
        stage = .renameNewName(slot: ws.index, slotName: ws.name, buffer: "")
        return .idle
    }

    private func atRenameNewName(_ key: PromptKey, slot: Int, slotName: String,
                                 buf: String) -> ManageAction {
        switch key {
        case .escape:
            stage = .renameTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
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
            return .runWs(verb: "name", args: ["name", String(slot), new])
        case .char(let c):
            stage = .renameNewName(slot: slot, slotName: slotName, buffer: buf + String(c))
            return .idle
        case .tab, .backTab: return .idle
        }
    }

    private func atDestroyTarget(_ key: PromptKey, filter: String, sel: Int,
                                 inQueryMode: Bool) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            if inQueryMode, let target = digitTarget(filter: filter) {
                return commitDestroy(slot: target)
            }
            let matches = filteredWorkspaces(filter: filter)
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            stage = .destroyConfirm(slot: pick.index, slotName: pick.name)
            return .idle
        case .tab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .destroyTarget(filter: filter,
                                   selection: cycle(sel, count: matches.count, by: +1),
                                   inQueryMode: inQueryMode)
            return .idle
        case .backTab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .destroyTarget(filter: filter,
                                   selection: cycle(sel, count: matches.count, by: -1),
                                   inQueryMode: inQueryMode)
            return .idle
        case .backspace:
            if filter.isEmpty { return .idle }
            stage = .destroyTarget(filter: String(filter.dropLast()),
                                   selection: 0, inQueryMode: inQueryMode)
            return .idle
        case .char(let c):
            if !inQueryMode, c.isASCII, c.isNumber {
                let slot: Int = (c == "0") ? 10 : Int(String(c)) ?? -1
                return commitDestroy(slot: slot)
            }
            stage = .destroyTarget(filter: filter + String(c).lowercased(),
                                   selection: 0, inQueryMode: true)
            return .idle
        }
    }

    private func commitDestroy(slot: Int) -> ManageAction {
        guard let ws = workspaces.first(where: { $0.index == slot }) else {
            stage = .result(title: "destroy: rejected",
                            body: "slot \(slot) does not exist", success: false)
            return .idle
        }
        stage = .destroyConfirm(slot: ws.index, slotName: ws.name)
        return .idle
    }

    private func atDestroyConfirm(_ key: PromptKey, slot: Int,
                                  slotName: String) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("d"), .char("D"), .char("y"), .char("Y"), .enter:
            // Destroy the actual macOS Space. yabai's space_destroyed
            // signal fires the cascade (on-space-destroyed.sh), which
            // prunes the slot from spaces.json on its own — so we don't
            // need a follow-up `ws remove`. Requires yabai's scripting
            // addition to be loaded; failure surfaces in the result
            // panel ("cannot destroy space due to an error with the
            // scripting-addition.").
            stage = .running(verb: "destroy")
            return .runYabai(verb: "destroy",
                             args: ["-m", "space", "--destroy", String(slot)])
        default:
            stage = .destroyTarget(filter: "", selection: focusedSelection, inQueryMode: false)
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
            return .runWs(verb: "layout save", args: ["layout", "save", name])
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
        let matches = FuzzyMatch.filter(snapshots, query: filter, keyPath: { $0 })
        switch key {
        case .escape:        stage = .layoutVerb; return .idle
        case .enter:
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            switch mode {
            case .load:
                stage = .running(verb: "layout load")
                return .runWs(verb: "layout load",
                              args: ["layout", "load", pick, "-y"])
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
            return .runWs(verb: "layout delete",
                          args: ["layout", "delete", name, "-y"])
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

    /// Same broad subsequence match focus/send use — `arc` matches
    /// `archives`, `hm` matches `home-mgmt`. Substring-only was too
    /// restrictive for the manage target pickers, where you usually
    /// remember a couple of letters rather than a contiguous prefix.
    func filteredWorkspaces(filter: String) -> [Workspace] {
        FuzzyMatch.filter(workspaces, query: filter, keyPath: { $0.name })
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
