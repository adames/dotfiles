import Foundation
import OSLog

public enum TopologyLog {
    public static let subsystem = "com.adames.workspace.topology"

    public static let topology      = Logger(subsystem: subsystem, category: "topology")
    public static let policy        = Logger(subsystem: subsystem, category: "policy")
    public static let icon          = Logger(subsystem: subsystem, category: "icon")
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
}
