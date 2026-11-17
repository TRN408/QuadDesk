import AppKit
import QuadCore

/// An AppKit coordinate transform keeps both WebKit's CSS viewport and native
/// mouse/text input intact. No page zoom, screenshots or synthetic events.
@MainActor
final class ScaledBrowserTile: NSView {
    let pane: MobileBrowserPane
    override var isFlipped: Bool { true }

    init(pane: MobileBrowserPane) {
        self.pane = pane
        super.init(frame: .zero)
        // The fixed canvas must not take its height from Auto Layout's physical
        // frame. Only the outer host scales; all inner geometry stays logical.
        pane.translatesAutoresizingMaskIntoConstraints = true
        pane.autoresizingMask = []
        addSubview(pane)
    }
    required init?(coder: NSCoder) { fatalError("Use init(pane:)") }

    func place(in frame: CGRect) {
        self.frame = frame
        let width = CGFloat(pane.viewport.rawValue)
        let logical = CGSize(width: width, height: width * BrowserGridPlan.referenceSize.height / BrowserGridPlan.referenceSize.width)
        setBoundsSize(logical)
        pane.frame = CGRect(origin: .zero, size: logical)
        pane.needsLayout = true
        pane.layoutSubtreeIfNeeded()
    }
}

@MainActor
final class MobileBrowserGridView: NSView {
    override var isFlipped: Bool { true }
    private(set) var tiles: [ScaledBrowserTile] = []
    var mode: BrowserGridMode = .twoRows { didSet { needsLayout = true } }
    var onLayout: ((BrowserGridPlan) -> Void)?
    private(set) var plan = BrowserGridPlan(available: .zero, mode: .twoRows, paneCount: 0)

    func add(_ pane: MobileBrowserPane) {
        let tile = ScaledBrowserTile(pane: pane)
        tiles.append(tile); addSubview(tile); needsLayout = true
    }
    func remove(_ pane: MobileBrowserPane) {
        guard let index = tiles.firstIndex(where: { $0.pane === pane }) else { return }
        tiles.remove(at: index).removeFromSuperview(); needsLayout = true
    }
    override func layout() {
        super.layout()
        plan = BrowserGridPlan(available: bounds.size, mode: mode, paneCount: tiles.count)
        for (tile, frame) in zip(tiles, plan.frames) { tile.place(in: frame) }
        onLayout?(plan)
    }
}
