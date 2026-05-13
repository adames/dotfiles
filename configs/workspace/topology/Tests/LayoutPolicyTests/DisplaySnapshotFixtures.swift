import CoreGraphics
import DisplayTopology
import Foundation

enum Fixtures {
    /// Notched M3 Max 14" (`Mac15,10`) reference: 3456x2234 pixels at 2x backing,
    /// 1728x1117 points, ~32pt safe-area top inset, auxiliary left/right areas
    /// flanking the camera housing.
    static func notchedM3Max(id: CGDirectDisplayID = 1) -> DisplaySnapshot {
        let framePoints = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1085)
        let aux = CGRect(x: 0, y: 1085, width: 720, height: 32)
        let auxR = CGRect(x: 1008, y: 1085, width: 720, height: 32)
        return DisplaySnapshot(
            id: id,
            isBuiltIn: true,
            isPrimaryMenuBarDisplay: true,
            isAppMainDisplay: true,
            framePoints: framePoints,
            visibleFramePoints: visible,
            safeAreaInsets: EdgeInsetsCodable(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: aux,
            auxiliaryTopRightArea: auxR,
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 3456, height: 2234),
            mirrorMasterID: nil,
            densityClass: .retinaLike,
            stableUUID: "FIXTURE-M3MAX"
        )
    }

    /// Compact built-in: M1 13" 2020 (`MacBookPro17,1`), 2560x1600 pixels at 2x,
    /// 1440x900 points, no notch.
    static func compactM1(id: CGDirectDisplayID = 2) -> DisplaySnapshot {
        let framePoints = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        return DisplaySnapshot(
            id: id,
            isBuiltIn: true,
            isPrimaryMenuBarDisplay: true,
            isAppMainDisplay: true,
            framePoints: framePoints,
            visibleFramePoints: visible,
            safeAreaInsets: EdgeInsetsCodable.zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 2560, height: 1600),
            mirrorMasterID: nil,
            densityClass: .retinaLike,
            stableUUID: "FIXTURE-M1"
        )
    }

    /// 4K external (~163 ppi class): 3840x2160 at 2x backing → 1920x1080 points.
    static func external4K(id: CGDirectDisplayID = 3) -> DisplaySnapshot {
        let frame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        return DisplaySnapshot(
            id: id,
            isBuiltIn: false,
            isPrimaryMenuBarDisplay: false,
            isAppMainDisplay: false,
            framePoints: frame,
            visibleFramePoints: visible,
            safeAreaInsets: EdgeInsetsCodable.zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 3840, height: 2160),
            mirrorMasterID: nil,
            densityClass: .midExternal,
            stableUUID: "FIXTURE-4K"
        )
    }

    /// External standing in as the mirror SECONDARY of `master`.
    static func mirrorSecondary(id: CGDirectDisplayID = 4, masterID: CGDirectDisplayID) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            isBuiltIn: false,
            isPrimaryMenuBarDisplay: false,
            isAppMainDisplay: false,
            framePoints: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFramePoints: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaInsets: EdgeInsetsCodable.zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 3840, height: 2160),
            mirrorMasterID: masterID,
            densityClass: .midExternal,
            stableUUID: "FIXTURE-MIRROR"
        )
    }
}
