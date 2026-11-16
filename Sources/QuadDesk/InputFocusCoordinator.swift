import AppKit
import ApplicationServices
import QuadCore
import QuadInput

enum InputFocusResult { case ready, failed, cancelled }

private final class InputFocusLease: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// A nonactivating board can receive a click while a different app stays active.
/// NSWorkspace supplies the system activation context even when the board itself
/// stays inactive. Input waits for the target application and window to agree.
@MainActor
final class InputFocusCoordinator {
    private let queue = DispatchQueue(label: "io.github.TRN408.QuadDesk.inputFocus", qos: .userInitiated)
    private var task: Task<Void, Never>?
    private var lease: InputFocusLease?
    private var completion: ((InputFocusResult) -> Void)?
    private var generation = 0
    var isSwitching: Bool { task != nil }

    func cancel() {
        generation += 1
        lease?.cancel(); lease = nil
        task?.cancel(); task = nil
        let callback = completion; completion = nil
        callback?(.cancelled)
    }

    func request(_ source: SourceWindow, completion: @escaping (InputFocusResult) -> Void) {
        cancel()
        guard source.isAlive, let target = NSRunningApplication(processIdentifier: source.candidate.pid) else {
            completion(.failed); return
        }
        let token = generation
        let lease = InputFocusLease()
        self.lease = lease
        self.completion = completion
        let probe = AXProbeTarget(pid: source.candidate.pid, element: source.element)
        InputDiagnostics.note("input focus request windowID=\(source.candidate.id) sourcePID=\(source.candidate.pid) hostActive=\(NSApp.isActive) targetActive=\(target.isActive) frontmostPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        // Asking our nonactivating panel to activate itself is not reliable
        // while another source app is active. Let Workspace handle the handoff
        // in the original mouse/menu action, without an intermediate host focus.
        if !isForeground(target) {
            guard let url = target.bundleURL else {
                self.lease = nil; self.completion = nil
                completion(.failed); return
            }
            if target.isHidden { target.unhide() }
            if NSApp.isActive { NSApp.yieldActivation(to: target) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                InputDiagnostics.note("input workspace activation accepted=\(error == nil && application?.processIdentifier == probe.pid)")
            }
        }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.handoff(target, probe: probe, lease: lease)
            guard self.generation == token, !lease.isCancelled else { return }
            self.task = nil; self.lease = nil
            let callback = self.completion; self.completion = nil
            callback?(outcome)
        }
    }

    private func handoff(_ target: NSRunningApplication, probe: AXProbeTarget,
                         lease: InputFocusLease) async -> InputFocusResult {
        if !isForeground(target) {
            guard await waitFor(1.5, lease: lease, condition: { self.isForeground(target) }) else {
                InputDiagnostics.note("input target activation not confirmed")
                return .failed
            }
        }
        guard !lease.isCancelled else { return .cancelled }
        await raise(probe, lease: lease)
        let deadline = ProcessInfo.processInfo.systemUptime + 1.2
        repeat {
            guard !lease.isCancelled, !target.isTerminated else { return .cancelled }
            let matches = await focused(probe, lease: lease)
            if matches, isForeground(target) {
                InputDiagnostics.note("input focus confirmed")
                return .ready
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        InputDiagnostics.note("input focus confirmation timed out")
        return .failed
    }

    private func isForeground(_ target: NSRunningApplication) -> Bool {
        target.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    private func waitFor(_ seconds: TimeInterval, lease: InputFocusLease, condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            guard !lease.isCancelled, !Task.isCancelled else { return false }
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    private func raise(_ target: AXProbeTarget, lease: InputFocusLease) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if !lease.isCancelled {
                    AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                }
                if !lease.isCancelled { AXUIElementPerformAction(target.element, kAXRaiseAction as CFString) }
                if !lease.isCancelled {
                    // An app can be active and report this as its AX window
                    // while Electron's actual key window still has no focus.
                    let application = AXUIElementCreateApplication(target.pid)
                    AXUIElementSetMessagingTimeout(application, 1)
                    let appStatus = AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, target.element)
                    let windowStatus = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    InputDiagnostics.note("input window focus requested applicationAX=\(appStatus.rawValue) windowAX=\(windowStatus.rawValue)")
                }
                continuation.resume()
            }
        }
    }

    private func focused(_ target: AXProbeTarget, lease: InputFocusLease) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !lease.isCancelled else { continuation.resume(returning: false); return }
                let application = AXUIElementCreateApplication(target.pid)
                AXUIElementSetMessagingTimeout(application, 1)
                let focused = Access.value(application, kAXFocusedWindowAttribute)
                let matches = focused.map { CFEqual($0, target.element) } == true
                if matches {
                    let windowFocused = Access.value(target.element, kAXFocusedAttribute) as? Bool
                    let hasFocusedElement = Access.value(application, kAXFocusedUIElementAttribute) != nil
                    InputDiagnostics.note("input focus AXwindow=\(windowFocused.map { String($0) } ?? "unsupported") elementPresent=\(hasFocusedElement)")
                }
                continuation.resume(returning: matches)
            }
        }
    }
}
