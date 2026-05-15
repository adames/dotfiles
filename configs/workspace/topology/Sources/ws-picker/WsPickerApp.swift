import AppKit
import Foundation
import SwiftUI

/// AppKit shell for ws-picker. Mirrors ws-prompt's WsPromptApp:
///   - Borderless modalPanel overlay that joins all spaces
///   - Local NSEvent monitor that swallows keyDown so chords don't leak
///   - SIGTERM handler for the second-invocation toggle
///   - PID-file single-instance lock under ~/.cache/workspace/
///   - windowDidResignKey blur dismissal
///
/// External dependencies (yabai) come in via WindowSource so the App is
/// in principle testable, though the live overlay path is exercised
/// end-to-end via the bash harness.
final class WsPickerApp {
    private let source: WindowSource
    private let window: PickerWindow
    private let controller: PickerController
    private let pidPath: URL

    private var eventMonitorToken: Any?
    private var windowDelegate: WindowDelegate?
    private var signalSource: DispatchSourceSignal?

    init(source: WindowSource) {
        self.source = source
        self.pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-picker.pid")

        let items = source.loadWindows()
        self.controller = PickerController(items: items)

        let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
        let win = PickerWindow(
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
        win.contentView = NSHostingView(rootView: PickerView(controller: controller))
        self.window = win
    }

    // MARK: - Lifecycle

    func run() {
        // Single-instance toggle: a second Caps+e while the picker is
        // open closes it. Same pattern as ws-prompt — one PID file
        // distinct from any prompt PID file so the two overlays don't
        // collide.
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

    private func installKeyMonitor() {
        eventMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let key = self.decodeKey(event) else { return event }
            self.dispatch(key)
            return nil
        }
    }

    private func decodeKey(_ event: NSEvent) -> PickerKey? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  return .escape
        case 36:  return .enter
        case 48:  return mods.contains(.shift) ? .backTab : .tab
        case 51:  return .backspace
        default:
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            return .char(c)
        }
    }

    private func dispatch(_ key: PickerKey) {
        switch controller.handle(key) {
        case .idle, .refilter:    return
        case .cancel:             terminate()
        case .commit(let id):
            source.focus(windowID: id)
            terminate()
        }
    }

    // MARK: - Signals + PID

    private func installSignalHandler() {
        let dispatch = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        dispatch.setEventHandler { [weak self] in self?.terminate() }
        dispatch.resume()
        signal(SIGTERM, SIG_IGN)
        signalSource = dispatch
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

final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onBlur: () -> Void
    init(onBlur: @escaping () -> Void) { self.onBlur = onBlur }
    func windowDidResignKey(_ notification: Notification) { onBlur() }
}
