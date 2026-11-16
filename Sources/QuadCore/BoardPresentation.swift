import Foundation

/// An explicit display intent: a visibility repair must not undo "original" or
/// "settings", and waking a session must never start screen capture on its own.
public struct BoardPresentation {
    public enum Mode: String { case setup, board, original }
    public private(set) var mode: Mode = .setup
    public private(set) var sessionRunning = false
    public var sessionActive = true
    public var displaysAwake = true
    public init() {}
    public var wantsBoard: Bool { sessionRunning && mode == .board && sessionActive && displaysAwake }
    public mutating func begin() { sessionRunning = true; mode = .board }
    public mutating func showBoard() { mode = sessionRunning ? .board : .setup }
    public mutating func showSettings() { mode = .setup }
    public mutating func showOriginal() { mode = sessionRunning ? .original : .setup }
    public mutating func end() { sessionRunning = false; mode = .setup }
}
