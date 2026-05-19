import AppKit
import CoreGraphics
import DisplayTopology
import Foundation
import LayoutPolicy
import OSLog
import WorkspaceState

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())
let exitCode = run(args: args)
exit(exitCode)

func run(args: [String]) -> Int32 {
    guard let subcommand = args.first else {
        printUsage()
        return 2
    }

    let rest = Array(args.dropFirst())

    switch subcommand {
    case "dump":          return cmdDump(args: rest)
    case "layout":        return cmdLayout(args: rest)
    case "migrate":       return cmdMigrate(args: rest)
    case "resolve-icon":  return cmdResolveIcon(args: rest)
    case "emit-skhd":     return cmdEmitSkhd(args: rest)
    case "help", "-h", "--help":
        printUsage()
        return 0
    default:
        FileHandle.standardError.write(Data("ws-topology: unknown subcommand: \(subcommand)\n".utf8))
        printUsage()
        return 2
    }
}

func printUsage() {
    let usage = """
    usage: ws-topology <subcommand> [args]

      dump                  print the current display topology as JSON
      layout                print the per-display layout policy as JSON
      migrate [--apply]     migrate spaces.json from v1 to v2 (dry-run by default).
                            Idempotent on already-v2 files; useful for importing
                            legacy spaces.default.json seeds on fresh installs.
      resolve-icon <slot>   resolve the icon for a slot index or name; --surface=font|native
      emit-skhd [--write]   emit the dynamic skhd fragment to stdout or to disk

    common flags:
      --config PATH         override spaces.json location (default ~/.config/workspace/spaces.json)
      --cache-dir PATH      override cache directory (default ~/.cache/workspace)

    """
    FileHandle.standardError.write(Data(usage.utf8))
}

// MARK: - Common arg parsing

struct CommonOptions {
    var configURL: URL
    var cacheDirURL: URL
    var remaining: [String]
}

func parseCommonOptions(_ args: [String]) -> CommonOptions {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var configPath = ProcessInfo.processInfo.environment["WS_CONFIG"]
        ?? home.appendingPathComponent(".config/workspace/spaces.json").path
    var cachePath  = ProcessInfo.processInfo.environment["WS_CACHE_DIR"]
        ?? home.appendingPathComponent(".cache/workspace").path

    var remaining: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--config", i + 1 < args.count {
            configPath = args[i+1]; i += 2; continue
        }
        if a == "--cache-dir", i + 1 < args.count {
            cachePath = args[i+1]; i += 2; continue
        }
        remaining.append(a); i += 1
    }
    return CommonOptions(
        configURL: URL(fileURLWithPath: configPath),
        cacheDirURL: URL(fileURLWithPath: cachePath),
        remaining: remaining
    )
}

// MARK: - dump

func cmdDump(args: [String]) -> Int32 {
    return MainActor.assumeIsolated {
        let snapshot = DisplayTopologyService.snapshot()
        do {
            let json = try CacheEncoding.encode(snapshot)
            print(json)
            return 0
        } catch {
            FileHandle.standardError.write(Data("dump: \(error)\n".utf8))
            return 1
        }
    }
}

// MARK: - layout

func cmdLayout(args: [String]) -> Int32 {
    return MainActor.assumeIsolated {
        let snapshot = DisplayTopologyService.snapshot()
        let policies = LayoutPolicyEngine.policies(for: snapshot.displays)
        do {
            let json = try CacheEncoding.encode(policies)
            print(json)
            return 0
        } catch {
            FileHandle.standardError.write(Data("layout: \(error)\n".utf8))
            return 1
        }
    }
}

// MARK: - migrate

func cmdMigrate(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    let apply = opts.remaining.contains("--apply")

    let data: Data
    do {
        data = try Data(contentsOf: opts.configURL)
    } catch {
        FileHandle.standardError.write(Data("migrate: cannot read \(opts.configURL.path): \(error)\n".utf8))
        return 1
    }

    let result: MigrationResult
    do {
        result = try Migration.migrate(jsonData: data)
    } catch {
        FileHandle.standardError.write(Data("migrate: \(error)\n".utf8))
        return 1
    }

    if !apply {
        FileHandle.standardError.write(Data("# DRY RUN — pass --apply to write. slotsTouched=\(result.slotsTouched) alreadyV2=\(result.alreadyV2)\n".utf8))
        print(result.outputJSON, terminator: "")
        return 0
    }

    if result.alreadyV2 && result.slotsTouched == 0 {
        FileHandle.standardError.write(Data("migrate: already v2, no changes\n".utf8))
        return 0
    }

    do {
        try CacheEncoding.atomicWrite(result.outputJSON, to: opts.configURL)
    } catch {
        FileHandle.standardError.write(Data("migrate: write failed: \(error)\n".utf8))
        return 1
    }
    FileHandle.standardError.write(Data("migrate: wrote v2 (slotsTouched=\(result.slotsTouched))\n".utf8))
    return 0
}

