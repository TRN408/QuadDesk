import CoreGraphics
import XCTest
@testable import QuadCore

final class BrowserGridTests: XCTestCase {
    func testTwoRowsFitWithoutChangingAspectOrAddingGutters() {
        let plan = BrowserGridPlan(available: CGSize(width: 1440, height: 800), mode: .twoRows, paneCount: 16)
        XCTAssertEqual(plan.rows, 2)
        XCTAssertEqual(plan.columns, 8)
        XCTAssertEqual(plan.recommendedCapacity, 16)
        XCTAssertLessThanOrEqual(plan.scale, 1)
        for frame in plan.frames {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertLessThanOrEqual(frame.maxX, 1440 + 0.001)
            XCTAssertLessThanOrEqual(frame.maxY, 800 + 0.001)
            XCTAssertEqual(frame.width / frame.height, 390.0 / 844.0, accuracy: 0.000001)
        }
        XCTAssertEqual(plan.frames[0].maxX, plan.frames[1].minX, accuracy: 0.000001)
        XCTAssertEqual(plan.frames[0].maxY, plan.frames[8].minY, accuracy: 0.000001)
    }
    func testClosingOrResizingNeverRequiresDroppingExistingPages() {
        let plan = BrowserGridPlan(available: CGSize(width: 700, height: 400), mode: .twoRows, paneCount: 25)
        XCTAssertEqual(plan.rows, 2)
        XCTAssertEqual(plan.columns, 13)
        XCTAssertEqual(plan.frames.count, 25)
        XCTAssertTrue(plan.frames.allSatisfy { $0.maxX <= 700.001 && $0.maxY <= 400.001 })
    }
    func testInvalidAndExtremeSizesAreBounded() {
        XCTAssertEqual(BrowserGridPlan(available: .zero, mode: .twoRows, paneCount: 4).frames.count, 0)
        XCTAssertEqual(BrowserGridPlan(available: CGSize(width: CGFloat.infinity, height: 100), mode: .twoRows, paneCount: 4).recommendedCapacity, 0)
        let wide = BrowserGridPlan(available: CGSize(width: 100000, height: 100), mode: .twoRows, paneCount: 1000)
        XCTAssertEqual(wide.recommendedCapacity, 64)
        XCTAssertEqual(wide.frames.count, 64)
    }
}
