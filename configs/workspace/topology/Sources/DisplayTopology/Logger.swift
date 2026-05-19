import Foundation
import OSLog
import WorkspaceState

public enum TopologyLog {
    public static let subsystem = WorkspaceConfig.logSubsystem

    public static let topology      = Logger(subsystem: subsystem, category: "topology")
    public static let policy        = Logger(subsystem: subsystem, category: "policy")
    public static let icon          = Logger(subsystem: subsystem, category: "icon")
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
}
