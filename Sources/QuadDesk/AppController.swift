import AppKit
import Carbon
import ScreenCaptureKit
import QuadCore
import QuadInput
import OSLog

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var setup: NSWindow!
    private var board: DeskPanel?
    private let pointerCapture = PointerCapture()
    private var capturedButtons: [Int: Int] = [:]
    private var controlsTracking = false
    private var controlsPressed = false
    private var pointerGeneration = 0
    private var lastCapturedMove: TimeInterval = 0
    private var lastGlobalProbe: TimeInterval = 0
    private var statusItem: NSStatusItem!
    private var permissionLabel: NSTextField!
    private var messageLabel: NSTextField!
    private var popups: [NSPopUpButton] = []
    private var startButton: NSButton!
    private var refreshButton: NSButton!
    private var recoverButton: NSButton!
    private var candidates: [Candidate] = []
    private var sources: [SourceWindow] = []
    private var captures: [WindowCapture] = []
    private var tiles: [TileView] = []
    private var healthTimer: Timer?
    private var permissionTimer: Timer?
    private var hotKey: EventHotKeyRef?
    private var resumeHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var busy = false
    private var terminating = false
    private var selectedIndex: Int?
    private var activationObserver: NSObjectProtocol?
    private var captureLifecycle = CaptureLifecycle()
    private let captureLogger = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "CaptureLifecycle")
    private let healthLogger = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "CaptureHealth")
    private var lastHealthReport: TimeInterval = 0
    private var pressureSource: DispatchSourceMemoryPressure?
    private var memoryConstrained = false
    private var thermalObserver: NSObjectProtocol?
    private let accessibilityProbeQueue = DispatchQueue(label: "io.github.TRN408.QuadDesk.health", qos: .utility)
    private var accessibilityProbeInFlight = false
    private var selectionGeneration = 0
    private let inputFocus = InputFocusCoordinator()
    private var presentation = BoardPresentation()
    private var visibilityObservers: [NSObjectProtocol] = []
    private var boardDisplayID: NSNumber?
    private let store = RecoveryStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuadDesk/window-recovery.json"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Access.configureTimeouts()
        createMenu()
        createStatusItem()
        createSetup()
        registerEmergencyShortcut()
        installVisibilityObservers()
        pressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressureSource?.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, let event = self.pressureSource?.data else { return }
                self.memoryConstrained = !event.contains(.normal)
                self.updateCapturePriorities()
            }
        }
        pressureSource?.resume()
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateCapturePriorities() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.ensureBoardVisible(force: true)
                self?.refreshSelection()
            }
        }
        updatePermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermissions() }
        }
        setup.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CGPreflightScreenCaptureAccess() { refreshWindows() }
    }

    private func createMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "4画面に戻る（⌃⌥R）", action: #selector(resumeBoard), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "QuadDesk の設定", action: #selector(showSetup), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "停止して元の配置へ戻す", action: #selector(stopAction), keyEquivalent: "").target = self
        if UserDefaults.standard.bool(forKey: "enableCaptureFaultTest") {
            appMenu.addItem(withTitle: "診断用: 収録停止を模擬", action: #selector(simulateCaptureFailure), keyEquivalent: "").target = self
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "QuadDesk を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "QuadDesk")
        let menu = NSMenu()
        menu.addItem(withTitle: "4画面に戻る（⌃⌥R）", action: #selector(resumeBoard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "設定を表示", action: #selector(showSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "停止して元の配置へ戻す（⌃⌥Esc）", action: #selector(stopAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "QuadDesk を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func createSetup() {
        setup = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 740, height: 670), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        setup.title = "QuadDesk — 4つの作業画面"
        setup.isReleasedWhenClosed = false
        setup.center()
        setup.delegate = self
        let content = NSView()
        setup.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26)
        ])
        func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
            let view = NSTextField(wrappingLabelWithString: text)
            view.font = .systemFont(ofSize: size, weight: weight)
            view.preferredMaxLayoutWidth = 680
            return view
        }
        stack.addArrangedSubview(label("大きな作業画面を、4つ並べる。", size: 25, weight: .semibold))
        stack.addArrangedSubview(label("元のウィンドウを画面いっぱいの通常サイズに広げ、内容を縮小して表示します。枠内をクリックすると、そのアプリで入力できます。", size: 13))
        permissionLabel = label("")
        stack.addArrangedSubview(permissionLabel)
        let permissions = NSStackView(views: [
            button("画面収録を許可", #selector(requestRecording)),
            button("アクセシビリティを許可", #selector(requestAccessibility))
        ])
        permissions.spacing = 10
        stack.addArrangedSubview(permissions)
        stack.addArrangedSubview(label("表示するウィンドウ（同じデスクトップで開き、最小化・フルスクリーンを解除）", weight: .medium))
        let positions = ["左上", "右上", "左下", "右下"]
        for position in positions {
            let name = label(position)
            name.widthAnchor.constraint(equalToConstant: 42).isActive = true
            let popup = NSPopUpButton()
            popup.addItem(withTitle: "使用しない")
            popup.widthAnchor.constraint(equalToConstant: 600).isActive = true
            popups.append(popup)
            let row = NSStackView(views: [name, popup]); row.spacing = 10
            stack.addArrangedSubview(row)
        }
        refreshButton = button("ウィンドウを再読込", #selector(refreshWindows))
        startButton = button("4画面を開始", #selector(startAction))
        startButton.bezelColor = .systemTeal
        let actions = NSStackView(views: [refreshButton, startButton]); actions.spacing = 12
        stack.addArrangedSubview(actions)
        recoverButton = button("前回のウィンドウ配置を復元", #selector(recoverAction))
        stack.addArrangedSubview(recoverButton)
        let note = label("停止・終了時に元の配置へ戻します。文字も約半分の大きさになります。\n中央の「…」から元画面への切り替え・停止ができます。緊急停止：Control + Option + Esc。4画面へ戻る：Control + Option + R、またはDockのQuadDesk。")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        messageLabel = label("まず上の2つの許可を設定し、ウィンドウを再読込してください。")
        messageLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(messageLabel)
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
    private func updatePermissions() {
        guard permissionLabel != nil else { return }
        let recording = CGPreflightScreenCaptureAccess(), accessibility = Access.trusted
        permissionLabel.stringValue = "画面収録：\(recording ? "許可済み" : "未許可")    アクセシビリティ：\(accessibility ? "許可済み" : "未許可")"
        startButton.isEnabled = recording && accessibility && !busy && sources.isEmpty && !candidates.isEmpty
        refreshButton.isEnabled = recording && !busy && sources.isEmpty
        for popup in popups { popup.isEnabled = !busy && sources.isEmpty }
        let hasRecovery = FileManager.default.fileExists(atPath: store.url.path)
        recoverButton.isHidden = !hasRecovery
        recoverButton.isEnabled = accessibility && !busy && sources.isEmpty
        if !accessibility, !sources.isEmpty {
            tiles.forEach { $0.inputEnabled = false }
        }
    }
    @objc private func requestRecording() {
        if CGRequestScreenCaptureAccess() { refreshWindows() }
        else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            messageLabel.stringValue = "「QuadDesk」の画面収録を許可してください。必要ならQuadDeskを再起動して、再読込してください。"
        }
        updatePermissions()
    }
    @objc private func requestAccessibility() {
        Access.request()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        updatePermissions()
    }
    @objc private func refreshWindows() {
        guard !busy, sources.isEmpty else { return }
        busy = true; updatePermissions()
        let previous = popups.map { $0.selectedItem?.representedObject as? UInt32 }
        Task {
            defer { busy = false; updatePermissions() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                candidates = content.windows.compactMap { window in
                    guard let app = window.owningApplication, app.processID != getpid(), window.windowLayer == 0,
                          window.frame.width > 160, window.frame.height > 100 else { return nil }
                    return Candidate(id: window.windowID, pid: app.processID, appName: app.applicationName,
                                     title: window.title ?? "", frame: window.frame)
                }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                for (index, popup) in popups.enumerated() {
                    popup.removeAllItems(); popup.addItem(withTitle: "使用しない")
                    for candidate in candidates {
                        popup.addItem(withTitle: candidate.label)
                        popup.lastItem?.representedObject = candidate.id
                    }
                    if let id = previous[index], let match = candidates.firstIndex(where: { $0.id == id }) {
                        popup.selectItem(at: match + 1)
                    }
                }
                messageLabel.stringValue = "\(candidates.count)件のウィンドウが見つかりました。1〜4つを選んで開始してください。"
            } catch { report(error) }
        }
    }
    @objc private func startAction() {
        guard !busy, sources.isEmpty, Access.trusted, CGPreflightScreenCaptureAccess() else { return }
        guard WindowEvents.isSupported else {
            messageLabel.stringValue = "このmacOSでは縮小画面への入力方式に対応していません。"; return
        }
        let selections: [(Int, Candidate)] = popups.enumerated().compactMap { index, popup in
            guard let id = popup.selectedItem?.representedObject as? UInt32, let item = candidates.first(where: { $0.id == id }) else { return nil }
            return (index, item)
        }
        guard !selections.isEmpty else { messageLabel.stringValue = "少なくとも1つのウィンドウを選んでください。"; return }
        guard Set(selections.map { $0.1.id }).count == selections.count else { messageLabel.stringValue = "同じウィンドウは複数の枠に選べません。"; return }
        guard !FileManager.default.fileExists(atPath: store.url.path) else {
            messageLabel.stringValue = "前回の配置情報が残っています。先に「前回のウィンドウ配置を復元」を押してください。"; return
        }
        guard let screen = setup.screen ?? NSScreen.main, let primary = NSScreen.screens.first else { return }
        let captureSession = captureLifecycle.begin()
        busy = true; updatePermissions()
        Task {
            do {
                // Refresh immediately before matching AX references, since the user may have moved windows.
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                var resolved: [(Int, SourceWindow)] = []
                for (slot, candidate) in selections {
                    guard let live = content.windows.first(where: { $0.windowID == candidate.id }) else { throw QuadError("選択したウィンドウが閉じられています。再読込してください。") }
                    let current = Candidate(id: candidate.id, pid: candidate.pid, appName: candidate.appName,
                                            title: live.title ?? "", frame: live.frame)
                    resolved.append((slot, try SourceWindow(current)))
                }
                // Persist *all* original positions before changing the first window.
                try store.write(resolved.map { $0.1.saved })
                sources = resolved.map(\.1)
                let area = Projection.quartzRect(appKit: screen.visibleFrame, primaryScreenHeight: primary.frame.height)
                let targets = SourceLayout.frames(in: area, count: sources.count)
                for (index, source) in sources.enumerated() {
                    let target = targets[index]
                    InputDiagnostics.note("resize target=\(target)")
                    source.focus()
                    try await Task.sleep(nanoseconds: 100_000_000)
                    var enlarged = false
                    for _ in 0..<3 {
                        try await Access.setFrame(source.element, target, windowID: source.candidate.id, pid: source.candidate.pid, tolerance: 0.5)
                        try await Task.sleep(nanoseconds: 180_000_000)
                        guard source.refreshFrame() else { throw QuadError("元ウィンドウのサイズを確認できません。") }
                        InputDiagnostics.note("resize actual=\(source.frame)")
                        if abs(source.frame.width - target.width) < 0.5 && abs(source.frame.height - target.height) < 0.5 {
                            enlarged = true; break
                        }
                    }
                    guard enlarged else { throw QuadError("「\(source.candidate.title)」を通常の最大サイズへ広げられませんでした。元画面の最小化・フルスクリーン・サイズ制限を確認してください。") }
                }
                let resized = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                var slots: [Int: TileView] = [:]
                for (slot, source) in resolved {
                    guard source.refreshFrame(), let window = resized.windows.first(where: { $0.windowID == source.candidate.id }) else {
                        throw QuadError("拡大後のウィンドウを取得できません。")
                    }
                    let tile = TileView(source: source, slot: slot)
                    tile.onSelect = { [weak self] tile, completion in
                        guard let self else { completion(.cancelled); return }
                        self.select(tile, completion: completion)
                    }
                    tiles.append(tile); slots[slot] = tile
                    let capture = WindowCapture()
                    capture.onFrame = { [weak tile] frame in tile?.show(frame) }
                    capture.onError = { [weak self] failure in self?.captureDidFail(failure, session: captureSession) }
                    captures.append(capture)
                    try await capture.start(window: window, size: source.frame.size)
                    if let failure = captureLifecycle.failure { throw failure }
                }
                if let failure = captureLifecycle.failure { throw failure }
                try makeBoard(screen: screen, slots: slots)
                lastHealthReport = 0
                setup.orderOut(nil)
                // Startup resumes after asynchronous capture work, outside the
                // initiating click's activation context. Select a pane visually;
                // its first real click/scroll performs the confirmed handoff.
                if let tile = tiles.first {
                    selectedIndex = 0
                    tile.selected = true
                    updateCapturePriorities()
                }
                healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkSources() }
                }
                messageLabel.stringValue = "4画面で作業中です。終了すると配置を復元します。"
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                captureLogger.notice("Session started: version=\(version, privacy: .public) panes=\(self.captures.count) pixelFormat=420f activeFPS=24 backgroundFPS=8")
            } catch {
                let hadCaptureFailure = captureLifecycle.failure != nil
                await stop(showSettings: true)
                if !hadCaptureFailure { report(error) }
            }
            busy = false; updatePermissions()
        }
    }

    private func makeBoard(screen: NSScreen, slots: [Int: TileView]) throws {
        let panel = DeskPanel(contentRect: screen.visibleFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QuadDesk · 枠内クリックで入力先を選択 · ⌃⌥Esc で停止"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Fully opaque coverage can suspend Chromium's native painting even
        // while its DOM keeps changing. Keep native exposed corners visible.
        panel.alphaValue = 0.999
        // A nonactivating panel never becomes the active window. Follow Spaces
        // and Stage Manager app sets without relying on activation to move it.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 800, height: 500)
        panel.delegate = self
        let controlsMenu = NSMenu()
        controlsMenu.addItem(withTitle: "選択中のアプリを元画面で操作 ↗", action: #selector(showSelectedOriginal), keyEquivalent: "").target = self
        controlsMenu.addItem(withTitle: "停止して元の配置へ戻す", action: #selector(stopAction), keyEquivalent: "").target = self
        controlsMenu.addItem(withTitle: "QuadDesk の設定", action: #selector(showSetup), keyEquivalent: "").target = self
        let view = BoardView(menu: controlsMenu)
        view.onMenuTracking = { [weak self] tracking in self?.controlsTracking = tracking }
        for slot in 0..<4 {
            if let tile = slots[slot] { view.tiles.append(tile); view.addSubview(tile, positioned: .below, relativeTo: nil) }
            else {
                let empty = EmptySlot(slot: slot)
                view.addSubview(empty, positioned: .below, relativeTo: nil)
                view.emptySlots[slot] = empty
            }
        }
        view.slotIndices = tiles.map { tile in slots.first(where: { $0.value === tile })!.key }
        panel.contentView = view
        panel.setFrame(screen.visibleFrame, display: true)
        board = panel
        boardDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        presentation.begin()
        pointerCapture.consume = { [weak self] event in self?.capturePointer(event) ?? false }
        pointerCapture.consumeGlobal = { [weak self] event in self?.captureGlobalPointer(event) ?? false }
        let captureSession = captureLifecycle.session
        let generation = pointerGeneration
        pointerCapture.disabled = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.pointerGeneration == generation,
                      let captureSession, self.captureLifecycle.session == captureSession else { return }
                self.captureDidFail(CaptureFailure(domain: "QuadDesk.PointerCapture", code: 1,
                    message: "マウス入力の受け取りが停止しました。", isSimulation: false), session: captureSession)
            }
        }
        guard pointerCapture.start() else {
            throw QuadError("マウス入力を受け取れませんでした。アクセシビリティの許可を確認してください。")
        }
        ensureBoardVisible(force: true)
    }

    private func captureGlobalPointer(_ event: CGEvent) -> Bool {
        guard presentation.wantsBoard, !controlsTracking, let board,
              board.isVisible, board.isOnActiveSpace, !NSApp.isHidden,
              let view = board.contentView as? BoardView,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let frame = Projection.quartzRect(appKit: board.frame, primaryScreenHeight: primaryHeight)
        let point = CGPoint(x: event.location.x - frame.minX, y: event.location.y - frame.minY)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let continuing = capturedButtons[button] != nil
            && [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        guard continuing || frame.contains(event.location) || controlsPressed else { return false }
        if event.type == .mouseMoved {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastGlobalProbe >= 1.0 / 24 else { return false }
            lastGlobalProbe = now
        }
        if !continuing {
            let rawID = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
            let windowID = rawID > 0 && rawID <= Int64(UInt32.max) ? UInt32(rawID) : 0
            let rows = windowID == 0 ? nil : CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
            let layer = (rows?.first?[kCGWindowLayer as String] as? NSNumber)?.intValue
            switch PointerWindowRoute.decide(windowID: windowID, layer: layer, boardLevel: board.level.rawValue) {
            case .passThrough: return false
            case .unavailable:
                if PointerCapture.suppresses(event.type) {
                    InputDiagnostics.note("global pointer unavailable type=\(event.type.rawValue) interactiveWindow=\(windowID)")
                    pointerCapture.disabled?()
                }
                return PointerCapture.suppresses(event.type)
            case .capture: break
            }
        }
        if controlsPressed {
            if event.type == .leftMouseUp {
                controlsPressed = false
                if view.controlsRect.contains(point) {
                    DispatchQueue.main.async { [weak view] in view?.showControls() }
                }
            }
            return PointerCapture.suppresses(event.type)
        }
        if !continuing && view.controlsRect.contains(point) {
            if event.type == .leftMouseDown { controlsPressed = true }
            return PointerCapture.suppresses(event.type)
        }
        return routePointer(event, boardPoint: point, origin: "global")
    }

    private func capturePointer(_ native: NSEvent) -> Bool {
        guard presentation.wantsBoard, let board, native.window === board,
              board.isVisible, !NSApp.isHidden,
              let view = board.contentView as? BoardView, let event = native.cgEvent else { return false }
        let point = view.convert(native.locationInWindow, from: nil)
        guard !view.controlsRect.contains(point) else { return false }
        return routePointer(event, boardPoint: point, origin: "local")
    }

    private func routePointer(_ event: CGEvent, boardPoint: CGPoint, origin: String) -> Bool {
        if event.type == .mouseMoved {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCapturedMove >= 1.0 / 24 else { return false }
            lastCapturedMove = now
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let up = [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        let drag = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        var index: Int?
        if up || drag { index = capturedButtons[button] }
        if index == nil { index = tiles.firstIndex(where: { $0.frame.contains(boardPoint) }) }
        guard let index, tiles.indices.contains(index) else { return PointerCapture.suppresses(event.type) }
        if down { capturedButtons[button] = index }
        if up { capturedButtons.removeValue(forKey: button) }
        guard let copy = event.copy() else { return PointerCapture.suppresses(event.type) }
        let tile = tiles[index]
        let local = CGPoint(x: boardPoint.x - tile.frame.minX, y: boardPoint.y - tile.frame.minY)
        let generation = pointerGeneration
        DispatchQueue.main.async { [weak self, weak tile] in
            guard let self, self.pointerGeneration == generation, self.presentation.wantsBoard else { return }
            if copy.type != .mouseMoved { InputDiagnostics.note("captured \(origin) pointer type=\(copy.type.rawValue) slot=\(index)") }
            tile?.capturedPointer(copy, localPoint: local)
        }
        return PointerCapture.suppresses(event.type)
    }
    private func select(_ tile: TileView, completion: @escaping (InputFocusResult) -> Void) {
        guard tile.source.isAlive else { completion(.failed); return }
        selectionGeneration += 1
        for item in tiles where item !== tile { item.releaseButtons() }
        tiles.forEach { $0.selected = $0 === tile }
        selectedIndex = tiles.firstIndex(where: { $0 === tile })
        inputFocus.request(tile.source) { [weak self] result in
            if case .cancelled = result { completion(result); return }
            self?.selectionGeneration += 1
            completion(result)
            if case .ready = result {
                self?.ensureBoardVisible(force: true)
                self?.refreshSelection()
            }
        }
        updateCapturePriorities()
        ensureBoardVisible(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refreshSelection() }
    }
    private func showOriginal(_ tile: TileView) {
        presentation.showOriginal()
        inputFocus.cancel()
        tiles.forEach { $0.releaseButtons() }
        board?.orderOut(nil)
        inputFocus.request(tile.source) { _ in }
        updateCapturePriorities()
    }
    @objc private func showSelectedOriginal() {
        guard !busy, let index = selectedIndex, tiles.indices.contains(index) else { return }
        showOriginal(tiles[index])
    }
    @objc private func resumeBoard() {
        guard !busy else { return }
        guard !sources.isEmpty else { showSetup(); return }
        presentation.showBoard()
        setup.orderOut(nil)
        ensureBoardVisible(force: true)
        if let index = selectedIndex, tiles.indices.contains(index) { tiles[index].requestInputFocus() }
    }
    @objc private func showSetup() {
        presentation.showSettings()
        inputFocus.cancel()
        tiles.forEach { $0.releaseButtons() }
        board?.orderOut(nil)
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        setup.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updatePermissions()
        updateCapturePriorities()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if sources.isEmpty { showSetup() } else { resumeBoard() }
        return false
    }
    private func installVisibilityObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [Notification.Name] = [NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification]
        for name in events {
            visibilityObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let event = notification.name
                Task { @MainActor in
                    guard let self else { return }
                    if event == NSWorkspace.sessionDidResignActiveNotification { self.presentation.sessionActive = false }
                    if event == NSWorkspace.sessionDidBecomeActiveNotification { self.presentation.sessionActive = true }
                    if event == NSWorkspace.screensDidSleepNotification { self.presentation.displaysAwake = false }
                    if event == NSWorkspace.screensDidWakeNotification { self.presentation.displaysAwake = true }
                    if event == NSWorkspace.sessionDidResignActiveNotification || event == NSWorkspace.screensDidSleepNotification {
                        self.inputFocus.cancel()
                        self.tiles.forEach { $0.releaseButtons() }
                    }
                    self.ensureBoardVisible(force: true)
                    self.updateCapturePriorities()
                }
            })
        }
    }
    private func ensureBoardVisible(force: Bool = false) {
        guard presentation.wantsBoard, !terminating, !sources.isEmpty, let board else { return }
        let hidden = NSApp.isHidden
        let missing = !board.isVisible || !board.isOnActiveSpace
        if hidden { NSApp.unhideWithoutActivation() }
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == boardDisplayID
        }) ?? board.screen ?? NSScreen.main, board.frame != screen.visibleFrame {
            board.setFrame(screen.visibleFrame, display: true)
        }
        if force || hidden || missing {
            board.orderFrontRegardless()
            if hidden || missing {
                healthLogger.notice("Board visibility repaired: appHidden=\(hidden) missingFromSpace=\(missing)")
            }
        }
    }
    @objc private func stopAction() {
        guard !busy else { return }
        busy = true; updatePermissions()
        Task {
            await stop(showSettings: true)
            busy = false; updatePermissions()
        }
    }
    private func captureDidFail(_ failure: CaptureFailure, session: UUID) {
        guard captureLifecycle.accept(failure, from: session) else { return }
        captureLogger.error("Capture stopped: domain=\(failure.domain, privacy: .public) code=\(failure.code) kind=\(failure.kind.rawValue, privacy: .public) simulation=\(failure.isSimulation)")
        tiles.forEach { $0.fail(failure.title) }
        // Startup owns cleanup until its next await completes. Do not race its mutations.
        guard !busy else { return }
        busy = true; updatePermissions()
        Task {
            await stop(showSettings: true)
            busy = false; updatePermissions()
        }
    }
    @objc private func simulateCaptureFailure() {
        guard !busy, !sources.isEmpty, let session = captureLifecycle.session else { return }
        captureDidFail(CaptureFailure(domain: CaptureFailure.streamErrorDomain, code: -3821,
            message: "Diagnostic simulation", isSimulation: true), session: session)
    }
    private func stop(showSettings: Bool) async {
        pointerCapture.stop()
        pointerGeneration += 1
        capturedButtons.removeAll()
        controlsPressed = false; controlsTracking = false
        presentation.end()
        inputFocus.cancel()
        selectionGeneration += 1
        let captureFailure = captureLifecycle.failure
        captureLifecycle.finish()
        healthTimer?.invalidate(); healthTimer = nil
        tiles.forEach { $0.stopRendering() }
        board?.orderOut(nil); board = nil
        for capture in captures { await capture.stop() }
        captures.removeAll(); tiles.removeAll(); selectedIndex = nil
        do {
            let remaining = sources.isEmpty ? 0 : try await restoreSaved(liveSources: sources)
            sources.removeAll()
            captureLogger.notice("Session ended: remainingRestore=\(remaining)")
            let restoration = remaining == 0 ? "元のウィンドウ配置へ戻しました。" : "\(remaining)件を復元できませんでした。「前回のウィンドウ配置を復元」で再試行してください。"
            if let captureFailure {
                messageLabel.stringValue = captureFailure.title + restoration + "\n" + captureFailure.guidance
                messageLabel.textColor = remaining == 0 ? .systemOrange : .systemRed
            } else {
                messageLabel.stringValue = "停止しました。" + restoration
                messageLabel.textColor = remaining == 0 ? .secondaryLabelColor : .systemRed
            }
        } catch {
            sources.removeAll()
            report(error)
            if let captureFailure { messageLabel.stringValue = captureFailure.title + "\n" + messageLabel.stringValue }
        }
        if showSettings { showSetup() }
    }
    private func restoreSaved(liveSources: [SourceWindow] = []) async throws -> Int {
        let saved = try store.read()
        var remaining: [SavedWindow] = []
        for record in saved {
            // A restarted app or a recycled pid/window id must never receive an old restore.
            guard let app = NSRunningApplication(processIdentifier: record.processID),
                  app.launchDate == record.launchDate, (app.bundleIdentifier ?? "") == record.bundleID,
                  let current = currentWindowInfo(record.windowID, pid: record.processID) else { continue }
            do {
                let element: AXUIElement
                if let live = liveSources.first(where: { $0.saved == record }) { element = live.element }
                else { element = try Access.find(pid: record.processID, title: current.title, frame: current.frame) }
                if (Access.value(element, kAXMinimizedAttribute) as? Bool) == true {
                    AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                Access.focus(element, pid: record.processID)
                try await Task.sleep(nanoseconds: 100_000_000)
                try await Access.setFrame(element, record.originalFrame, windowID: record.windowID, pid: record.processID)
                guard let actual = currentWindow(record.windowID, pid: record.processID),
                      abs(actual.minX - record.originalFrame.minX) < 3,
                      abs(actual.minY - record.originalFrame.minY) < 3,
                      abs(actual.width - record.originalFrame.width) < 3,
                      abs(actual.height - record.originalFrame.height) < 3 else { remaining.append(record); continue }
            } catch { remaining.append(record) }
        }
        try store.write(remaining)
        return remaining.count
    }
    @objc private func recoverAction() {
        guard !busy, sources.isEmpty else { return }
        busy = true; updatePermissions()
        Task {
            defer { busy = false; updatePermissions() }
            do {
                let count = try await restoreSaved()
                messageLabel.stringValue = count == 0 ? "前回の配置情報を処理しました。" : "\(count)件の配置を復元できませんでした。対象ウィンドウの名前・接続画面・許可を確認してください。"
            } catch { report(error) }
        }
    }
    private func checkSources() {
        ensureBoardVisible()
        refreshSelection()
        for tile in tiles {
            if !tile.source.isAlive { tile.fail("元のウィンドウが閉じられました。停止して選び直してください。") }
            else if !Access.trusted { tile.fail("アクセシビリティの許可が失われました。停止して許可を確認してください。") }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastHealthReport >= 30 {
            lastHealthReport = now
            let footprint = ProcessResources.physicalFootprintMiB.map(String.init) ?? "unavailable"
            healthLogger.notice("process footprintMiB=\(footprint, privacy: .public) memoryConstrained=\(self.memoryConstrained) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
            healthLogger.notice("board mode=\(self.presentation.mode.rawValue, privacy: .public) visible=\(self.board?.isVisible ?? false) activeSpace=\(self.board?.isOnActiveSpace ?? false) appHidden=\(NSApp.isHidden) unoccluded=\(self.board?.occlusionState.contains(.visible) ?? false)")
            for (index, capture) in captures.enumerated() {
                let drops = tiles.indices.contains(index) ? tiles[index].displayDrops : 0
                let presented = tiles.indices.contains(index) ? tiles[index].presentedFrames : 0
                healthLogger.notice("pane=\(index + 1) \(capture.health(), privacy: .public) presented=\(presented) displayDrops=\(drops)")
            }
        }
    }
    private func refreshSelection() {
        guard presentation.wantsBoard, board?.isVisible == true, !inputFocus.isSwitching, !accessibilityProbeInFlight,
              let session = captureLifecycle.session,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        accessibilityProbeInFlight = true
        let generation = selectionGeneration
        let windows = tiles.map { AXProbeTarget(pid: $0.source.candidate.pid, element: $0.source.element) }
        // A busy source must not block video delivery or QuadDesk's stop menu.
        accessibilityProbeQueue.async { [weak self] in
            let focused = Access.value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
            let matches = windows.map { target in target.pid == pid && focused.map { CFEqual($0, target.element) } == true }
            let minimized = windows.map { (Access.value($0.element, kAXMinimizedAttribute) as? Bool) == true }
            DispatchQueue.main.async {
                guard let self else { return }
                self.accessibilityProbeInFlight = false
                guard self.captureLifecycle.session == session, self.selectionGeneration == generation,
                      !self.inputFocus.isSwitching,
                      self.board?.isVisible == true,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                for (index, tile) in self.tiles.enumerated() {
                    let selected = matches.indices.contains(index) && matches[index]
                    tile.selected = selected
                    if selected { self.selectedIndex = index }
                    if minimized.indices.contains(index), minimized[index] {
                        tile.fail("元のウィンドウが最小化されました。\n元画面で解除して、停止・再開してください。")
                    }
                }
                self.updateCapturePriorities()
            }
        }
    }
    private func updateCapturePriorities() {
        let thermal = ProcessInfo.processInfo.thermalState
        let constrained = memoryConstrained || thermal == .serious || thermal == .critical || !presentation.wantsBoard
        for (index, capture) in captures.enumerated() {
            capture.setPriority(active: presentation.wantsBoard && tiles.indices.contains(index) && tiles[index].selected, constrained: constrained)
        }
    }
    private func report(_ error: Error) {
        messageLabel.stringValue = error.localizedDescription
        messageLabel.textColor = .systemRed
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === board { stopAction(); return false }
        if sources.isEmpty { NSApp.terminate(nil); return false }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateNow }
        // Startup mutates windows across await points; do not terminate midway through it.
        if busy { messageLabel.stringValue = "処理が完了してから終了してください。"; return .terminateCancel }
        if sources.isEmpty { return .terminateNow }
        terminating = true; busy = true
        Task {
            await stop(showSettings: false)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    private func registerEmergencyShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID(signature: 0, id: 0)
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            let command = identifier.id
            let controller = Unmanaged<AppController>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                if command == 2 { controller.resumeBoard() } else { controller.stopAction() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let identifier = EventHotKeyID(signature: OSType(0x5144534B), id: 1)
        let keyStatus = RegisterEventHotKey(UInt32(kVK_Escape), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        let resumeIdentifier = EventHotKeyID(signature: OSType(0x5144534B), id: 2)
        let resumeStatus = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), resumeIdentifier, GetApplicationEventTarget(), 0, &resumeHotKey)
        if handlerStatus != noErr || keyStatus != noErr || resumeStatus != noErr {
            messageLabel.stringValue = "停止・復帰キーの一部を登録できません。メニューバーのQuadDeskまたはDockを使ってください。"
        }
    }
}

final class EmptySlot: NSView {
    let label: NSTextField
    init(slot: Int) {
        label = NSTextField(labelWithString: ["左上", "右上", "左下", "右下"][slot] + " · 未使用")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        layer?.cornerRadius = 10
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); label.frame = CGRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 20) }
}
