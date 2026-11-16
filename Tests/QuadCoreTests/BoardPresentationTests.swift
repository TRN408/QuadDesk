import XCTest
@testable import QuadCore

final class BoardPresentationTests: XCTestCase {
    func testNoCaptureSessionCannotBeResumedByVisibilityRepair() {
        var state = BoardPresentation()
        state.showBoard()
        XCTAssertFalse(state.wantsBoard)
        XCTAssertEqual(state.mode, .setup)
    }
    func testOriginalAndSettingsRemainHiddenUntilExplicitResume() {
        var state = BoardPresentation()
        state.begin()
        XCTAssertTrue(state.wantsBoard)
        state.showOriginal()
        XCTAssertFalse(state.wantsBoard)
        state.sessionActive = false
        state.sessionActive = true
        XCTAssertFalse(state.wantsBoard)
        state.showBoard()
        XCTAssertTrue(state.wantsBoard)
        state.showSettings()
        XCTAssertFalse(state.wantsBoard)
        XCTAssertTrue(state.sessionRunning)
    }
    func testInactiveSessionOrSleepingDisplaySuppressesBoardRepair() {
        var state = BoardPresentation()
        state.begin()
        state.sessionActive = false
        XCTAssertFalse(state.wantsBoard)
        state.displaysAwake = false
        state.sessionActive = true
        XCTAssertFalse(state.wantsBoard)
        state.displaysAwake = true
        XCTAssertTrue(state.wantsBoard)
    }
    func testWakeDoesNotRestartEndedCapture() {
        var state = BoardPresentation()
        state.begin()
        state.displaysAwake = false
        state.end()
        state.displaysAwake = true
        state.showBoard()
        XCTAssertFalse(state.wantsBoard)
        XCTAssertFalse(state.sessionRunning)
    }
}
