import AppKit
import CoreGraphics
import Foundation

/// Enumerates the live `NSScreen` set and combines it with Quartz Display Services
/// facts into a `TopologySnapshot`. The service does no caching; it is meant to be
/// called whenever a coalesced reconfiguration event fires.
///
/// All inputs are public AppKit/CoreGraphics surfaces: no private APIs.
public enum DisplayTopologyService {

    /// Capture the current topology snapshot. Must be called on the main thread —
    /// `NSScreen` access is documented as main-thread-only.
    @MainActor
    public static func snapshot() -> TopologySnapshot {
        let primaryID = CGMainDisplayID()
        let appMainID = NSScreen.main.flatMap(displayID(for:))

        let snapshots = NSScreen.screens.compactMap(displaySnapshot(from:))

        return TopologySnapshot(
            schemaVersion: 1,
            capturedAt: Date(),
            primaryDisplayID: primaryID,
            appMainDisplayID: appMainID,
            displays: snapshots
        )
    }

    @MainActor
    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let raw = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(raw.uint32Value)
    }

    @MainActor
    public static func displaySnapshot(from screen: NSScreen) -> DisplaySnapshot? {
        guard let id = displayID(for: screen) else { return nil }

        let mirrorMaster = CGDisplayMirrorsDisplay(id)
        let resolvedMirror: CGDirectDisplayID? =
            (mirrorMaster == kCGNullDirectDisplay) ? nil : mirrorMaster

        let pixelWidth  = CGDisplayPixelsWide(id)
        let pixelHeight = CGDisplayPixelsHigh(id)
        let pixelSize   = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

        let backing = screen.backingScaleFactor

        let safeArea = EdgeInsetsCodable(
            top:    screen.safeAreaInsets.top,
            left:   screen.safeAreaInsets.left,
            bottom: screen.safeAreaInsets.bottom,
            right:  screen.safeAreaInsets.right
        )

        let auxLeft  = nonZeroRect(screen.auxiliaryTopLeftArea)
        let auxRight = nonZeroRect(screen.auxiliaryTopRightArea)

        let isBuiltIn  = CGDisplayIsBuiltin(id) != 0
        let isPrimary  = CGDisplayIsMain(id) != 0
        let isAppMain  = (NSScreen.main.flatMap(displayID(for:)) == id)

        let density = DensityClass.classify(
            backingScaleFactor: backing,
            framePoints: screen.frame,
            pixelSize: pixelSize,
            isBuiltIn: isBuiltIn
        )

        return DisplaySnapshot(
            id: id,
            isBuiltIn: isBuiltIn,
            isPrimaryMenuBarDisplay: isPrimary,
            isAppMainDisplay: isAppMain,
            framePoints: screen.frame,
            visibleFramePoints: screen.visibleFrame,
            safeAreaInsets: safeArea,
            auxiliaryTopLeftArea: auxLeft,
            auxiliaryTopRightArea: auxRight,
            backingScaleFactor: backing,
            pixelSize: pixelSize,
            mirrorMasterID: resolvedMirror,
            densityClass: density,
            stableUUID: stableUUID(for: id)
        )
    }

    static func nonZeroRect(_ rect: CGRect?) -> CGRect? {
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    static func stableUUID(for id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = cf.takeRetainedValue()
        let str  = CFUUIDCreateString(nil, uuid)
        return str as String?
    }
}

// MARK: - Density classification (re-exported here so call sites don't import LayoutPolicy)

extension DensityClass {
    /// Re-implements the same logic as `LayoutPolicy.DensityClassifier` so that
    /// the topology service can self-classify without depending on the LayoutPolicy
    /// module. Keep these two in sync — the test suite exercises both paths.
    static func classify(
        backingScaleFactor: CGFloat,
        framePoints: CGRect,
        pixelSize: CGSize,
        isBuiltIn: Bool = false
    ) -> DensityClass {
        if backingScaleFactor < 2.0 {
            return .coarseExternal
        }
        if isBuiltIn {
            return .retinaLike
        }
        guard framePoints.width > 0, pixelSize.width > 0 else {
            return .midExternal
        }
        let pixelsPerPoint = pixelSize.width / framePoints.width
        let proxy = pixelsPerPoint * 100.0 * backingScaleFactor
        return proxy >= 200.0 ? .retinaLike : .midExternal
    }
}
