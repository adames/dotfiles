import Foundation
import SwiftUI
import WsUI

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
    case iconTarget(filter: String, selection: Int, inQueryMode: Bool)
    case iconPick(slot: Int, slotName: String, filter: String, selection: Int)
    case layoutVerb
    case layoutSaveName(buffer: String)
    case layoutLoadPick(snapshots: [String], filter: String, selection: Int)
    case layoutDeletePick(snapshots: [String], filter: String, selection: Int)
    case layoutDeleteConfirm(name: String)
    case running(verb: String)
    case result(title: String, body: String, success: Bool)
}

/// What ManageController.handle returns. `.idle` means the view should
/// re-render but no further action is required from the host. `.terminate`
/// closes the overlay. Command execution is no longer surfaced through
/// this enum — the controller drives commands directly via its injected
/// `WorkspaceService` and re-renders when their completions land.
enum ManageAction: Equatable {
    case idle
    case terminate
}

/// Multi-stage state machine for the manage overlay.
///
/// Holds its own state (`stage`) as a `@Published` so SwiftUI views bind
/// directly to the controller — no separate view-model. Side effects
/// (yabai create / destroy, `ws name` / `ws layout`, …) are dispatched
/// through the injected `WorkspaceService`, which lets tests pin every
/// transition with no Process spawning. Once a command completes the
/// controller flips itself to `.result(...)` on the main queue and the
/// view re-renders.
final class ManageController: ObservableObject {
    @Published private(set) var stage: ManageStage = .verbPicker

    let workspaces: [Workspace]
    private let service: WorkspaceService

    /// Yabai's currently-focused space index, captured once at overlay
    /// open. Used to default the rename/destroy target pickers to "act
    /// on the workspace I'm already on" so Enter-without-typing is the
    /// fast path. Nil → fall back to selection index 0.
    private let focusedIndex: Int?

    /// Layout-snapshot list is loaded on demand the first time the user
    /// enters the layout sub-flow; cached after that.
    private var snapshotCache: [String]?

    /// Host wires this up to dismiss the overlay window. Called on
    /// command-completion success so the user doesn't have to press a
    /// key to acknowledge an "ok" result. Failures still flow through
    /// `.result(...)` because the error output is the whole point.
    var onTerminate: (() -> Void)?

