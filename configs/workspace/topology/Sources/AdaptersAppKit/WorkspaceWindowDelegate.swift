import AppKit
import DisplayTopology
import LayoutPolicy

/// Pure-Swift window delegate that consumes a `TopologySnapshot` published by the
/// daemon and applies layout policy when the hosting window crosses displays or
/// the backing properties change.
@MainActor
public final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {

    public var onScreenChange:  ((NSWindow, DisplaySnapshot?) -> Void)?
    public var onBackingChange: ((NSWindow, DisplaySnapshot?) -> Void)?
    public var snapshotProvider: () -> TopologySnapshot? = { nil }

    public override init() {}

    public func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let display = currentDisplay(for: window)
        onScreenChange?(window, display)
        restoreFirstResponder(of: window)
    }

    public func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let display = currentDisplay(for: window)
        onBackingChange?(window, display)
    }

    public func applicationDidChangeScreenParameters(_ notification: Notification) {
        // App-wide notification mirrored here for consumers that want a single
        // delegate. The daemon handles the canonical reconfiguration callback;
        // this is purely a hook for window-level reactions to app-wide changes.
    }

    private func currentDisplay(for window: NSWindow) -> DisplaySnapshot? {
        guard let screen = window.screen,
              let snapshot = snapshotProvider(),
              let id = DisplayTopologyService.displayID(for: screen) else {
            return nil
        }
        return snapshot.displays.first(where: { $0.id == id })
    }

    private func restoreFirstResponder(of window: NSWindow) {
        if window.firstResponder == nil {
            _ = window.makeFirstResponder(window.contentView)
        }
    }
}
