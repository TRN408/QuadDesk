import XCTest
@testable import QuadCore

final class MobileBrowserTests: XCTestCase {
    func testAddressesUseHTTPSAndKeepPathsQueriesAndFragments() {
        XCTAssertEqual(BrowserAddress.resolve(" example.com/a?q=b#c ")?.absoluteString, "https://example.com/a?q=b#c")
        XCTAssertEqual(BrowserAddress.resolve("http://localhost:8080/probe")?.host, "localhost")
        XCTAssertEqual(BrowserAddress.resolve("https://例え.jp")?.scheme, "https")
        XCTAssertEqual(BrowserAddress.resolve("http://[::1]:8080")?.port, 8080)
    }
    func testRejectsScriptsLocalFilesCredentialsAndNonURLs() {
        for input in ["", "some search words", "javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "ftp://example.com", "https://", "https://user:secret@example.com", "https://example.com\n/x"] {
            XCTAssertNil(BrowserAddress.resolve(input), input)
        }
    }
    func testMobileWidthsAndDesktopAreDistinct() {
        XCTAssertEqual(MobileViewport.allCases.filter(\.isMobile).map(\.rawValue), [320, 390, 430])
        XCTAssertFalse(MobileViewport.desktop.isMobile)
        XCTAssertFalse(BrowserAddress.allowsNavigation(to: URL(string: "x-custom:open")!))
        XCTAssertTrue(BrowserAddress.allowsNavigation(to: URL(string: "about:blank")!))
        let inline = URL(string: "data:text/html,inline")!
        XCTAssertFalse(BrowserAddress.allowsNavigation(to: inline))
        XCTAssertTrue(BrowserAddress.allowsNavigation(to: inline, isMainFrame: false))
        XCTAssertTrue(BrowserAddress.allowsNavigation(to: URL(string: "about:srcdoc")!, isMainFrame: false))
    }
}
