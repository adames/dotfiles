import Foundation

/// Abstraction over window managers (yabai, aerospace, rectangle, etc.)
/// Provides workspace/space operations without vendor-specific assumptions.
public protocol WindowManager {
    /// The type of window manager (yabai, aerospace, rectangle, none)
    static var kind: WindowManagerKind { get }
    
    /// Path to the window manager binary
    var binaryPath: String { get }
    
    // MARK: - Space Operations
    
    /// Focus the space with the given index (1-based)
    func focusSpace(index: Int) throws
    
    /// Send the focused window to the space with the given index, optionally following it
    func sendWindowToSpace(index: Int, follow: Bool) throws
    
    /// Create a new space, returning its index
    func createSpace() throws -> Int
    
    /// Destroy the space with the given index
    func destroySpace(index: Int) throws
    
    /// Get the currently focused space index (1-based)
    func focusedSpaceIndex() throws -> Int?
    
    /// Get the total number of spaces
    func spaceCount() throws -> Int
    
    // MARK: - Window Operations
    
    /// Get the ID of the currently focused window
    func focusedWindowID() throws -> Int?
    
    /// Focus the window with the given ID
    func focusWindow(id: Int) throws
}

public enum WindowManagerKind: String, Sendable {
    case yabai
    case aerospace
    case rectangle
    case none
}

/// Errors that can occur during window manager operations
public enum WindowManagerError: Error {
    case binaryNotFound(String)
    case commandFailed(String)
    case parseError(String)
    case notImplemented(String)
    case unavailable
}
