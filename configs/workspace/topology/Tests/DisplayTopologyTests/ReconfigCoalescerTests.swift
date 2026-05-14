import DisplayTopology
import Foundation
import Testing

/// Validates the trailing-edge debounce on `ReconfigCoalescer`. Each test
/// installs the callback inside Swift Testing's `confirmation { }`
/// scope, drives the coalescer, then awaits a window long enough for
/// the trailing fire (or its absence) to be observable.
@Suite("ReconfigCoalescer trailing-edge debounce")
struct ReconfigCoalescerTests {

    @Test func two_bumps_within_window_produce_one_emission() async {
        await confirmation("single emission", expectedCount: 1) { confirm in
            let coalescer = ReconfigCoalescer(trailingWindow: 0.05) { confirm() }
            coalescer.bump()
            coalescer.bump()
            try? await Task.sleep(nanoseconds: 400_000_000)   // 0.4 s
        }
    }

    @Test func two_bumps_far_apart_produce_two_emissions() async {
        await confirmation("two emissions", expectedCount: 2) { confirm in
            let coalescer = ReconfigCoalescer(trailingWindow: 0.03) { confirm() }
            coalescer.bump()
            try? await Task.sleep(nanoseconds: 150_000_000)   // wider than the window
            coalescer.bump()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    @Test func cancel_prevents_emission() async {
        await confirmation("no emission", expectedCount: 0) { confirm in
            let coalescer = ReconfigCoalescer(trailingWindow: 0.05) { confirm() }
            coalescer.bump()
            coalescer.cancel()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
