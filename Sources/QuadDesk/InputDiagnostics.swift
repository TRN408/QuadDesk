import AppKit
import OSLog

enum InputDiagnostics {
    private static let logger = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "InputDiagnostics")
    static func note(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: "traceInput") else { return }
        // Opt-in only. Never log keystrokes, window titles, or captured content.
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }
}
