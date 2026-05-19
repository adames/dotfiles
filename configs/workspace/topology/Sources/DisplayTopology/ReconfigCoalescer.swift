import CoreGraphics
import Dispatch
import Foundation
import WorkspaceState

/// Coalesces bursts of `CGDisplayRegisterReconfigurationCallback` notifications
/// into a single emission. Apple's docs (and the research) note the callback
/// fires twice for one physical event (begin + post-config); we collect both
/// within a short window and only call the consumer once.
public final class ReconfigCoalescer: @unchecked Sendable {
    public let trailingWindow: TimeInterval
    public let queue: DispatchQueue
    private let onFire: () -> Void

    private var scheduledWorkItem: DispatchWorkItem?
    private var lock = os_unfair_lock()

    public init(
        trailingWindow: TimeInterval = 0.05,
        queue: DispatchQueue = DispatchQueue(label: "\(WorkspaceConfig.bundlePrefix).topology.coalesce"),
        onFire: @escaping () -> Void
    ) {
        self.trailingWindow = trailingWindow
        self.queue = queue
        self.onFire = onFire
    }

    /// Schedule a trailing emission. Repeated calls within the window collapse
    /// into one final invocation.
    public func bump() {
        os_unfair_lock_lock(&lock)
        scheduledWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onFire()
        }
        scheduledWorkItem = item
        os_unfair_lock_unlock(&lock)
        queue.asyncAfter(deadline: .now() + trailingWindow, execute: item)
    }

    /// Cancel any pending emission without firing. Useful for shutdown.
    public func cancel() {
        os_unfair_lock_lock(&lock)
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
        os_unfair_lock_unlock(&lock)
    }
}
