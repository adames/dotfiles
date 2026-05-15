import Foundation

/// Token format for `--simulate-keys` — same vocabulary as ws-prompt's
/// Simulation.swift. Kept here (not promoted to WsUI) because the two
/// binaries dispatch into different controller types and a shared
/// parser would have to bridge across PickerKey/PromptKey enums for no
/// real win.
///
///   plain letters / digits   →  .char(c)
///   <CR>                     →  .enter
///   <ESC>                    →  .escape
///   <TAB>                    →  .tab
///   <S-TAB>                  →  .backTab
///   <BS>                     →  .backspace
enum PickerKeySequence {
    static func parse(_ raw: String) -> [PickerKey] {
        var out: [PickerKey] = []
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

/// Stable, grep-friendly output for the simulate harness. Bash tests
/// assert against these strings.
enum PickerSimReporter {
    static func print(action: PickerAction) -> Int32 {
        switch action {
        case .idle:
            Swift.print("action=idle")
            return 0
        case .refilter:
            Swift.print("action=refilter")
            return 0
        case .commit(let id):
            Swift.print("action=commit window=\(id)")
            return 0
        case .cancel:
            Swift.print("action=cancel")
            return 1
        }
    }
}
