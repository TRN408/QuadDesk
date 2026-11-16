import XCTest
@testable import QuadCore

final class WindowMenuEntryTests: XCTestCase {
    func testRemovedSelectionClearsOnlyItsSlotAfterReordering() {
        XCTAssertEqual(WindowMenuEntry.retainedSelections([10, 20, 30, 40], available: [40, 30, 20, 50]), [nil, 20, 30, 40])
    }
    func testSameNamedWindowsKeepTheirDistinctIdentities() {
        let result = WindowMenuEntry.unique([.init(id: 10, title: "App — Document"), .init(id: 20, title: "App — Document")])
        XCTAssertEqual(result, [.init(id: 10, title: "App — Document"), .init(id: 20, title: "App — Document（2）")])
    }
    func testRepeatedIdentityDoesNotCreateAnotherMenuItem() {
        XCTAssertEqual(WindowMenuEntry.unique([.init(id: 10, title: "First"), .init(id: 10, title: "Changed")]), [.init(id: 10, title: "First")])
    }
    func testLiteralNumberedTitlesCannotCollideWithGeneratedNames() {
        let result = WindowMenuEntry.unique([.init(id: 1, title: "Doc"), .init(id: 2, title: "Doc"), .init(id: 3, title: "Doc（2）")])
        XCTAssertEqual(Set(result.map(\.title)).count, 3)
        XCTAssertEqual(result.map(\.id), [1, 2, 3])
    }
}
