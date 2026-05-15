import Foundation
import SwiftUI
import WsUI

/// A single input event the controller understands. Same vocabulary as
/// ws-prompt's PromptKey — kept local because the two binaries don't
/// share a controller and copying one enum keeps WsUI free of
/// app-specific types.
enum PickerKey: Equatable {
    case char(Character)
    case enter
    case escape
    case tab
    case backTab
    case backspace
}

/// Outcome of a key. The UI re-renders on every event; the binary
/// dispatches `yabai -m window --focus` on `.commit`.
enum PickerAction: Equatable {
    case idle
    case refilter
    case commit(id: Int)
    case cancel
}

/// State machine for the window picker. Mirrors `PromptController`'s
/// shape — letters build a fuzzy query, Tab cycles matches, Enter
/// commits, Esc cancels. No digit-fast-path: window IDs are 6-digit
/// yabai handles, not slot numbers.
final class PickerController: ObservableObject {
    let items: [WindowItem]

    @Published private(set) var query: String = ""
    @Published private(set) var selection: Int = 0

    init(items: [WindowItem]) {
        self.items = items
    }

    func handle(_ key: PickerKey) -> PickerAction {
        switch key {
        case .escape:
            return .cancel
        case .enter:
            return commitFromQuery()
        case .tab:
            return cycle(by: +1)
        case .backTab:
            return cycle(by: -1)
        case .backspace:
            if query.isEmpty { return .idle }
            query.removeLast()
            selection = 0
            return .refilter
        case .char(let c):
            query.append(Character(String(c).lowercased()))
            selection = 0
            return .refilter
        }
    }

    /// Pure helper for tests — fold a list of keys through `handle`
    /// and return the final non-idle action.
    func simulate(_ keys: [PickerKey]) -> PickerAction {
        var last: PickerAction = .idle
        for key in keys {
            let action = handle(key)
            switch action {
            case .commit, .cancel:    return action
            case .refilter:           last = action
            case .idle:               continue
            }
        }
        return last
    }

    private func commitFromQuery() -> PickerAction {
        let matches = currentMatches()
        guard !matches.isEmpty else { return .cancel }
        let pick = matches[selection.clamped(to: 0...(matches.count - 1))]
        return .commit(id: pick.id)
    }

    private func cycle(by delta: Int) -> PickerAction {
        let count = currentMatches().count
        guard count > 0 else { return .idle }
        selection = ((selection + delta) % count + count) % count
        return .refilter
    }

    func currentMatches() -> [WindowItem] {
        FuzzyMatch.filter(items, query: query, keyPath: { $0.matchKey })
    }
}
