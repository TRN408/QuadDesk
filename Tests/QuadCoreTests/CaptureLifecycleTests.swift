import XCTest
@testable import QuadCore

final class CaptureLifecycleTests: XCTestCase {
    private let systemFailure = CaptureFailure(domain: CaptureFailure.streamErrorDomain, code: -3821, message: "system stopped")

    func testFourStreamsRequestOnlyOneSessionStop() {
        var state = CaptureLifecycle()
        let id = state.begin()
        XCTAssertTrue(state.accept(systemFailure, from: id))
        XCTAssertFalse(state.accept(systemFailure, from: id))
        XCTAssertFalse(state.accept(systemFailure, from: id))
        XCTAssertFalse(state.accept(systemFailure, from: id))
        XCTAssertEqual(state.failure, systemFailure)
    }
    func testLateFailureCannotStopNextSession() {
        var state = CaptureLifecycle()
        let old = state.begin()
        state.finish()
        let current = state.begin()
        XCTAssertFalse(state.accept(systemFailure, from: old))
        XCTAssertEqual(state.session, current)
        XCTAssertNil(state.failure)
        XCTAssertTrue(state.accept(systemFailure, from: current))
    }
    func testExpectedShutdownIgnoresCallbacksAndDoesNotRestart() {
        var state = CaptureLifecycle()
        let id = state.begin()
        state.finish()
        XCTAssertFalse(state.accept(systemFailure, from: id))
        XCTAssertNil(state.session)
        XCTAssertNil(state.failure)
    }
    func testFailureCanBeRecordedWhileStartupIsInProgress() {
        var state = CaptureLifecycle()
        let id = state.begin()
        XCTAssertTrue(state.accept(systemFailure, from: id))
        XCTAssertEqual(state.failure?.kind, .systemStopped)
        state.finish()
        XCTAssertNil(state.session)
    }
    func testErrorClassificationDistinguishesUserAndSystemAndDomains() {
        XCTAssertEqual(systemFailure.kind, .systemStopped)
        XCTAssertEqual(CaptureFailure(domain: CaptureFailure.streamErrorDomain, code: -3817, message: "user stopped").kind, .userStopped)
        XCTAssertEqual(CaptureFailure(domain: CaptureFailure.streamErrorDomain, code: -3801, message: "denied").kind, .permissionDenied)
        XCTAssertEqual(CaptureFailure(domain: "other", code: -3817, message: "unrelated").kind, .other)
        let bridged = CaptureFailure(error: NSError(domain: CaptureFailure.streamErrorDomain, code: -3821))
        XCTAssertEqual(bridged.kind, .systemStopped)
        XCTAssertFalse(bridged.isSimulation)
    }
}
