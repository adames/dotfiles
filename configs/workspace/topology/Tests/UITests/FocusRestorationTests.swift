import AppKit
@testable import AdaptersAppKit
import Testing

/// Validates that `WorkspaceWindowDelegate` restores first responder when a
/// window crosses displays.
///
/// Like the rest of the UITests target, requires a host app to instantiate
/// `NSWindow` instances in a UI context. Skipped under `swift test` until
/// such a host exists; drop the `.disabled` trait to opt in.
@Suite("Focus restoration on screen change")
struct FocusRestorationTests {

    @Test(.disabled("host app target required; see ScreenshotOnLaunchTests for setup"))
    func focus_restored_after_screen_change_notification() {
        // TODO: Once host app exists:
        //
        // let window = NSWindow(
        //     contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
        //     styleMask: [.titled, .closable],
        //     backing: .buffered,
        //     defer: false)
        // let delegate = WorkspaceWindowDelegate()
        // window.delegate = delegate
        // window.makeFirstResponder(nil)
        // #expect(window.firstResponder == nil)
        //
        // NotificationCenter.default.post(
        //     name: NSWindow.didChangeScreenNotification,
        //     object: window)
        //
        // #expect(window.firstResponder != nil)
    }
}
