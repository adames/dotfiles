import Foundation

// ws-picker [--simulate-keys "<keys>"]
//
// Window-picker overlay bound to Caps+e in skhdrc. Lists every visible
// yabai window, fuzzy-filters by app + title + space, focuses the pick
// on Enter. Runtime split:
//
//   PickerController       — state machine (pure-ish; ObservableObject)
//   ProductionWindowSource — single seam to yabai
//   WsPickerApp            — AppKit window + key dispatch + lifecycle
//   PickerView             — SwiftUI rendering bound to the controller
//
// This file just parses argv and picks production vs simulate.

let rawArgs = Array(CommandLine.arguments.dropFirst())

if let i = rawArgs.firstIndex(of: "--simulate-keys"), i + 1 < rawArgs.count {
    let keys = rawArgs[i + 1]
    let source = ProductionWindowSource()
    let controller = PickerController(items: source.loadWindows())
    let result = controller.simulate(PickerKeySequence.parse(keys))
    exit(PickerSimReporter.print(action: result))
}

let app = WsPickerApp(source: ProductionWindowSource())
app.run()
