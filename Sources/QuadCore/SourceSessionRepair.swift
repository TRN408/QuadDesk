import Foundation

public enum SourceSessionRepair {
    public enum Plan: Equatable {
        case ready
        case recover([SavedWindow])
    }
    public struct ConflictingOriginals: LocalizedError {
        public var errorDescription: String? { "同じウィンドウの元配置が一致しません。復元記録を保持しました。" }
        public init() {}
    }
    private struct Identity: Hashable {
        let window: UInt32
        let process: Int32
        let bundle: String
        let launch: Date
        init(_ record: SavedWindow) {
            window = record.windowID; process = record.processID
            bundle = record.bundleID; launch = record.launchDate
        }
    }
    /// Include originals held in memory before resetting a stale session. A
    /// missing journal entry must not orphan a window that still needs restoring.
    public static func plan(stored: [SavedWindow], expected: [SavedWindow], live: [SavedWindow]) throws -> Plan {
        if stored.isEmpty && expected.isEmpty { return .ready }
        var merged: [SavedWindow] = []
        var originals: [Identity: SavedWindow] = [:]
        for record in stored + expected {
            let identity = Identity(record)
            if let previous = originals[identity] {
                guard previous.originalFrame == record.originalFrame else { throw ConflictingOriginals() }
            } else { originals[identity] = record; merged.append(record) }
        }
        if expected.count == 4, stored.count == 4, live.count == 4,
           Set(expected.map(Identity.init)).count == 4,
           expected.allSatisfy({ stored.contains($0) && live.contains($0) }) { return .ready }
        return .recover(merged)
    }
}
