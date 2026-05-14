import Foundation

// ws-prompt <focus|send|manage> [--simulate-keys "<keys>"]
//
// The runtime is split across:
//
//   PromptController     — focus/send state machine (pure-ish; ObservableObject)
//   ManageController     — manage state machine (multi-stage; ObservableObject)
//   WorkspaceService     — single seam to yabai / ws CLI / file system
//   WsPromptApp          — AppKit window + key dispatch + lifecycle
//   PromptView/ManageView — SwiftUI rendering bound to the controllers
//
// This file just parses argv, picks production vs. simulate path, and
// hands off.

let rawArgs = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data(
        "usage: ws-prompt <focus|send|manage> [--simulate-keys \"<keys>\"]\n".utf8))
    exit(2)
}

guard let modeArg = rawArgs.first, let mode = PromptMode(rawValue: modeArg) else { usage() }

// Optional --simulate-keys "<keys>" → headless smoke harness for the
// focus/send state machine. Manage is too stateful (Process side
// effects + completion handlers) for a useful one-shot sim, so reject
// the flag for manage explicitly.
if let i = rawArgs.firstIndex(of: "--simulate-keys"), i + 1 < rawArgs.count {
    let keys = rawArgs[i + 1]
    guard mode != .manage else {
        FileHandle.standardError.write(Data(
            "ws-prompt: --simulate-keys is not supported in manage mode\n".utf8))
        exit(2)
    }
    let service = ProductionWorkspaceService()
    let controller = PromptController(mode: mode, workspaces: service.loadWorkspaces())
    let result = controller.simulate(KeySequenceParser.parse(keys))
    exit(SimulateReporter.print(action: result, mode: mode))
}

// Live mode: build the App and run its NSApp loop. The App handles
// PID-file single-instance, NSEvent monitoring, SIGTERM, and the
// terminate path.
let app = WsPromptApp(mode: mode, service: ProductionWorkspaceService())
app.run()
