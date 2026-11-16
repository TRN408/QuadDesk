import CoreGraphics

/// Require two observations of an active source enlarged in both dimensions.
/// Ordinary clicks, small resizes and background windows must not change scale.
public struct WindowExpansion {
    private var candidate: Int?
    public init() {}
    public mutating func observe(slot: Int?, current: CGRect?, tile: CGRect?, isFullscreen: Bool = false) -> Int? {
        guard let slot, let tile, tile.width > 0, tile.height > 0 else {
            candidate = nil; return nil
        }
        // Native fullscreen can keep the original WindowServer frame at its
        // tile size, or temporarily hide it while a separate Space is visible.
        let enlarged = current.map { $0.width >= tile.width * 1.5 && $0.height >= tile.height * 1.5 } == true
        guard isFullscreen || enlarged else {
            candidate = nil; return nil
        }
        defer { candidate = slot }
        return candidate == slot ? slot : nil
    }
}
