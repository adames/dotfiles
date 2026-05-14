import AppKit
import Foundation
import SwiftUI

/// Top-level AppKit + key-dispatch shell for ws-prompt. Owns the
/// borderless overlay window, the NSEvent monitor token, the SIGTERM
/// signal source, the PID-file single-instance lock, and the
/// controller(s) for the chosen mode.
///
/// Lifecycle:
///   init(mode:, service:)  → builds controllers + window
///   run()                  → blocks on NSApp.run()
///   terminate()            → removes PID file, removes NSEvent
///                            monitor, terminates NSApp
///
/// External dependencies (yabai, ws, file system) come in through
/// `service` so the App class itself is testable in principle — though
/// the live overlay path is exercised end-to-end via the bash harness.
final class WsPromptApp {
    private let mode: PromptMode
    private let service: WorkspaceService
    private let window: PromptWindow
    private let pidPath: URL

    // Strong refs so the runtime keeps everything alive.
    private let promptController: PromptController?
    private let manageController: ManageController?
    private let workspaces: [Workspace]
    private let focusedIndex: Int?
    private var eventMonitorToken: Any?
    private var windowDelegate: WindowDelegate?
    private var signalSource: DispatchSourceSignal?

    init(mode: PromptMode, service: WorkspaceService) {
        self.mode = mode
        self.service = service
        self.pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-prompt.\(mode.rawValue).pid")

        let workspaces = service.loadWorkspaces()
        // Snapshot the focused slot once at overlay open. Used by
        // dispatchFocusOrSend to fire sketchybar's optimistic pre-paint
        // trigger the instant the chord commits — no extra yabai RPC
        // at commit time.
        let focusedIndex = service.focusedSpaceIndex()
        self.workspaces = workspaces
        self.focusedIndex = focusedIndex

        let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
        let win = PromptWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .modalPanel
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.isReleasedWhenClosed = false
        self.window = win

        // Build the right controller pair and content view for the mode.
        switch mode {
        case .focus, .send:
            let ctl = PromptController(mode: mode, workspaces: workspaces)
            self.promptController = ctl
            self.manageController = nil
            win.contentView = NSHostingView(rootView: PromptView(controller: ctl))
        case .manage:
            let ctl = ManageController(
                workspaces: workspaces, focusedIndex: focusedIndex, service: service
            )
            self.manageController = ctl
            self.promptController = nil
            win.contentView = NSHostingView(rootView: ManageView(controller: ctl))
        }

        // Wire the controller's "command succeeded" callback to the
        // App's terminate path. Set after all stored properties exist
        // so `self` is fully initialized when the closure captures it.
        manageController?.onTerminate = { [weak self] in self?.terminate() }
    }

    // MARK: - Lifecycle

    func run() {
        // Single-instance toggle: a second invocation of the same chord
        // dismisses the open instance and exits. Per-mode PID files so
        // a stuck focus prompt doesn't block manage.
        if let existing = readExistingPID() {
            kill(existing, SIGTERM)
            exit(0)
        }
        writePID()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = WindowDelegate { [weak self] in self?.terminate() }
        windowDelegate = delegate
        window.delegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()
        installSignalHandler()

        app.run()
    }

    func terminate() -> Never {
        if let token = eventMonitorToken {
            NSEvent.removeMonitor(token)
            eventMonitorToken = nil
        }
        signalSource?.cancel()
        try? FileManager.default.removeItem(at: pidPath)
        NSApp.terminate(nil)
        exit(0)
    }

    // MARK: - Key dispatch

    /// Local key monitor — runs on the main queue, sees every keyDown
    /// while we're the key window. We swallow the event (return nil)
    /// to keep it from leaking into the foreground app.
    private func installKeyMonitor() {
        eventMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let key = self.decodeKey(event) else { return event }
            self.dispatch(key)
            return nil
        }
    }

    private func decodeKey(_ event: NSEvent) -> PromptKey? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  return .escape      // kVK_Escape
        case 36:  return .enter       // kVK_Return
        case 48:  return mods.contains(.shift) ? .backTab : .tab   // kVK_Tab
        case 51:  return .backspace   // kVK_Delete
        default:
            // `charactersIgnoringModifiers` strips most modifiers but
            // keeps Shift, so Shift+L still resolves to "L".
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            return .char(c)
        }
    }

    private func dispatch(_ key: PromptKey) {
        switch mode {
        case .focus, .send:  dispatchFocusOrSend(key)
        case .manage:        dispatchManage(key)
        }
    }

    private func dispatchFocusOrSend(_ key: PromptKey) {
        guard let ctl = promptController else { return }
        switch ctl.handle(key) {
        case .idle, .refilter:           return
        case .cancel:                    terminate()
        case .commitFocus(let slot):
            firePrePaint(targetSlot: slot)
            service.spawnFocus(slot: slot)
            terminate()
        case .commitSend(let slot):
            firePrePaint(targetSlot: slot)
            service.spawnSend(slot: slot)
            terminate()
        }
    }

    /// Optimistic pre-paint. Fires the sketchybar trigger with the
    /// target SID + OLD SID + target display before we even spawn the
    /// bash helper. Removes the helper's subprocess fork + yabai-RPC
    /// cost (~30–40 ms) from the chord-to-pill latency. Helper still
    /// fires the same trigger as a defensive backstop when invoked
    /// from the CLI directly.
    private func firePrePaint(targetSlot: Int) {
        guard let oldSlot = focusedIndex, oldSlot != targetSlot else { return }
        guard let target = workspaces.first(where: { $0.index == targetSlot }) else { return }
        service.fireOptimisticPrePaint(newSlot: targetSlot,
                                       oldSlot: oldSlot,
                                       display: target.display)
    }

    private func dispatchManage(_ key: PromptKey) {
        guard let ctl = manageController else { return }
        switch ctl.handle(key) {
        case .idle:        return
        case .terminate:   terminate()
        }
    }

    // MARK: - Signals + PID

    private func installSignalHandler() {
        // SIGTERM from a second `--toggle` invocation: close cleanly.
        // libdispatch handles the signal; ignore the default action.
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in self?.terminate() }
        source.resume()
        signal(SIGTERM, SIG_IGN)
        signalSource = source
    }

    private func readExistingPID() -> Int32? {
        guard let data = try? Data(contentsOf: pidPath),
              let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str), kill(pid, 0) == 0
        else { return nil }
        return pid
    }

    private func writePID() {
        let dir = pidPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "\(getpid())".write(to: pidPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Helper types

/// NSWindow subclass with `canBecomeKey = true` — required for a
/// borderless window to receive keyDown events.
final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Routes window-delegate events (specifically `windowDidResignKey` —
/// blur cancels) back into the App via a closure. Decoupling lets the
/// App own the cancel policy without making it an NSObject subclass.
final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onBlur: () -> Void
    init(onBlur: @escaping () -> Void) { self.onBlur = onBlur }
    func windowDidResignKey(_ notification: Notification) { onBlur() }
}
