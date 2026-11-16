import XCTest
import AppKit
@testable import QuadInput

final class WindowEventTests: XCTestCase {
    func testPostingGuardRequiresAnAddressedPointerEvent() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 200, y: 300), mouseButton: .left))
        XCTAssertFalse(WindowEvents.canPost(event, to: getpid()))
        XCTAssertTrue(WindowEvents.stamp(event, point: CGPoint(x: 200, y: 300),
            frame: CGRect(x: 100, y: 50, width: 1000, height: 800), windowID: 77, pid: getpid()))
        XCTAssertEqual(event.getIntegerValueField(.eventTargetUnixProcessID), Int64(getpid()))
        XCTAssertTrue(WindowEvents.canPost(event, to: getpid()))
        XCTAssertFalse(WindowEvents.canPost(event, to: 0))
        XCTAssertFalse(WindowEvents.canPost(event, to: getpid() + 1))
        // This adapter never injects keyboard input, even with window metadata.
        event.type = .keyDown
        XCTAssertFalse(WindowEvents.canPost(event, to: getpid()))
        // No test invokes a posting API or sends input to a process.
    }
    func testForwardingSourcePermitsPhysicalInputDuringHoverAndDrag() throws {
        let source = try XCTUnwrap(WindowEvents.forwardingSource)
        XCTAssertEqual(source.localEventsSuppressionInterval, 0, accuracy: 0.0001)
        let states: [CGEventSuppressionState] = [.eventSuppressionStateSuppressionInterval, .eventSuppressionStateRemoteMouseDrag]
        for state in states {
            let permitted = source.getLocalEventsFilterDuringSuppressionState(state)
            XCTAssertTrue(permitted.contains(.permitLocalKeyboardEvents))
            XCTAssertTrue(permitted.contains(.permitLocalMouseEvents))
            XCTAssertTrue(permitted.contains(.permitSystemDefinedEvents))
        }
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 200, y: 300), mouseButton: .left))
        event.flags = [.maskShift]
        event.timestamp = 123456789
        XCTAssertTrue(WindowEvents.stamp(event, point: CGPoint(x: 200, y: 300),
            frame: CGRect(x: 100, y: 50, width: 1000, height: 800), windowID: 77, pid: getpid()))
        // .privateState requests a private table; macOS assigns its runtime ID.
        XCTAssertNotEqual(source.sourceStateID, .combinedSessionState)
        XCTAssertNotEqual(source.sourceStateID, .hidSystemState)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceStateID), Int64(source.sourceStateID.rawValue))
        XCTAssertEqual(event.flags, [.maskShift])
        XCTAssertEqual(event.timestamp, 123456789)
    }
    func testWindowIdentityAndLocalPointSurviveCGEventBridge() throws {
        let frame = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let point = CGPoint(x: -1200, y: 140)
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
        XCTAssertTrue(WindowEvents.isSupported, "Window input SPI is unavailable; interactive mode must remain disabled")
        XCTAssertTrue(WindowEvents.stamp(event, point: point, frame: frame, windowID: 1234, pid: getpid()))
        let roundTrip = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(roundTrip.windowNumber, 1234)
        // NSEvent cannot resolve a foreign window's AppKit frame inside this process.
        // Validate the actual window-local metadata, not NSEvent's global-coordinate fallback.
        let local = try XCTUnwrap(WindowEvents.localPoint(of: event))
        XCTAssertEqual(local.x, 240, accuracy: 0.01)
        XCTAssertEqual(local.y, 100, accuracy: 0.01)
        XCTAssertEqual(event.location, point)
    }
    func testScrollTargetsWindowAndRetainsPixelDeltas() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 48, wheel2: -17, wheel3: 0))
        let before = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        XCTAssertTrue(WindowEvents.stamp(event, point: CGPoint(x: 400, y: 300), frame: CGRect(x: 100, y: 50, width: 1200, height: 800), windowID: 99, pid: getpid()))
        XCTAssertEqual(NSEvent(cgEvent: event)?.windowNumber, 99)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), before)
        XCTAssertEqual(WindowEvents.localPoint(of: event), CGPoint(x: 300, y: 250))
    }
    func testUnknownWindowCannotReceiveInput() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertFalse(WindowEvents.stamp(event, point: .zero, frame: .zero, windowID: 0, pid: getpid()))
    }
    func testMouseFactoryPreservesUpTypeAndModifierFlags() throws {
        let event = try XCTUnwrap(WindowEvents.mouse(type: .leftMouseUp, point: CGPoint(x: 200, y: 300),
            frame: CGRect(x: 100, y: 50, width: 1000, height: 800), windowID: 77, pid: getpid(),
            button: 0, clickCount: 2, flags: [.maskShift]))
        XCTAssertEqual(event.type, .leftMouseUp)
        XCTAssertEqual(event.flags, [.maskShift])
        XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 2)
        XCTAssertEqual(NSEvent(cgEvent: event)?.windowNumber, 77)
        XCTAssertEqual(WindowEvents.localPoint(of: event), CGPoint(x: 100, y: 250))
    }
}
