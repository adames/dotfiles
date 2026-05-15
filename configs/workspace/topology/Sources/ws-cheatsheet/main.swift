import AppKit
import Foundation
import SwiftUI

// MARK: - Single-instance toggle via PID file
//
// Usage:
//   ws-cheatsheet              → open (or refuse silently if already open)
//   ws-cheatsheet --toggle     → open if closed; close if open
//
// Behavior: writes our PID to ~/.cache/workspace/cheatsheet.pid on open.
// On --toggle, if the pidfile points at a live process, send SIGTERM and
// exit (the running instance handles the signal by closing the window
// and removing the pidfile).

let pidPath = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".cache/workspace/cheatsheet.pid")

let args = Array(CommandLine.arguments.dropFirst())
let isToggle = args.contains("--toggle")

func readExistingPID() -> Int32? {
    guard let data = try? Data(contentsOf: pidPath),
          let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(str) else { return nil }
    // kill(pid, 0) returns 0 if the process exists, -1 otherwise.
    if kill(pid, 0) == 0 { return pid }
    return nil
}

func writePID() {
    let dir = pidPath.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? "\(getpid())".write(to: pidPath, atomically: true, encoding: .utf8)
}

func removePID() {
    try? FileManager.default.removeItem(at: pidPath)
}

if let existing = readExistingPID() {
    if isToggle {
        // Tell the existing instance to close + clean up.
        kill(existing, SIGTERM)
        exit(0)
    } else {
        // Already open and we're not toggling → silently exit (the user
        // probably bound the hotkey to plain `ws-cheatsheet` and pressed
        // it twice; we don't want a second window stacking up).
        exit(0)
    }
}

writePID()

// MARK: - App + window
//
// LSUIElement-equivalent setup at runtime: accessory policy keeps the
// cheatsheet out of the Dock / cmd-tab. We rely on `activate(ignoringOtherApps:)`
// to bring the window forward.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Load the document. If the file is missing or malformed, show a single
// error card rather than crashing — the user can fix the JSON and reopen.
let document: CheatsheetDocument
do {
    document = try CheatsheetLoader.load()
} catch {
    let errorSection = CheatsheetDocument.Section(
        title: "Error",
        rows: [
            ["path", CheatsheetLoader.defaultPath.path],
            ["reason", "\(error)"],
        ],
        color: "#ef4444",
        sub: "ws-cheatsheet — load failure"
    )
    document = CheatsheetDocument(
        banner: [.init(k: "ERR", v: "cheatsheet.json not loadable")],
        columns: [.init(sections: [errorSection])]
    )
}

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm"
let timestamp = formatter.string(from: Date())

let view = CheatsheetView(document: document, timestamp: timestamp)

// Pick the focused display so the HUD opens where the user is looking.
let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
let frame = screen.frame

let window = CheatsheetWindow(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.level = .modalPanel
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
window.isReleasedWhenClosed = false
window.contentView = NSHostingView(rootView: view)

window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

// MARK: - Dismissal: Esc, focus loss, SIGTERM

class AppController: NSObject, NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // User clicked elsewhere — close the HUD.
        terminate()
    }
}
let controller = AppController()
window.delegate = controller

// Esc dismiss via a local key monitor (scoped to our app's first responder).
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // 53 = kVK_Escape
    if event.keyCode == 53 {
        terminate()
    }
    return event
}

// SIGTERM from a second `--toggle` invocation: close cleanly.
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigSource.setEventHandler { terminate() }
sigSource.resume()
signal(SIGTERM, SIG_IGN)   // libdispatch handles it; ignore default action

func terminate() -> Never {
    removePID()
    NSApp.terminate(nil)
    exit(0)
}

// CleanUp guard: if the process gets killed via SIGINT etc, remove the
// pidfile so the next invocation sees a clean state.
atexit {
    try? FileManager.default.removeItem(
        at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/cheatsheet.pid")
    )
}

app.run()

// MARK: - NSWindow subclass that can become key (required for keyDown delivery
// to a borderless window).
final class CheatsheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
