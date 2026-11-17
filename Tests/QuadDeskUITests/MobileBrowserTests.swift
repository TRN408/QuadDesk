import AppKit
import WebKit
import XCTest
@testable import QuadDesk
import QuadCore

final class MobileBrowserUITests: XCTestCase {
    @MainActor
    func testPaneLimitRemovalAndIsolatedTestingStore() {
        _ = NSApplication.shared
        let store = WKWebsiteDataStore.nonPersistent()
        let browser = MobileBrowserController(dataStore: store)
        for _ in 0..<6 { XCTAssertNotNil(browser.addPane()) }
        XCTAssertNil(browser.addPane())
        XCTAssertEqual(browser.columns.arrangedSubviews.count, 6)
        XCTAssertTrue(browser.panes.allSatisfy { $0.webView.configuration.websiteDataStore === store })
        let removed = browser.panes[0]
        browser.removePane(removed)
        XCTAssertNil(removed.webView.navigationDelegate)
        XCTAssertNil(removed.webView.superview)
        XCTAssertNotNil(browser.addPane())
        browser.close()
        XCTAssertTrue(browser.panes.isEmpty)
        XCTAssertTrue(browser.columns.arrangedSubviews.isEmpty)
    }

    @MainActor
    func testTwoLivePagesAtMobileWidthsWithIndependentContentAndSharedCookies() async throws {
        _ = NSApplication.shared
        let browser = MobileBrowserController(dataStore: .nonPersistent())
        let first = try XCTUnwrap(browser.addPane())
        let second = try XCTUnwrap(browser.addPane())
        defer { browser.close() }
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        // No visible window or permissions. Real WebKit processes render the pages.
        host.addSubview(browser.columns)
        browser.columns.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            browser.columns.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            browser.columns.topAnchor.constraint(equalTo: host.topAnchor),
            browser.columns.heightAnchor.constraint(equalToConstant: 680)
        ])
        first.applyViewport(.compact, reloadPage: false)
        second.applyViewport(.wide, reloadPage: false)
        host.layoutSubtreeIfNeeded()
        let html = """
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body { margin:0 } @media(max-width:350px) { body { --compact: yes } }</style>
        <input id="entry" aria-label="Probe input"><a href="about:blank" target="_blank">New</a>
        <script>window.ticks=0; setInterval(()=>window.ticks++,30);</script>
        """
        first.webView.loadHTMLString(html, baseURL: nil)
        second.webView.loadHTMLString(html, baseURL: nil)
        for _ in 0..<200 {
            let ready = (try? await first.webView.evaluateJavaScript("document.getElementById('entry') !== null")) as? Bool
            let ready2 = (try? await second.webView.evaluateJavaScript("document.getElementById('entry') !== null")) as? Bool
            if ready == true && ready2 == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(first.webView.frame.width, 320, accuracy: 1)
        XCTAssertEqual(second.webView.frame.width, 430, accuracy: 1)
        let firstWidth = try await first.webView.evaluateJavaScript("window.innerWidth") as? Int
        let secondWidth = try await second.webView.evaluateJavaScript("window.innerWidth") as? Int
        XCTAssertEqual(firstWidth, 320)
        XCTAssertEqual(secondWidth, 430)
        let responsive = try await first.webView.evaluateJavaScript("matchMedia('(max-width:350px)').matches") as? Bool
        XCTAssertEqual(responsive, true)
        let ua = try await first.webView.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertTrue(ua?.contains("iPhone") == true)
        _ = try await first.webView.evaluateJavaScript("document.getElementById('entry').value='日本語の入力'; document.getElementById('entry').value")
        let input = try await first.webView.evaluateJavaScript("document.getElementById('entry').value") as? String
        XCTAssertEqual(input, "日本語の入力")
        // Hidden test web views may throttle timers; wait for both independently.
        for _ in 0..<100 {
            let a = try await first.webView.evaluateJavaScript("window.ticks") as? Int ?? 0
            let b = try await second.webView.evaluateJavaScript("window.ticks") as? Int ?? 0
            if a > 0 && b > 0 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        for pane in [first, second] {
            let ticks = try await pane.webView.evaluateJavaScript("window.ticks") as? Int
            XCTAssertGreaterThan(try XCTUnwrap(ticks), 0)
        }
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "quaddesk.test", .path: "/", .name: "probe", .value: "shared", .secure: "TRUE"]))
        await first.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        let cookies = await second.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "probe" && $0.value == "shared" })
        first.applyViewport(.desktop, reloadPage: false)
        let desktopAgent = try await first.webView.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertFalse(try XCTUnwrap(desktopAgent).contains("iPhone"))
    }
}
