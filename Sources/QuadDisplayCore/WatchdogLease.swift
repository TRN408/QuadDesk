import Foundation
import Darwin

public func configureHeartbeatPipe(_ descriptor: Int32) throws {
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0,
          fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
        throw DisplayFailure("復帰監視の接続を準備できません。表示は変更しません。")
    }
}

/// A preview has two bounded phases: preparation, then a single visible period.
/// Heartbeats never extend previews. Work sessions must keep proving that their
/// owner's main run loop is responsive.
public struct WatchdogLease {
    public enum Mode { case preview, work }
    public let mode: Mode
    private let started: TimeInterval
    private var lastHeartbeat: TimeInterval?
    private var previewVisible: TimeInterval?
    public static let heartbeatTimeout: TimeInterval = 10
    public init(mode: Mode, started: TimeInterval) { self.mode = mode; self.started = started }
    /// False asks the watchdog to restore immediately; unknown input fails closed.
    public mutating func receive(_ line: String, at time: TimeInterval) -> Bool {
        guard !expired(at: time) else { return false }
        switch mode {
        case .preview:
            guard line == "VISIBLE", previewVisible == nil else { return false }
            previewVisible = time
            return true
        case .work:
            guard line == "PING" else { return false }
            lastHeartbeat = time
            return true
        }
    }
    public func expired(at time: TimeInterval) -> Bool {
        if let lastHeartbeat { return time-lastHeartbeat >= Self.heartbeatTimeout }
        if let previewVisible { return time-previewVisible >= NativePreviewPlan.watchdogSeconds }
        return time-started >= NativePreviewPlan.watchdogSeconds
    }
}
