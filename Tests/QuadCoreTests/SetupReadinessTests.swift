import XCTest
@testable import QuadCore

final class SetupReadinessTests: XCTestCase {
    let selected: [UInt32?] = [1, 2, 3, 4]
    func testNeitherPermissionCannotChooseOrStart() {
        let state = SetupReadiness(screenRecording: false, accessibility: false, selections: selected)
        XCTAssertFalse(state.canChooseWindows); XCTAssertFalse(state.canStart)
    }
    func testScreenOnlyCannotStart() {
        XCTAssertFalse(SetupReadiness(screenRecording: true, accessibility: false, selections: selected).canStart)
    }
    func testAccessibilityOnlyCannotStart() {
        XCTAssertFalse(SetupReadiness(screenRecording: false, accessibility: true, selections: selected).canStart)
    }
    func testGrantingBothPermitsChoosingBeforeFourAreSelected() {
        let state = SetupReadiness(screenRecording: true, accessibility: true, selections: [nil, nil, nil, nil])
        XCTAssertTrue(state.canChooseWindows); XCTAssertFalse(state.canStart)
    }
    func testFourDistinctWindowsPermitStart() {
        XCTAssertTrue(SetupReadiness(screenRecording: true, accessibility: true, selections: selected).canStart)
    }
    func testDuplicateOrMissingWindowsCannotStart() {
        let cases: [[UInt32?]] = [[1, 2, 2, 4], [1, 2, nil, 4], [1, 2, 3], [1, 2, 3, 4, 5]]
        for ids in cases {
            XCTAssertFalse(SetupReadiness(screenRecording: true, accessibility: true, selections: ids).canStart)
        }
    }
    func testRefreshingCannotStartEvenWithPermissionsAndSelections() {
        let state = SetupReadiness(screenRecording: true, accessibility: true, selections: selected, isBusy: true)
        XCTAssertFalse(state.canChooseWindows); XCTAssertFalse(state.canStart)
    }
    func testRevokingEitherPermissionBlocksPreviouslyReadySelection() {
        XCTAssertTrue(SetupReadiness(screenRecording: true, accessibility: true, selections: selected).canStart)
        XCTAssertFalse(SetupReadiness(screenRecording: false, accessibility: true, selections: selected).canStart)
        XCTAssertFalse(SetupReadiness(screenRecording: true, accessibility: false, selections: selected).canStart)
    }
}
