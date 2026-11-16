import AppKit
import Darwin

/// Experimental window-targeting adapter. These metadata are not a supported Apple contract.
/// Keep SPI isolated and fail closed if the symbol or event round-trip is unavailable.
public enum WindowEvents {
    static let forwardingTag: Int64 = 0x5144554144
    /// Posting is asynchronous: true means queued, never proof of consumption.
    @discardableResult
    public static func post(_ event: CGEvent, to pid: Int32) -> Bool {
        guard canPost(event, to: pid) else { return false }
        event.postToPid(pid)
        return true
    }
    static func canPost(_ event: CGEvent, to pid: Int32) -> Bool {
        let pointerTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
            .otherMouseDragged, .scrollWheel]
        return pointerTypes.contains(event.type) && pid > 0 && event.getIntegerValueField(windowNumber) > 0
            && event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(pid)
    }
    // Never let continuously forwarded hover/drag events suppress real typing
    // or trackpad input. Configure our own source, not the system-wide filter.
    static let forwardingSource: CGEventSource? = {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        source.userData = forwardingTag
        source.localEventsSuppressionInterval = 0
        let hardware: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source.setLocalEventsFilterDuringSuppressionState(hardware, state: .eventSuppressionStateSuppressionInterval)
        source.setLocalEventsFilterDuringSuppressionState(hardware, state: .eventSuppressionStateRemoteMouseDrag)
        return source
    }()
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private typealias GetWindowLocation = @convention(c) (CGEvent) -> CGPoint
    private static let setWindowLocation: SetWindowLocation? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let address = dlsym(handle, "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(address, to: SetWindowLocation.self)
    }()
    private static let getWindowLocation: GetWindowLocation? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let address = dlsym(handle, "CGEventGetWindowLocation") else { return nil }
        return unsafeBitCast(address, to: GetWindowLocation.self)
    }()
    private static let windowNumber = CGEventField(rawValue: 51)!
    public static var isSupported: Bool { setWindowLocation != nil && getWindowLocation != nil && forwardingSource != nil }
    static func localPoint(of event: CGEvent) -> CGPoint? { getWindowLocation?(event) }

    public static func mouse(type: CGEventType, point: CGPoint, frame: CGRect, windowID: UInt32, pid: Int32,
                             button: Int, clickCount: Int, flags: CGEventFlags) -> CGEvent? {
        guard let nativeType = NSEvent.EventType(rawValue: UInt(type.rawValue)) else { return nil }
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        let pressed = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type)
        guard let native = NSEvent.mouseEvent(with: nativeType, location: local,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(windowID), context: nil,
                eventNumber: 0, clickCount: clickCount, pressure: pressed ? 1 : 0), let event = native.cgEvent else { return nil }
        event.flags = flags
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.setDoubleValueField(.mouseEventPressure, value: pressed ? 1 : 0)
        guard stamp(event, point: point, frame: frame, windowID: windowID, pid: pid) else { return nil }
        return event
    }

    public static func stamp(_ event: CGEvent, point: CGPoint, frame: CGRect, windowID: UInt32, pid: Int32) -> Bool {
        guard let setWindowLocation, let getWindowLocation, let forwardingSource, windowID != 0 else { return false }
        let flags = event.flags
        let timestamp = event.timestamp
        event.setSource(forwardingSource)
        event.flags = flags
        event.timestamp = timestamp
        event.location = point
        event.setIntegerValueField(windowNumber, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(getpid()))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        // Window-relative AppKit event subtype; undocumented value used only in this adapter.
        if event.type != .scrollWheel { event.setIntegerValueField(.mouseEventSubtype, value: 3) }
        // CG window-local metadata uses a top-left origin, unlike NSEvent's constructor.
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        setWindowLocation(event, local)
        guard let roundTrip = NSEvent(cgEvent: event) else { return false }
        let readBack = getWindowLocation(event)
        return roundTrip.windowNumber == Int(windowID) && abs(readBack.x - local.x) < 0.01 && abs(readBack.y - local.y) < 0.01
    }
}
