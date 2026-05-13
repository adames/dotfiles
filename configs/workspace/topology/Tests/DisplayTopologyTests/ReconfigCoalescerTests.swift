import DisplayTopology
import XCTest

final class ReconfigCoalescerTests: XCTestCase {
    func test_two_bumps_within_window_produce_one_emission() {
        let exp = expectation(description: "single emission")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        let coalescer = ReconfigCoalescer(trailingWindow: 0.05) {
            exp.fulfill()
        }
        coalescer.bump()
        coalescer.bump()
        wait(for: [exp], timeout: 0.4)
    }

    func test_two_bumps_far_apart_produce_two_emissions() {
        let exp = expectation(description: "two emissions")
        exp.expectedFulfillmentCount = 2
        exp.assertForOverFulfill = true
        let coalescer = ReconfigCoalescer(trailingWindow: 0.03) {
            exp.fulfill()
        }
        coalescer.bump()
        // Sleep longer than the trailing window.
        Thread.sleep(forTimeInterval: 0.15)
        coalescer.bump()
        wait(for: [exp], timeout: 1.0)
    }

    func test_cancel_prevents_emission() {
        let exp = expectation(description: "no emission")
        exp.isInverted = true
        let coalescer = ReconfigCoalescer(trailingWindow: 0.05) {
            exp.fulfill()
        }
        coalescer.bump()
        coalescer.cancel()
        wait(for: [exp], timeout: 0.2)
    }
}
