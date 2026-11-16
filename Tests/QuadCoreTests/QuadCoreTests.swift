import XCTest
import CoreGraphics
@testable import QuadCore

final class QuadCoreTests: XCTestCase {
    func testFullLayoutFitsQuarterWithoutCropping() {
        let source = CGRect(x: 0, y: 25, width: 1440, height: 900)
        let viewport = CGRect(x: 8, y: 38, width: 720, height: 450)
        XCTAssertEqual(Projection.fittedRect(source: source.size, in: viewport), viewport)
        let center = Projection.sourcePoint(CGPoint(x: 368, y: 263), source: source, viewport: viewport)!
        XCTAssertEqual(center.x, 720, accuracy: 0.001)
        XCTAssertEqual(center.y, 475, accuracy: 0.001)
    }
    func testLetterboxNeverForwardsClicksOutsideImage() {
        let source = CGRect(x: 10, y: 20, width: 1600, height: 900)
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 800)
        XCTAssertEqual(Projection.fittedRect(source: source.size, in: viewport), CGRect(x: 0, y: 175, width: 800, height: 450))
        XCTAssertNil(Projection.sourcePoint(CGPoint(x: 400, y: 100), source: source, viewport: viewport))
        XCTAssertEqual(Projection.sourcePoint(CGPoint(x: 400, y: 175), source: source, viewport: viewport), CGPoint(x: 810, y: 20))
    }
    func testDragBeyondImageClampsAndCanReleaseAtEdge() {
        let source = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        let point = Projection.sourcePoint(CGPoint(x: 9999, y: -100), source: source,
                                           viewport: CGRect(x: 0, y: 0, width: 800, height: 450), clamp: true)!
        XCTAssertEqual(point.x, -0.01, accuracy: 0.001)
        XCTAssertEqual(point.y, -900, accuracy: 0.001)
    }
    func testMultiDisplayOriginsAndAppKitYFlip() {
        let frame = Projection.quartzRect(appKit: CGRect(x: -1920, y: 1080, width: 1920, height: 1080), primaryScreenHeight: 1080)
        XCTAssertEqual(frame, CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        let point = Projection.sourcePoint(CGPoint(x: 480, y: 270), source: frame,
                                           viewport: CGRect(x: 0, y: 0, width: 960, height: 540))
        XCTAssertEqual(point, CGPoint(x: -960, y: -540))
    }
    func testZeroSizedViewDoesNotCreateInvalidEvents() {
        XCTAssertNil(Projection.sourcePoint(.zero, source: .zero, viewport: .zero))
        XCTAssertEqual(Projection.fittedRect(source: CGSize(width: 10, height: 0), in: CGRect(x: 0, y: 0, width: 100, height: 100)), .zero)
    }
    func testCaptureResolutionIsBoundedAndKeepsAspect() {
        let size = Projection.captureSize(source: CGSize(width: 3200, height: 2000))
        XCTAssertEqual(size, CGSize(width: 1600, height: 1000))
        XCTAssertEqual(Projection.captureSize(source: CGSize(width: 1200, height: 800)), CGSize(width: 1200, height: 800))
    }
    func testMatcherDoesNotSelectWrongSameNamedWindow() {
        let expected = WindowDescriptor(title: "Editor", frame: CGRect(x: 100, y: 100, width: 900, height: 600))
        let other = WindowDescriptor(title: "Editor", frame: CGRect(x: 200, y: 200, width: 900, height: 600))
        XCTAssertEqual(WindowMatcher.bestMatch(for: expected, candidates: [other, expected]), 1)
        XCTAssertNil(WindowMatcher.bestMatch(for: expected, candidates: [expected, expected]))
        XCTAssertNil(WindowMatcher.bestMatch(for: expected, candidates: [other]))
        XCTAssertNil(WindowMatcher.bestMatch(for: expected, candidates: [WindowDescriptor(title: "Terminal", frame: expected.frame)]))
    }
    func testRecoverySurvivesInterruptedSessionAndClearsOnlyOnSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(url: directory.appendingPathComponent("recovery.json"))
        let first = SavedWindow(windowID: 7, processID: 100, bundleID: "test.editor", launchDate: Date(timeIntervalSince1970: 1), title: "日本語.md",
                                originalFrame: CGRect(x: -1440, y: 40, width: 1200, height: 800))
        let second = SavedWindow(windowID: 8, processID: 101, bundleID: "test.terminal", launchDate: Date(timeIntervalSince1970: 2), title: "shell",
                                 originalFrame: CGRect(x: 50, y: 80, width: 900, height: 600))
        XCTAssertEqual(try store.read(), [])
        try store.write([first, second])
        XCTAssertEqual(try store.read(), [first, second])
        try store.write([second])
        XCTAssertEqual(try store.read(), [second])
        try store.write([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
    func testChromiumAXTitleSuffixStillRequiresUniqueGeometry() {
        let frame = CGRect(x: 100, y: 80, width: 1000, height: 700)
        let screenCapture = WindowDescriptor(title: "QuadDesk Test", frame: frame)
        let decorated = WindowDescriptor(title: "QuadDesk Test - Google Chrome - Profile", frame: frame)
        let other = WindowDescriptor(title: decorated.title, frame: CGRect(x: 200, y: 80, width: 1000, height: 700))
        XCTAssertEqual(WindowMatcher.bestMatch(for: screenCapture, candidates: [other, decorated]), 1)
        XCTAssertNil(WindowMatcher.bestMatch(for: screenCapture, candidates: [decorated, decorated]))
        XCTAssertNil(WindowMatcher.bestMatch(for: screenCapture, candidates: [other]))
    }
    func testCorruptRecoveryIsNotSilentlyDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recovery.json")
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try RecoveryStore(url: url).read())
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
}
