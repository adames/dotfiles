import CoreGraphics
import DisplayTopology
import Foundation

public enum LayoutClass: String, Codable, Sendable {
    case notchedBuiltIn
    case compactBuiltIn
    case externalRectangular
    case mirrorSecondary
}

public struct LayoutPolicy: Codable, Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let layoutClass: LayoutClass
    public let topOrnamentRegion: CGRect
    /// On notched displays, the right-side auxiliary region (the strip
    /// to the right of the camera housing). Nil for non-notched classes.
    /// Used by the shell-side `recenter.sh` to implement the "centered,
    /// split symmetrically around the notch" anchor strategy.
    public let auxiliaryTopRightRegion: CGRect?
    /// The camera-housing region itself (between left and right aux
    /// areas). Nil for non-notched classes.
    public let notchRegion: CGRect?
    public let barHeightPoints: CGFloat
    public let ornamentDensityMultiplier: CGFloat
    public let maxVisibleSlots: Int
    public let shouldUseAuxiliaryTopAreas: Bool
    public let fallbackScreenIDOnDisconnect: CGDirectDisplayID?
    public let isCollapsedMirrorSecondary: Bool
    public let pillAverageWidthPoints: CGFloat

    public init(
        displayID: CGDirectDisplayID,
        layoutClass: LayoutClass,
        topOrnamentRegion: CGRect,
        auxiliaryTopRightRegion: CGRect? = nil,
        notchRegion: CGRect? = nil,
        barHeightPoints: CGFloat,
        ornamentDensityMultiplier: CGFloat,
        maxVisibleSlots: Int,
        shouldUseAuxiliaryTopAreas: Bool,
        fallbackScreenIDOnDisconnect: CGDirectDisplayID?,
        isCollapsedMirrorSecondary: Bool,
        pillAverageWidthPoints: CGFloat
    ) {
        self.displayID = displayID
        self.layoutClass = layoutClass
        self.topOrnamentRegion = topOrnamentRegion
        self.auxiliaryTopRightRegion = auxiliaryTopRightRegion
        self.notchRegion = notchRegion
        self.barHeightPoints = barHeightPoints
        self.ornamentDensityMultiplier = ornamentDensityMultiplier
        self.maxVisibleSlots = maxVisibleSlots
        self.shouldUseAuxiliaryTopAreas = shouldUseAuxiliaryTopAreas
        self.fallbackScreenIDOnDisconnect = fallbackScreenIDOnDisconnect
        self.isCollapsedMirrorSecondary = isCollapsedMirrorSecondary
        self.pillAverageWidthPoints = pillAverageWidthPoints
    }
}

public struct LayoutPolicySet: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var capturedAt: Date
    public var policies: [LayoutPolicy]
    public var reduceMotion: Bool
    public var increaseContrast: Bool

    public init(
        schemaVersion: Int = 1,
        capturedAt: Date = Date(),
        policies: [LayoutPolicy],
        reduceMotion: Bool,
        increaseContrast: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.policies = policies
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
    }
}