    init(workspaces: [Workspace],
         focusedIndex: Int? = nil,
         service: WorkspaceService) {
        self.workspaces = workspaces
        self.focusedIndex = focusedIndex
        self.service = service
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

    /// Drive the state machine. One key in, one Action out. Side effects
    /// are scheduled via `service` — the action only reports whether the
    /// host should terminate or just re-render.
    func handle(_ key: PromptKey) -> ManageAction {
        switch stage {
        case .verbPicker:                       return handleVerbPicker(key)
        case .addName(let buf):                 return handleAddName(key, buf: buf)
        case .addIcon(let n, let buf):          return handleAddIcon(key, name: n, buf: buf)
        case .renameTarget(let f, let s, let q):
            return handleRenameTarget(key, filter: f, sel: s, inQueryMode: q)
        case .renameNewName(let i, let nm, let buf):
            return handleRenameNewName(key, slot: i, slotName: nm, buf: buf)
        case .destroyTarget(let f, let s, let q):
            return handleDestroyTarget(key, filter: f, sel: s, inQueryMode: q)
        case .destroyConfirm(let i, let nm):    return handleDestroyConfirm(key, slot: i, slotName: nm)
        case .iconTarget(let f, let s, let q):
            return handleIconTarget(key, filter: f, sel: s, inQueryMode: q)
        case .iconPick(let i, let nm, let f, let s):
            return handleIconPick(key, slot: i, slotName: nm, filter: f, sel: s)
        case .layoutVerb:                       return handleLayoutVerb(key)
        case .layoutSaveName(let buf):          return handleLayoutSaveName(key, buf: buf)
        case .layoutLoadPick(let snaps, let f, let s):
            return handleLayoutPick(key, snapshots: snaps, filter: f, sel: s, mode: .load)
        case .layoutDeletePick(let snaps, let f, let s):
            return handleLayoutPick(key, snapshots: snaps, filter: f, sel: s, mode: .delete)
        case .layoutDeleteConfirm(let name):    return handleLayoutDeleteConfirm(key, name: name)
        case .running:                          return .idle    // ignore input mid-command
        case .result:                           return .terminate // any key dismisses
        }
    }

    // MARK: - Verb picker

    private func handleVerbPicker(_ key: PromptKey) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("a"), .char("A"):
            stage = .addName(buffer: "");           return .idle
        case .char("r"), .char("R"):
            stage = .renameTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .char("d"), .char("D"):
            stage = .destroyTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .char("i"), .char("I"):
            stage = .iconTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .char("L"):              // capital L only (Shift+L), avoids clashing with destroy 'd'
            stage = .layoutVerb
            return .idle
        case .char("v"), .char("V"):
            dispatch(verb: "verify") { [weak self] in self?.service.runWs(args: ["verify"], completion: $0) }
            return .idle
        case .char("?"):
            dispatch(verb: "doctor") { [weak self] in self?.service.runWs(args: ["doctor"], completion: $0) }
            return .idle
        default:                     return .idle
        }
    }

    // MARK: - Add

    private func handleAddName(_ key: PromptKey, buf: String) -> ManageAction {
        switch key {
        case .escape:                stage = .verbPicker; return .idle
        case .backspace:
            stage = .addName(buffer: String(buf.dropLast())); return .idle
        case .enter:
            // Empty input → fall back to the spelled-out cardinal for the
            // next slot index (matches `_default_name_for_slot` in the
            // bash CLI). Names never start with a digit, so the default
            // is always shape-legal.
            let trimmed = buf.trimmingCharacters(in: .whitespaces)
            let name = trimmed.isEmpty
                ? Self.defaultName(forSlot: workspaces.count + 1)
                : trimmed
            guard !name.first!.isNumber else {
                stage = .result(title: "add: rejected",
                                body: "name cannot start with a digit (reserved for slot indices)",
                                success: false)
                return .idle
            }
            stage = .addIcon(name: name, buffer: "")
            return .idle
        case .char(let c):
            // Reject a leading digit early so the rule is visible while
            // typing — `ws name` would reject on commit anyway.
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

    /// Default workspace name for slot N. Mirrors `_default_name_for_slot`
    /// in `configs/workspace/cli/ws` so the overlay produces the same
    /// shape the CLI does when the user accepts the prompt's empty
    /// default (one … twenty, then ws${N} for 21+).
    static func defaultName(forSlot slot: Int) -> String {
        let cardinals = [
            "one", "two", "three", "four", "five",
            "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen",
            "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        ]
        if slot >= 1, slot <= cardinals.count { return cardinals[slot - 1] }
        return "ws\(slot)"
    }

    private func handleAddIcon(_ key: PromptKey, name: String, buf: String) -> ManageAction {
        switch key {
        case .escape:                stage = .addName(buffer: name); return .idle
        case .backspace:
            stage = .addIcon(name: name, buffer: String(buf.dropLast())); return .idle
        case .enter:
            // Icon resolution policy: empty → no icon (CLI default).
            // SF Symbol name → stored directly. Nerd Font codepoint path
            // available for cross-platform use. Silently drop invalid icons
            // so the workspace is created cleanly.
            let icon = (!buf.isEmpty && service.iconResolvable(buf)) ? buf : nil
            dispatch(verb: "add") { [weak self] completion in
                self?.service.runAdd(name: name, icon: icon, completion: completion)
            }
            return .idle
        case .char(let c):
            stage = .addIcon(name: name, buffer: buf + String(c)); return .idle
        case .tab, .backTab:         return .idle
        }
    }

    // MARK: - Rename

    private func handleRenameTarget(_ key: PromptKey, filter: String, sel: Int,
                                    inQueryMode: Bool) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            // Enter on empty filter → commit focused workspace.
            // All-numeric query while in query mode → literal slot (11+).
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
            // First-keystroke digit → commit that slot directly. 0 = 10.
            if !inQueryMode, c.isASCII, c.isNumber {
                let slot = (c == "0") ? 10 : Int(String(c))!
                return commitRename(slot: slot)
            }
            stage = .renameTarget(filter: filter + String(c).lowercased(),
                                  selection: 0, inQueryMode: true)
            return .idle
        }
    }

    private func commitRename(slot: Int) -> ManageAction {
        guard let ws = workspaces.first(where: { $0.index == slot }) else {
            stage = .result(title: "rename: rejected",
                            body: "slot \(slot) does not exist", success: false)
            return .idle
        }
        stage = .renameNewName(slot: ws.index, slotName: ws.name, buffer: "")
        return .idle
    }

    private func handleRenameNewName(_ key: PromptKey, slot: Int, slotName: String,
                                     buf: String) -> ManageAction {
        switch key {
        case .escape:
            stage = .renameTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .backspace:
            stage = .renameNewName(slot: slot, slotName: slotName,
                                   buffer: String(buf.dropLast())); return .idle
        case .enter:
            let new = buf.trimmingCharacters(in: .whitespaces)
            guard !new.isEmpty else { return .idle }
            guard !new.first!.isNumber else {
                stage = .result(title: "rename: rejected",
                                body: "name cannot start with a digit", success: false)
                return .idle
            }
            dispatch(verb: "name") { [weak self] completion in
                self?.service.runWs(args: ["name", String(slot), new], completion: completion)
            }
            return .idle
        case .char(let c):
            stage = .renameNewName(slot: slot, slotName: slotName, buffer: buf + String(c))
            return .idle
        case .tab, .backTab:         return .idle
        }
    }

    // MARK: - Destroy

    private func handleDestroyTarget(_ key: PromptKey, filter: String, sel: Int,
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
                let slot = (c == "0") ? 10 : Int(String(c))!
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

    private func handleDestroyConfirm(_ key: PromptKey, slot: Int,
                                      slotName: String) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("d"), .char("D"), .char("y"), .char("Y"), .enter:
            // yabai's space_destroyed signal fires the cascade
            // (on-space-destroyed.sh) which prunes spaces.json on its
            // own — no follow-up `ws remove` needed.
            dispatch(verb: "destroy") { [weak self] completion in
                self?.service.runYabai(args: ["-m", "space", "--destroy", String(slot)],
                                       completion: completion)
            }
            return .idle
        default:
            stage = .destroyTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        }
    }

    // MARK: - Icon
    //
    // Two stages: pick a target slot (mirrors rename/destroy target
    // pickers — digit fast-path, fuzzy name, focused-default), then
    // fuzzy-pick an SF Symbol from the catalog.
    // Commit dispatches `ws icon SLOT NAME`.

    private func handleIconTarget(_ key: PromptKey, filter: String, sel: Int,
                                  inQueryMode: Bool) -> ManageAction {
        switch key {
        case .escape: stage = .verbPicker; return .idle
        case .enter:
            if inQueryMode, let target = digitTarget(filter: filter) {
                return commitIconTarget(slot: target)
            }
            let matches = filteredWorkspaces(filter: filter)
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            stage = .iconPick(slot: pick.index, slotName: pick.name,
                              filter: "", selection: 0)
            return .idle
        case .tab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .iconTarget(filter: filter,
                                selection: cycle(sel, count: matches.count, by: +1),
                                inQueryMode: inQueryMode)
            return .idle
        case .backTab:
            let matches = filteredWorkspaces(filter: filter)
            stage = .iconTarget(filter: filter,
                                selection: cycle(sel, count: matches.count, by: -1),
                                inQueryMode: inQueryMode)
            return .idle
        case .backspace:
            if filter.isEmpty { return .idle }
            stage = .iconTarget(filter: String(filter.dropLast()),
                                selection: 0, inQueryMode: inQueryMode)
            return .idle
        case .char(let c):
            if !inQueryMode, c.isASCII, c.isNumber {
                let slot = (c == "0") ? 10 : Int(String(c))!
                return commitIconTarget(slot: slot)
            }
            stage = .iconTarget(filter: filter + String(c).lowercased(),
                                selection: 0, inQueryMode: true)
            return .idle
        }
    }

    private func commitIconTarget(slot: Int) -> ManageAction {
        guard let ws = workspaces.first(where: { $0.index == slot }) else {
            stage = .result(title: "icon: rejected",
                            body: "slot \(slot) does not exist", success: false)
            return .idle
        }
        stage = .iconPick(slot: ws.index, slotName: ws.name, filter: "", selection: 0)
        return .idle
    }

    /// Catalog snapshot loaded once on first entry to the picker so
    /// keystroke handling — and the SwiftUI body's per-render fuzzy
    /// filter — don't re-read the JSON each tab.
    private var catalogCache: [IconCatalogEntry]?
    private func catalog() -> [IconCatalogEntry] {
        if let c = catalogCache { return c }
        let c = service.iconCatalog()
        catalogCache = c
        return c
    }
    /// Public accessor for the view-side fuzzy filter.
    var iconCatalogCached: [IconCatalogEntry] { catalog() }

    private func handleIconPick(_ key: PromptKey, slot: Int, slotName: String,
                                filter: String, sel: Int) -> ManageAction {
        let matches = FuzzyMatch.filter(catalog(), query: filter, keyPath: { $0.sfName })
        switch key {
        case .escape:
            stage = .iconTarget(filter: "", selection: focusedSelection, inQueryMode: false)
            return .idle
        case .enter:
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            dispatch(verb: "icon") { [weak self] completion in
                self?.service.runWs(args: ["icon", String(slot), pick.sfName],
                                    completion: completion)
            }
            return .idle
        case .tab:
            stage = .iconPick(slot: slot, slotName: slotName, filter: filter,
                              selection: cycle(sel, count: matches.count, by: +1))
            return .idle
        case .backTab:
            stage = .iconPick(slot: slot, slotName: slotName, filter: filter,
                              selection: cycle(sel, count: matches.count, by: -1))
            return .idle
        case .backspace:
            if filter.isEmpty { return .idle }
            stage = .iconPick(slot: slot, slotName: slotName,
                              filter: String(filter.dropLast()), selection: 0)
            return .idle
        case .char(let c):
            stage = .iconPick(slot: slot, slotName: slotName,
                              filter: filter + String(c).lowercased(), selection: 0)
            return .idle
        }
    }

    // MARK: - Layout

    private func handleLayoutVerb(_ key: PromptKey) -> ManageAction {
        switch key {
        case .escape:                stage = .verbPicker; return .idle
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

    private func handleLayoutSaveName(_ key: PromptKey, buf: String) -> ManageAction {
        switch key {
        case .escape:                stage = .layoutVerb; return .idle
        case .backspace:
            stage = .layoutSaveName(buffer: String(buf.dropLast())); return .idle
        case .enter:
            let name = buf.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .idle }
            dispatch(verb: "layout save") { [weak self] completion in
                self?.service.runWs(args: ["layout", "save", name], completion: completion)
            }
            return .idle
        case .char(let c):
            // CLI validator matches [A-Za-z0-9._-]+. Reject early so the
            // rule is visible.
            guard c.isLetter || c.isNumber || c == "." || c == "_" || c == "-"
            else { return .idle }
            stage = .layoutSaveName(buffer: buf + String(c))
            return .idle
        case .tab, .backTab:         return .idle
        }
    }

    enum LayoutPickMode { case load, delete }

    private func handleLayoutPick(_ key: PromptKey, snapshots: [String], filter: String,
                                  sel: Int, mode: LayoutPickMode) -> ManageAction {
        let matches = FuzzyMatch.filter(snapshots, query: filter, keyPath: { $0 })
        switch key {
        case .escape:                stage = .layoutVerb; return .idle
        case .enter:
            guard !matches.isEmpty else { return .idle }
            let pick = matches[sel.clamped(to: 0...(matches.count - 1))]
            switch mode {
            case .load:
                dispatch(verb: "layout load") { [weak self] completion in
                    self?.service.runWs(args: ["layout", "load", pick, "-y"],
                                        completion: completion)
                }
            case .delete:
                stage = .layoutDeleteConfirm(name: pick)
            }
            return .idle
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

    private func handleLayoutDeleteConfirm(_ key: PromptKey, name: String) -> ManageAction {
        switch key {
        case .escape:                return .terminate
        case .char("d"), .char("D"), .char("y"), .char("Y"), .enter:
            dispatch(verb: "layout delete") { [weak self] completion in
                self?.service.runWs(args: ["layout", "delete", name, "-y"],
                                    completion: completion)
            }
            return .idle
        default:
            stage = .layoutVerb
            return .idle
        }
    }

    // MARK: - Command dispatch

    /// Transition to `.running(verb:)`, kick off the side effect, and
    /// either auto-dismiss on success or flip to `.result(...)` on
    /// failure. `runner` is whichever of `service.runWs / runYabai /
    /// runAdd` makes sense for this verb — the controller composes the
    /// dispatch contract here so every verb shares the
    /// running → done | error transition.
    private func dispatch(verb: String,
                          runner: (@escaping (CommandResult) -> Void) -> Void) {
        stage = .running(verb: verb)
        runner { [weak self] result in
            guard let self else { return }
            if result.success {
                // Skip the "ok" panel — it's an extra keystroke the
                // user doesn't owe us. The visible result is in the
                // bar (pill highlight, chip label, etc.). Errors
                // still flow into the result panel because the body
                // carries the actual diagnostic.
                self.onTerminate?()
                return
            }
            self.stage = .result(
                title: "\(verb): failed",
                body: result.output.trimmingCharacters(in: .whitespacesAndNewlines),
                success: false
            )
        }
    }

    // MARK: - Helpers

    private func loadSnapshots() -> [String] {
        if let cached = snapshotCache { return cached }
        let snaps = service.listSnapshots()
        snapshotCache = snaps
        return snaps
    }

    private func layoutPickStage(mode: LayoutPickMode, snaps: [String],
                                 filter: String, sel: Int) -> ManageStage {
        switch mode {
        case .load:   return .layoutLoadPick(snapshots: snaps, filter: filter, selection: sel)
        case .delete: return .layoutDeletePick(snapshots: snaps, filter: filter, selection: sel)
        }
    }

    func filteredWorkspaces(filter: String) -> [Workspace] {
        FuzzyMatch.filter(workspaces, query: filter, keyPath: { $0.name })
    }

    /// All-numeric filter buffer → literal slot index. Used by the
    /// rename/destroy target pickers' enter key after an explicit
    /// query-mode entry (backspace-erasure of a leading letter is the
    /// only way to get an all-numeric buffer; the first-keystroke digit
    /// fast path commits before query mode opens).
    private func digitTarget(filter: String) -> Int? {
        guard !filter.isEmpty, filter.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(filter)
    }

    private func cycle(_ sel: Int, count: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((sel + delta) % count + count) % count
    }
}
