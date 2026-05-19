import Foundation

/// Central configuration for workspace system.
/// These values are read from environment variables at build time,
/// allowing customization without code changes.
public enum WorkspaceConfig {
    /// The bundle prefix for all workspace binaries.
    /// Override with WORKSPACE_BUNDLE_PREFIX env var at build time.
    /// Default: "com.user.workspace"
    public static let bundlePrefix: String = {
        ProcessInfo.processInfo.environment["WORKSPACE_BUNDLE_PREFIX"]
            ?? "com.user.workspace"
    }()
    
    /// The OSLog subsystem identifier.
    public static let logSubsystem: String = "\(bundlePrefix).topology"
    
    /// The LaunchAgent label prefix.
    public static let launchAgentPrefix: String = bundlePrefix
    
    /// Base paths - respect XDG conventions when possible
    public static let homeDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
    }()
    
    public static let configDirectory: URL = {
        if let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdgConfig).appendingPathComponent("workspace")
        }
        return homeDirectory.appendingPathComponent(".config/workspace")
    }()
    
    public static let cacheDirectory: URL = {
        if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            return URL(fileURLWithPath: xdgCache).appendingPathComponent("workspace")
        }
        return homeDirectory.appendingPathComponent(".cache/workspace")
    }()
    
    public static let binDirectory: URL = {
        homeDirectory.appendingPathComponent(".local/bin")
    }()
    
    /// LaunchAgent directory
    public static let launchAgentsDirectory: URL = {
        homeDirectory.appendingPathComponent("Library/LaunchAgents")
    }()
    
    /// File names
    public static let spacesFileName: String = "spaces.json"
    public static let topologyFileName: String = "topology.json"
    public static let layoutEnvFileName: String = "layout.env"
    public static let currentEnvFileName: String = "current.env"
}

/// Window manager integration configuration
public enum WindowManagerConfig {
    /// The window manager to use.
    /// Override with WORKSPACE_WINDOW_MANAGER env var.
    /// Supported: "yabai", "aerospace", "rectangle", "none"
    public static let `default`: String = {
        ProcessInfo.processInfo.environment["WORKSPACE_WINDOW_MANAGER"]
            ?? "yabai"
    }()
    
    /// Path to window manager binary
    public static let binaryPath: String = {
        switch `default` {
        case "yabai":
            return "/opt/homebrew/bin/yabai"
        case "aerospace":
            return "/opt/homebrew/bin/aerospace"
        case "rectangle":
            return "/Applications/Rectangle.app/Contents/MacOS/Rectangle"
        default:
            return ""
        }
    }()
}
