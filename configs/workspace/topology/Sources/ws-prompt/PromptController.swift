import Foundation

/// Two prompts the overlay can render. Picked from the first CLI arg.
enum PromptMode: String {
    case focus, send
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

/// Pure state machine. Owns no NSEvent / NSApp — feed it `PromptKey`,
/// it tells the caller what to do. Spawning helpers is the caller's job.
final class PromptController {
    let mode: PromptMode
    private(set) var workspaces: [Workspace]

    /// Empty before any input. First key decides whether we enter
    /// digit-fast-path (single digit commits immediately) or query mode
    /// (letters build a fuzzy filter; digits join the buffer afterward).
    private(set) var query: String = ""

    /// Sticky once we've entered query mode (first key was a letter, or
    /// the user explicitly opted in some other way). Backspace can empty
    /// the buffer without dropping back into digit-fast-path — once in
    /// query mode, always in query mode for the rest of this prompt's
    /// lifetime. This is what makes the documented "x<BS>11<CR>" path
    /// resolve to slot 11 rather than slot 1.
    private(set) var inQueryMode: Bool = false

    /// Index into `currentMatches()` for Tab cycling. Reset on every
    /// refilter.
    private(set) var selection: Int = 0

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
        let slot: Int = (c == "0") ? 10 : Int(String(c)) ?? -1
        guard slot >= 1, slot <= max(workspaces.last?.index ?? 0, 10) else {
            // Out-of-range single digit: cancel rather than commit a
            // bogus slot. The bash helpers would notify but we don't
            // even try.
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

    // MARK: - Fuzzy match
    //
    // Subsequence match, case-insensitive, scored by tightness. "hm"
    // matches "home" (subsequence h…m) and "home-management". Ranking
    // prefers earlier matches and shorter span. Good enough for a list of
    // <20 workspaces; no full fzf algorithm needed.

    func currentMatches() -> [Workspace] {
        if query.isEmpty { return workspaces }
        let q = query.lowercased()
        var scored: [(Workspace, Int)] = []
        for ws in workspaces {
            if let score = Self.subseqScore(query: q, name: ws.name.lowercased()) {
                scored.append((ws, score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.index < rhs.0.index
        }
        return scored.map(\.0)
    }

    private static func subseqScore(query: String, name: String) -> Int? {
        var qi = query.startIndex
        var span = 0
        var firstHit: Int? = nil
        var lastHit: Int = 0
        for (i, ch) in name.enumerated() {
            if qi == query.endIndex { break }
            if ch == query[qi] {
                if firstHit == nil { firstHit = i }
                lastHit = i
                qi = query.index(after: qi)
            }
        }
        guard qi == query.endIndex, let first = firstHit else { return nil }
        span = lastHit - first
        // Lower score wins: small span + early start.
        return span * 100 + first
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
