import AppKit
import ApplicationServices
import QuadCore
import Darwin
import OSLog

/// Optional SPI boundary; no private symbol is required at link time.
/// Signature: https://github.com/asmvik/yabai/blob/master/src/misc/extern.h
private enum AXWindowIdentity {
    private typealias Query = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private static let query: Query? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: Query.self)
    }()
    static func id(_ element: AXUIElement) -> CGWindowID? {
        guard let query else { return nil }
        var id: CGWindowID = 0
        guard query(element, &id) == AXError.success.rawValue, id != 0 else { return nil }
        return id
    }
}

struct QuadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// An immutable retained CF identity, not mutable Swift UI state. Probe work only
/// reads remote attributes, on one serial queue; results cross back as Bool values.
/// AX handle attributes/timeouts are not mutated by the probe itself.
struct AXProbeTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
}

enum Access {
    private static let logger = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "AXIdentity")
    static func configureTimeouts() {
        // Bound IPC waits in this process when a source app is busy or hung.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2)
    }
    static var trusted: Bool { AXIsProcessTrusted() }
    static func windowID(_ element: AXUIElement) -> CGWindowID? { AXWindowIdentity.id(element) }
    static func isFocusedWindow(_ element: AXUIElement, pid: pid_t) -> Bool {
        if (value(element, kAXFocusedAttribute) as? Bool) == true { return true }
        guard let focused = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return false }
        if CFEqual(focused, element) { return true }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID(), let id = windowID(element) else { return false }
        return windowID(focused as! AXUIElement) == id
    }
    static func noteGeometryCapabilities(_ element: AXUIElement, windowID: CGWindowID) {
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
            if status != .success || !settable.boolValue {
                logger.notice("Geometry capability advisory window=\(windowID) attribute=\(attribute, privacy: .public) status=\(status.rawValue) settable=\(settable.boolValue); verifying actual frame instead")
            }
        }
    }
    static func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    static func title(_ window: AXUIElement) -> String { value(window, kAXTitleAttribute) as? String ?? "" }
    static func windows(pid: pid_t) -> [AXUIElement] {
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &result)
        var windows: [AXUIElement] = []
        if let result, CFGetTypeID(result) == CFArrayGetTypeID() {
            let array = result as! CFArray
            for index in 0..<CFArrayGetCount(array) {
                guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
                let object = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
                if CFGetTypeID(object) == AXUIElementGetTypeID() { windows.append(object as! AXUIElement) }
            }
        }
        if status != .success || windows.isEmpty {
            logger.error("AXWindows pid=\(pid) status=\(status.rawValue) count=\(windows.count)")
        }
        return windows
    }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func find(pid: pid_t, title: String, frame: CGRect, windowID: CGWindowID? = nil) throws -> AXUIElement {
        let candidates = windows(pid: pid).map { element -> (AXUIElement, IdentifiedWindowDescriptor) in
            let frame = self.frame(element) ?? .zero
            return (element, IdentifiedWindowDescriptor(windowID: AXWindowIdentity.id(element),
                window: WindowDescriptor(title: self.title(element), frame: frame)))
        }
        let expected = WindowDescriptor(title: title, frame: frame)
        let match: Int?
        if let windowID {
            match = WindowMatcher.bestMatch(windowID: windowID, expected: expected, candidates: candidates.map(\.1))
        } else {
            match = WindowMatcher.bestMatch(for: expected, candidates: candidates.map { $0.1.window })
        }
        guard let index = match else {
            let details = candidates.map { "id=\($0.1.windowID ?? 0) frame=\($0.1.window.frame)" }.joined(separator: "; ")
            logger.error("AX lookup rejected pid=\(pid) window=\(windowID ?? 0) candidates=[\(details, privacy: .public)]")
            throw QuadError("「\(title)」の操作対象を特定できません。同じ名前・位置のウィンドウを移動して再読込してください。")
        }
        return candidates[index].0
    }
    static func setFrame(_ window: AXUIElement, _ frame: CGRect, windowID: CGWindowID, pid: pid_t, tolerance: CGFloat = 3) async throws {
        var window = window
        var point = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimension = AXValueCreate(.cgSize, &size) else {
            throw QuadError("ウィンドウの位置・サイズを作成できません。")
        }
        func matches(_ actual: CGRect) -> Bool {
            abs(actual.minX - frame.minX) < tolerance && abs(actual.minY - frame.minY) < tolerance
                && abs(actual.width - frame.width) < tolerance && abs(actual.height - frame.height) < tolerance
        }
        // AX may return cannotComplete even though its asynchronous mutation was
        // applied. WindowServer geometry, not the IPC return code, decides success.
        func positionMatches(_ actual: CGRect) -> Bool {
            abs(actual.minX - frame.minX) < tolerance && abs(actual.minY - frame.minY) < tolerance
        }
        func sizeMatches(_ actual: CGRect) -> Bool {
            abs(actual.width - frame.width) < tolerance && abs(actual.height - frame.height) < tolerance
        }
        func actualFrame() throws -> CGRect {
            guard let actual = currentWindow(windowID, pid: pid) else { throw QuadError("元のウィンドウが閉じられています。") }
            return actual
        }
        func waitFor(_ predicate: (CGRect) -> Bool) async throws {
            for _ in 0..<20 {
                if predicate(try actualFrame()) { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        var positionStatus = AXError.success, sizeStatus = AXError.success
        func move() async throws {
            if positionMatches(try actualFrame()) { return }
            positionStatus = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            try await waitFor(positionMatches)
        }
        func resize() async throws {
            if sizeMatches(try actualFrame()) { return }
            sizeStatus = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension)
            try await waitFor(sizeMatches)
        }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            if matches(try actualFrame()) { return }
            if attempt > 0 {
                let current = try actualFrame()
                // A stale AX reference or capability response must not require
                // manual reselection. Reacquire only the same WindowServer id.
                window = try find(pid: pid, title: title(window), frame: current, windowID: windowID)
                focus(window, pid: pid)
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let before = try actualFrame()
            if matches(before) { return }
            // A growing window must reach its destination before resizing;
            // otherwise AppKit can clamp its size against an animated origin.
            // Shrink first when restoring a smaller window to a distant origin.
            if frame.width <= before.width && frame.height <= before.height {
                try await resize()
                try await move()
            } else {
                try await move()
                try await resize()
                try await move()
            }
            if matches(try actualFrame()) { return }
        }
        throw QuadError("元のウィンドウが指定の位置・サイズへ反映されませんでした（AX位置: \(positionStatus.rawValue)／サイズ: \(sizeStatus.rawValue)）。元アプリの応答とサイズ制限を確認し、再試行してください。")
    }
    static func focus(_ window: AXUIElement, pid: pid_t) {
        if let target = NSRunningApplication(processIdentifier: pid) {
            if target.isHidden { target.unhide() }
            if NSApp.isActive { NSApp.yieldActivation(to: target) }
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
}

struct Candidate {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
    var label: String { "\(appName) — \(title.isEmpty ? "名称なし" : title)" }
}

/// Recheck the WindowServer id before using a retained accessibility reference.
func currentWindowInfo(_ id: CGWindowID, pid: pid_t) -> (frame: CGRect, title: String)? {
    guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
          let info = list.first,
          (info[kCGWindowOwnerPID as String] as? Int32) == pid,
          let bounds = info[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
    return (frame, info[kCGWindowName as String] as? String ?? "")
}

func currentWindow(_ id: CGWindowID, pid: pid_t) -> CGRect? { currentWindowInfo(id, pid: pid)?.frame }

final class SourceWindow {
    let candidate: Candidate
    var element: AXUIElement
    let saved: SavedWindow
    var frame: CGRect
    init(_ candidate: Candidate) throws {
        self.candidate = candidate
        element = try Access.find(pid: candidate.pid, title: candidate.title, frame: candidate.frame, windowID: candidate.id)
        // Capability metadata can be unavailable during activation. Decide from
        // the bounded, observed frame application rather than this advisory.
        Access.noteGeometryCapabilities(element, windowID: candidate.id)
        if (Access.value(element, kAXMinimizedAttribute) as? Bool) == true
            || (Access.value(element, "AXFullScreen") as? Bool) == true {
            throw QuadError("「\(candidate.title)」の最小化・フルスクリーンを解除してください。")
        }
        guard let app = NSRunningApplication(processIdentifier: candidate.pid), let launch = app.launchDate,
              let original = Access.frame(element) else { throw QuadError("元のウィンドウ状態を取得できません。") }
        frame = original
        saved = SavedWindow(windowID: candidate.id, processID: candidate.pid, bundleID: app.bundleIdentifier ?? "",
                            launchDate: launch, title: candidate.title, originalFrame: original)
    }
    var isAlive: Bool { currentWindow(candidate.id, pid: candidate.pid) != nil }
    func refreshAccessibility() throws {
        guard let app = NSRunningApplication(processIdentifier: saved.processID),
              app.launchDate == saved.launchDate, app.bundleIdentifier == saved.bundleID else {
            throw QuadError("選んだアプリが終了または再起動されています。")
        }
        guard let current = currentWindowInfo(candidate.id, pid: candidate.pid) else {
            throw QuadError("選んだウィンドウが閉じられています。")
        }
        // App-level AXWindows may temporarily be empty during activation. The
        // retained reference is safe only while its exact window id still matches.
        if Access.windowID(element) == candidate.id, Access.frame(element) != nil { return }
        element = try Access.find(pid: candidate.pid, title: current.title, frame: current.frame, windowID: candidate.id)
    }
    var isInputForeground: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == candidate.pid
            && NSRunningApplication(processIdentifier: candidate.pid)?.isActive == true
    }
    func refreshFrame() -> Bool {
        // WindowServer owns the capture geometry. Avoid synchronous AX requests
        // on every mouse/scroll event, while still rechecking window id and pid.
        guard let actual = currentWindow(candidate.id, pid: candidate.pid) else { return false }
        frame = actual
        return true
    }
    func focus() { Access.focus(element, pid: candidate.pid) }
}
