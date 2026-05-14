import AppKit
import Foundation
import SwiftUI

// ws-prompt <focus|send> [--simulate-keys "<keys>"]
//
// Live mode: a transient SwiftUI overlay that captures keystrokes,
// invokes the matching ws-* helper on commit, and exits. Replaces the
// old skhd sticky modes (focus / send). Nothing here owns a persistent
// state — the overlay terminates on every commit, cancel, blur, or
// SIGTERM.
//
// Simulate mode: headless, feeds `--simulate-keys` through the same
// PromptController and prints the action it WOULD have taken. Used by
// tests/unit/ws-prompt.test.sh; no AppKit, no helper spawning.

let rawArgs = Array(CommandLine.arguments.dropFirst())

// MARK: - Argument parsing

func parseMode(_ args: [String]) -> PromptMode? {
    guard let first = args.first else { return nil }
    return PromptMode(rawValue: first)
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: ws-prompt <focus|send> [--simulate-keys \"<keys>\"]\n".utf8))
    exit(2)
}

guard let mode = parseMode(rawArgs) else { usage() }
let simulateIdx = rawArgs.firstIndex(of: "--simulate-keys")
let simulateKeys: String? = {
    guard let i = simulateIdx, i + 1 < rawArgs.count else { return nil }
    return rawArgs[i + 1]
}()

// MARK: - Simulate mode (headless)

if let keys = simulateKeys {
    let wsConfig: URL = {
        if let p = ProcessInfo.processInfo.environment["WS_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/workspace/spaces.json")
    }()
    let yabai = WorkspaceLoader.resolveYabaiBinary()
    let workspaces = WorkspaceLoader.load(yabaiBinary: yabai, wsConfig: wsConfig)
    let controller = PromptController(mode: mode, workspaces: workspaces)
    let parsed = KeySequenceParser.parse(keys)
    let result = controller.simulate(parsed)
    let exitCode = SimulateReporter.print(action: result, mode: mode)
    exit(exitCode)
}

// MARK: - Live mode (AppKit overlay)

let pidPath = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".cache/workspace/ws-prompt.\(mode.rawValue).pid")

func readExistingPID() -> Int32? {
    guard let data = try? Data(contentsOf: pidPath),
          let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(str) else { return nil }
    if kill(pid, 0) == 0 { return pid }
    return nil
}
func writePID() {
    let dir = pidPath.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? "\(getpid())".write(to: pidPath, atomically: true, encoding: .utf8)
}
func removePID() { try? FileManager.default.removeItem(at: pidPath) }

if let existing = readExistingPID() {
    // Same chord pressed twice: dismiss the open one and exit. Mirrors
    // ws-cheatsheet's --toggle behavior. PIDs are per-mode so a stuck
    // focus prompt doesn't block opening manage.
    kill(existing, SIGTERM)
    exit(0)
}
writePID()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let yabai = WorkspaceLoader.resolveYabaiBinary()
let workspaces = WorkspaceLoader.load(yabaiBinary: yabai)
let controller = PromptController(mode: mode, workspaces: workspaces)
let vm = PromptViewModel(mode: mode, workspaces: workspaces)

let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
let frame = screen.frame

final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

let window = PromptWindow(
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
window.contentView = NSHostingView(rootView: PromptView(vm: vm))
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

final class AppController: NSObject, NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Blur cancels — same contract as ws-cheatsheet.
        terminate()
    }
}
let delegate = AppController()
window.delegate = delegate

// MARK: - Key dispatch
//
// Key codes for the few non-character keys we care about. Modeled
// directly on the constants in <Carbon/HIToolbox/Events.h>.
let kVK_Return: UInt16    = 36
let kVK_Tab: UInt16       = 48
let kVK_Delete: UInt16    = 51   // backspace
let kVK_Escape: UInt16    = 53

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    let promptKey: PromptKey? = {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case kVK_Escape: return .escape
        case kVK_Return: return .enter
        case kVK_Tab:    return mods.contains(.shift) ? .backTab : .tab
        case kVK_Delete: return .backspace
        default:
            // Build a single-character key from the typed input. Use
            // charactersIgnoringModifiers so layout-mapped letters
            // (e.g. Dvorak) still resolve to the printable letter.
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            return .char(c)
        }
    }()
    guard let key = promptKey else { return event }
    dispatch(key)
    return nil   // swallow the event — the overlay owns input
}

let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigSource.setEventHandler { terminate() }
sigSource.resume()
signal(SIGTERM, SIG_IGN)

atexit {
    try? FileManager.default.removeItem(
        at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-prompt.\(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "focus").pid")
    )
}

func dispatch(_ key: PromptKey) {
    let action = controller.handle(key)
    // Reflect controller state into the view model after every key.
    vm.query = controller.query
    vm.matches = controller.currentMatches()
    vm.selection = min(controller.selection, max(0, vm.matches.count - 1))

    switch action {
    case .idle, .refilter:
        return
    case .cancel:
        terminate()
    case .commitFocus(let slot):
        runHelper("ws-focus", String(slot))
        terminate()
    case .commitSend(let slot):
        runHelper("ws-send-follow", String(slot))
        terminate()
    }
}

func runHelper(_ name: String, _ arg: String...) {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/\(name)").path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arg
    do { try task.run() } catch {
        // Helpers themselves notify on failure; if even the spawn fails,
        // log to stderr but stay silent in the UI — we're already
        // tearing down.
        FileHandle.standardError.write(Data("ws-prompt: spawn \(name) failed: \(error)\n".utf8))
    }
    // Don't wait — let the helper finish on its own. The bash side is
    // fire-and-forget anyway.
}

func terminate() -> Never {
    removePID()
    NSApp.terminate(nil)
    exit(0)
}

app.run()
