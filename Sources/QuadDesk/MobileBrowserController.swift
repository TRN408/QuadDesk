import AppKit
import WebKit
import QuadCore

/// Independent of the display/AX session. Every column owns a real, live web view.
@MainActor
final class MobileBrowserController: NSObject, NSWindowDelegate {
    static let maximumPanes = BrowserGridPlan.maximumPanes
    private(set) var panes: [MobileBrowserPane] = []
    private(set) var window: NSWindow?
    let grid = MobileBrowserGridView()
    private let addButton = NSButton(title: "タブを追加", target: nil, action: nil)
    private let count = NSTextField(labelWithString: "")
    private let mode = NSPopUpButton()
    private let dataStore: WKWebsiteDataStore
    private let paneLimit: Int

    init(dataStore: WKWebsiteDataStore? = nil, paneLimit: Int = BrowserGridPlan.maximumPanes) {
        self.dataStore = dataStore ?? .default()
        self.paneLimit = max(1, min(Self.maximumPanes, paneLimit))
        super.init()
        grid.onLayout = { [weak self] plan in self?.updateControls(plan: plan) }
    }

    func installMenu() {
        guard let root = NSApp.mainMenu else { return }
        let item = NSMenuItem(title: "ブラウザ", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "ブラウザ")
        menu.addItem(withTitle: "モバイルブラウザを開く", action: #selector(show), keyEquivalent: "b").target = self
        item.submenu = menu; root.addItem(item)
        if !root.items.contains(where: { $0.title == "編集" }) {
            let edit = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
            let actions = NSMenu(title: "編集")
            for (title, action, key) in [("取り消す", "undo:", "z"), ("切り取り", "cut:", "x"),
                                         ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"),
                                         ("すべて選択", "selectAll:", "a")] {
                actions.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
            }
            edit.submenu = actions; root.addItem(edit)
        }
    }

    @objc func show() {
        if window == nil { createWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        let window = NSWindow(contentRect: area, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        window.setFrame(area, display: false)
        window.title = "QuadDesk — モバイル画面分割"
        window.contentMinSize = CGSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false; window.delegate = self
        let content = NSView(); window.contentView = content
        let title = NSTextField(labelWithString: "モバイル画面分割")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        count.textColor = .secondaryLabelColor
        addButton.target = self; addButton.action = #selector(addAction); addButton.bezelStyle = .rounded
        mode.addItems(withTitles: BrowserGridMode.allCases.map(\.title))
        mode.target = self; mode.action = #selector(gridModeChanged)
        mode.setAccessibilityLabel("画面分割の配置")
        let fill = NSButton(title: "入るだけ追加", target: self, action: #selector(fillAction))
        fill.bezelStyle = .rounded
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [title, mode, count, spacer, fill, addButton]); toolbar.spacing = 8
        for view in [toolbar, grid] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            grid.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor), grid.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.layoutSubtreeIfNeeded()
        fillAction()
    }

    @discardableResult
    func addPane(configuration: WKWebViewConfiguration? = nil) -> MobileBrowserPane? {
        guard panes.count < paneLimit else { return nil }
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil { config.websiteDataStore = dataStore }
        let pane = MobileBrowserPane(configuration: config)
        pane.onClose = { [weak self, weak pane] in
            guard let self, let pane else { return }; self.removePane(pane)
        }
        pane.onNewWindow = { [weak self] config in self?.addPane(configuration: config)?.webView }
        pane.onViewportChanged = { [weak self] in self?.grid.needsLayout = true }
        panes.append(pane); grid.add(pane); updateControls(plan: grid.plan)
        return pane
    }

    func removePane(_ pane: MobileBrowserPane) {
        guard panes.contains(where: { $0 === pane }) else { return }
        pane.dispose(); grid.remove(pane); pane.removeFromSuperview()
        panes.removeAll { $0 === pane }; updateControls(plan: grid.plan)
    }

    @objc private func addAction() {
        guard let pane = addPane() else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.makeFirstResponder(pane.address)
    }
    @objc private func gridModeChanged() {
        grid.mode = BrowserGridMode.allCases[mode.indexOfSelectedItem]
        grid.layoutSubtreeIfNeeded()
    }
    @objc private func fillAction() {
        let plan = BrowserGridPlan(available: grid.bounds.size, mode: grid.mode, paneCount: panes.count)
        let target = min(paneLimit, plan.recommendedCapacity)
        while panes.count < target { _ = addPane() }
        grid.needsLayout = true; grid.layoutSubtreeIfNeeded()
    }
    private func updateControls(plan: BrowserGridPlan) {
        let text = "\(plan.rows)段 × \(plan.columns)列 · \(Int(plan.scale * 100))% · \(panes.count)画面"
        if count.stringValue != text { count.stringValue = text }
        addButton.isEnabled = panes.count < paneLimit
    }
    func windowWillClose(_ notification: Notification) { close() }
    func close() {
        for pane in panes { pane.dispose(); grid.remove(pane); pane.removeFromSuperview() }
        panes.removeAll()
        window?.delegate = nil; window?.orderOut(nil); window = nil
    }
}

@MainActor
final class MobileBrowserPane: NSView, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let address = NSTextField()
    private(set) var viewport: MobileViewport = .standard
    let status = NSTextField(labelWithString: "URLを入力して開く")
    private let mode = NSPopUpButton()
    private let back = NSButton(), forward = NSButton(), reload = NSButton()
    private let heading = NSTextField(labelWithString: "新しいタブ")
    private let empty = NSTextField(wrappingLabelWithString: "ここでWebサイトを開く\n\n上の欄にURLを入力してください。\n例：https://example.com")
    private var width: NSLayoutConstraint!
    private var observations: [NSKeyValueObservation] = []
    var onClose: (() -> Void)?
    var onViewportChanged: (() -> Void)?
    var onNewWindow: ((WKWebViewConfiguration) -> WKWebView?)?
    private var disposed = false

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 0
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = icon("xmark", "タブを閉じる", #selector(closeAction))
        let header = NSStackView(views: [heading, close]); header.spacing = 8
        address.placeholderString = "URLを入力（https://…）"
        address.font = .systemFont(ofSize: 12); address.target = self; address.action = #selector(openAddress)
        address.setAccessibilityLabel("このタブのURL")
        address.lineBreakMode = .byTruncatingTail
        configure(back, "chevron.left", "戻る", #selector(goBack))
        configure(forward, "chevron.right", "進む", #selector(goForward))
        configure(reload, "arrow.clockwise", "再読み込み／読み込みを停止", #selector(reloadOrStop))
        mode.addItems(withTitles: MobileViewport.allCases.map(\.title))
        mode.selectItem(at: 1); mode.target = self; mode.action = #selector(viewportChanged)
        mode.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        mode.setAccessibilityLabel("表示幅")
        let controls = NSStackView(views: [back, forward, reload, mode]); controls.spacing = 6
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        empty.alignment = .center; empty.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize: 14)
        for view in [header, address, controls, webView, status, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        width = widthAnchor.constraint(equalToConstant: CGFloat(viewport.rawValue))
        NSLayoutConstraint.activate([
            width, header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            address.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            address.leadingAnchor.constraint(equalTo: header.leadingAnchor), address.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            controls.topAnchor.constraint(equalTo: address.bottomAnchor, constant: 6), controls.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
            webView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: header.leadingAnchor), status.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            empty.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: header.leadingAnchor), empty.trailingAnchor.constraint(equalTo: header.trailingAnchor)
        ])
        applyViewport(.standard, reloadPage: false)
        observations = [webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateNavigation() } },
                        webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateNavigation() } },
                        webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateNavigation() } },
                        webView.observe(\.url, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncAddress() } },
                        webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                            MainActor.assumeIsolated { self?.heading.stringValue = view.title ?? "新しいタブ" }
                        }]
    }
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    private func icon(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(); configure(button, symbol, label, action); return button
    }
    private func configure(_ button: NSButton, _ symbol: String, _ label: String, _ action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.title = ""; button.target = self; button.action = action; button.bezelStyle = .inline
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    private func updateNavigation() {
        back.isEnabled = webView.canGoBack; forward.isEnabled = webView.canGoForward
        reload.image = NSImage(systemSymbolName: webView.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: "再読み込み／停止")
    }
    @objc func openAddress() {
        guard let url = BrowserAddress.resolve(address.stringValue) else {
            status.stringValue = "http:// または https:// のURLを入力してください。"; return
        }
        load(url)
        window?.makeFirstResponder(webView)
    }
    func load(_ url: URL) {
        guard BrowserAddress.allowsNavigation(to: url), !disposed else { return }
        address.stringValue = url.absoluteString; empty.isHidden = true
        webView.load(URLRequest(url: url))
    }
    func applyViewport(_ viewport: MobileViewport, reloadPage: Bool = true) {
        self.viewport = viewport; width.constant = CGFloat(viewport.rawValue)
        mode.selectItem(at: MobileViewport.allCases.firstIndex(of: viewport)!)
        // This requests mobile site variants. It is still macOS WebKit, not an iPhone runtime.
        webView.customUserAgent = viewport.isMobile
            ? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
            : nil
        onViewportChanged?()
        if reloadPage, webView.url != nil { webView.reload() }
    }
    @objc private func viewportChanged() { applyViewport(MobileViewport.allCases[mode.indexOfSelectedItem]) }
    @objc private func closeAction() { onClose?() }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadOrStop() {
        if webView.isLoading { webView.stopLoading(); status.stringValue = "読み込みを停止しました。" }
        else { webView.reload() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, BrowserAddress.allowsNavigation(to: url, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true), !navigationAction.shouldPerformDownload else {
            status.stringValue = "このリンクは開けません。Webページの表示に対応しています。"
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.canShowMIMEType else {
            status.stringValue = "この形式の表示・ダウンロードには対応していません。"
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        empty.isHidden = true; status.stringValue = "読み込み中…"
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { syncAddress() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncAddress(); status.stringValue = "\(viewport.rawValue) px · \(viewport.isMobile ? "モバイル表示" : "PC表示")"
    }
    private func syncAddress() {
        // Do not replace a URL while the user is typing a new one.
        if address.currentEditor() == nil { address.stringValue = webView.url?.absoluteString ?? "" }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
    private func show(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        status.stringValue = "読み込めません：\(error.localizedDescription)"; status.toolTip = status.stringValue
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { status.stringValue = "ページが終了しました。再読み込みしてください。" }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, BrowserAddress.allowsNavigation(to: url) else { return nil }
        guard let view = onNewWindow?(configuration) else {
            status.stringValue = "タブは最大\(MobileBrowserController.maximumPanes)個です。不要なタブを閉じてください。"; return nil
        }
        return view
    }
    func webViewDidClose(_ webView: WKWebView) { onClose?() }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard let window else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }

    private func dialog(_ message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "Webページ" : frame.securityOrigin.host
        alert.informativeText = message
        return alert
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window else { completionHandler(); return }
        let alert = dialog(message, frame: frame); alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window else { completionHandler(false); return }
        let alert = dialog(message, frame: frame); alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "キャンセル")
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let window else { completionHandler(nil); return }
        let alert = dialog(prompt, frame: frame); alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "キャンセル")
        let input = NSTextField(frame: CGRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = defaultText ?? ""; alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil) }
    }

    func dispose() {
        disposed = true; observations.removeAll()
        webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.removeFromSuperview(); onClose = nil; onNewWindow = nil; onViewportChanged = nil
    }
}

@MainActor
final class MobileBrowserApp: NSObject, NSApplicationDelegate {
    let browser = MobileBrowserController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let root = NSMenu(), item = NSMenuItem(), menu = NSMenu()
        root.addItem(item); item.submenu = menu
        menu.addItem(withTitle: "QuadDeskを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = root; browser.installMenu(); browser.show()
    }
    func applicationWillTerminate(_ notification: Notification) { browser.close() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
