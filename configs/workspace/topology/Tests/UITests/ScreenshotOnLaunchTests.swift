import XCTest

#if canImport(XCUIAutomation)
import XCUIAutomation
#endif

/// UI test scaffolding for the helper window app. This file is intentionally
/// thin — XCUITest requires:
///   1. Full Xcode (the XCUIAutomation framework does not ship with Command Line Tools)
///   2. A host application bundle (Swift Package executable targets don't qualify)
///
/// To run these tests, create a thin macOS app target in Xcode that links
/// against `AdaptersAppKit` and uses it as the test host. The scaffolding below
/// captures the assertions that test should perform; flesh out once a host app
/// exists.
final class ScreenshotOnLaunchTests: XCTestCase {

    func test_screenshot_on_launch_attaches_artifact() throws {
        // TODO: Drive the host app to its main window via XCUIApplication.
        //
        // let app = XCUIApplication()
        // app.launch()
        // let screenshot = app.windows.firstMatch.screenshot()
        // let attachment = XCTAttachment(screenshot: screenshot)
        // attachment.lifetime = .keepAlways
        // attachment.name = "launch-\(testRun!.test.name)"
        // add(attachment)
        try XCTSkipIf(true, "host app target required; see file header")
    }
}
