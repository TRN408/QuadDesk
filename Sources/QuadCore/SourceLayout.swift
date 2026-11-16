import CoreGraphics

/// Leave each native source a small exposed corner, regardless of z-order.
/// The covering board must also be translucent for WindowServer visibility.
public enum SourceLayout {
    public static func frames(in area: CGRect, count: Int) -> [CGRect] {
        guard area.width > 160, area.height > 100, (1...4).contains(count) else { return [] }
        guard count > 1 else { return [area] }
        let width = floor(area.width - 8)
        let height = floor(area.height * width / area.width)
        let dx = area.width - width, dy = area.height - height
        return (0..<count).map { index in
            CGRect(x: area.minX + (index % 2 == 0 ? 0 : dx),
                   y: area.minY + (index / 2 == 0 ? 0 : dy), width: width, height: height)
        }
    }
}
