import CoreGraphics
import Foundation

public enum DensityClass: String, Codable, Sendable, CaseIterable {
    case coarseExternal
    case midExternal
    case retinaLike
}

public struct EdgeInsetsCodable: Codable, Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = EdgeInsetsCodable(top: 0, left: 0, bottom: 0, right: 0)
}

public struct DisplaySnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let isBuiltIn: Bool
    public let isPrimaryMenuBarDisplay: Bool
    public let isAppMainDisplay: Bool
    public let framePoints: CGRect
    public let visibleFramePoints: CGRect
    public let safeAreaInsets: EdgeInsetsCodable
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?
    public let backingScaleFactor: CGFloat
    public let pixelSize: CGSize
    public let mirrorMasterID: CGDirectDisplayID?
    public let densityClass: DensityClass
    public let stableUUID: String?

    public init(
        id: CGDirectDisplayID,
        isBuiltIn: Bool,
        isPrimaryMenuBarDisplay: Bool,
        isAppMainDisplay: Bool,
        framePoints: CGRect,
        visibleFramePoints: CGRect,
        safeAreaInsets: EdgeInsetsCodable,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        backingScaleFactor: CGFloat,
        pixelSize: CGSize,
        mirrorMasterID: CGDirectDisplayID?,
        densityClass: DensityClass,
        stableUUID: String?
    ) {
        self.id = id
        self.isBuiltIn = isBuiltIn
        self.isPrimaryMenuBarDisplay = isPrimaryMenuBarDisplay
        self.isAppMainDisplay = isAppMainDisplay
        self.framePoints = framePoints
        self.visibleFramePoints = visibleFramePoints
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.backingScaleFactor = backingScaleFactor
        self.pixelSize = pixelSize
        self.mirrorMasterID = mirrorMasterID
        self.densityClass = densityClass
        self.stableUUID = stableUUID
    }
}

public struct TopologySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var capturedAt: Date
    public var primaryDisplayID: CGDirectDisplayID
    public var appMainDisplayID: CGDirectDisplayID?
    public var displays: [DisplaySnapshot]

    public init(
        schemaVersion: Int = 1,
        capturedAt: Date = Date(),
        primaryDisplayID: CGDirectDisplayID,
        appMainDisplayID: CGDirectDisplayID?,
        displays: [DisplaySnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.primaryDisplayID = primaryDisplayID
        self.appMainDisplayID = appMainDisplayID
        self.displays = displays
    }
}
