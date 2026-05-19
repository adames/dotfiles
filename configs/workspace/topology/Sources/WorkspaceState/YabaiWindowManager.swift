import Foundation

/// WindowManager implementation for yabai (https://github.com/koekeishiya/yabai)
public final class YabaiWindowManager: WindowManager {
    public static let kind: WindowManagerKind = .yabai
    
    public let binaryPath: String
    
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? "/opt/homebrew/bin/yabai"
    }
    
    // MARK: - Space Operations
    
    public func focusSpace(index: Int) throws {
        try runYabai(args: ["-m", "space", "--focus", "\(index)"])
    }
    
    public func sendWindowToSpace(index: Int, follow: Bool) throws {
        let windowID = try focusedWindowID()
        try runYabai(args: ["-m", "window", "--space", "\(index)"])
        if follow, let wid = windowID {
            try focusWindow(id: wid)
        }
    }
    
    public func createSpace() throws -> Int {
        try runYabai(args: ["-m", "space", "--create"])
        // Return the new space count (the new space is the last one)
        return try spaceCount()
    }
    
    public func destroySpace(index: Int) throws {
        try runYabai(args: ["-m", "space", "\(index)", "--destroy"])
    }
    
    public func focusedSpaceIndex() throws -> Int? {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--spaces", "--space"]) else {
            return nil
        }
        guard let data = output.data(using: .utf8) else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["index"] as? Int
    }
    
    public func spaceCount() throws -> Int {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--spaces"]) else {
            return 0
        }
        guard let data = output.data(using: .utf8) else { return 0 }
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json?.count ?? 0
    }
    
    // MARK: - Window Operations
    
    public func focusedWindowID() throws -> Int? {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--windows", "--window"]) else {
            return nil
        }
        guard let data = output.data(using: .utf8) else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["id"] as? Int
    }
    
    public func focusWindow(id: Int) throws {
        try runYabai(args: ["-m", "window", "--focus", "\(id)"])
    }
    
    // MARK: - Private Helpers
    
    private func runYabai(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WindowManagerError.commandFailed("yabai \(args.joined(separator: " ")): \(error)")
        }
    }
    
    private func runYabaiWithOutput(args: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
