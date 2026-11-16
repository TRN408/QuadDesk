import Foundation

public struct CaptureFailure: LocalizedError, Equatable {
    public enum Kind: String { case userStopped, systemStopped, permissionDenied, other }
    public static let streamErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
    public let domain: String
    public let code: Int
    public let message: String
    public let isSimulation: Bool

    public init(domain: String, code: Int, message: String, isSimulation: Bool = false) {
        self.domain = domain; self.code = code; self.message = message; self.isSimulation = isSimulation
    }
    public init(error: Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code, message: error.localizedDescription)
    }
    public var kind: Kind {
        guard domain == Self.streamErrorDomain else { return .other }
        switch code {
        case -3817: return .userStopped
        case -3821: return .systemStopped
        case -3801: return .permissionDenied
        default: return .other
        }
    }
    public var title: String {
        if isSimulation { return "動作検証のため収録停止を模擬しました。" }
        switch kind {
        case .userStopped: return "画面収録が停止されました。"
        case .systemStopped: return "macOS側で画面収録が停止しました。"
        case .permissionDenied: return "画面収録の許可を確認できませんでした。"
        case .other: return "映像の取得が停止しました。"
        }
    }
    public var guidance: String {
        switch kind {
        case .systemStopped: return "空きディスク容量やメモリ状況を確認してから、もう一度開始してください。"
        case .permissionDenied: return "システム設定でQuadDeskの画面収録の許可を確認してください。"
        case .userStopped: return "再開するときは「4画面を開始」を押してください。"
        case .other: return "対象のアプリを確認してから、もう一度開始してください。"
        }
    }
    public var errorDescription: String? { title + "\n" + guidance }
}

/// Coalesce a multi-stream failure and reject callbacks from a previous session.
/// A failure never starts a new session; only an explicit begin can do so.
public struct CaptureLifecycle {
    public private(set) var session: UUID?
    public private(set) var failure: CaptureFailure?
    public init() {}
    @discardableResult public mutating func begin() -> UUID {
        let id = UUID()
        session = id; failure = nil
        return id
    }
    public mutating func accept(_ error: CaptureFailure, from id: UUID) -> Bool {
        guard session == id, failure == nil else { return false }
        failure = error
        return true
    }
    public mutating func finish() { session = nil; failure = nil }
}
