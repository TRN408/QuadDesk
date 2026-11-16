import CoreGraphics
import Foundation

public struct DisplayFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum NativePreviewPlan {
    public static let previewSeconds: TimeInterval = 15
    public static let watchdogSeconds: TimeInterval = 25
    /// Quartz coordinates: the top menu bar remains outside the four windows.
    public static func tiles(in area: CGRect) -> [CGRect] {
        let x = area.minX + floor(area.width / 2), y = area.minY + floor(area.height / 2)
        return [CGRect(x: area.minX, y: area.minY, width: x-area.minX, height: y-area.minY),
                CGRect(x: x, y: area.minY, width: area.maxX-x, height: y-area.minY),
                CGRect(x: area.minX, y: y, width: x-area.minX, height: area.maxY-y),
                CGRect(x: x, y: y, width: area.maxX-x, height: area.maxY-y)]
    }
}

public struct DisplaySnapshot {
    public let id: CGDirectDisplayID
    public let mode: CGDisplayMode

    public static func captureSingleDisplay() throws -> Self {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success, count == 1,
              ids[0] == CGMainDisplayID(), CGDisplayMirrorsDisplay(ids[0]) == kCGNullDirectDisplay,
              CGDisplayIsInMirrorSet(ids[0]) == 0, let mode = CGDisplayCopyDisplayMode(ids[0]) else {
            throw DisplayFailure("この比較版はミラーリングしていない1画面のMac専用です。表示構成は変更していません。")
        }
        return Self(id: ids[0], mode: mode)
    }
    public func restore() throws {
        guard CGDisplayIsOnline(id) != 0 else { throw DisplayFailure("元のディスプレイが接続されていません。") }
        var config: CGDisplayConfigRef?
        try checked(CGBeginDisplayConfiguration(&config), "復元の開始")
        guard let config else { throw DisplayFailure("復元設定を作成できません。") }
        do {
            try checked(CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay), "ミラーリングの解除")
            try checked(CGConfigureDisplayWithDisplayMode(config, id, mode, nil), "元の表示モードの復元")
            try checked(CGConfigureDisplayOrigin(config, id, 0, 0), "元の主画面の復元")
        } catch { CGCancelDisplayConfiguration(config); throw error }
        try checked(CGCompleteDisplayConfiguration(config, .forSession), "復元の適用")
    }
    public func verifyRestored() -> Bool {
        guard let current = CGDisplayCopyDisplayMode(id) else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success,
              count == 1, ids[0] == id else { return false }
        return CGDisplayIsInMirrorSet(id) == 0 && CGMainDisplayID() == id
            && current.ioDisplayModeID == mode.ioDisplayModeID
            && current.width == mode.width && current.height == mode.height
    }
}

public func checked(_ result: CGError, _ operation: String) throws {
    guard result == .success else { throw DisplayFailure("\(operation)に失敗しました（\(result.rawValue)）。") }
}
