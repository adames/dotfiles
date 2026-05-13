import CoreGraphics
import DisplayTopology
import LayoutPolicy
import XCTest

final class NotchedBuiltInTests: XCTestCase {
    func test_notched_uses_auxiliary_top_areas() throws {
        let display = Fixtures.notchedM3Max()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try XCTUnwrap(set.policies.first { $0.displayID == display.id })

        XCTAssertEqual(policy.layoutClass, .notchedBuiltIn)
        XCTAssertTrue(policy.shouldUseAuxiliaryTopAreas)
        XCTAssertEqual(policy.topOrnamentRegion, display.auxiliaryTopLeftArea)
        XCTAssertEqual(policy.barHeightPoints, 26)
        // 720pt aux width / ~38pt pill = ~18 visible slots possible. Should clamp ≥ 1.
        XCTAssertGreaterThanOrEqual(policy.maxVisibleSlots, 1)
        XCTAssertLessThanOrEqual(policy.maxVisibleSlots, 19)
    }
}

final class CompactBuiltInTests: XCTestCase {
    func test_m1_13_uses_full_width_top_edge() throws {
        let display = Fixtures.compactM1()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try XCTUnwrap(set.policies.first { $0.displayID == display.id })

        XCTAssertEqual(policy.layoutClass, .compactBuiltIn)
        XCTAssertFalse(policy.shouldUseAuxiliaryTopAreas)
        XCTAssertEqual(policy.topOrnamentRegion.width, display.visibleFramePoints.width)
        XCTAssertEqual(policy.barHeightPoints, 26)
    }
}

final class ExternalRectangularTests: XCTestCase {
    func test_external_4k_takes_full_top_edge() throws {
        let display = Fixtures.external4K()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try XCTUnwrap(set.policies.first { $0.displayID == display.id })

        XCTAssertEqual(policy.layoutClass, .externalRectangular)
        XCTAssertFalse(policy.shouldUseAuxiliaryTopAreas)
        XCTAssertEqual(policy.topOrnamentRegion.width, display.visibleFramePoints.width)
        // 4K is midExternal density → 24pt bar.
        XCTAssertEqual(policy.barHeightPoints, 24)
    }
}

final class MirrorCollapseTests: XCTestCase {
    func test_mirror_secondary_is_collapsed() throws {
        let primary   = Fixtures.notchedM3Max(id: 1)
        let secondary = Fixtures.mirrorSecondary(id: 2, masterID: 1)
        let set = LayoutPolicyEngine.policies(for: [primary, secondary])

        let primaryPolicy = try XCTUnwrap(set.policies.first { $0.displayID == 1 })
        let secondaryPolicy = try XCTUnwrap(set.policies.first { $0.displayID == 2 })

        XCTAssertEqual(primaryPolicy.layoutClass, .notchedBuiltIn)
        XCTAssertFalse(primaryPolicy.isCollapsedMirrorSecondary)

        XCTAssertEqual(secondaryPolicy.layoutClass, .mirrorSecondary)
        XCTAssertTrue(secondaryPolicy.isCollapsedMirrorSecondary)
        XCTAssertEqual(secondaryPolicy.maxVisibleSlots, 0)
    }
}

final class DisconnectFallbackTests: XCTestCase {
    func test_fallback_id_resolves_to_primary_when_available() throws {
        let primary  = Fixtures.notchedM3Max(id: 7)
        let external = Fixtures.external4K(id: 8)
        let set = LayoutPolicyEngine.policies(for: [primary, external])
        for p in set.policies {
            XCTAssertEqual(p.fallbackScreenIDOnDisconnect, 7)
        }
    }

    func test_fallback_id_falls_through_to_lowest_builtin() throws {
        // No display is primary; engine should reach for the lowest-ID built-in.
        var nonPrimaryExternal = Fixtures.external4K(id: 99)
        nonPrimaryExternal = DisplaySnapshot(
            id: nonPrimaryExternal.id,
            isBuiltIn: false,
            isPrimaryMenuBarDisplay: false,
            isAppMainDisplay: false,
            framePoints: nonPrimaryExternal.framePoints,
            visibleFramePoints: nonPrimaryExternal.visibleFramePoints,
            safeAreaInsets: nonPrimaryExternal.safeAreaInsets,
            auxiliaryTopLeftArea: nonPrimaryExternal.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: nonPrimaryExternal.auxiliaryTopRightArea,
            backingScaleFactor: nonPrimaryExternal.backingScaleFactor,
            pixelSize: nonPrimaryExternal.pixelSize,
            mirrorMasterID: nonPrimaryExternal.mirrorMasterID,
            densityClass: nonPrimaryExternal.densityClass,
            stableUUID: nonPrimaryExternal.stableUUID
        )
        let builtIn = DisplaySnapshot(
            id: 42,
            isBuiltIn: true,
            isPrimaryMenuBarDisplay: false,   // intentionally no primary
            isAppMainDisplay: false,
            framePoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFramePoints: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaInsets: EdgeInsetsCodable.zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 2560, height: 1600),
            mirrorMasterID: nil,
            densityClass: .retinaLike,
            stableUUID: "F"
        )
        let set = LayoutPolicyEngine.policies(for: [nonPrimaryExternal, builtIn])
        for p in set.policies {
            XCTAssertEqual(p.fallbackScreenIDOnDisconnect, 42)
        }
    }
}
