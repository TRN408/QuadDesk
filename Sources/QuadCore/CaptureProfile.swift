import Foundation
import CoreGraphics

/// Keep text resolution stable while reducing work in the three inactive panes.
public struct CaptureProfile: Equatable {
    public let framesPerSecond: Int32
    public let longestEdge: CGFloat

    public init(active: Bool, constrained: Bool = false) {
        framesPerSecond = constrained ? (active ? 12 : 4) : (active ? 24 : 8)
        longestEdge = constrained ? 1280 : 1440
    }

    public func dimensions(for source: CGSize) -> CGSize {
        let size = Projection.captureSize(source: source, longestEdge: longestEdge)
        // Bi-planar 4:2:0 requires even dimensions. Do not exceed the pixel budget.
        return CGSize(width: max(2, floor(size.width / 2) * 2),
                      height: max(2, floor(size.height / 2) * 2))
    }
}
