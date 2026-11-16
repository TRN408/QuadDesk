// Manual integration fixture. Receives input only inside its own two windows.
// No event taps, foreign-app inspection, or generated input.
import AppKit

enum ProbeLog {
    static var sequence = 0
    static func write(_ kind: String, window: NSWindow?, fields: [String: Any] = [:]) {
        sequence += 1
        var entry = fields
        entry["kind"] = kind
        entry["pid"] = getpid()
        entry["sequence"] = sequence
        entry["uptime"] = ProcessInfo.processInfo.systemUptime
        entry["window"] = window?.title ?? "none"
        entry["windowNumber"] = window?.windowNumber ?? 0
        entry["appActive"] = NSApp.isActive
        entry["windowKey"] = window?.isKeyWindow ?? false
        entry["unoccluded"] = window?.occlusionState.contains(.visible) ?? false
        entry["textResponder"] = window?.firstResponder is NSTextView
        if let frame = window?.frame {
            entry["frameAppKit"] = [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
        }
        if let scroll = window?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first {
            entry["scrollOriginY"] = Double(scroll.contentView.bounds.origin.y)
            if let text = scroll.documentView as? NSTextView {
                entry["textLength"] = text.string.utf16.count
                entry["selectionLocation"] = text.selectedRange().location
            }
        }
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ProbeLogPath") as? String,
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch {}
    }
}

final class ProbeText: NSTextView {
    override func mouseDown(with event: NSEvent) {
        ProbeLog.write("mouseDown", window: window, fields: ["x": event.locationInWindow.x, "y": event.locationInWindow.y])
        super.mouseDown(with: event)
        ProbeLog.write("afterMouseDown", window: window)
    }
    override func scrollWheel(with event: NSEvent) {
        ProbeLog.write("scroll", window: window, fields: ["x": event.locationInWindow.x, "y": event.locationInWindow.y,
            "deltaY": event.scrollingDeltaY, "phase": event.phase.rawValue, "momentum": event.momentumPhase.rawValue])
        super.scrollWheel(with: event)
        if let origin = enclosingScrollView?.contentView.bounds.origin {
            ProbeLog.write("afterScroll", window: window, fields: ["originY": origin.y])
        }
    }
    override func keyDown(with event: NSEvent) {
        ProbeLog.write("keyDown", window: window)
        let before = string.utf16.count
        super.keyDown(with: event)
        ProbeLog.write("afterKeyDown", window: window, fields: ["beforeLength": before, "afterLength": string.utf16.count])
    }
}

final class ProbeCanvas: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { ProbeLog.write("unfocusedKeyDown", window: window) }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var labels: [NSTextField] = []
    var heartbeat = 0
    var timer: Timer?
    var inputMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        let commands = NSMenu(); root.submenu = commands
        let reset = commands.addItem(withTitle: "Reset test focus", action: #selector(resetFocus), keyEquivalent: "")
        reset.target = self
        commands.addItem(withTitle: "Quit Input Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown]) { event in
            var fields: [String: Any] = ["type": event.type.rawValue,
                "eventWindowNumber": event.windowNumber, "x": event.locationInWindow.x, "y": event.locationInWindow.y]
            if let point = event.window?.convertPoint(toScreen: event.locationInWindow), let screen = NSScreen.screens.first {
                fields["nativeQuartzX"] = Double(point.x)
                fields["nativeQuartzY"] = Double(screen.frame.height - point.y)
            }
            ProbeLog.write("applicationEvent", window: event.window, fields: fields)
            return event
        }
        let instance = Bundle.main.object(forInfoDictionaryKey: "ProbeInstance") as? String ?? "One"
        for (index, name) in ["A", "B"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 160 + index * 40, y: 140 + index * 40, width: 840, height: 580),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "QuadDesk Probe \(instance) \(name)"
            window.delegate = self
            window.isReleasedWhenClosed = false
            let content = ProbeCanvas(frame: NSRect(x: 0, y: 0, width: 840, height: 580))
            content.autoresizingMask = [.width, .height]
            let label = NSTextField(labelWithString: "Heartbeat 0 — click and scroll below")
            label.frame = NSRect(x: 16, y: 546, width: 800, height: 24)
            label.autoresizingMask = [.width, .minYMargin]
            labels.append(label); content.addSubview(label)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 840, height: 538))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = ProbeText(frame: NSRect(x: 0, y: 0, width: 820, height: 3000))
            text.isRichText = false
            text.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.string = (1...150).map { "Probe \(name) line \($0): editable native text" }.joined(separator: "\n")
            text.setSelectedRange(NSRange(location: 0, length: 0))
            scroll.documentView = text
            content.addSubview(scroll)
            window.contentView = content
            window.initialFirstResponder = content
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(content)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Inspect an unposted event object: does the old factory inherit any
        // hardware-input suppression settings? This never generates input.
        if let window = windows.first,
           let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0)?.cgEvent,
           let source = CGEventSource(event: event) {
            ProbeLog.write("eventSourceDefaults", window: window, fields: [
                "interval": source.localEventsSuppressionInterval,
                "intervalFilter": source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval).rawValue,
                "dragFilter": source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag).rawValue])
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.heartbeat += 1
            for (index, label) in self.labels.enumerated() {
                label.stringValue = "Heartbeat \(self.heartbeat) — \(index == 0 ? "A" : "B") — editable text below"
                if self.heartbeat % 4 == 0 { ProbeLog.write("heartbeat", window: self.windows[index], fields: ["beat": self.heartbeat]) }
            }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) { ProbeLog.write("becameKey", window: notification.object as? NSWindow) }
    @objc func resetFocus() {
        for window in windows {
            if let scroll = window.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first {
                (scroll.documentView as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            window.makeFirstResponder(window.contentView)
            ProbeLog.write("resetFocus", window: window)
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { ProbeLog.write("becameActive", window: NSApp.keyWindow) }
    func applicationDidResignActive(_ notification: Notification) { ProbeLog.write("resignedActive", window: NSApp.keyWindow) }
}

let application = NSApplication.shared
let delegate = ProbeDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
