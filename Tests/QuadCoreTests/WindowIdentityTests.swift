import XCTest
@testable import QuadCore

final class WindowIdentityTests: XCTestCase {
    private let original = WindowDescriptor(title: "Document", frame: CGRect(x: 160, y: 151, width: 842, height: 609))
    func testIdentitySurvivesChangedTitleAndPresentationFrame() {
        let changed = WindowDescriptor(title: "Edited document", frame: CGRect(x: 100, y: 100, width: 380, height: 231))
        let candidates = [IdentifiedWindowDescriptor(windowID: 23, window: original),
                          IdentifiedWindowDescriptor(windowID: 17, window: changed)]
        XCTAssertEqual(WindowMatcher.bestMatch(windowID: 17, expected: original, candidates: candidates), 1)
    }
    func testKnownDifferentIdCannotBeReplacedByPerfectGeometryMatch() {
        XCTAssertNil(WindowMatcher.bestMatch(windowID: 17, expected: original,
            candidates: [IdentifiedWindowDescriptor(windowID: 23, window: original)]))
    }
    func testDuplicateIdentityIsAmbiguous() {
        let candidate = IdentifiedWindowDescriptor(windowID: 17, window: original)
        XCTAssertNil(WindowMatcher.bestMatch(windowID: 17, expected: original, candidates: [candidate, candidate]))
    }
    func testUnavailableIdentityUsesOnlyUnambiguousStrictFallback() {
        let candidate = IdentifiedWindowDescriptor(windowID: nil, window: original)
        XCTAssertEqual(WindowMatcher.bestMatch(windowID: 17, expected: original, candidates: [candidate]), 0)
        XCTAssertNil(WindowMatcher.bestMatch(windowID: 17, expected: original, candidates: [candidate, candidate]))
    }
}
