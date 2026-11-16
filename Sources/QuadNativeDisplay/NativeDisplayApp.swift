import AppKit
import Carbon
import CoreGraphics
import QuadVirtualDisplay
import QuadDisplayCore
import OSLog

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PreviewTextView: NSTextView {
    var report: ((String) -> Void)?
    private var lastScroll: TimeInterval = 0
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        report?("click key=\(window?.isKeyWindow == true) active=\(NSApp.isActive)")
    }
    override func didChangeText() {
        super.didChangeText()
        report?("edit length=\(string.count) key=\(window?.isKeyWindow == true)")
    }
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        let now = ProcessInfo.processInfo.systemUptime
        if now-lastScroll > 0.5 {
            lastScroll = now; report?("scroll y=\(enclosingScrollView?.contentView.bounds.minY ?? 0)")
        }
    }
}

@MainActor
public final class NativeDisplayApp: NSObject, NSApplicationDelegate {
    public enum SourceValidation {
        case ready
        case restart
        case reselect(String)
    }
    public var heading = "入力を転送せず、Mac自身で縮小する"
    public var instructions: String?
    public var setupHeight: CGFloat = 490
    public var configureSources: ((NSStackView) -> Void)?
    public var prepareSources: (() async throws -> Void)?
    public var validateSources: (() async throws -> SourceValidation)?
    public var presentSources: ((NSScreen, @escaping () -> Bool) async throws -> Void)?
    public var restoreSources: (() async throws -> Void)?
    public var prepareFocus: ((Int) async throws -> Void)?
    public var focusSource: ((Int, NSScreen) async throws -> Void)?
    public var sourceNames: [String] = [] { didSet { updateFocusMenu() } }
    public var fourScreenVisible: Bool {
        virtual != nil && helperReady && fourReady && !restoring && !finishingRestore && focusTask == nil
    }
    public var isSingleScreenSession: Bool { focusedSource != nil }
    public var continuousWork = false {
        didSet { start?.title = continuousWork ? "4画面で作業を開始" : "表示構成を変更して15秒プレビュー" }
    }
    public override init() { super.init() }
    public func setStatus(_ message: String) { status.stringValue = message }
    @discardableResult
    public func endSession() -> Bool {
        let active = focusedSource != nil || helper != nil || virtual != nil || focusTask != nil
        if active { stop() }
        return active
    }
    private var finishingRestore = false
    private var presentationTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var statusItem: NSStatusItem?
    private var activeWork = false
    private var fourReady = false
    private var pendingFocus: Int?
    private var focusedSource: Int?
    private var focusTask: Task<Void, Never>?
    private var focusCancelled = false
    private var focusItems: [NSMenuItem] = []
    private var resumeItem: NSMenuItem?
    private var setup: NSWindow!
    private var start: NSButton!
    private let status = NSTextField(wrappingLabelWithString: "表示構成は変更していません。")
    private var virtual: QDVirtualDisplayHandle?
    private var snapshot: DisplaySnapshot?
    private var helper: Process?
    private var helperInput: Pipe?
    private var helperOutput: Pipe?
    private var outputBuffer = ""
    private var helperReady = false
    private var restoring = false
    private var quitAfterRestore = false
    private var demos: [NSWindow] = []
    private var deadline: Timer?
    private var hotKey: EventHotKeyRef?
    private var focusHotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var generation = 0
    private var previewError: String?
    private let log = Logger(subsystem: "io.github.TRN408.QuadDeskNativePreview", category: "display")

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let root = NSMenu(), appItem = NSMenuItem(), menu = NSMenu()
        root.addItem(appItem); appItem.submenu = menu
        menu.addItem(withTitle: "今すぐ元の表示に戻す", action: #selector(stop), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "比較版を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = root
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "QuadDesk")
        let statusMenu = NSMenu(); statusMenu.autoenablesItems = false
        if focusSource != nil {
            for index in 0..<4 {
                let choice = statusMenu.addItem(withTitle: "\(index + 1)：1画面へ拡大", action: #selector(focusMenu(_:)), keyEquivalent: "")
                choice.tag = index; choice.target = self; focusItems.append(choice)
            }
            let resume = statusMenu.addItem(withTitle: "4画面へ戻る（⌃⌥0）", action: #selector(resumeFour), keyEquivalent: "")
            resume.target = self; resumeItem = resume
            statusMenu.addItem(.separator())
        }
        statusMenu.addItem(withTitle: "4画面を停止して元へ戻す（⌃⌥Esc）", action: #selector(stop), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = statusMenu; statusItem = item

        setup = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 740, height: setupHeight),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        setup.title = focusSource == nil ? "QuadDesk — ネイティブ表示の比較" : "QuadDesk — 4画面ワークスペース"
        setup.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: heading)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: instructions ??
            "広い仮想デスクトップを作り、内蔵画面へ縮小ミラーリングします。比較用の4つの入力画面を表示します。Discordなど実アプリの配置は、この比較の後に検証します。\n\nMac全体のメニューや他のウィンドウも小さくなり、切り替え時に暗転する場合があります。15秒で自動終了します。Control + Option + Escでも停止できます。\n\n復帰用の別プロセスを先に起動し、比較アプリが応答しない場合は25秒で終了・復元を試みます。このMacでの復元動作はまだ未検証です。")
        explanation.font = .systemFont(ofSize: 14)
        start = NSButton(title: "表示構成を変更して15秒プレビュー", target: self, action: #selector(begin))
        start.bezelStyle = .rounded
        let problem = QDVirtualDisplayHandle.supportProblem()
        if !problem.isEmpty { start.isEnabled = false; status.stringValue = "未対応：\(problem)" }
        else if let physical = try? DisplaySnapshot.captureSingleDisplay() {
            status.stringValue = "現在 \(physical.mode.width) × \(physical.mode.height) → 比較 \(physical.mode.width * 2) × \(physical.mode.height * 2)。\nOSの必要な機能を検出済み。表示構成は未変更です。"
        } else { start.isEnabled = false; status.stringValue = "ミラーリングしていない1画面のMacでのみ比較できます。" }
        let stack = NSStackView(views: [title, explanation])
        configureSources?(stack)
        stack.addArrangedSubview(start); stack.addArrangedSubview(status)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        setup.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: setup.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: setup.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: setup.contentView!.topAnchor, constant: 28),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        setup.center(); setup.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        updateFocusMenu()
    }

    private func updateFocusMenu() {
        for (index, item) in focusItems.enumerated() {
            let name = sourceNames.indices.contains(index) ? sourceNames[index] : "未選択"
            item.title = "\(index + 1)：\(name)を1画面へ（⌃⌥\(index + 1)）"
            item.isEnabled = fourScreenVisible
        }
        resumeItem?.isEnabled = focusedSource != nil && !restoring && !finishingRestore
    }
    @objc private func focusMenu(_ sender: NSMenuItem) { requestFocus(sender.tag) }
    @objc private func resumeFour() {
        guard focusedSource != nil else { return }
        begin()
    }
    public func requestFocus(_ index: Int) {
        guard fourScreenVisible, sourceNames.indices.contains(index), prepareFocus != nil else { return }
        let generation = self.generation
        focusCancelled = false
        focusTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await prepareFocus?(index)
                try Task.checkCancellation()
                guard isCurrent(generation) else { return }
                pendingFocus = index; focusTask = nil
                stopDisplay()
            } catch {
                guard !Task.isCancelled, isCurrent(generation) else { return }
                focusTask = nil; previewError = error.localizedDescription; stop()
            }
        }
        updateFocusMenu()
    }

    @objc private func begin() {
        guard helper == nil, virtual == nil, !finishingRestore, !restoring, focusTask == nil else { return }
        start.isEnabled = false
        focusTask = Task { [weak self] in
            guard let self else { return }
            var validated = false
            defer {
                focusTask = nil
                if !restoring && !finishingRestore && helper == nil { start.isEnabled = true }
            }
            do {
                let validation = try await validateSources?() ?? .ready
                try Task.checkCancellation()
                validated = true
                switch validation {
                case .ready: break
                case .restart:
                    focusedSource = nil; pendingFocus = nil; removeShortcuts()
                case .reselect(let message):
                    focusedSource = nil; pendingFocus = nil; removeShortcuts()
                    status.stringValue = message
                    setup.makeKeyAndOrderFront(nil); updateFocusMenu()
                    return
                }
                if let index = focusedSource { try await prepareFocus?(index) }
                try await prepareSources?()
                try Task.checkCancellation()
                beginPrepared(sourcesPrepared: prepareSources != nil)
            } catch {
                guard !Task.isCancelled else { return }
                focusTask = nil
                if validated && focusedSource != nil {
                    previewError = error.localizedDescription; stop()
                } else {
                    status.stringValue = error.localizedDescription
                    setup.makeKeyAndOrderFront(nil)
                }
            }
        }
        updateFocusMenu()
    }

    private func beginPrepared(sourcesPrepared: Bool) {
        guard helper == nil, virtual == nil, !finishingRestore, !restoring else { return }
        generation += 1
        let generation = self.generation
        previewError = nil
        activeWork = continuousWork
        start.isEnabled = false; status.stringValue = "復帰用プロセスを準備しています…"
        let prepared = sourcesPrepared
        do {
            guard QDVirtualDisplayHandle.supportProblem().isEmpty else { throw DisplayFailure("仮想画面の機能が未対応です。") }
            let saved = try DisplaySnapshot.captureSingleDisplay()
            guard saved.mode.width * 2 <= 4096, saved.mode.height * 2 <= 4096 else { throw DisplayFailure("比較版の解像度上限を超えています。") }
            focusedSource = nil
            snapshot = saved
            log.notice("Preparing preview physical=\(saved.id) originalMode=\(saved.mode.ioDisplayModeID) logical=\(saved.mode.width)x\(saved.mode.height)")
            let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuadDisplayWatchdog")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw DisplayFailure("復帰用プロセスがありません。表示は変更しません。") }
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = executable; process.arguments = [activeWork ? "--guard-work" : "--guard-preview"]
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            helper = process; helperInput = input; helperOutput = output
            if activeWork {
                try configureHeartbeatPipe(input.fileHandleForWriting.fileDescriptor)
            }
            outputBuffer = ""; helperReady = false; restoring = false
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                guard let value = String(data: data, encoding: .utf8), !value.isEmpty else { return }
                DispatchQueue.main.async { self?.receive(value, generation: generation) }
            }
            process.terminationHandler = { [weak self, weak process] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard let self, let process, self.helper === process else { return }
                    if self.restoring || self.virtual != nil {
                        self.fallbackRestore("復帰用プロセスが終了しました。")
                    } else if !self.helperReady {
                        self.restoring = true
                        self.finishRestore("復帰用プロセスを開始できませんでした。表示は変更していません。")
                    } else {
                        self.stop()
                        self.fallbackRestore("比較前に復帰用プロセスが終了しました。")
                    }
                }
            }
            try process.run()
            // No UI/display mutation is allowed until a matching READY is received.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.helper === process, !self.helperReady else { return }
                self.stop()
            }
        } catch {
            clearHelper(); snapshot = nil
            if prepared, restoreSources != nil {
                previewError = error.localizedDescription; restoring = true
                finishRestore("表示構成を変更する前に停止しました。")
            } else if focusedSource != nil {
                previewError = error.localizedDescription; stop()
            } else {
                start.isEnabled = true
                status.stringValue = "\(error.localizedDescription)\n表示構成は変更していません。"
                setup.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func receive(_ value: String, generation: Int) {
        guard self.generation == generation, helper != nil else { return }
        outputBuffer += value
        while let end = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<end]); outputBuffer.removeSubrange(...end)
            log.notice("Watchdog: \(line, privacy: .public)")
            if line.hasPrefix("READY "), !helperReady, !restoring, let saved = snapshot {
                let expected = "READY \(saved.id) \(saved.mode.ioDisplayModeID)"
                guard line == expected else { stop(); return }
                helperReady = true
                // Layout yields to the main loop but can exceed the initial
                // lease on a busy Mac. Protect liveness during setup as well.
                if activeWork { beginHeartbeats(generation: generation) }
                presentationTask = Task { await showPreview(generation: generation) }
            } else if line == "RESTORED" {
                if snapshot?.verifyRestored() == true { finishRestore("元の表示モードと主画面へ戻りました。") }
                else { fallbackRestore("復帰の再確認を行います。") }
            } else if line.hasPrefix("ERROR ") { fallbackRestore(line) }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation && helperReady && !restoring && helper?.isRunning == true
    }
    private func logTopology(_ phase: String) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        _ = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        let state = ids.prefix(Int(count)).map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            return "id=\(id) active=\(CGDisplayIsActive(id)) mirrorOf=\(CGDisplayMirrorsDisplay(id)) mode=\(mode?.width ?? 0)x\(mode?.height ?? 0) bounds=\(CGDisplayBounds(id))"
        }.joined(separator: "; ")
        let screens = NSScreen.screens.map { screen in
            "id=\((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) frame=\(screen.frame)"
        }.joined(separator: "; ")
        log.notice("Topology \(phase, privacy: .public) main=\(CGMainDisplayID()) displays=[\(state, privacy: .public)] screens=[\(screens, privacy: .public)]")
    }
    private func showPreview(generation: Int) async {
        guard let saved = snapshot, isCurrent(generation) else { return }
        do {
            try registerShortcut()
            let timer = Timer(timeInterval: NativePreviewPlan.previewSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard self?.generation == generation else { return }
                    self?.stop()
                }
            }
            if !activeWork { deadline = timer; RunLoop.main.add(timer, forMode: .common) }
            virtual = try QDVirtualDisplayHandle(width: UInt(saved.mode.width * 2), height: UInt(saved.mode.height * 2))
            guard let virtual else { throw DisplayFailure("仮想画面を作成できません。") }
            log.notice("Created virtual display=\(virtual.displayID)")
            logTopology("created")
            var stableReads = 0
            let desiredWidth = saved.mode.width * 2, desiredHeight = saved.mode.height * 2
            for _ in 0..<30 {
                guard isCurrent(generation) else { return }
                var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
                let enumerated = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success
                let mode = CGDisplayCopyDisplayMode(virtual.displayID)
                let screenExists = NSScreen.screens.contains {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == virtual.displayID
                }
                let ready = enumerated && Set(ids.prefix(Int(count))) == Set([saved.id, virtual.displayID])
                    && CGDisplayIsActive(virtual.displayID) != 0 && screenExists
                    && mode?.width == desiredWidth && mode?.height == desiredHeight
                stableReads = ready ? stableReads + 1 : 0
                if stableReads >= 2 { break }
                // Yield even when IsOnline is already true: AppKit/CG must process
                // the display-added notification before configuration is legal.
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard isCurrent(generation) else { return }
            logTopology("before mirror")
            guard stableReads >= 2 else { throw DisplayFailure("仮想画面の配置と表示モードが準備されませんでした。") }
            guard let mode = (CGDisplayCopyAllDisplayModes(virtual.displayID, nil) as? [CGDisplayMode])?.first(where: {
                $0.width == desiredWidth && $0.height == desiredHeight
            }) else { throw DisplayFailure("比較用の表示モードを取得できません。") }
            log.notice("Virtual topology ready active=\(CGDisplayIsActive(virtual.displayID)) bounds=\(String(describing: CGDisplayBounds(virtual.displayID)), privacy: .public)")
            var config: CGDisplayConfigRef?
            try checked(CGBeginDisplayConfiguration(&config), "比較設定の開始")
            guard let config else { throw DisplayFailure("比較設定を作成できません。") }
            do {
                try checked(CGConfigureDisplayWithDisplayMode(config, virtual.displayID, mode, nil), "仮想画面の表示モード")
                try checked(CGConfigureDisplayMirrorOfDisplay(config, saved.id, virtual.displayID), "縮小ミラーリング")
            } catch { CGCancelDisplayConfiguration(config); throw error }
            try checked(CGCompleteDisplayConfiguration(config, .forAppOnly), "比較設定の適用")
            log.notice("Applied app-scoped mirror physical=\(saved.id) master=\(virtual.displayID)")
            for _ in 0..<20 {
                guard isCurrent(generation) else { return }
                if CGDisplayMirrorsDisplay(saved.id) == virtual.displayID { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard isCurrent(generation) else { return }
            logTopology("after mirror")
            guard CGDisplayMirrorsDisplay(saved.id) == virtual.displayID else {
                throw DisplayFailure("ミラーリングの方向を確認できません。")
            }
            // Establish the mirror before changing its master's origin. Followers
            // inherit that origin; explicitly moving them would dissolve the set.
            if CGMainDisplayID() != virtual.displayID {
                var originConfig: CGDisplayConfigRef?
                try checked(CGBeginDisplayConfiguration(&originConfig), "主画面設定の開始")
                guard let originConfig else { throw DisplayFailure("主画面の設定を作成できません。") }
                let result = CGConfigureDisplayOrigin(originConfig, virtual.displayID, 0, 0)
                if result != .success { CGCancelDisplayConfiguration(originConfig); try checked(result, "仮想主画面の設定") }
                try checked(CGCompleteDisplayConfiguration(originConfig, .forAppOnly), "主画面設定の適用")
            }
            for _ in 0..<20 {
                guard isCurrent(generation) else { return }
                if CGMainDisplayID() == virtual.displayID,
                   Int(CGDisplayBounds(virtual.displayID).width) == saved.mode.width * 2,
                   CGDisplayMirrorsDisplay(saved.id) == virtual.displayID { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard isCurrent(generation) else { return }
            guard CGMainDisplayID() == virtual.displayID,
                  Int(CGDisplayBounds(virtual.displayID).width) == saved.mode.width * 2,
                  Int(CGDisplayBounds(virtual.displayID).height) == saved.mode.height * 2,
                  CGDisplayMirrorsDisplay(saved.id) == virtual.displayID,
                  let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == virtual.displayID })
            else { throw DisplayFailure("期待した解像度とミラーリング方向を確認できません。") }
            setup.orderOut(nil)
            if let presentSources {
                try await presentSources(screen, { [weak self] in self?.isCurrent(generation) == true })
            } else { showDemos(on: screen) }
            guard isCurrent(generation) else { return }
            guard isCurrent(generation) else { return }
            fourReady = true
            log.notice("Preview visible logical=\(screen.frame.width)x\(screen.frame.height) sources=\(self.presentSources == nil ? "demo" : "apps", privacy: .public)")
            updateFocusMenu()
        } catch {
            guard isCurrent(generation) else { return }
            previewError = error.localizedDescription
            logTopology("failed")
            log.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            status.stringValue = error.localizedDescription; stop()
        }
    }

    private func beginHeartbeats(generation: Int) {
        func send() {
            guard isCurrent(generation), let pipe = helperInput else { return }
            do { try pipe.fileHandleForWriting.write(contentsOf: Data("PING\n".utf8)) }
            catch { previewError = "復帰監視との接続が切れたため停止しました。"; stop() }
        }
        send()
        guard isCurrent(generation) else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.isCurrent(generation) == true else { return }
                send()
            }
        }
        heartbeatTimer = timer; RunLoop.main.add(timer, forMode: .common)
        log.notice("Work session heartbeat started; automatic 15-second stop disabled")
    }

    private func showDemos(on screen: NSScreen) {
        // AppKit origin is bottom-left; order the upper row first for the labels.
        let frames = NativePreviewPlan.tiles(in: screen.visibleFrame)
        for index in 0..<4 {
            let window = PreviewWindow(contentRect: frames[[2, 3, 0, 1][index]], styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "QuadDesk 比較 \(index + 1)"
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = PreviewTextView(frame: CGRect(origin: .zero, size: scroll.contentSize))
            text.isRichText = false; text.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            text.backgroundColor = index % 2 == 0 ? NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.34, alpha: 1) : .textBackgroundColor
            text.textColor = index % 2 == 0 ? .white : .textColor
            text.string = "比較 \(index + 1) — ここをクリックして入力できます\n15秒で元の表示へ戻ります。⌃⌥Escで今すぐ停止。\n\n" + (1...100).map { "\($0) クリック・文字入力・スクロールを確認するための試験画面です。" }.joined(separator: "\n")
            text.report = { [weak self] event in self?.log.notice("Demo pane=\(index + 1) \(event, privacy: .public)") }
            scroll.documentView = text; window.contentView!.addSubview(scroll)
            demos.append(window); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(text)
        }
    }

    private func registerShortcut() throws {
        if hotKey != nil { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let app = Unmanaged<NativeDisplayApp>.fromOpaque(context).takeUnretainedValue()
                app.log.notice("Registered shortcut command=\(key.id)")
                if key.id == 1 { app.stop() }
                else if key.id == 2 { app.resumeFour() }
                else if (3...6).contains(key.id) { app.requestFocus(Int(key.id) - 3) }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else {
            throw DisplayFailure("緊急停止の登録に失敗しました。")
        }
        guard RegisterEventHotKey(UInt32(kVK_Escape), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x51445052, id: 1), GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            throw DisplayFailure("緊急停止キーが他のアプリに使われています。")
        }
        if focusSource != nil {
            for (offset, code) in [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4].enumerated() {
                var key: EventHotKeyRef?
                guard RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey),
                    EventHotKeyID(signature: 0x51445052, id: UInt32(offset + 2)), GetApplicationEventTarget(), 0, &key) == noErr,
                      let key else { throw DisplayFailure("1画面切替のControl + Option + 数字キーが他のアプリに使われています。") }
                focusHotKeys.append(key)
            }
        }
    }

    @objc private func stop() {
        focusCancelled = true
        pendingFocus = nil
        focusTask?.cancel()
        if (focusedSource != nil || focusTask != nil), helper == nil, virtual == nil, !finishingRestore {
            focusedSource = nil; restoring = true
            removeShortcuts(); finishRestore("1画面の作業を終了し、元の配置へ戻しました。")
            return
        }
        stopDisplay()
    }
    private func removeShortcuts() {
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
        focusHotKeys.forEach { UnregisterEventHotKey($0) }; focusHotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
    private func stopDisplay() {
        guard helper != nil || virtual != nil else { removeShortcuts(); return }
        guard !restoring else { return }; restoring = true
        fourReady = false
        presentationTask?.cancel()
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        log.notice("Stopping preview and releasing virtual display")
        deadline?.invalidate(); deadline = nil
        demos.forEach { $0.close() }; demos.removeAll()
        virtual = nil
        if pendingFocus == nil { removeShortcuts() }
        updateFocusMenu()
        status.stringValue = "元の表示へ戻しています…"
        // EOF asks the already armed helper to restore its own original snapshot.
        try? helperInput?.fileHandleForWriting.close()
        setup.makeKeyAndOrderFront(nil)
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.generation == generation, self.restoring else { return }
            self.fallbackRestore("復帰の応答を再確認しています。")
        }
    }

    private func fallbackRestore(_ reason: String) {
        if !restoring { stop() }
        do {
            guard let snapshot else { finishRestore("\(reason) 表示変更前に停止しました。"); return }
            try snapshot.restore()
            let generation = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.generation == generation, self.restoring else { return }
                if snapshot.verifyRestored() { self.finishRestore("\(reason) 元の表示への復帰を確認しました。") }
                else { self.status.stringValue = "元の表示への復帰を確認できません。比較を終了し、システム設定のディスプレイを確認してください。" }
            }
        } catch { status.stringValue = "復帰エラー：\(error.localizedDescription)" }
    }

    private func clearHelper() {
        helperOutput?.fileHandleForReading.readabilityHandler = nil
        try? helperInput?.fileHandleForWriting.close()
        helper = nil; helperInput = nil; helperOutput = nil; helperReady = false
    }
    private func finishRestore(_ message: String) {
        guard !finishingRestore else { return }
        finishingRestore = true
        clearHelper(); snapshot = nil
        Task {
            var message = message
            await focusTask?.value
            focusTask = nil
            await presentationTask?.value
            presentationTask = nil
            if let index = pendingFocus, !focusCancelled, !quitAfterRestore, let screen = NSScreen.screens.first {
                pendingFocus = nil
                do {
                    try await focusSource?(index, screen)
                    if !quitAfterRestore && !focusCancelled {
                        focusedSource = index
                        restoring = false; finishingRestore = false; start.isEnabled = true
                        setup.orderOut(nil); updateFocusMenu()
                        log.notice("Single source visible index=\(index) normal=\(screen.frame.width)x\(screen.frame.height)")
                        return
                    }
                } catch { message += "\n" + error.localizedDescription }
            }
            pendingFocus = nil; focusedSource = nil; removeShortcuts()
            do { try await restoreSources?() } catch { message += "\n" + error.localizedDescription }
            restoring = false; finishingRestore = false; start.isEnabled = true
            setup.center(); setup.makeKeyAndOrderFront(nil)
            status.stringValue = [previewError, message].compactMap { $0 }.joined(separator: "\n")
            updateFocusMenu()
            log.notice("Restore finished: \(message, privacy: .public)")
            if quitAfterRestore { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A failed/exited helper must not trap the user in terminateLater.
        if finishingRestore { quitAfterRestore = true; return .terminateLater }
        if virtual == nil && helper?.isRunning != true && focusedSource == nil && focusTask == nil { return .terminateNow }
        quitAfterRestore = true; stop(); return .terminateLater
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if focusedSource != nil { resumeFour() }
        else if helper != nil || virtual != nil { stop() }
        else { setup.makeKeyAndOrderFront(nil) }
        return true
    }
}
