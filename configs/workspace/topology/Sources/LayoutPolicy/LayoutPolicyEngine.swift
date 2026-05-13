import CoreGraphics
import DisplayTopology
import Foundation

public enum LayoutPolicyEngine {
    /// Average pill width at density 1.0. Density-class adjusts via the
    /// `ornamentDensityMultiplier`. Derived from the existing shell `PILL_AVG_WIDTH=38`
    /// (which mixed icon + label widths in points-equivalent), retained as the
    /// retina baseline.
    public static let basePillWidthPoints: CGFloat = 38.0

    /// Compute the per-display layout policy set. Pure function: same input → same output.
    /// Reduce-motion / increase-contrast flags are carried alongside but do not enter
    /// the per-display layout math.
    public static func policies(
        for snapshots: [DisplaySnapshot],
        reduceMotion: Bool = false,
        increaseContrast: Bool = false
    ) -> LayoutPolicySet {
        let primaryID = snapshots.first(where: \.isPrimaryMenuBarDisplay)?.id
        let fallbackID = resolveFallbackID(snapshots: snapshots, primaryID: primaryID)

        let mirrorMasters = Set(snapshots.compactMap(\.mirrorMasterID))

        let policies: [LayoutPolicy] = snapshots.map { snapshot in
            policy(
                for: snapshot,
                fallbackID: fallbackID,
                mirrorMasters: mirrorMasters
            )
        }

        return LayoutPolicySet(
            policies: policies,
            reduceMotion: reduceMotion,
            increaseContrast: increaseContrast
        )
    }

    static func policy(
        for snapshot: DisplaySnapshot,
        fallbackID: CGDirectDisplayID?,
        mirrorMasters: Set<CGDirectDisplayID>
    ) -> LayoutPolicy {
        // Mirrored secondaries: the snapshot's mirrorMasterID points at another display.
        // We collapse: adapters skip these and let the master handle the layout.
        if let master = snapshot.mirrorMasterID, master != 0 {
            return LayoutPolicy(
                displayID: snapshot.id,
                layoutClass: .mirrorSecondary,
                topOrnamentRegion: .zero,
                barHeightPoints: 0,
                ornamentDensityMultiplier: 1.0,
                maxVisibleSlots: 0,
                shouldUseAuxiliaryTopAreas: false,
                fallbackScreenIDOnDisconnect: fallbackID,
                isCollapsedMirrorSecondary: true,
                pillAverageWidthPoints: basePillWidthPoints
            )
        }

        let multiplier = densityMultiplier(for: snapshot.densityClass)
        let pillWidth  = basePillWidthPoints * multiplier
        let barHeight  = barHeight(for: snapshot.densityClass)

        // Notched built-in: safe-area top > 0 AND we have an auxiliary top region to
        // paint into. The policy carries BOTH aux regions plus the derived notch
        // region so the shell-side recenter can implement "centered, split
        // symmetrically around the notch". `maxVisibleSlots` reflects total
        // pills across both aux regions (each half holds ~half).
        if snapshot.safeAreaInsets.top > 0,
           let auxLeft = snapshot.auxiliaryTopLeftArea,
           auxLeft.width > 0 {
            let auxRight = snapshot.auxiliaryTopRightArea
            // Notch region = gap between aux-left's right edge and aux-right's left edge.
            let notch: CGRect? = auxRight.map { r in
                let notchX = auxLeft.maxX
                let notchW = r.minX - notchX
                return CGRect(x: notchX, y: auxLeft.minY, width: notchW, height: auxLeft.height)
            }
            // Combined usable width = both auxes together (excluding the notch gap).
            let combinedUsable = auxLeft.width + (auxRight?.width ?? 0)
            let maxVisible = max(1, Int(floor(combinedUsable / pillWidth)))
            return LayoutPolicy(
                displayID: snapshot.id,
                layoutClass: .notchedBuiltIn,
                topOrnamentRegion: auxLeft,
                auxiliaryTopRightRegion: auxRight,
                notchRegion: notch,
                barHeightPoints: barHeight,
                ornamentDensityMultiplier: multiplier,
                maxVisibleSlots: maxVisible,
                shouldUseAuxiliaryTopAreas: true,
                fallbackScreenIDOnDisconnect: fallbackID,
                isCollapsedMirrorSecondary: false,
                pillAverageWidthPoints: pillWidth
            )
        }

        // Compact built-in (non-notched laptop like the M1 13"): full width inside
        // visible frame. No aux area.
        if snapshot.isBuiltIn {
            let region = topEdgeRegion(of: snapshot.visibleFramePoints, height: barHeight)
            let maxVisible = max(1, Int(floor(region.width / pillWidth)))
            return LayoutPolicy(
                displayID: snapshot.id,
                layoutClass: .compactBuiltIn,
                topOrnamentRegion: region,
                barHeightPoints: barHeight,
                ornamentDensityMultiplier: multiplier,
                maxVisibleSlots: maxVisible,
                shouldUseAuxiliaryTopAreas: false,
                fallbackScreenIDOnDisconnect: fallbackID,
                isCollapsedMirrorSecondary: false,
                pillAverageWidthPoints: pillWidth
            )
        }

        // External rectangular.
        let region = topEdgeRegion(of: snapshot.visibleFramePoints, height: barHeight)
        let maxVisible = max(1, Int(floor(region.width / pillWidth)))
        return LayoutPolicy(
            displayID: snapshot.id,
            layoutClass: .externalRectangular,
            topOrnamentRegion: region,
            barHeightPoints: barHeight,
            ornamentDensityMultiplier: multiplier,
            maxVisibleSlots: maxVisible,
            shouldUseAuxiliaryTopAreas: false,
            fallbackScreenIDOnDisconnect: fallbackID,
            isCollapsedMirrorSecondary: false,
            pillAverageWidthPoints: pillWidth
        )
    }

    /// Density-class multiplier on chrome spacing. Retina-like and 5K-class externals
    /// get full spacing; coarser displays get tighter spacing so menu-bar chrome
    /// doesn't visually balloon.
    static func densityMultiplier(for cls: DensityClass) -> CGFloat {
        switch cls {
        case .coarseExternal: return 0.90
        case .midExternal:    return 0.95
        case .retinaLike:     return 1.00
        }
    }

    static func barHeight(for cls: DensityClass) -> CGFloat {
        switch cls {
        case .coarseExternal, .midExternal: return 24
        case .retinaLike:                   return 26
        }
    }

    static func topEdgeRegion(of visibleFrame: CGRect, height: CGFloat) -> CGRect {
        // `visibleFrame` in AppKit coords has origin at the bottom-left of the screen
        // and excludes the menu bar; the "top edge" in points is therefore the highest
        // y inside visibleFrame. We return a strip `height` points tall along it.
        let y = visibleFrame.maxY - height
        return CGRect(x: visibleFrame.minX, y: y, width: visibleFrame.width, height: height)
    }

    static func resolveFallbackID(
        snapshots: [DisplaySnapshot],
        primaryID: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if let primaryID { return primaryID }
        // Lowest-ID built-in.
        if let builtIn = snapshots.filter({ $0.isBuiltIn }).map(\.id).min() {
            return builtIn
        }
        // Lowest-ID anything.
        return snapshots.map(\.id).min()
    }
}
