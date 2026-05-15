import Foundation

/// Single seam between the picker and yabai. Sync read at overlay open;
/// async fire-and-forget focus on commit. Mirrors ws-prompt's
/// `WorkspaceService` protocol — one boundary, one place to mock.
protocol WindowSource {
    func loadWindows() -> [WindowItem]
    func focus(windowID: Int)
}

/// Production implementation: shells out to yabai.
final class ProductionWindowSource: WindowSource {
    private let yabaiBinary: String

    init(yabaiBinary: String = ProductionWindowSource.resolveYabai()) {
        self.yabaiBinary = yabaiBinary
    }

    func loadWindows() -> [WindowItem] {
        guard let data = runCapture(args: ["-m", "query", "--windows"]) else { return [] }
        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([YabaiWindow].self, from: data) else { return [] }
        // Drop windows the user can't visually see: minimized, on a
        // hidden space, etc. The picker is "switch to a visible window"
        // — exposing zombies just dilutes the fuzzy match.
        return entries
            .filter { $0.isVisible && !$0.isMinimized }
            .map(\.toItem)
    }

    func focus(windowID: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabaiBinary)
        task.arguments = ["-m", "window", "--focus", String(windowID)]
        do { try task.run() } catch {
            FileHandle.standardError.write(Data(
                "ws-picker: yabai window --focus \(windowID) failed: \(error)\n".utf8))
        }
    }

    // MARK: - Internals

    private func runCapture(args: [String]) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabaiBinary)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        guard task.terminationStatus == 0 else { return nil }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    /// yabai install path varies by host. YABAI_BIN env var wins (used
    /// by the bash test harness); otherwise probe the two Homebrew
    /// locations; last resort, rely on PATH.
    static func resolveYabai() -> String {
        if let override = ProcessInfo.processInfo.environment["YABAI_BIN"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "yabai"
    }
}
