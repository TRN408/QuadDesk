import XCTest
@testable import QuadCore

final class WindowExpansionTests: XCTestCase {
    let tile = CGRect(x: 1440, y: 25, width: 1440, height: 887)
    func testNativeFullscreenWithUnchangedTileGeometryStillExpands() {
        var detector = WindowExpansion()
        XCTAssertNil(detector.observe(slot: 3, current: tile, tile: tile, isFullscreen: true))
        XCTAssertEqual(detector.observe(slot: 3, current: tile, tile: tile, isFullscreen: true), 3)
    }
    func testNativeFullscreenSurvivesMissingOriginalWindowServerFrame() {
        var detector = WindowExpansion()
        XCTAssertNil(detector.observe(slot: 2, current: nil, tile: tile, isFullscreen: true))
        XCTAssertEqual(detector.observe(slot: 2, current: nil, tile: tile, isFullscreen: true), 2)
    }
    func testTransientFullscreenAndUnselectedWindowDoNotConfirm() {
        var detector = WindowExpansion()
        XCTAssertNil(detector.observe(slot: 1, current: tile, tile: tile, isFullscreen: true))
        XCTAssertNil(detector.observe(slot: 1, current: tile, tile: tile))
        XCTAssertNil(detector.observe(slot: 1, current: nil, tile: tile, isFullscreen: true))
        XCTAssertNil(detector.observe(slot: nil, current: nil, tile: tile, isFullscreen: true))
        XCTAssertNil(detector.observe(slot: 1, current: tile, tile: tile, isFullscreen: true))
    }
    func testMaximizeRequiresTwoConsecutiveObservations() {
        var detector = WindowExpansion()
        let enlarged = CGRect(x: 0, y: 25, width: 2880, height: 1775)
        XCTAssertNil(detector.observe(slot: 1, current: enlarged, tile: tile))
        XCTAssertEqual(detector.observe(slot: 1, current: enlarged, tile: tile), 1)
    }
    func testPartialResizeAndLostFocusResetDetection() {
        var detector = WindowExpansion()
        let enlarged = CGRect(x: 0, y: 0, width: 2880, height: 1800)
        let wide = CGRect(x: 0, y: 25, width: 2880, height: 887)
        XCTAssertNil(detector.observe(slot: 0, current: enlarged, tile: tile))
        XCTAssertNil(detector.observe(slot: nil, current: nil, tile: nil))
        XCTAssertNil(detector.observe(slot: 0, current: enlarged, tile: tile))
        XCTAssertNil(detector.observe(slot: 0, current: wide, tile: tile))
        XCTAssertNil(detector.observe(slot: 0, current: enlarged, tile: tile))
    }
    func testChangingSourceDoesNotConfirmPreviousSource() {
        var detector = WindowExpansion()
        let enlarged = CGRect(x: 0, y: 0, width: 2880, height: 1800)
        XCTAssertNil(detector.observe(slot: 0, current: enlarged, tile: tile))
        XCTAssertNil(detector.observe(slot: 2, current: enlarged, tile: tile))
        XCTAssertEqual(detector.observe(slot: 2, current: enlarged, tile: tile), 2)
        XCTAssertNil(detector.observe(slot: 2, current: tile, tile: tile))
    }
}
