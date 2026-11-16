import AppKit
import XCTest
@testable import QuadDesk
@testable import QuadNativeDisplay

final class SetupConstructionTests: XCTestCase {
    @MainActor
    func testSmallSetupViewWrapsTextAndScrollsToTheLastControl() {
        _ = NSApplication.shared
        let text = NSTextField(wrappingLabelWithString: String(repeating: "Permission setup and window restoration. ", count: 50))
        let button = NSButton(title: "Start preview", target: nil, action: nil)
        let stack = NSStackView(views: [text, button])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let scroll = SetupScrollView(stack: stack)
        scroll.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        scroll.layoutSubtreeIfNeeded()
        guard let document = scroll.documentView else { return XCTFail("Missing document") }
        XCTAssertEqual(document.frame.width, scroll.contentView.bounds.width, accuracy: 1)
        XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
        XCTAssertGreaterThan(button.frame.height, 0)
        XCTAssertLessThanOrEqual(text.frame.maxX, document.frame.width - 28 + 1)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    }
    @MainActor
    func testPermissionAndSelectionControlsConstructWithoutAWindow() {
        _ = NSApplication.shared
        // Construct real controls offscreen. This catches constraints activated
        // before their views share an ancestor, without opening any window or
        // requesting permissions / changing display configuration.
        let controller = NativeWindowsController()
        let stack = NSStackView()
        controller.host.configureSources?(stack)
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let views = descendants(stack)
        let buttons = views.compactMap { $0 as? NSButton }
        XCTAssertTrue(buttons.contains { $0.title == "1. 画面収録を設定" })
        XCTAssertTrue(buttons.contains { $0.title == "2. アクセシビリティを設定" })
        XCTAssertTrue(buttons.contains { $0.title == "状態を再確認" })
        XCTAssertEqual(views.compactMap { $0 as? NSPopUpButton }.count, 4)
    }
}
