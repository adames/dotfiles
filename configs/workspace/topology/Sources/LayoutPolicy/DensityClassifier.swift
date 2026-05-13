import CoreGraphics
import DisplayTopology

public enum DensityClassifier {
    /// Density classification uses backing scale + built-in status as the primary
    /// signals; the pixel-to-point ratio is a secondary tuning input only.
    /// `CGDisplayScreenSize` is documented as potentially estimated, so we never
    /// reason in physical inches.
    public static func classify(
        backingScaleFactor: CGFloat,
        framePoints: CGRect,
        pixelSize: CGSize,
        isBuiltIn: Bool = false
    ) -> DensityClass {
        if backingScaleFactor < 2.0 {
            return .coarseExternal
        }
        // Modern Apple Silicon built-ins are all Retina-class.
        if isBuiltIn {
            return .retinaLike
        }
        let pointsPerInchProxy = effectivePointsPerInchProxy(
            framePoints: framePoints,
            pixelSize: pixelSize,
            backingScaleFactor: backingScaleFactor
        )
        return pointsPerInchProxy >= retinaLikeThreshold ? .retinaLike : .midExternal
    }

    static let retinaLikeThreshold: CGFloat = 200.0

    /// Approximates effective points-per-inch from pixel size and point size.
    /// Without a reliable physical inch (`CGDisplayScreenSize` is flaky), we
    /// compare pixels to points to get a *relative* density bucket.
    static func effectivePointsPerInchProxy(
        framePoints: CGRect,
        pixelSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGFloat {
        guard framePoints.width > 0, pixelSize.width > 0 else { return 0 }
        let pixelsPerPoint = pixelSize.width / framePoints.width
        return pixelsPerPoint * 100.0 * backingScaleFactor
    }
}
