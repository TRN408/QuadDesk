import XCTest
@testable import QuadCore

final class WindowRestorationTests: XCTestCase {
    private enum Unavailable: Error { case accessibility }
    func testAlreadyRestoredWindowDoesNotNeedWorkingAccessibility() async throws {
        let frame = CGRect(x: 160, y: 151, width: 842, height: 609)
        let invoked = try await WindowRestoration.applyIfNeeded(current: frame, original: frame) {
            throw Unavailable.accessibility
        }
        XCTAssertFalse(invoked)
    }
    func testChangedPlacementStillAttemptsRecoveryAndPropagatesFailure() async {
        let original = CGRect(x: 160, y: 151, width: 842, height: 609)
        for current in [original.offsetBy(dx: 3, dy: 0), CGRect(x: 160, y: 151, width: 1440, height: 888)] {
            do {
                try await WindowRestoration.applyIfNeeded(current: current, original: original) {
                    throw Unavailable.accessibility
                }
                XCTFail("A changed window must require recovery")
            } catch Unavailable.accessibility { }
            catch { XCTFail("Unexpected error: \(error)") }
        }
    }
}
