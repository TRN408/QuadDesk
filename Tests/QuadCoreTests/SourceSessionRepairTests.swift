import XCTest
@testable import QuadCore

final class SourceSessionRepairTests: XCTestCase {
    private var originals: [SavedWindow] {
        (1...4).map { SavedWindow(windowID: UInt32($0), processID: 123, bundleID: "test.app",
            launchDate: Date(timeIntervalSince1970: 100), title: "Window \($0)",
            originalFrame: CGRect(x: $0 * 100, y: 50, width: 800, height: 600)) }
    }
    func testFreshStartAndIntactSessionNeedNoRecovery() throws {
        XCTAssertEqual(try SourceSessionRepair.plan(stored: [], expected: [], live: []), .ready)
        XCTAssertEqual(try SourceSessionRepair.plan(stored: originals, expected: originals, live: originals), .ready)
    }
    func testClosedSourceRecoversAllOriginalsRatherThanGuessingReplacement() throws {
        XCTAssertEqual(try SourceSessionRepair.plan(stored: originals, expected: originals, live: Array(originals.dropLast())), .recover(originals))
    }
    func testMissingJournalEntryKeepsOriginalHeldInMemory() throws {
        XCTAssertEqual(try SourceSessionRepair.plan(stored: Array(originals.dropLast()), expected: originals, live: originals), .recover(originals))
    }
    func testStartupWithPendingJournalRequiresAutomaticRecovery() throws {
        XCTAssertEqual(try SourceSessionRepair.plan(stored: originals, expected: [], live: []), .recover(originals))
    }
    func testConflictingOriginalsAreNotOverwritten() {
        var changed = originals; changed[0].originalFrame.origin.x += 50
        XCTAssertThrowsError(try SourceSessionRepair.plan(stored: originals, expected: changed, live: originals)) {
            XCTAssertTrue($0 is SourceSessionRepair.ConflictingOriginals)
        }
    }
    func testRestartedProcessIsNotTheSameOriginal() throws {
        var previous = originals[0]; previous.launchDate = Date(timeIntervalSince1970: 99)
        let result = try SourceSessionRepair.plan(stored: [previous], expected: originals, live: originals)
        XCTAssertEqual(result, .recover([previous] + originals))
    }
}
