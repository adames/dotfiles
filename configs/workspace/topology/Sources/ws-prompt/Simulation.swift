import Foundation

/// Token format for `--simulate-keys`:
///
///   plain letters / digits   →  .char(c)
///   <CR>                     →  .enter
///   <ESC>                    →  .escape
///   <TAB>                    →  .tab
///   <S-TAB>                  →  .backTab
///   <BS>                     →  .backspace
///
/// Anything else falls through as a literal char. Designed for the bash
/// test harness, which builds key strings like "home<CR>" or "x<BS>11<CR>".
enum KeySequenceParser {
    static func parse(_ raw: String) -> [PromptKey] {
        var out: [PromptKey] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            if raw[i] == "<" {
                if let close = raw[i...].firstIndex(of: ">") {
                    let token = String(raw[raw.index(after: i)..<close]).uppercased()
                    switch token {
                    case "CR":    out.append(.enter)
                    case "ESC":   out.append(.escape)
                    case "TAB":   out.append(.tab)
                    case "S-TAB": out.append(.backTab)
                    case "BS":    out.append(.backspace)
                    default:
                        // Unknown token — emit the literal "<token>" so a
                        // typo is loud rather than silently dropped.
                        for c in "<\(token)>" { out.append(.char(c)) }
                    }
                    i = raw.index(after: close)
                    continue
                }
            }
            out.append(.char(raw[i]))
            i = raw.index(after: i)
        }
        return out
    }
}

/// Prints the final action in a stable, grep-friendly format and
/// returns the exit code. The bash tests assert against this output.
enum SimulateReporter {
    static func print(action: PromptAction, mode: PromptMode) -> Int32 {
        switch action {
        case .idle:
            Swift.print("action=idle mode=\(mode.rawValue)")
            return 0
        case .refilter(let q, let m):
            Swift.print("action=refilter mode=\(mode.rawValue) query=\(q) matches=\(m.map(String.init).joined(separator: ","))")
            return 0
        case .commitFocus(let slot):
            Swift.print("action=commit mode=focus helper=ws-focus arg=\(slot)")
            return 0
        case .commitSend(let slot):
            Swift.print("action=commit mode=send helper=ws-send-follow arg=\(slot)")
            return 0
        case .cancel:
            Swift.print("action=cancel mode=\(mode.rawValue)")
            return 1
        }
    }
}
