import Testing

#if canImport(XCUIAutomation)
import XCUIAutomation
#endif

/// UI test scaffolding for the helper window app. Skipped under
/// `swift test` because XCUITest requires:
///   1. Full Xcode (XCUIAutomation does not ship with Command Line Tools)
///   2. A host application bundle (SwiftPM executable targets don't qualify)
///
/// To run these, create a thin macOS app target in Xcode that links
/// against `AdaptersAppKit` and uses it as the test host, then drop the
/// `.disabled` trait below.
@Suite("Screenshot-on-launch UI tests")
struct ScreenshotOnLaunchTests {

    @Test(.disabled("host app target required; see file header"))
    func screenshot_on_launch_attaches_artifact() {
        // TODO: Drive the host app to its main window via XCUIApplication.
        //
        // let app = XCUIApplication()
        // app.launch()
        // let screenshot = app.windows.firstMatch.screenshot()
        // let attachment = Attachment(screenshot, named: "launch")
        // …
    }
}
