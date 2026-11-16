import CoreGraphics

public enum WindowRestoration {
    /// Avoid requiring remote accessibility when WindowServer already confirms
    /// the saved placement, e.g. after reverting an app-scoped display setup.
    @discardableResult
    @MainActor
    public static func applyIfNeeded(current: CGRect, original: CGRect,
                                     operation: @MainActor () async throws -> Void) async rethrows -> Bool {
        if abs(current.minX-original.minX) < 3, abs(current.minY-original.minY) < 3,
           abs(current.width-original.width) < 3, abs(current.height-original.height) < 3 { return false }
        try await operation()
        return true
    }
}
