import CoreGraphics
import Foundation

public enum BrowserGridMode: Int, CaseIterable {
    case twoRows, twoColumns
    public var title: String { self == .twoRows ? "上下2段" : "左右2列" }
}

/// A fixed 390×844 browser canvas, uniformly reduced without gutters or cropping.
/// Integer rows/columns can leave a remainder at the outside edge of the window.
public struct BrowserGridPlan {
    public static let referenceSize = CGSize(width: 390, height: 844)
    public static let maximumPanes = 64
    public let rows: Int
    public let columns: Int
    public let recommendedCapacity: Int
    public let scale: CGFloat
    public let frames: [CGRect]

    public init(available: CGSize, mode: BrowserGridMode, paneCount: Int) {
        guard available.width.isFinite, available.height.isFinite,
              available.width > 0, available.height > 0 else {
            rows = 0; columns = 0; recommendedCapacity = 0; scale = 0; frames = []; return
        }
        let reference = Self.referenceSize
        let count = max(0, min(paneCount, Self.maximumPanes))
        let fixedAxisScale = mode == .twoRows
            ? min(1, available.height / (2 * reference.height))
            : min(1, available.width / (2 * reference.width))
        let along = mode == .twoRows
            ? available.width / (reference.width * fixedAxisScale)
            : available.height / (reference.height * fixedAxisScale)
        // One extra column/row trades a small uniform reduction for a fuller grid.
        let recommended = Int(min(CGFloat(Self.maximumPanes / 2), max(1, ceil(along))))
        recommendedCapacity = recommended * 2
        let variable = max(recommended, (count + 1) / 2)
        rows = mode == .twoRows ? 2 : variable
        columns = mode == .twoRows ? variable : 2
        scale = min(1, available.width / (CGFloat(columns) * reference.width),
                    available.height / (CGFloat(rows) * reference.height))
        let tile = CGSize(width: reference.width * scale, height: reference.height * scale)
        let columnCount = columns
        frames = (0..<count).map { index in
            CGRect(x: CGFloat(index % columnCount) * tile.width,
                   y: CGFloat(index / columnCount) * tile.height, width: tile.width, height: tile.height)
        }
    }
}
