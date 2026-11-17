import AppKit
import ApplicationServices
import ScreenCaptureKit
import QuadCore
import QuadDisplayCore
import QuadNativeDisplay
import OSLog

/// Uses the public QuadDesk identity and the persistent recovery format.
/// It never starts a capture stream or pointer/keyboard monitor.
@MainActor
final class NativeWindowsController: NSObject {
    let host = NativeDisplayApp()
    private let mobileBrowser = MobileBrowserController()
    private var popups: [NSPopUpButton] = []
    private var candidates: [Candidate] = []
    private var sources: [(Int, SourceWindow)] = []
    private let permissions = NSTextField(labelWithString: "")
    private let setupHint = NSTextField(wrappingLabelWithString: "")
    private let recordingButton = NSButton(title: "1. 画面収録を設定", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "2. アクセシビリティを設定", target: nil, action: nil)
    private let recheckButton = NSButton(title: "状態を再確認", target: nil, action: nil)
    private var permissionTimer: Timer?
    private var previouslyGranted = false
    private let log = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "NativeWindows")
    private let store = RecoveryStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuadDesk/window-recovery.json"))
    private var refreshing = false
    private var restoringSources = false
    private var preparingSources = false
    private var layoutTimer: Timer?
    private var expansion = WindowExpansion()
    private var tileFrames: [CGRect] = []
    private let expansionQueue = DispatchQueue(label: "io.github.TRN408.QuadDesk.expansion", qos: .utility)
    private var expansionProbeInFlight = false
    private var layoutGeneration: UInt64 = 0
    private var confirmedFullscreenSlot: Int?

    override init() {
        super.init()
        Access.configureTimeouts()
        host.heading = "4アプリを、Mac自身で縮小する"
        host.setupHeight = 790
        host.instructions = "選んだ4ウィンドウを広いデスクトップに並べ、内蔵画面へ縮小表示します。\n\nウィンドウを最大化すると通常の表示倍率で1画面に切り替えます。Control + Option + 1〜4でも各画面を拡大できます。4画面へ戻る操作はControl + Option + 0、または格子メニューです。切り替え時に暗転する場合があります。\n\n初期設定は4枠の配置後から15秒のプレビューです。準備にも時間がかかる場合があります。作業モードは停止まで続きます。Control + Option + Esc、終了で作業開始前の配置へ戻します。"
        host.configureSources = { [weak self] stack in self?.configure(stack) }
        host.prepareSources = { [weak self] in
            guard let self else { throw QuadError("設定が終了しました。") }; try await self.prepare()
        }
        host.validateSources = { [weak self] in
            guard let self else { throw QuadError("設定が終了しました。") }
            return try await self.validateSession()
        }
        host.presentSources = { [weak self] screen, active in
            guard let self else { throw CancellationError() }; try await self.present(on: screen, active: active)
        }
        host.restoreSources = { [weak self] in try await self?.restore() }
        host.prepareFocus = { [weak self] index in try await self?.prepareFocus(index) }
        host.focusSource = { [weak self] index, screen in try await self?.showSingle(index, on: screen) }
    }

    private func configure(_ stack: NSStackView) {
        mobileBrowser.installMenu()
        let browserButton = NSButton(title: "モバイルブラウザを開く", target: mobileBrowser, action: #selector(MobileBrowserController.show))
        browserButton.bezelStyle = .rounded
        stack.addArrangedSubview(browserButton)
        let location = NSTextField(wrappingLabelWithString: "")
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
        location.stringValue = path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
            ? "アプリケーションに配置済みです。次に2つの権限を設定します。"
            : "先にQuadDesk.appを「アプリケーション」へ移動し、そこから開き直すと権限設定が安定します。"
        location.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(location)
        location.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(permissions)
        recordingButton.target = self; recordingButton.action = #selector(requestRecording)
        accessibilityButton.target = self; accessibilityButton.action = #selector(requestAccessibility)
        recheckButton.target = self; recheckButton.action = #selector(recheckPermissions)
        for button in [recordingButton, accessibilityButton, recheckButton] { button.bezelStyle = .rounded }
        let permissionRow = NSStackView(views: [recordingButton, accessibilityButton, recheckButton])
        permissionRow.spacing = 8; stack.addArrangedSubview(permissionRow)
        setupHint.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(setupHint)
        setupHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let folder = NSButton(title: "アプリケーションを開く", target: self, action: #selector(openApplications))
        let quit = NSButton(title: "終了して権限設定を反映", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        folder.bezelStyle = .rounded; quit.bezelStyle = .rounded
        let helpRow = NSStackView(views: [folder, quit]); helpRow.spacing = 8
        stack.addArrangedSubview(helpRow)
        for position in ["左上", "右上", "左下", "右下"] {
            let label = NSTextField(labelWithString: position)
            label.widthAnchor.constraint(equalToConstant: 42).isActive = true
            let popup = NSPopUpButton(); popup.addItem(withTitle: "ウィンドウを選択")
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
            popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            popup.target = self; popup.action = #selector(selectionChanged)
            popups.append(popup)
            let row = NSStackView(views: [label, popup]); row.spacing = 10
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let refresh = NSButton(title: "ウィンドウを再読込", target: self, action: #selector(refreshAction))
        let recover = NSButton(title: "前回の配置を復元", target: self, action: #selector(recoverAction))
        refresh.bezelStyle = .rounded; recover.bezelStyle = .rounded
        let row = NSStackView(views: [refresh, recover]); row.spacing = 10
        stack.addArrangedSubview(row)
        let workMode = NSButton(checkboxWithTitle: "作業モード（15秒制限なし・停止するまで表示）", target: self, action: #selector(modeChanged(_:)))
        stack.addArrangedSubview(workMode)
        updateSetupState()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSetupState() }
        }
        permissionTimer = timer; RunLoop.main.add(timer, forMode: .common)
        refreshAction()
    }

    private func updateSetupState() {
        let state = SetupReadiness(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: Access.trusted,
            selections: popups.map { $0.selectedItem?.representedObject as? UInt32 },
            isBusy: refreshing || restoringSources || preparingSources)
        permissions.stringValue = "画面収録：\(state.screenRecording ? "許可済み" : "未許可")    アクセシビリティ：\(state.accessibility ? "許可済み" : "未許可")"
        recordingButton.isEnabled = !state.screenRecording && sources.isEmpty
        accessibilityButton.isEnabled = !state.accessibility && sources.isEmpty
        recheckButton.isEnabled = sources.isEmpty && !state.isBusy
        popups.forEach { $0.isEnabled = state.canChooseWindows && sources.isEmpty }
        host.sourceRequirementsMet = state.canStart
        if !state.permissionsGranted {
            setupHint.stringValue = "画面収録は対象一覧の取得、アクセシビリティは配置・復元に使います。映像の保存・外部送信はありません。設定後は自動で再確認します。未反映なら終了して同じアプリを開き直してください。設定がオンでも未許可の場合は、設定一覧の「Finderに表示」で公開版を確認し、その項目だけを削除して現在のアプリを追加し直してください。"
        } else if state.isBusy {
            setupHint.stringValue = "対象ウィンドウを確認しています…"
        } else if !state.hasFourDistinctWindows {
            setupHint.stringValue = "権限は確認できました。異なる4つのウィンドウを選ぶと開始できます。最初は15秒プレビューで表示と復元を確認してください。"
        } else {
            setupHint.stringValue = "準備できました。初回は15秒プレビューをおすすめします。停止はControl + Option + Esc、または格子メニューです。"
        }
        let newlyGranted = state.permissionsGranted && !previouslyGranted
        previouslyGranted = state.permissionsGranted
        if newlyGranted && sources.isEmpty { Task { await reloadCandidates() } }
    }

    @objc private func selectionChanged() { updateSetupState() }
    @objc private func openApplications() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) }
    @objc private func requestRecording() {
        _ = CGRequestScreenCaptureAccess()
        if !CGPreflightScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        updateSetupState()
    }
    @objc private func requestAccessibility() {
        Access.request()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        updateSetupState()
    }
    @objc private func recheckPermissions() {
        updateSetupState()
        if CGPreflightScreenCaptureAccess(), Access.trusted { Task { await reloadCandidates() } }
    }

    @objc private func modeChanged(_ sender: NSButton) { host.continuousWork = sender.state == .on }

    @objc private func refreshAction() {
        Task { await reloadCandidates() }
    }

    private func reloadCandidates(note: String? = nil) async {
        guard !refreshing, !preparingSources, sources.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess(), Access.trusted else {
            host.setStatus("上の設定ボタンからQuadDeskの画面収録・アクセシビリティを許可してください。表示構成は変更していません。")
            return
        }
        refreshing = true
        updateSetupState()
        defer { refreshing = false; updateSetupState() }
        let selected = popups.map { $0.selectedItem?.representedObject as? UInt32 }
        let previous = candidates
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            candidates = content.windows.compactMap { window in
                guard let app = window.owningApplication, app.processID != getpid(), window.windowLayer == 0,
                      window.frame.width > 160, window.frame.height > 100,
                      let current = currentWindowInfo(window.windowID, pid: app.processID) else { return nil }
                return Candidate(id: window.windowID, pid: app.processID, appName: app.applicationName,
                    title: window.title ?? "", frame: current.frame)
            }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            // A covered selected window may be omitted by ScreenCaptureKit.
            // Retain only the exact previously selected id and owner.
            for id in selected.compactMap({ $0 }) where !candidates.contains(where: { $0.id == id }) {
                if let old = previous.first(where: { $0.id == id }),
                   let current = currentWindowInfo(id, pid: old.pid) {
                    candidates.append(Candidate(id: id, pid: old.pid, appName: old.appName,
                        title: current.title, frame: current.frame))
                }
            }
            candidates.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            let entries = WindowMenuEntry.unique(candidates.map { WindowMenuEntry(id: $0.id, title: $0.label) })
            let available = Set(candidates.filter { currentWindowInfo($0.id, pid: $0.pid) != nil }.map(\.id))
            let retained = WindowMenuEntry.retainedSelections(selected, available: available)
            for (index, popup) in popups.enumerated() {
                popup.removeAllItems(); popup.addItem(withTitle: "ウィンドウを選択")
                for entry in entries {
                    let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                    item.representedObject = entry.id
                    popup.menu?.addItem(item)
                }
                if let id = retained[index], let item = popup.itemArray.first(where: { ($0.representedObject as? UInt32) == id }) {
                    popup.select(item)
                }
            }
            host.setStatus(note ?? "\(entries.count)件のウィンドウが見つかりました。4つを選んでください。表示構成は未変更です。")
        } catch { host.setStatus(error.localizedDescription) }
    }

    private func validateSession() async throws -> NativeDisplayApp.SourceValidation {
        for _ in 0..<40 {
            if !refreshing { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !refreshing, !restoringSources else { throw QuadError("ウィンドウの状態を確認中です。しばらくしてから再試行してください。") }
        let expected = sources.map { $0.1.saved }
        let stored = try store.read()
        // Check for conflicting originals before any normalization can mutate UI.
        _ = try SourceSessionRepair.plan(stored: stored, expected: expected, live: [])
        for (_, source) in sources {
            let saved = source.saved
            guard let app = NSRunningApplication(processIdentifier: saved.processID),
                  app.launchDate == saved.launchDate, app.bundleIdentifier == saved.bundleID else { continue }
            source.focus()
            try await Task.sleep(nanoseconds: 100_000_000)
            source.element = try await normalElement(source.element, pid: saved.processID, windowID: saved.windowID,
                title: saved.title, frame: source.frame)
        }
        func liveOriginals() -> [SavedWindow] {
            sources.compactMap { _, source in
                let saved = source.saved
                guard let app = NSRunningApplication(processIdentifier: saved.processID),
                      app.launchDate == saved.launchDate, app.bundleIdentifier == saved.bundleID,
                      source.isAlive else { return nil }
                return saved
            }
        }
        var live = liveOriginals()
        if !expected.isEmpty && live.count != expected.count {
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 200_000_000)
                live = liveOriginals()
                if live.count == expected.count { break }
            }
        }
        switch try SourceSessionRepair.plan(stored: stored, expected: expected, live: live) {
        case .ready:
            return .ready
        case .recover(let records):
            log.notice("Automatically repairing source session expected=\(expected.count) live=\(live.count) records=\(records.count)")
            try store.write(records)
            try await restore(refreshAfter: false)
            try Task.checkCancellation()
            let message = "対象の変更を検出したため、残っているウィンドウを元の配置へ自動復元しました。空いた枠を選び直して開始してください。"
            await reloadCandidates(note: message)
            let ids = popups.compactMap { $0.selectedItem?.representedObject as? UInt32 }
            if ids.count == 4, Set(ids).count == 4,
               ids.allSatisfy({ id in candidates.contains(where: { $0.id == id && currentWindowInfo(id, pid: $0.pid) != nil }) }) {
                return .restart
            }
            return .reselect(message)
        }
    }

    private func prepare() async throws {
        guard !refreshing, !restoringSources, !preparingSources, Access.trusted, CGPreflightScreenCaptureAccess() else {
            throw QuadError("再読込の完了とQuadDeskの両権限を確認してください。")
        }
        preparingSources = true
        updateSetupState()
        defer { preparingSources = false; updateSetupState() }
        if !sources.isEmpty {
            let saved = try store.read()
            guard sources.count == 4, saved.count == 4,
                  sources.allSatisfy({ saved.contains($0.1.saved) && $0.1.isAlive }) else {
                throw QuadError("対象の変更を検出しました。元の配置へ自動復元します。")
            }
            return // Preserve the originals across any number of focus cycles.
        }
        guard !FileManager.default.fileExists(atPath: store.url.path) else {
            throw QuadError("前回の配置情報が残っています。「前回の配置を復元」を先に押してください。")
        }
        let selections = popups.enumerated().compactMap { index, popup -> (Int, Candidate)? in
            guard let id = popup.selectedItem?.representedObject as? UInt32,
                  let item = candidates.first(where: { $0.id == id }) else { return nil }
            return (index, item)
        }
        guard selections.count == 4, Set(selections.map { $0.1.id }).count == 4 else {
            throw QuadError("異なる4つのウィンドウを選んでください。")
        }
        var resolved: [(Int, SourceWindow)] = []
        for (slot, candidate) in selections {
            try Task.checkCancellation()
            guard let current = currentWindowInfo(candidate.id, pid: candidate.pid) else {
                popups[slot].selectItem(at: 0)
                throw QuadError("選択した対象が見つからないため、その枠の選択を解除しました。対象を前面に出して再選択してください。")
            }
            let app = NSRunningApplication(processIdentifier: candidate.pid)
            if app?.isHidden == true { app?.unhide() }
            if NSApp.isActive, let app { NSApp.yieldActivation(to: app) }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(candidate.pid),
                kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            app?.activate(options: [])
            var source: SourceWindow?
            var lastError: Error?
            for _ in 0..<8 {
                try await Task.sleep(nanoseconds: 100_000_000)
                do {
                    let element = try Access.find(pid: candidate.pid, title: current.title,
                        frame: current.frame, windowID: candidate.id)
                    _ = try await normalElement(element, pid: candidate.pid, windowID: candidate.id,
                        title: current.title, frame: current.frame)
                    source = try SourceWindow(Candidate(id: candidate.id, pid: candidate.pid, appName: candidate.appName,
                        title: current.title, frame: current.frame))
                    break
                } catch { lastError = error }
            }
            guard let source else { throw lastError ?? QuadError("操作対象を確認できませんでした。") }
            resolved.append((slot, source))
        }
        try Task.checkCancellation()
        try store.write(resolved.map { $0.1.saved })
        sources = resolved
        host.sourceNames = resolved.map { ["左上", "右上", "左下", "右下"][$0.0] + " " + $0.1.candidate.appName }
        log.notice("Saved original geometry for \(resolved.count) native windows")
    }

    private func present(on screen: NSScreen, active: @escaping () -> Bool) async throws {
        let area = Projection.quartzRect(appKit: screen.visibleFrame, primaryScreenHeight: screen.frame.height)
        let frames = NativePreviewPlan.tiles(in: area)
        layoutGeneration &+= 1
        confirmedFullscreenSlot = nil
        layoutTimer?.invalidate(); tileFrames = frames; expansion = WindowExpansion()
        for (slot, source) in sources {
            guard active() else { throw CancellationError() }
            source.focus()
            try await Task.sleep(nanoseconds: 100_000_000)
            guard active() else { throw CancellationError() }
            try await refreshAccessibility(source)
            try await Access.setFrame(source.element, frames[slot], windowID: source.candidate.id, pid: source.candidate.pid)
            guard active(), source.refreshFrame() else { throw CancellationError() }
            log.notice("Native pane=\(slot + 1) window=\(source.candidate.id) frame=\(String(describing: source.frame), privacy: .public)")
        }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.detectExpansion() }
        }
        layoutTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func detectExpansion() {
        guard host.fourScreenVisible else { expansion = WindowExpansion(); return }
        guard !expansionProbeInFlight,
              let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let probes = sources.filter { $0.1.candidate.pid == foreground }.map {
            (slot: $0.0, windowID: $0.1.candidate.id, target: AXProbeTarget(pid: $0.1.candidate.pid, element: $0.1.element))
        }
        guard !probes.isEmpty else { expansion = WindowExpansion(); return }
        let generation = layoutGeneration
        let queue = expansionQueue
        expansionProbeInFlight = true
        Task { [weak self] in
            // Read only immutable retained identities off the main loop. A busy
            // app must not block display-watchdog heartbeats or queue more probes.
            let fullscreen: [Int] = await withCheckedContinuation { continuation in
                queue.async {
                    let app = AXUIElementCreateApplication(foreground)
                    AXUIElementSetMessagingTimeout(app, 1)
                    let focused = Access.value(app, kAXFocusedWindowAttribute)
                    var focusedID: CGWindowID?
                    if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                        focusedID = Access.windowID(focused as! AXUIElement)
                    }
                    let slots = probes.compactMap { item -> Int? in
                        guard (Access.value(item.target.element, "AXFullScreen") as? Bool) == true else { return nil }
                        let id = Access.windowID(item.target.element)
                        let same = focused.map { CFEqual($0, item.target.element) } == true
                            || (id != nil && id == focusedID)
                            || (Access.value(item.target.element, kAXFocusedAttribute) as? Bool) == true
                        Logger(subsystem: "io.github.TRN408.QuadDesk", category: "NativeWindows").notice("Fullscreen probe original=\(item.windowID) retained=\(id ?? 0) focused=\(focusedID ?? 0) same=\(same)")
                        return same ? item.slot : nil
                    }
                    continuation.resume(returning: slots)
                }
            }
            guard let self else { return }
            defer { expansionProbeInFlight = false }
            guard layoutGeneration == generation, host.fourScreenVisible,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground else {
                expansion = WindowExpansion(); return
            }
            let enlarged = sources.first { slot, source in
                guard source.candidate.pid == foreground, self.tileFrames.indices.contains(slot),
                      let frame = currentWindowInfo(source.candidate.id, pid: source.candidate.pid)?.frame else { return false }
                return frame.width >= self.tileFrames[slot].width * 1.5 && frame.height >= self.tileFrames[slot].height * 1.5
            }
            let slot = fullscreen.count == 1 ? fullscreen[0] : enlarged?.0
            let source = sources.first { $0.0 == slot }?.1
            let frame = source.flatMap { currentWindowInfo($0.candidate.id, pid: $0.candidate.pid)?.frame }
            let tile = slot.flatMap { self.tileFrames.indices.contains($0) ? self.tileFrames[$0] : nil }
            let isFullscreen = fullscreen.count == 1 && fullscreen.first == slot
            if let selected = expansion.observe(slot: slot, current: frame, tile: tile, isFullscreen: isFullscreen) {
                log.notice("Expansion detected slot=\(selected) fullscreen=\(isFullscreen) frame=\(String(describing: frame), privacy: .public)")
                confirmedFullscreenSlot = isFullscreen ? selected : nil
                host.requestFocus(selected)
            }
        }
    }

    private func prepareFocus(_ index: Int, settle: Bool = true) async throws {
        layoutGeneration &+= 1
        layoutTimer?.invalidate(); layoutTimer = nil
        guard let source = sources.first(where: { $0.0 == index }),
              let app = NSRunningApplication(processIdentifier: source.1.saved.processID),
              app.launchDate == source.1.saved.launchDate, app.bundleIdentifier == source.1.saved.bundleID,
              source.1.isAlive || confirmedFullscreenSlot == index
                || (Access.value(source.1.element, "AXFullScreen") as? Bool) == true else {
            throw QuadError("選んだウィンドウが閉じられています。作業を停止して選び直してください。")
        }
        // For four -> one, release the virtual desktop first. Chrome can accept
        // AXFullScreen=false without finishing the Space transition while it is
        // mirrored. showSingle normalizes on the restored physical desktop.
        // A one -> four resume still normalizes before creating that desktop.
        guard host.isSingleScreenSession else { return }
        if !Access.isFocusedWindow(source.1.element, pid: source.1.candidate.pid) {
            source.1.focus()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        source.1.element = try await normalElement(source.1.element, pid: source.1.candidate.pid,
            windowID: source.1.candidate.id, title: source.1.candidate.title, frame: source.1.frame, settle: settle)
        try await refreshAccessibility(source.1)
    }

    private func refreshAccessibility(_ source: SourceWindow) async throws {
        var lastError: Error?
        for _ in 0..<8 {
            try Task.checkCancellation()
            do { try source.refreshAccessibility(); return }
            catch { lastError = error }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw lastError ?? QuadError("操作対象を確認できませんでした。")
    }

    private func normalElement(_ initial: AXUIElement, pid: pid_t, windowID: CGWindowID,
                               title: String, frame: CGRect, settle: Bool = false) async throws -> AXUIElement {
        var element = initial
        func refresh() {
            if Access.windowID(element) == windowID, Access.frame(element) != nil { return }
            // Never guess a replacement for an absent WindowServer identity.
            guard let current = currentWindowInfo(windowID, pid: pid) else { return }
            if let latest = try? Access.find(pid: pid, title: current.title,
                frame: current.frame, windowID: windowID) { element = latest }
        }
        refresh()
        if (Access.value(element, kAXMinimizedAttribute) as? Bool) == true {
            let result = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            for _ in 0..<20 {
                try Task.checkCancellation()
                refresh()
                if (Access.value(element, kAXMinimizedAttribute) as? Bool) == false { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard (Access.value(element, kAXMinimizedAttribute) as? Bool) == false else {
                throw QuadError("最小化の自動解除が完了しませんでした（AX: \(result.rawValue)）。対象アプリの応答を確認してください。")
            }
        }
        // AXFullScreen can become true after the maximize animation begins.
        // Give an incoming Space transition time to publish its final state.
        if settle {
            for _ in 0..<6 {
                if (Access.value(element, "AXFullScreen") as? Bool) == true { break }
                try await Task.sleep(nanoseconds: 100_000_000)
                refresh()
            }
        }
        let fullScreen = Access.value(element, "AXFullScreen") as? Bool
        log.notice("Normalizing window=\(windowID) fullscreen=\(String(describing: fullScreen), privacy: .public)")
        if fullScreen == true {
            if !Access.isFocusedWindow(element, pid: pid) { Access.focus(element, pid: pid) }
            // AX can report cannotComplete while the asynchronous Space change
            // succeeds. Decide from the observed state, not that return code.
            let result = AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, kCFBooleanFalse)
            for _ in 0..<40 {
                try Task.checkCancellation()
                refresh()
                if (Access.value(element, "AXFullScreen") as? Bool) == false { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard (Access.value(element, "AXFullScreen") as? Bool) == false else {
                log.notice("Fullscreen exit pending original=\(windowID) retained=\(Access.windowID(element) ?? 0) focused=\(Access.isFocusedWindow(element, pid: pid)) frame=\(String(describing: Access.frame(element)), privacy: .public)")
                throw QuadError("フルスクリーンの解除が完了しませんでした（AX: \(result.rawValue)）。解除してから再試行してください。")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            refresh()
        }
        return element
    }

    private func showSingle(_ index: Int, on screen: NSScreen) async throws {
        guard let (_, source) = sources.first(where: { $0.0 == index }),
              let app = NSRunningApplication(processIdentifier: source.saved.processID),
              app.launchDate == source.saved.launchDate, app.bundleIdentifier == source.saved.bundleID else {
            throw QuadError("1画面にするウィンドウを確認できません。")
        }
        let area = Projection.quartzRect(appKit: screen.visibleFrame, primaryScreenHeight: screen.frame.height)
        source.element = try await normalElement(source.element, pid: source.candidate.pid,
            windowID: source.candidate.id, title: source.candidate.title, frame: source.frame, settle: true)
        try await refreshAccessibility(source)
        source.focus()
        try await Task.sleep(nanoseconds: 200_000_000)
        try await refreshAccessibility(source)
        try await Access.setFrame(source.element, area, windowID: source.candidate.id, pid: source.candidate.pid)
        guard source.refreshFrame() else { throw QuadError("拡大後のウィンドウを確認できません。") }
        confirmedFullscreenSlot = nil
        log.notice("Single native source slot=\(index) frame=\(String(describing: source.frame), privacy: .public)")
    }

    @objc private func recoverAction() {
        guard !refreshing, !restoringSources else { return }
        if host.endSession() { return }
        Task {
            do { try await restore(); host.setStatus("元のウィンドウ配置を確認しました。") }
            catch { host.setStatus(error.localizedDescription) }
        }
    }

    private func restore(refreshAfter: Bool = true) async throws {
        guard !restoringSources else { throw QuadError("ウィンドウ配置を復元中です。") }
        restoringSources = true
        layoutGeneration &+= 1
        confirmedFullscreenSlot = nil
        layoutTimer?.invalidate(); layoutTimer = nil
        defer { restoringSources = false; updateSetupState() }
        let records: [SavedWindow]
        switch try SourceSessionRepair.plan(stored: store.read(), expected: sources.map { $0.1.saved }, live: []) {
        case .ready: records = []
        case .recover(let merged): records = merged
        }
        try store.write(records)
        var remaining: [SavedWindow] = []
        for record in records {
            guard let app = NSRunningApplication(processIdentifier: record.processID),
                  app.launchDate == record.launchDate, (app.bundleIdentifier ?? "") == record.bundleID,
                  let current = currentWindowInfo(record.windowID, pid: record.processID) else { continue }
            do {
                let neededAX = try await WindowRestoration.applyIfNeeded(current: current.frame, original: record.originalFrame) {
                    var element: AXUIElement
                    if let live = sources.first(where: { $0.1.saved == record })?.1.element { element = live }
                    else {
                        if app.isHidden { app.unhide() }
                        if NSApp.isActive { NSApp.yieldActivation(to: app) }
                        let frontmost = AXUIElementSetAttributeValue(AXUIElementCreateApplication(record.processID),
                            kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                        let accepted = app.activate(options: [])
                        log.notice("Activating recovery owner pid=\(record.processID) hidden=\(app.isHidden) active=\(app.isActive) accepted=\(accepted) AX=\(frontmost.rawValue)")
                        try await Task.sleep(nanoseconds: 200_000_000)
                        var found: AXUIElement?
                        var lastError: Error?
                        for _ in 0..<8 {
                            do {
                                found = try Access.find(pid: record.processID, title: current.title,
                                    frame: current.frame, windowID: record.windowID)
                                break
                            } catch { lastError = error; try await Task.sleep(nanoseconds: 100_000_000) }
                        }
                        guard let found else { throw lastError ?? QuadError("復元先を確認できません。") }
                        element = found
                    }
                    element = try await normalElement(element, pid: record.processID, windowID: record.windowID,
                        title: current.title, frame: current.frame)
                    let logical = Access.frame(element)
                    log.notice("Recovery window=\(record.windowID) CG=\(String(describing: current.frame), privacy: .public) AX=\(String(describing: logical), privacy: .public) original=\(String(describing: record.originalFrame), privacy: .public)")
                    if let logical,
                       abs(logical.minX-record.originalFrame.minX) < 3, abs(logical.minY-record.originalFrame.minY) < 3,
                       abs(logical.width-record.originalFrame.width) < 3, abs(logical.height-record.originalFrame.height) < 3 {
                        log.notice("Recovery window=\(record.windowID) already at original logical frame")
                        return
                    }
                    Access.focus(element, pid: record.processID)
                    try await Task.sleep(nanoseconds: 100_000_000)
                    try await Access.setFrame(element, record.originalFrame, windowID: record.windowID, pid: record.processID)
                }
                if !neededAX { log.notice("Recovery window=\(record.windowID) already at original WindowServer frame") }
            } catch {
                let errorText = error.localizedDescription.replacingOccurrences(of: current.title, with: "対象ウィンドウ")
                log.error("Recovery failed window=\(record.windowID) CG=\(String(describing: current.frame), privacy: .public) reason=\(errorText, privacy: .public)")
                remaining.append(record)
            }
        }
        try store.write(remaining); sources.removeAll()
        log.notice("Native windows restored remaining=\(remaining.count)")
        guard remaining.isEmpty else { throw QuadError("\(remaining.count)件の配置を復元できません。前回の配置を復元から再試行してください。") }
        if refreshAfter { await reloadCandidates() }
    }
}
