import AppKit
import WebKit
import QuadCore

private final class BrowserChromeCanvas: NSView {
    override var isFlipped: Bool { true }
}

/// Native chrome is transformed; WebKit is a sibling at the actual display
/// size. Native pageZoom keeps its CSS viewport while avoiding a full-size
/// Retina web surface that would subsequently be downsampled.
@MainActor
final class ScaledBrowserTile: NSView {
    let pane: MobileBrowserPane
    private let chrome = BrowserChromeCanvas()
    private var lastFrame: CGRect?
    private var lastViewport: Int?
    private(set) var placementCount = 0
    override var isFlipped: Bool { true }

    init(pane: MobileBrowserPane) {
        self.pane = pane
        super.init(frame: .zero)
        pane.translatesAutoresizingMaskIntoConstraints = true
        pane.autoresizingMask = []
        addSubview(chrome); chrome.addSubview(pane)
        pane.onWebViewCreated = { [weak self] view in
            guard let self else { return }
            view.autoresizingMask = []
            self.addSubview(view)
            self.placeWebContent()
        }
        pane.onContentLayout = { [weak self] in self?.placeWebContent() }
        if let view = pane.activeWebView { addSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("Use init(pane:)") }

    func place(in frame: CGRect) {
        let width = pane.viewport.rawValue
        guard lastFrame != frame || lastViewport != width else { return }
        lastFrame = frame; lastViewport = width; placementCount += 1
        self.frame = frame
        chrome.frame = bounds
        let logical = CGSize(width: CGFloat(width), height: CGFloat(width) * BrowserGridPlan.referenceSize.height / BrowserGridPlan.referenceSize.width)
        chrome.setBoundsSize(logical)
        pane.frame = CGRect(origin: .zero, size: logical)
        pane.needsLayout = true
        pane.layoutSubtreeIfNeeded()
        placeWebContent()
    }

    private func placeWebContent() {
        guard let view = pane.activeWebView, bounds.width > 0 else { return }
        let displayed = pane.webContentSlot.convert(pane.webContentSlot.bounds, to: self)
        guard displayed.width > 0, displayed.height > 0 else { return }
        let zoom = displayed.width / CGFloat(pane.viewport.rawValue)
        // Redundant assignments can cause sixteen remote page layout/paint
        // commits even when no window or viewport geometry changed.
        if view.frame != displayed { view.frame = displayed }
        if abs(view.pageZoom - zoom) > 0.000001 { view.pageZoom = zoom }
    }
}

@MainActor
final class MobileBrowserGridView: NSView {
    override var isFlipped: Bool { true }
    private(set) var tiles: [ScaledBrowserTile] = []
    var mode: BrowserGridMode = .twoRows { didSet { if oldValue != mode { needsLayout = true } } }
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
