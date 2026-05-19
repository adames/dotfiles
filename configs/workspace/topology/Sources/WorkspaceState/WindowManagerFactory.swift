import Foundation

/// Factory for creating the appropriate WindowManager based on configuration.
/// Respects the WORKSPACE_WINDOW_MANAGER environment variable and config.
public enum WindowManagerFactory {
    /// Create a WindowManager based on the current configuration.
    /// Defaults to yabai if no configuration is found.
    public static func create() -> WindowManager {
        let kind = configuredKind()
        
        switch kind {
        case .yabai:
            return YabaiWindowManager(binaryPath: WindowManagerConfig.binaryPath)
        case .aerospace:
            // TODO: Implement AerospaceWindowManager
            // For now, fall back to yabai with a warning
            print("Warning: aerospace support not yet implemented, falling back to yabai")
            return YabaiWindowManager()
        case .rectangle:
            // Rectangle doesn't support spaces, return a no-op manager
            print("Warning: rectangle does not support workspace spaces")
            return NoOpWindowManager()
        case .none:
            return NoOpWindowManager()
        }
    }
    
    /// Get the configured window manager kind from environment or config.
    public static func configuredKind() -> WindowManagerKind {
        // Check environment variable first
        if let env = ProcessInfo.processInfo.environment["WORKSPACE_WINDOW_MANAGER"],
           let kind = WindowManagerKind(rawValue: env) {
            return kind
        }
        
        // Check if yabai is installed (default)
        let yabaiPaths = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai"
        ]
        for path in yabaiPaths {
            if FileManager.default.fileExists(atPath: path) {
                return .yabai
            }
        }
        
        // Check for aerospace
        let aerospacePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace"
        ]
        for path in aerospacePaths {
            if FileManager.default.fileExists(atPath: path) {
                return .aerospace
            }
        }
        
        return .none
    }
    
    /// Check if a window manager is available.
    public static func isAvailable(_ kind: WindowManagerKind) -> Bool {
        switch kind {
        case .yabai:
            let paths = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        case .aerospace:
            let paths = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        case .rectangle:
            return FileManager.default.fileExists(atPath: "/Applications/Rectangle.app")
        case .none:
            return true
        }
    }
}

/// No-op window manager for when no window manager is available.
public final class NoOpWindowManager: WindowManager {
    public static let kind: WindowManagerKind = .none
    public let binaryPath: String = ""
    
    public init() {}
    
    public func focusSpace(index: Int) throws {
        throw WindowManagerError.unavailable
    }
    
    public func sendWindowToSpace(index: Int, follow: Bool) throws {
        throw WindowManagerError.unavailable
    }
    
    public func createSpace() throws -> Int {
        throw WindowManagerError.unavailable
    }
    
    public func destroySpace(index: Int) throws {
        throw WindowManagerError.unavailable
    }
    
    public func focusedSpaceIndex() throws -> Int? {
        return nil
    }
    
    public func spaceCount() throws -> Int {
        return 0
    }
    
    public func focusedWindowID() throws -> Int? {
        return nil
    }
    
    public func focusWindow(id: Int) throws {
        throw WindowManagerError.unavailable
    }
}
