import AppKit
import AVFoundation
import QuadCore
import QuadInput

/// Never steals keyboard focus: the real app receives keyboard events and handles its own IME.
final class DeskPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TileView: NSView {
    private struct BufferedInput {
        let event: CGEvent
        let localPoint: CGPoint
    }
    let source: SourceWindow
    let video = AVSampleBufferDisplayLayer()
    let statusLabel = NSTextField(labelWithString: "接続中…")
    var onSelect: ((TileView, @escaping (InputFocusResult) -> Void) -> Void)?
    private var tracking: NSTrackingArea?
    private var heldButtons: Set<Int> = []
    private var postedButtons: Set<Int> = []
    private var lastPoint: CGPoint?
    private var hasFrame = false
    private var failed = false
    private let capturedSize: CGSize
    private var pendingEvents: [BufferedInput] = []
    private var deliveryGeneration = 0
    private var focusPending = false
    private var focusReady = false
    private var focusMessage: String?
    private var lastGeometryRefresh: TimeInterval = 0
    private var lastHover: TimeInterval = 0
    private(set) var displayDrops = 0
    private(set) var presentedFrames = 0
    private var pendingDisplay: CMSampleBuffer?
    private var requestingDisplay = false
    private var displayGeneration = 0
    var inputEnabled = false
    var selected = false {
        didSet {
            if !selected {
                focusReady = false
                if oldValue { releaseButtons() }
            }
            updateBorder()
        }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var viewport: CGRect { bounds }

    init(source: SourceWindow, slot: Int) {
        self.source = source
        capturedSize = source.frame.size
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        setAccessibilityLabel("\(slot + 1)  \(source.candidate.appName) · \(source.candidate.title)")
        video.videoGravity = .resizeAspect
        video.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(video)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        addSubview(statusLabel)
        updateBorder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        statusLabel.frame = CGRect(x: 20, y: bounds.midY - 28, width: max(0, bounds.width - 40), height: 56)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        video.frame = viewport
        CATransaction.commit()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: viewport, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    func show(_ sample: CMSampleBuffer) {
        guard !failed else { return }
        if video.status == .failed { video.flush() }
        // Bound the display backlog to one latest frame, including when a static
        // source has no subsequent update to replace a frame dropped under load.
        if pendingDisplay != nil { displayDrops += 1 }
        pendingDisplay = sample
        if !requestingDisplay, video.isReadyForMoreMediaData { presentLatest(); return }
        guard !requestingDisplay else { return }
        requestingDisplay = true
        let generation = displayGeneration
        video.requestMediaDataWhenReady(on: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.displayGeneration, self.requestingDisplay,
                      !self.failed, self.video.isReadyForMoreMediaData else { return }
                self.video.stopRequestingMediaData()
                self.requestingDisplay = false
                self.presentLatest()
            }
        }
    }
    private func presentLatest() {
        guard let sample = pendingDisplay else { return }
        pendingDisplay = nil
        video.enqueue(sample)
        presentedFrames += 1
        hasFrame = true
        inputEnabled = true
        updateFocusMessage()
    }
    func fail(_ message: String) {
        stopRendering()
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }
    func stopRendering() {
        releaseButtons()
        failed = true
        inputEnabled = false
        displayGeneration += 1
        video.stopRequestingMediaData()
        requestingDisplay = false
        pendingDisplay = nil
        video.flushAndRemoveImage()
    }
    private func updateBorder() {
        layer?.borderWidth = selected ? 1 / (window?.backingScaleFactor ?? 2) : 0
        layer?.borderColor = NSColor.systemTeal.cgColor
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateBorder() }

    private func mapped(_ event: NSEvent, clamp: Bool = false, localPoint: CGPoint? = nil) -> CGPoint? {
        guard inputEnabled, hasFrame, Access.trusted else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        let hover = event.type == .mouseMoved
        let continuingScroll = event.type == .scrollWheel && (event.phase == .changed || event.momentumPhase == .changed)
        if !(hover || continuingScroll) || now - lastGeometryRefresh >= 0.25 {
            guard source.refreshFrame() else { return nil }
            lastGeometryRefresh = now
        }
        guard abs(source.frame.width - capturedSize.width) < 2, abs(source.frame.height - capturedSize.height) < 2 else {
            fail("元のウィンドウのサイズが変わりました。\n停止して、もう一度開始してください。")
            return nil
        }
        return Projection.sourcePoint(localPoint ?? convert(event.locationInWindow, from: nil), source: source.frame, viewport: viewport, clamp: clamp)
    }
    private func decorate(_ event: CGEvent, point: CGPoint) -> Bool {
        WindowEvents.stamp(event, point: point, frame: source.frame, windowID: source.candidate.id, pid: source.candidate.pid)
    }
    func requestInputFocus() {
        guard !failed, !focusPending else { return }
        deliveryGeneration += 1
        let generation = deliveryGeneration
        focusPending = true; focusReady = false
        focusMessage = "入力先を切り替え中…"
        updateFocusMessage()
        guard let onSelect else { finishInputFocus(.failed, generation: generation); return }
        onSelect(self) { [weak self] result in self?.finishInputFocus(result, generation: generation) }
    }
    private func finishInputFocus(_ result: InputFocusResult, generation: Int) {
        guard deliveryGeneration == generation, !failed else { return }
        focusPending = false
        switch result {
        case .ready:
            focusReady = true; focusMessage = nil
            guard inputEnabled, Access.trusted, source.isInputForeground, source.refreshFrame() else {
                pendingEvents.removeAll(); focusReady = false; updateFocusMessage(); return
            }
            guard abs(source.frame.width - capturedSize.width) < 2, abs(source.frame.height - capturedSize.height) < 2 else {
                fail("元のウィンドウのサイズが変わりました。\n停止して、もう一度開始してください。")
                return
            }
            let events = pendingEvents; pendingEvents.removeAll()
            // Activation/Stage Manager may move a window while input waits.
            // Rebase against its confirmed frame, keeping the clicked local point.
            for input in events {
                let point = CGPoint(x: source.frame.minX + input.localPoint.x, y: source.frame.minY + input.localPoint.y)
                guard decorate(input.event, point: point) else {
                    fail("入力座標を確認できません。元画面へ切り替えてください。")
                    return
                }
                post(input.event)
            }
        case .failed:
            releaseButtons()
            focusMessage = "入力先を切り替えられませんでした。\n再度クリックするか、「…」から元画面へ切り替えてください。"
        case .cancelled:
            releaseButtons(); focusMessage = nil
        }
        updateFocusMessage()
    }
    private func updateFocusMessage() {
        if let focusMessage { statusLabel.stringValue = focusMessage }
        statusLabel.isHidden = hasFrame && focusMessage == nil
    }
    private func post(_ event: CGEvent) {
        guard source.isInputForeground else { return }
        // A newly selected web content view has not seen this pointer yet.
        // Prime its hit testing before the first click/scroll, after focus and
        // geometry have been confirmed. Never synthesize an extra click.
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        if down || (event.type == .scrollWheel && lastPoint != event.location) {
            guard let move = WindowEvents.mouse(type: .mouseMoved, point: event.location, frame: source.frame,
                windowID: source.candidate.id, pid: source.candidate.pid, button: 0, clickCount: 0,
                flags: event.flags) else { fail("マウス位置を転送できません。元画面で操作してください。"); return }
            move.timestamp = event.timestamp
            guard WindowEvents.post(move, to: source.candidate.pid) else {
                fail("入力転送方式を利用できません。元画面で操作してください。"); return
            }
        }
        lastPoint = event.location
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { postedButtons.insert(button) }
        if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) {
            guard postedButtons.remove(button) != nil else { return }
        }
        if !WindowEvents.post(event, to: source.candidate.pid) {
            fail("入力を転送できません。元画面で操作してください。")
            return
        }
        if event.type != .mouseMoved {
            InputDiagnostics.note("queued type=\(event.type.rawValue) windowID=\(source.candidate.id)")
        }
    }
    private func deliver(_ event: CGEvent) {
        if focusPending {
            guard pendingEvents.count < 512 else {
                releaseButtons()
                focusMessage = "入力先の切り替え待ちが長いため入力を中止しました。再度クリックしてください。"
                updateFocusMessage(); return
            }
            pendingEvents.append(BufferedInput(event: event,
                localPoint: CGPoint(x: event.location.x - source.frame.minX, y: event.location.y - source.frame.minY)))
        } else if focusReady { post(event) }
    }
    private func sendMouse(_ event: NSEvent, type: NSEvent.EventType, clamp: Bool = false, localPoint: CGPoint? = nil) {
        guard localPoint != nil else {
            if type != .mouseMoved { InputDiagnostics.note("uncaptured panel pointer type=\(type.rawValue)") }
            return
        }
        if type != .mouseMoved {
            InputDiagnostics.note("receive type=\(type.rawValue) view=\(convert(event.locationInWindow, from: nil)) viewport=\(viewport) frame=\(source.frame)")
        }
        guard let point = mapped(event, clamp: clamp, localPoint: localPoint) else { return }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            requestInputFocus()
            heldButtons.insert(event.buttonNumber)
        }
        let local = CGPoint(x: point.x - source.frame.minX, y: source.frame.maxY - point.y)
        guard let cgType = CGEventType(rawValue: UInt32(type.rawValue)),
              let cg = WindowEvents.mouse(type: cgType, point: point, frame: source.frame,
                                          windowID: source.candidate.id, pid: source.candidate.pid,
                                          button: event.buttonNumber, clickCount: event.clickCount,
                                          flags: event.cgEvent?.flags ?? []) else {
            fail("このmacOSでウィンドウ入力を構成できません。元画面で操作してください。"); return
        }
        if type != .mouseMoved { InputDiagnostics.note("forward type=\(cg.type.rawValue) global=\(point) local=\(local) source=\(source.frame)") }
        deliver(cg)
        lastPoint = point
        if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type) { heldButtons.remove(event.buttonNumber) }
    }
    override func mouseDown(with event: NSEvent) { sendMouse(event, type: .leftMouseDown) }
    override func mouseUp(with event: NSEvent) { sendMouse(event, type: .leftMouseUp, clamp: !heldButtons.isEmpty) }
    override func mouseDragged(with event: NSEvent) { sendMouse(event, type: .leftMouseDragged, clamp: true) }
    override func rightMouseDown(with event: NSEvent) { sendMouse(event, type: .rightMouseDown) }
    override func rightMouseUp(with event: NSEvent) { sendMouse(event, type: .rightMouseUp, clamp: !heldButtons.isEmpty) }
    override func rightMouseDragged(with event: NSEvent) { sendMouse(event, type: .rightMouseDragged, clamp: true) }
    override func otherMouseDown(with event: NSEvent) { sendMouse(event, type: .otherMouseDown) }
    override func otherMouseUp(with event: NSEvent) { sendMouse(event, type: .otherMouseUp, clamp: !heldButtons.isEmpty) }
    override func otherMouseDragged(with event: NSEvent) { sendMouse(event, type: .otherMouseDragged, clamp: true) }
    override func mouseMoved(with event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        guard selected, focusReady, source.isInputForeground, now - lastHover >= 1.0 / 24 else { return }
        lastHover = now
        sendMouse(event, type: .mouseMoved)
    }
    override func scrollWheel(with event: NSEvent) { sendScroll(event) }
    private func sendScroll(_ event: NSEvent, localPoint: CGPoint? = nil) {
        guard localPoint != nil else { InputDiagnostics.note("uncaptured panel scroll"); return }
        guard let point = mapped(event, localPoint: localPoint), let cg = event.cgEvent?.copy() else { return }
        let needsFocus = !selected || !focusReady || !source.isInputForeground
        if needsFocus { requestInputFocus() }
        guard decorate(cg, point: point) else { return }
        // Keep trackpad pixel deltas, natural direction, and momentum phases unchanged.
        deliver(cg)
    }
    // Called after the session tap has consumed the original pointer event.
    // Use its explicit pane coordinates; NSEvent.window can refer to another app.
    func capturedPointer(_ raw: CGEvent, localPoint: CGPoint) {
        guard let event = NSEvent(cgEvent: raw) else { return }
        if raw.type == .scrollWheel { sendScroll(event, localPoint: localPoint); return }
        if raw.type == .mouseMoved {
            guard selected, focusReady, source.isInputForeground else { return }
        }
        let clamp = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                     .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(raw.type)
        sendMouse(event, type: event.type, clamp: clamp, localPoint: localPoint)
    }
    func releaseButtons() {
        deliveryGeneration += 1
        if focusPending { focusMessage = nil }
        focusPending = false; focusReady = false
        if !failed { updateFocusMessage() }
        pendingEvents.removeAll()
        guard let point = lastPoint, !postedButtons.isEmpty, source.isAlive else {
            heldButtons.removeAll(); postedButtons.removeAll(); return
        }
        for button in postedButtons {
            let type: CGEventType = button == 0 ? .leftMouseUp : (button == 1 ? .rightMouseUp : .otherMouseUp)
            if let event = WindowEvents.mouse(type: type, point: point, frame: source.frame,
                windowID: source.candidate.id, pid: source.candidate.pid,
                button: button, clickCount: 1, flags: []) {
                WindowEvents.post(event, to: source.candidate.pid)
            }
        }
        heldButtons.removeAll()
        postedButtons.removeAll()
    }
}

