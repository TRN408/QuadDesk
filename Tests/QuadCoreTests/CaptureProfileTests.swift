import XCTest
@testable import QuadCore

final class CaptureProfileTests: XCTestCase {
    func testFourPaneFrameBudgetAndPressureReduction() {
        let active = CaptureProfile(active: true)
        let idle = CaptureProfile(active: false)
        XCTAssertEqual(active.framesPerSecond + idle.framesPerSecond * 3, 48)
        XCTAssertLessThan(CaptureProfile(active: true, constrained: true).framesPerSecond, active.framesPerSecond)
        XCTAssertLessThan(CaptureProfile(active: false, constrained: true).framesPerSecond, idle.framesPerSecond)
    }
    func testYUVOutputIsEvenBoundedAndPreservesFullLayoutMapping() {
        let source = CGRect(x: -1440, y: 25, width: 1440, height: 875)
        for constrained in [false, true] {
            let profile = CaptureProfile(active: true, constrained: constrained)
            let size = profile.dimensions(for: source.size)
            XCTAssertEqual(Int(size.width) % 2, 0)
            XCTAssertEqual(Int(size.height) % 2, 0)
            XCTAssertLessThanOrEqual(max(size.width, size.height), profile.longestEdge)
            XCTAssertEqual(size.width / size.height, source.width / source.height, accuracy: 0.005)
            // Resolution and chroma format must never change source input coordinates.
            XCTAssertEqual(Projection.sourcePoint(CGPoint(x: 360, y: 218.75), source: source,
                viewport: CGRect(x: 0, y: 0, width: 720, height: 437.5)), CGPoint(x: -720, y: 462.5))
        }
    }
}
