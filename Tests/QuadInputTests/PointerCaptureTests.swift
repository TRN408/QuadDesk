import XCTest
import AppKit
@testable import QuadInput

final class PointerCaptureTests: XCTestCase {
    func testFilterCannotCaptureKeysOrRecaptureForwardedPointer() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        for kind in [CGEventType.keyDown, .keyUp, .flagsChanged, .null] {
            event.type = kind
            XCTAssertFalse(PointerCapture.accepts(event))
        }
        for kind in [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel] {
            event.type = kind
            XCTAssertTrue(PointerCapture.accepts(event))
            let forwarded = try XCTUnwrap(WindowEvents.mouse(type: .leftMouseDown,
                point: CGPoint(x: 200, y: 300), frame: CGRect(x: 100, y: 50, width: 1000, height: 800),
                windowID: 77, pid: getpid(), button: 0, clickCount: 1, flags: []))
            forwarded.type = kind
            XCTAssertEqual(forwarded.getIntegerValueField(.eventSourceUserData), WindowEvents.forwardingTag)
            XCTAssertFalse(PointerCapture.accepts(forwarded))
        }
        // Tests inspect in-memory events only: never install a tap or post input.
    }
    func testHardwareCursorMotionAndKeyboardAreNeverSuppressed() {
        for kind in [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                     .keyDown, .keyUp, .flagsChanged] {
            XCTAssertFalse(PointerCapture.suppresses(kind))
        }
        XCTAssertTrue(PointerCapture.suppresses(.leftMouseDown))
        XCTAssertTrue(PointerCapture.suppresses(.leftMouseUp))
        XCTAssertTrue(PointerCapture.suppresses(.scrollWheel))
    }
    func testRoutingUsesTheInteractiveWindowInsteadOfCoveringRectangles() {
        XCTAssertEqual(PointerWindowRoute.decide(windowID: 7, layer: 0, boardLevel: 3), .capture)
        XCTAssertEqual(PointerWindowRoute.decide(windowID: 8, layer: 101, boardLevel: 3), .passThrough)
        XCTAssertEqual(PointerWindowRoute.decide(windowID: 0, layer: 0, boardLevel: 3), .unavailable)
        XCTAssertEqual(PointerWindowRoute.decide(windowID: 9, layer: nil, boardLevel: 3), .unavailable)
    }
}
