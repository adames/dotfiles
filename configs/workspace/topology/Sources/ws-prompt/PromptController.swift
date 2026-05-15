import Foundation
import SwiftUI
import WsUI

/// Three prompts the overlay can render. Picked from the first CLI arg.
/// focus/send share the PromptController state machine here; manage has
/// its own multi-stage controller (ManageController) since the flow is
/// substantially richer (verb → target → payload → confirm → result).
enum PromptMode: String {
    case focus, send, manage
}

/// A single input event the controller understands. Modeled as a closed
/// enum (rather than raw Strings) so the simulator and the live key
/// monitor share one vocabulary.
enum PromptKey: Equatable {
    case char(Character)   // letters & digits join the query
    case enter
    case escape
    case tab
    case backTab           // Shift+Tab
    case backspace
}

/// Outcome of a key. The UI re-renders on every event; the binary
/// dispatches the side-effect helpers on `.commit*`.
enum PromptAction: Equatable {
    case idle
    case refilter(query: String, matches: [Int])// new query → updated match list (Workspace indices)
    case commitFocus(slot: Int)
    case commitSend(slot: Int)
    case cancel
}

/// State machine for the focus / send prompts. SwiftUI views bind to
/// the controller directly via `@ObservedObject` — `@Published` props
/// fan out re-renders on every mutation, so there's no separate
/// view-model. The controller owns no NSEvent / NSApp; key events come
/// in via `handle(_:)` and side effects (focus / send helpers) are the
/// host's job once the controller emits a `commit*` action.
final class PromptController: ObservableObject {
    let mode: PromptMode
    let workspaces: [Workspace]

    /// Empty before any input. First key decides whether we enter
    /// digit-fast-path (single digit commits immediately) or query mode
    /// (letters build a fuzzy filter; digits join the buffer afterward).
    @Published private(set) var query: String = ""

    /// Sticky once we've entered query mode (first key was a letter, or
    /// the user explicitly opted in some other way). Backspace can empty
    /// the buffer without dropping back into digit-fast-path — once in
    /// query mode, always in query mode for the rest of this prompt's
    /// lifetime. This is what makes the documented "x<BS>11<CR>" path
    /// resolve to slot 11 rather than slot 1.
    @Published private(set) var inQueryMode: Bool = false

    /// Index into `currentMatches()` for Tab cycling. Reset on every
    /// refilter.
    @Published private(set) var selection: Int = 0

    init(mode: PromptMode, workspaces: [Workspace]) {
        self.mode = mode
        self.workspaces = workspaces
    }

    /// Drive the state machine. One key in, one Action out.
    func handle(_ key: PromptKey) -> PromptAction {
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
            return .refilter(query: query, matches: currentMatches().map(\.index))
        case .char(let c):
            return absorb(c)
        }
    }

    /// Pure helper for tests. Folds a list of keys through `handle`,
    /// returning the final non-idle action (or `.idle` if every key was
    /// idle, or `.cancel` if no commit happened by end-of-input).
    func simulate(_ keys: [PromptKey]) -> PromptAction {
        var last: PromptAction = .idle
        for key in keys {
            let action = handle(key)
            switch action {
            case .commitFocus, .commitSend, .cancel:
                return action
            case .refilter:
                last = action
            case .idle:
                continue
            }
        }
        return last
    }

    /// Digit fast-path: a single-digit FIRST key commits immediately.
    /// Once we've entered query mode (first key was a letter), digits
    /// join the buffer like letters — even after backspace empties it.
    /// Names are forbidden from starting with a digit (enforced in the
    /// `ws` CLI), so an all-numeric query can be resolved as a literal
    /// slot index at commit time.
    private func absorb(_ c: Character) -> PromptAction {
        if !inQueryMode, c.isASCII, c.isNumber {
            return commitDigit(c)
        }
        inQueryMode = true
        query.append(Character(String(c).lowercased()))
        selection = 0
        return .refilter(query: query, matches: currentMatches().map(\.index))
    }

    private func commitDigit(_ c: Character) -> PromptAction {
        // Caller (`absorb`) has already gated on `c.isASCII && c.isNumber`,
        // so the unwrap is total. `0` is the convention-mapped alias for
        // slot 10 to keep the digit row visually contiguous.
        let slot = (c == "0") ? 10 : Int(String(c))!
        guard slot >= 1, slot <= max(workspaces.last?.index ?? 0, 10) else {
            return .cancel
        }
        return mode == .focus ? .commitFocus(slot: slot) : .commitSend(slot: slot)
    }

    private func commitFromQuery() -> PromptAction {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .cancel }

        // All-numeric query: literal slot index. Reachable only via
        // backspace-erasure of a leading letter (the digit fast-path
        // would have committed before query mode opened).
        if trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) {
            if let slot = Int(trimmed), slot >= 1 {
                return mode == .focus ? .commitFocus(slot: slot) : .commitSend(slot: slot)
            }
            return .cancel
        }

        let matches = currentMatches()
        guard !matches.isEmpty else { return .cancel }
        let pick = matches[selection.clamped(to: 0...(matches.count - 1))]
        return mode == .focus ? .commitFocus(slot: pick.index) : .commitSend(slot: pick.index)
    }

    private func cycle(by delta: Int) -> PromptAction {
        let count = currentMatches().count
        guard count > 0 else { return .idle }
        selection = ((selection + delta) % count + count) % count
        return .refilter(query: query, matches: currentMatches().map(\.index))
    }

    // Sequence-aware fuzzy match — see FuzzyMatch.swift. "hm" matches
    // both "home" and "home-management"; tighter, earlier matches sort
    // first. Good enough for a list of <20 workspaces.
    func currentMatches() -> [Workspace] {
        FuzzyMatch.filter(workspaces, query: query, keyPath: { $0.name })
    }
}
