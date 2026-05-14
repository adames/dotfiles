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
    // Capture the focused space index once, so rename/destroy default to
    // "act on the workspace I'm already on". Nil-tolerant — yabai not
    // responding just means the picker starts at index 0.
    let focusedIndex = WorkspaceLoader.queryFocusedSpaceIndex(yabaiBinary: yabai)
    let vm = ManageViewModel(workspaces: workspaces)
    let ctl = ManageController(workspaces: workspaces, focusedIndex: focusedIndex)
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
    case .runWs(let verb, let args):
        runManageCommand(verb: verb, binary: wsBinaryPath, args: args)
    case .runYabai(let verb, let args):
        runManageCommand(verb: verb, binary: WorkspaceLoader.resolveYabaiBinary(), args: args)
    case .runAdd(let name, let icon):
        runAddComposite(name: name, icon: icon)
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

let wsBinaryPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/bin/ws").path

/// Run a single external command (ws or yabai) and surface the result
/// back into the manage flow. Captures stderr + stdout because the CLI's
/// `ok`/`err` helpers emit to stderr; the user wants to see all of it
/// in the result panel. Runs in the background so the UI thread isn't
/// blocked; result is pushed back on the main queue.
@discardableResult
func runManageCommand(verb: String, binary: String, args: [String]) -> Process? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: binary)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    DispatchQueue.global(qos: .userInitiated).async {
        var output = ""
        var success = false
        do {
            try task.run()
            task.waitUntilExit()
            success = (task.terminationStatus == 0)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {
            output = "spawn failed: \(error)"
            success = false
        }
        DispatchQueue.main.async {
            guard let ctl = manageController, let vm = manageVM else { return }
            ctl.applyCommandResult(verb: verb, success: success, output: output)
            vm.stage = ctl.stage
        }
    }
    return task
}

/// Composite "add" — create the yabai Space, then attach identity via
/// `ws name <new_index> NAME [ICON]`. Run synchronously in a background
/// queue and surface the combined result. Without this two-step the add
/// path either creates an orphan macOS Space (ws-only) or an orphan
/// spaces.json entry (yabai-only). Failure at step 1 (yabai SA not
/// loaded) short-circuits; failure at step 2 leaves the new Space
/// nameless but visible.
func runAddComposite(name: String, icon: String?) {
    let yabai = WorkspaceLoader.resolveYabaiBinary()
    let body = "name=\(name)" + (icon.map { " icon=\($0)" } ?? "")

    DispatchQueue.global(qos: .userInitiated).async {
        // Step 1: create the macOS Space.
        let create = Process()
        create.executableURL = URL(fileURLWithPath: yabai)
        create.arguments = ["-m", "space", "--create"]
        let createPipe = Pipe()
        create.standardOutput = createPipe
        create.standardError = createPipe
        do {
            try create.run()
            create.waitUntilExit()
        } catch {
            DispatchQueue.main.async {
                guard let ctl = manageController, let vm = manageVM else { return }
                ctl.applyCommandResult(verb: "add", success: false,
                                       output: "yabai spawn failed: \(error)\n\(body)")
                vm.stage = ctl.stage
            }
            return
        }
        if create.terminationStatus != 0 {
            let data = createPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let ctl = manageController, let vm = manageVM else { return }
                ctl.applyCommandResult(verb: "add", success: false,
                                       output: "yabai space --create failed:\n\(out)\n\(body)")
                vm.stage = ctl.stage
            }
            return
        }

        // Step 2: count yabai's spaces; the new slot is the highest
        // index. Then attach identity via `ws name`.
        let newIndex = WorkspaceLoader.querySpaceCount(yabaiBinary: yabai)
        guard newIndex >= 1 else {
            DispatchQueue.main.async {
                guard let ctl = manageController, let vm = manageVM else { return }
                ctl.applyCommandResult(verb: "add", success: false,
                                       output: "yabai created the space but couldn't query the new count\n\(body)")
                vm.stage = ctl.stage
            }
            return
        }

        // `ws name` takes only NAME — icon is set via `ws icon SLOT GLYPH`
        // as a second call. Run inline so the composite result reflects
        // the final state.
        let nameTask = Process()
        nameTask.executableURL = URL(fileURLWithPath: wsBinaryPath)
        nameTask.arguments = ["name", String(newIndex), name]
        let namePipe = Pipe()
        nameTask.standardOutput = namePipe
        nameTask.standardError = namePipe
        var nameOut = ""
        var nameOK = false
        do {
            try nameTask.run()
            nameTask.waitUntilExit()
            nameOK = (nameTask.terminationStatus == 0)
            nameOut = String(data: namePipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
        } catch {
            nameOut = "ws name spawn failed: \(error)"
        }

        var iconOK = true
        var iconOut = ""
        if nameOK, let icon = icon {
            let iconTask = Process()
            iconTask.executableURL = URL(fileURLWithPath: wsBinaryPath)
            iconTask.arguments = ["icon", String(newIndex), icon]
            let iconPipe = Pipe()
            iconTask.standardOutput = iconPipe
            iconTask.standardError = iconPipe
            do {
                try iconTask.run()
                iconTask.waitUntilExit()
                iconOK = (iconTask.terminationStatus == 0)
                iconOut = String(data: iconPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            } catch {
                iconOK = false
                iconOut = "ws icon spawn failed: \(error)"
            }
        }
        DispatchQueue.main.async {
            guard let ctl = manageController, let vm = manageVM else { return }
            let success = nameOK && iconOK
            let combined = [nameOut, iconOut].filter { !$0.isEmpty }.joined(separator: "\n")
            ctl.applyCommandResult(verb: "add",
                                   success: success,
                                   output: combined.isEmpty
                                            ? "slot \(newIndex) → \(name)"
                                            : combined)
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
