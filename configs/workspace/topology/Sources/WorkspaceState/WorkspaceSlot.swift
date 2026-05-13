import Foundation

public struct WorkspaceSlot: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var color: String
    public var iconSpec: IconSpec
    public var stableLogicalLabel: String

    public init(
        id: Int,
        name: String,
        color: String,
        iconSpec: IconSpec,
        stableLogicalLabel: String
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.iconSpec = iconSpec
        self.stableLogicalLabel = stableLogicalLabel
    }
}

public struct WorkspaceConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var palette: String?
    public var theme: String?
    public var slots: [WorkspaceSlot]

    public init(version: Int, palette: String?, theme: String?, slots: [WorkspaceSlot]) {
        self.version = version
        self.palette = palette
        self.theme = theme
        self.slots = slots
    }
}
