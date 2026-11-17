import AppKit
import WebKit
import XCTest

final class NativeWebRenderingTests: XCTestCase {
    @MainActor
    func testNativePageZoomPreservesCSSViewportAtDisplayResolution() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 180, height: 332), configuration: configuration)
        view.pageZoom = 180.0 / 390.0
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><div id='probe' style='width:100px;height:100px'>Zoom probe</div>", baseURL: nil)
        defer { view.stopLoading() }
        var width: Double?
        for _ in 0..<160 {
            if let ready = try? await view.evaluateJavaScript("!!document.getElementById('probe')"), ready as? Bool == true {
                width = try await view.evaluateJavaScript("window.innerWidth") as? Double
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let info = try await view.evaluateJavaScript("JSON.stringify({innerWidth,innerHeight,dpr:devicePixelRatio,media:matchMedia('(min-width:375px)').matches,rect:document.getElementById('probe').getBoundingClientRect().width})")
        print("NativeZoomProbe \(String(describing: info))")
        XCTAssertEqual(try XCTUnwrap(width), 390, accuracy: 1)
        let media = try await view.evaluateJavaScript("matchMedia('(min-width:375px)').matches") as? Bool
        XCTAssertEqual(media, true)
    }
}
