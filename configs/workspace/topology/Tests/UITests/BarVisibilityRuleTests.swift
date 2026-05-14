import CoreGraphics
import DisplayTopology
import LayoutPolicy
import Testing

/// Validates that adapter-level visibility rules collapse mirrored displays
/// into a single logical bar. Pure-Swift assertions, no UI host needed.
@Suite("Bar visibility rules — mirror collapse")
struct BarVisibilityRuleTests {

    @Test func mirror_secondary_marked_invisible_for_bar_adapters() {
        let master = Fixtures.notchedM3Max(id: 1)
        let mirror = Fixtures.mirrorSecondary(id: 2, masterID: 1)
        let set = LayoutPolicyEngine.policies(for: [master, mirror])

        let visiblePolicies = set.policies.filter { !$0.isCollapsedMirrorSecondary }
        #expect(visiblePolicies.count == 1)
        #expect(visiblePolicies.first?.displayID == 1)
    }
}

// Duplicate of LayoutPolicyTests/DisplaySnapshotFixtures.swift kept here so the
// UITests target stays self-contained. Keep both in sync — the assertions in
// LayoutPolicyTests are the source of truth.
private enum Fixtures {
    static func notchedM3Max(id: CGDirectDisplayID) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            isBuiltIn: true,
            isPrimaryMenuBarDisplay: true,
            isAppMainDisplay: true,
            framePoints: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFramePoints: CGRect(x: 0, y: 0, width: 1728, height: 1085),
            safeAreaInsets: EdgeInsetsCodable(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 720, height: 32),
            auxiliaryTopRightArea: CGRect(x: 1008, y: 1085, width: 720, height: 32),
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 3456, height: 2234),
            mirrorMasterID: nil,
            densityClass: .retinaLike,
            stableUUID: "F"
        )
    }

    static func mirrorSecondary(id: CGDirectDisplayID, masterID: CGDirectDisplayID) -> DisplaySnapshot {
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
            stableUUID: "M"
        )
    }
}
