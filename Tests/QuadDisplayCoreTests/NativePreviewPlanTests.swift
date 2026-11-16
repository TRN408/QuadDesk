import XCTest
@testable import QuadDisplayCore

final class NativePreviewPlanTests: XCTestCase {
    func testFourWindowsCoverAreaWithoutGapsOrOverlap() {
        for area in [CGRect(x: 0, y: 25, width: 2880, height: 1775),
                     CGRect(x: -11, y: -1050, width: 3361, height: 2077)] {
            let tiles = NativePreviewPlan.tiles(in: area)
            XCTAssertEqual(tiles.count, 4)
            XCTAssertEqual(tiles.reduce(0) { $0 + $1.width * $1.height }, area.width * area.height)
            for i in tiles.indices {
                XCTAssertTrue(area.contains(tiles[i]))
                for j in tiles.indices where j > i {
                    let intersection = tiles[i].intersection(tiles[j])
                    XCTAssertTrue(intersection.isNull || intersection.width * intersection.height == 0)
                }
            }
        }
    }
}
