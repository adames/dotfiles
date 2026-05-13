import XCTest
import AppKit
@testable import AdaptersAppKit

/// Validates that `WorkspaceWindowDelegate` restores first responder when a
/// window crosses displays.
///
/// Like the rest of the UITests target, requires a host app to instantiate
/// `NSWindow` instances in a UI context. The pure-Swift assertions below
/// would run under full Xcode + a host app; without a host they are skipped.
final class FocusRestorationTests: XCTestCase {

    func test_focus_restored_after_screen_change_notification() throws {
        try XCTSkipIf(true, "host app target required; see ScreenshotOnLaunchTests for setup")

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
        // XCTAssertNil(window.firstResponder)
        //
        // NotificationCenter.default.post(
        //     name: NSWindow.didChangeScreenNotification,
        //     object: window)
        //
        // // Delegate's windowDidChangeScreen is called synchronously by the
        // // notification center post; first responder must be the content view.
        // XCTAssertNotNil(window.firstResponder)
    }
}
