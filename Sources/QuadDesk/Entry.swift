import AppKit
import ApplicationServices

@main
struct QuadDeskMain {
@MainActor static func main() throws {
if CommandLine.arguments.contains("--diagnostics") {
    let info: [String: Any] = [
        "screenRecording": CGPreflightScreenCaptureAccess(),
        "accessibility": AXIsProcessTrusted(),
        "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
        "bundleID": Bundle.main.bundleIdentifier ?? "unbundled",
        "screens": NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] }
    ]
    let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else {
    let application = NSApplication.shared
    if CommandLine.arguments.contains("--mobile-browser") {
        let delegate = MobileBrowserApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        return
    }
    if Bundle.main.object(forInfoDictionaryKey: "QuadDeskLegacyCapture") as? Bool != true {
        let controller = NativeWindowsController()
        application.delegate = controller.host
        withExtendedLifetime(controller) { application.run() }
        return
    }
    let delegate = AppController()
    application.delegate = delegate
    application.run()
}
}
}