final class BoardView: NSView {
    var tiles: [TileView] = []
    var slotIndices: [Int] = []
    var emptySlots: [Int: EmptySlot] = [:]
    private let controls = NSButton()
    private let controlsMenu: NSMenu
    var onMenuTracking: ((Bool) -> Void)?
    var controlsRect: CGRect { controls.frame }
    override var isFlipped: Bool { true }
    init(menu: NSMenu) {
        controlsMenu = menu
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1).cgColor
        controls.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "QuadDesk 操作")
        controls.imagePosition = .imageOnly
        controls.isBordered = false
        controls.contentTintColor = .white
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        controls.layer?.cornerRadius = 11
        controls.toolTip = "QuadDesk 操作（元画面・停止）"
        controls.setAccessibilityLabel("QuadDesk 操作")
        controls.target = self
        controls.action = #selector(showControls)
        addSubview(controls)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let width = bounds.width / 2
        let height = bounds.height / 2
        func rect(_ index: Int) -> CGRect {
            CGRect(x: CGFloat(index % 2) * width,
                   y: CGFloat(index / 2) * height, width: width, height: height)
        }
        for (index, tile) in tiles.enumerated() { tile.frame = rect(slotIndices.indices.contains(index) ? slotIndices[index] : index) }
        for (index, empty) in emptySlots { empty.frame = rect(index) }
        controls.frame = CGRect(x: bounds.midX - 11, y: bounds.midY - 11, width: 22, height: 22)
    }
    @objc func showControls() {
        onMenuTracking?(true)
        defer { onMenuTracking?(false) }
        controlsMenu.popUp(positioning: nil, at: CGPoint(x: controls.frame.minX, y: controls.frame.maxY), in: self)
    }
}