// MARK: - resolve-icon

func cmdResolveIcon(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    var surface: IconTargetSurface = .textBased
    var slotArg: String? = nil

    for arg in opts.remaining {
        if arg == "--surface=font" || arg == "--surface=font-driven" {
            surface = .textBased
        } else if arg == "--surface=native" || arg == "--surface=appkit" {
            surface = .nativeAppKit
        } else if !arg.hasPrefix("--") {
            slotArg = arg
        }
    }

    guard let slotArg else {
        FileHandle.standardError.write(Data("resolve-icon: missing slot argument (index or name)\n".utf8))
        return 2
    }

    let store = WorkspaceStateStore(configURL: opts.configURL)
    let config: WorkspaceConfig
    do {
        config = try store.load()
    } catch {
        FileHandle.standardError.write(Data("resolve-icon: \(error)\n".utf8))
        return 1
    }

    let slot: WorkspaceSlot?
    if let idx = Int(slotArg) {
        slot = config.slots.first { $0.id == idx }
    } else {
        slot = config.slots.first { $0.name.lowercased() == slotArg.lowercased() }
    }
    guard let slot else {
        FileHandle.standardError.write(Data("resolve-icon: no slot matches '\(slotArg)'\n".utf8))
        return 1
    }

    let availableFonts = AvailableFonts.current()
    let resolved = IconResolver.resolve(
        spec: slot.iconSpec,
        availableFonts: availableFonts,
        targetSurface: surface,
        sfSymbolExists: SfSymbolAvailability.exists(_:)
    )

    let json: [String: Any] = [
        "slot":  slot.id,
        "name":  slot.name,
        "kind":  resolved.kind.rawValue,
        "value": resolved.value,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
    return 0
}

// MARK: - emit-skhd

func cmdEmitSkhd(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    let store = WorkspaceStateStore(configURL: opts.configURL)
    let config: WorkspaceConfig
    do {
        config = try store.load()
    } catch {
        FileHandle.standardError.write(Data("emit-skhd: \(error)\n".utf8))
        return 1
    }

    let snippet = SkhdFragment.render(slotCount: config.slots.count)
    let writeFlag = opts.remaining.contains("--write")

    if writeFlag {
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/skhd/spaces.skhdrc")
        do {
            try CacheEncoding.atomicWrite(snippet, to: target)
            FileHandle.standardError.write(Data("emit-skhd: wrote \(target.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("emit-skhd: write failed: \(error)\n".utf8))
            return 1
        }
        if opts.remaining.contains("--reload") {
            _ = runSkhdReload()
        }
    } else {
        print(snippet, terminator: "")
    }
    return 0
}

@discardableResult
func runSkhdReload() -> Int32 {
    let proc = Process()
    proc.launchPath = "/bin/sh"
    proc.arguments = ["-c", "command -v skhd >/dev/null 2>&1 && skhd --reload >/dev/null 2>&1"]
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    } catch {
        return -1
    }
}

// MARK: - Supporting helpers

enum AvailableFonts {
    static func current() -> Set<String> {
        Set(NSFontManager.shared.availableFontFamilies)
    }
}

enum SfSymbolAvailability {
    static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

enum SkhdFragment {
    static func render(slotCount: Int) -> String {
        let visible = min(max(slotCount, 0), 10)
        var lines: [String] = []
        lines.append("# Generated by ws-topology emit-skhd. Do not edit by hand.")
        lines.append("# Hotkey range is capped at 10 by digit-key hardware; slots beyond")
        lines.append("# the cap are reachable via `workspace focus <name>`.")
        lines.append("# Slot count at generation time: \(slotCount)")
        lines.append("")
        if visible == 0 { return lines.joined(separator: "\n") + "\n" }

        lines.append("# Hyper+digit: focus space N")
        for n in 1...visible {
            let key = (n == 10) ? "0" : String(n)
            lines.append("cmd + alt + ctrl + shift - \(key) : yabai -m space --focus \(n)")
        }
        lines.append("")
        lines.append("# Mod+digit: move focused window to space N and follow")
        for n in 1...visible {
            let key = (n == 10) ? "0" : String(n)
            lines.append("cmd + alt + ctrl - \(key) : yabai -m window --space \(n) && yabai -m space --focus \(n)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
