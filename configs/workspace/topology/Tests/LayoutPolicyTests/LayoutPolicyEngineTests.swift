import CoreGraphics
import DisplayTopology
import LayoutPolicy
import Testing

@Suite("Notched built-in display policy")
struct NotchedBuiltInTests {
    @Test func notched_uses_auxiliary_top_areas() throws {
        let display = Fixtures.notchedM3Max()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try #require(set.policies.first { $0.displayID == display.id })

        #expect(policy.layoutClass == .notchedBuiltIn)
        #expect(policy.shouldUseAuxiliaryTopAreas)
        #expect(policy.topOrnamentRegion == display.auxiliaryTopLeftArea)
        #expect(policy.barHeightPoints == 26)
        // 720pt aux width / ~38pt pill = ~18 visible slots possible. Clamp ≥ 1.
        #expect(policy.maxVisibleSlots >= 1)
        #expect(policy.maxVisibleSlots <= 19)
    }
}

@Suite("Compact built-in display policy")
struct CompactBuiltInTests {
    @Test func m1_13_uses_full_width_top_edge() throws {
        let display = Fixtures.compactM1()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try #require(set.policies.first { $0.displayID == display.id })

        #expect(policy.layoutClass == .compactBuiltIn)
        #expect(!policy.shouldUseAuxiliaryTopAreas)
        #expect(policy.topOrnamentRegion.width == display.visibleFramePoints.width)
        #expect(policy.barHeightPoints == 26)
    }
}

@Suite("External rectangular display policy")
struct ExternalRectangularTests {
    @Test func external_4k_takes_full_top_edge() throws {
        let display = Fixtures.external4K()
        let set = LayoutPolicyEngine.policies(for: [display])
        let policy = try #require(set.policies.first { $0.displayID == display.id })

        #expect(policy.layoutClass == .externalRectangular)
        #expect(!policy.shouldUseAuxiliaryTopAreas)
        #expect(policy.topOrnamentRegion.width == display.visibleFramePoints.width)
        // 4K is midExternal density → 24pt bar.
        #expect(policy.barHeightPoints == 24)
    }
}

@Suite("Mirror secondary collapse")
struct MirrorCollapseTests {
    @Test func mirror_secondary_is_collapsed() throws {
        let primary   = Fixtures.notchedM3Max(id: 1)
        let secondary = Fixtures.mirrorSecondary(id: 2, masterID: 1)
        let set = LayoutPolicyEngine.policies(for: [primary, secondary])

        let primaryPolicy   = try #require(set.policies.first { $0.displayID == 1 })
        let secondaryPolicy = try #require(set.policies.first { $0.displayID == 2 })

        #expect(primaryPolicy.layoutClass == .notchedBuiltIn)
        #expect(!primaryPolicy.isCollapsedMirrorSecondary)

        #expect(secondaryPolicy.layoutClass == .mirrorSecondary)
        #expect(secondaryPolicy.isCollapsedMirrorSecondary)
        #expect(secondaryPolicy.maxVisibleSlots == 0)
    }
}

@Suite("Disconnect fallback resolution")
struct DisconnectFallbackTests {
    @Test func fallback_id_resolves_to_primary_when_available() {
        let primary  = Fixtures.notchedM3Max(id: 7)
        let external = Fixtures.external4K(id: 8)
        let set = LayoutPolicyEngine.policies(for: [primary, external])
        for p in set.policies {
            #expect(p.fallbackScreenIDOnDisconnect == 7)
        }
    }

    @Test func fallback_id_falls_through_to_lowest_builtin() {
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
            #expect(p.fallbackScreenIDOnDisconnect == 42)
        }
    }
}
