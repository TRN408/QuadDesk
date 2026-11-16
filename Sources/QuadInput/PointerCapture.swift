import AppKit

/// Captures real pointer input before dispatch while the board stays mouse-transparent.
/// A local monitor also accepts explicitly addressed test/control events.
/// Keyboard events are not subscribed to, read, changed, or reposted.
@MainActor
public final class PointerCapture {
    private var monitor: Any?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    public var consume: ((NSEvent) -> Bool)?
    public var consumeGlobal: ((CGEvent) -> Bool)?
    public var disabled: (() -> Void)?
    public init() {}

    nonisolated static let pointerTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
        .otherMouseDragged, .scrollWheel]
    nonisolated static func accepts(_ event: CGEvent) -> Bool {
        pointerTypes.contains(event.type) && event.getIntegerValueField(.eventSourceUserData) != WindowEvents.forwardingTag
    }
    /// Keep hardware cursor motion intact, including while dragging. The panel
    /// ignores its native motion handlers; only clicks and wheels are consumed.
    nonisolated public static func suppresses(_ kind: CGEventType) -> Bool {
        [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
         .otherMouseDown, .otherMouseUp, .scrollWheel].contains(kind)
    }

    public func start() -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
            .otherMouseDragged, .scrollWheel]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let raw = event.cgEvent, PointerCapture.accepts(raw) else { return false }
                return self.consume?(event) == true
            }
            return consumed ? nil : event
        }
        let callback: CGEventTapCallBack = { _, kind, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let consumed = MainActor.assumeIsolated {
                let owner = Unmanaged<PointerCapture>.fromOpaque(context).takeUnretainedValue()
                if kind == .tapDisabledByTimeout || kind == .tapDisabledByUserInput {
                    owner.disabled?()
                    return false
                }
                guard PointerCapture.accepts(event) else { return false }
                return owner.consumeGlobal?(event) == true
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        let eventMask = Self.pointerTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard monitor != nil,
              let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: eventMask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop(); return false
        }
        self.tap = tap; runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); return false }
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil; runLoopSource = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

public enum PointerWindowRoute: Equatable {
    case capture, passThrough, unavailable
    public static func decide(windowID: UInt32, layer: Int?, boardLevel: Int) -> Self {
        guard windowID != 0, let layer else { return .unavailable }
        return layer > boardLevel ? .passThrough : .capture
    }
}
