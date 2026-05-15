import Foundation

/// One row in the picker — a yabai window snapshot. Decoded from
/// `yabai -m query --windows` and reduced to the fields the overlay
/// renders or matches against.
struct WindowItem: Equatable, Identifiable {
    let id: Int
    let app: String
    let title: String
    let space: Int
    let display: Int

    /// Combined string used for fuzzy matching. Including the space and
    /// display indices lets the user reach by workspace number ("3 term"
    /// finds the Ghostty on space 3) without juggling separate filters.
    var matchKey: String {
        let titleSegment = title.isEmpty ? "" : " \(title)"
        return "\(app)\(titleSegment) \(space) \(display)"
    }

    /// What the row shows in the title column. Falls back to app name
    /// when the window has no title (common for new app windows that
    /// haven't loaded their document yet).
    var displayLabel: String {
        title.isEmpty ? app : title
    }
}

/// Wire shape of one entry from `yabai -m query --windows`. The yabai
/// JSON uses kebab-case keys, so we restate them explicitly.
struct YabaiWindow: Decodable {
    let id: Int
    let app: String
    let title: String
    let space: Int
    let display: Int
    let isVisible: Bool
    let isMinimized: Bool

    enum CodingKeys: String, CodingKey {
        case id, app, title, space, display
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
    }

    var toItem: WindowItem {
        WindowItem(id: id, app: app, title: title, space: space, display: display)
    }
}
