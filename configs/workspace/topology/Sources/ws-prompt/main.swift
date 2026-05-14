import AppKit
import Foundation
import SwiftUI

// ws-prompt <focus|send|manage> [--simulate-keys "<keys>"]
//
// Live mode: a transient SwiftUI overlay that captures keystrokes and
// exits on commit / cancel / blur / SIGTERM. Three flavours:
//
//   focus / send  — single-step "pick a workspace and act".
//                   PromptController + PromptView.
//   manage         — multi-step state machine (verb → target / payload →
//                   confirm → result). ManageController + ManageView.
//
// Simulate mode: headless smoke harness for the focus/send state machine
// (no Manage path simulated — its commands are stateful and live-tested).

let rawArgs = Array(CommandLine.arguments.dropFirst())

// MARK: - Argument parsing

func parseMode(_ args: [String]) -> PromptMode? {
    guard let first = args.first else { return nil }
    return PromptMode(rawValue: first)
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: ws-prompt <focus|send|manage> [--simulate-keys \"<keys>\"]\n".utf8))
    exit(2)
}

guard let mode = parseMode(rawArgs) else { usage() }
let simulateIdx = rawArgs.firstIndex(of: "--simulate-keys")
let simulateKeys: String? = {
    guard let i = simulateIdx, i + 1 < rawArgs.count else { return nil }
    return rawArgs[i + 1]
}()

// MARK: - Simulate mode (focus / send only — Manage is live-tested)

if let keys = simulateKeys {
    guard mode != .manage else {
        FileHandle.standardError.write(Data(
            "ws-prompt: --simulate-keys is not supported in manage mode\n".utf8))
        exit(2)
    }
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

// MARK: - Live mode: PID-file single-instance toggle

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
    // Same chord pressed twice → dismiss the open instance and exit.
    // PIDs are per-mode so a stuck focus prompt doesn't block manage.
    kill(existing, SIGTERM)
    exit(0)
}
writePID()

// MARK: - App + window

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let yabai = WorkspaceLoader.resolveYabaiBinary()
let workspaces = WorkspaceLoader.load(yabaiBinary: yabai)

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

final class AppController: NSObject, NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Blur cancels — same contract as ws-cheatsheet.
        terminate()
    }
}
let delegate = AppController()
window.delegate = delegate

// MARK: - Mode-specific setup
//
// focus / send and manage have different controllers + views. We bind
// the window's contentView and the keydown dispatcher conditionally
// to keep each mode's code path narrow.

let promptVM: PromptViewModel?
let promptController: PromptController?
let manageVM: ManageViewModel?
let manageController: ManageController?

switch mode {
case .focus, .send:
    let vm = PromptViewModel(mode: mode, workspaces: workspaces)
    let ctl = PromptController(mode: mode, workspaces: workspaces)
    promptVM = vm
    promptController = ctl
    manageVM = nil
    manageController = nil
    window.contentView = NSHostingView(rootView: PromptView(vm: vm))
case .manage:
    let vm = ManageViewModel(workspaces: workspaces)
    let ctl = ManageController(workspaces: workspaces)
    manageVM = vm
    manageController = ctl
    promptVM = nil
    promptController = nil
    window.contentView = NSHostingView(rootView: ManageView(vm: vm))
}

window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

// MARK: - Key dispatch

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
            // `charactersIgnoringModifiers` strips most modifiers but
            // *keeps* shift, so Shift+L still comes through as "L".
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            return .char(c)
        }
    }()
    guard let key = promptKey else { return event }
    dispatch(key)
    return nil
}

let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigSource.setEventHandler { terminate() }
sigSource.resume()
signal(SIGTERM, SIG_IGN)

atexit {
    try? FileManager.default.removeItem(
        at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".cache/workspace/ws-prompt.\(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "focus").pid")
    )
}

func dispatch(_ key: PromptKey) {
    switch mode {
    case .focus, .send: dispatchFocusOrSend(key)
    case .manage:       dispatchManage(key)
    }
}

func dispatchFocusOrSend(_ key: PromptKey) {
    guard let ctl = promptController, let vm = promptVM else { return }
    let action = ctl.handle(key)
    vm.query = ctl.query
    vm.matches = ctl.currentMatches()
    vm.selection = min(ctl.selection, max(0, vm.matches.count - 1))

    switch action {
    case .idle, .refilter:           return
    case .cancel:                    terminate()
    case .commitFocus(let slot):     runHelper("ws-focus", String(slot)); terminate()
    case .commitSend(let slot):      runHelper("ws-send-follow", String(slot)); terminate()
    }
}

func dispatchManage(_ key: PromptKey) {
    guard let ctl = manageController, let vm = manageVM else { return }
    let action = ctl.handle(key)
    vm.stage = ctl.stage

    switch action {
    case .idle:                              return
    case .terminate:                         terminate()
    case .runCommand(let verb, let args, let capture):
        runWsCommand(verb: verb, args: args, capture: capture)
    }
}

// MARK: - Helper / `ws` command runners

func runHelper(_ name: String, _ arg: String...) {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/\(name)").path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arg
    do { try task.run() } catch {
        FileHandle.standardError.write(Data("ws-prompt: spawn \(name) failed: \(error)\n".utf8))
    }
}

/// Run `ws <args>` and surface the result back into the manage flow.
/// We capture stderr + stdout together because the CLI's `ok`/`err`
/// helpers emit to stderr; the user wants to see all of it in the panel.
/// Runs in the background so the UI thread isn't blocked; result is
/// pushed back on the main queue.
func runWsCommand(verb: String, args: [String], capture: Bool) {
    let wsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/ws").path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: wsPath)
    task.arguments = args
    let pipe = Pipe()
    if capture {
        task.standardOutput = pipe
        task.standardError = pipe
    }

    DispatchQueue.global(qos: .userInitiated).async {
        var output = ""
        var success = false
        do {
            try task.run()
            task.waitUntilExit()
            success = (task.terminationStatus == 0)
            if capture {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8) ?? ""
            }
        } catch {
            output = "spawn failed: \(error)"
            success = false
        }
        DispatchQueue.main.async {
            // On a clean success that's not doctor/verify, jump straight
            // to a green "done" panel and let the user dismiss with any
            // key. Errors always show the panel with the captured output
            // so the user can read what went wrong.
            guard let ctl = manageController, let vm = manageVM else { return }
            ctl.applyCommandResult(verb: verb, success: success, output: output)
            vm.stage = ctl.stage
        }
    }
}

func terminate() -> Never {
    removePID()
    NSApp.terminate(nil)
    exit(0)
}

app.run()
