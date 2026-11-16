import AppKit
import QuadNativeDisplay
import QuadVirtualDisplay
import QuadDisplayCore

@main
struct NativePreviewMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--preflight") {
            let problem = QDVirtualDisplayHandle.supportProblem()
            print("virtualDisplaySupport: \(problem.isEmpty ? "available" : problem)")
            do {
                let saved = try DisplaySnapshot.captureSingleDisplay()
                print("original: \(saved.id), mode=\(saved.mode.ioDisplayModeID), \(saved.mode.width)x\(saved.mode.height)")
                print("proposed: \(saved.mode.width * 2)x\(saved.mode.height * 2), no display changes performed")
            } catch { print("preflight: \(error.localizedDescription)") }
            return
        }
        let app = NSApplication.shared, delegate = NativeDisplayApp()
        app.delegate = delegate; app.run()
    }
}
