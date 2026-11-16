import XCTest
@testable import QuadCore

final class SourceLayoutTests: XCTestCase {
    func testEachSourceHasAnExclusiveOnscreenCornerForAnyZOrder() {
        for area in [CGRect(x: 0, y: 25, width: 1440, height: 875),
                     CGRect(x: -1920, y: -1000, width: 1920, height: 1080)] {
            for count in 2...4 {
                let frames = SourceLayout.frames(in: area, count: count)
                XCTAssertEqual(frames.count, count)
                for (index, frame) in frames.enumerated() {
                    XCTAssertTrue(area.contains(frame))
                    XCTAssertGreaterThan(frame.width * frame.height / (area.width * area.height), 0.98)
                    let corner = CGPoint(x: index % 2 == 0 ? frame.minX + 0.25 : frame.maxX - 0.25,
                                         y: index / 2 == 0 ? frame.minY + 0.25 : frame.maxY - 0.25)
                    XCTAssertFalse(frames.enumerated().contains { $0.offset != index && $0.element.contains(corner) })
                }
            }
        }
        let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(SourceLayout.frames(in: area, count: 1), [area])
        XCTAssertTrue(SourceLayout.frames(in: area, count: 5).isEmpty)
    }
}
