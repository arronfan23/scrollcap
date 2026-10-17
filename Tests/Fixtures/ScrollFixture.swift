import AppKit
import WebKit

final class FixtureScroll: NSScrollView {
    var deltas: [CGFloat] = []
    var flags: UInt = 0
    var observed: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        deltas.append(event.scrollingDeltaY); if deltas.count > 40 { deltas.removeFirst() }
        flags = event.modifierFlags.rawValue
        super.scrollWheel(with: event); observed?()
    }
}

final class FixtureDocument: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); dirtyRect.fill()
        for row in 0..<24 {
            let y = CGFloat(row * 80 + 18)
            NSColor(calibratedHue: CGFloat((row * 37) % 100) / 100, saturation: 0.45, brightness: 0.8, alpha: 1).setFill()
            CGRect(x: 24, y: y, width: CGFloat(140 + row * 31 % 340), height: 12).fill()
            (String(format: "SCAP-%02d", row + 1) as NSString).draw(at: CGPoint(x: 24, y: y + 20),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.black])
            ("第 \(row + 1) 条测试消息 · 固定部分只保留一次" as NSString).draw(at: CGPoint(x: 160, y: y + 23),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray])
        }
    }
}

final class FixtureChrome: NSView {
    let text: String
    init(_ rect: CGRect, text: String) { self.text = text; super.init(frame: rect) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); bounds.fill()
        (text as NSString).draw(at: CGPoint(x: 24, y: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray])
    }
}

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var scroll: NSScrollView!
    var web: WKWebView!
    var root: NSView!
    var webMode = false
    var pendingMove = false, pendingHide = false
    var webOffset: Double = 0
    let bodyRect = CGRect(x: 0, y: 70, width: 640, height: 450)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: CGRect(x: 120, y: 100, width: 640, height: 580), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ScrollCap 自测窗口 · 24 条编号消息"
        root = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 580)); window.contentView = root
        root.addSubview(FixtureChrome(CGRect(x: 0, y: 520, width: 640, height: 60), text: "HEADER-ONCE · 固定标题"))
        root.addSubview(FixtureChrome(CGRect(x: 0, y: 0, width: 640, height: 70), text: "FOOTER-ONCE · 固定输入框"))
        let fixtureScroll = FixtureScroll(frame: bodyRect); scroll = fixtureScroll
        fixtureScroll.observed = { [weak self] in self?.wheelReceived(); self?.writeState() }
        scroll.hasVerticalScroller = false
        scroll.documentView = FixtureDocument(frame: CGRect(x: 0, y: 0, width: 640, height: 1940))
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in Task { @MainActor in self?.writeState() } }
        root.addSubview(scroll)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "scrollPosition")
        web = WKWebView(frame: bodyRect, configuration: configuration); web.navigationDelegate = self
        let rows = (1...24).map { i in "<section><i style='width:\(140 + (i - 1) * 31 % 340)px;background:hsl(\((i - 1) * 133),45%,65%)'></i><b>\(String(format: "SCAP-%02d", i))</b><span>第 \(i) 条网页测试消息</span></section>" }.joined()
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><style>*{box-sizing:border-box}html,body{margin:0;background:white}body{padding:18px 24px 2px}section{height:80px;position:relative}i{display:block;height:12px;margin-bottom:20px}b{font:20px Menlo}span{font:15px -apple-system;margin-left:20px}::-webkit-scrollbar{display:none}</style>\(rows)<script>addEventListener('scroll',()=>webkit.messageHandlers.scrollPosition.postMessage(scrollY))</script>", baseURL: nil)
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出自测窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = appMenu; menu.addItem(appItem)
        let testItem = NSMenuItem(), testMenu = NSMenu(title: "测试")
        for (title, action, key) in [("回到顶部", #selector(top), "t"), ("去到底部", #selector(bottom), "b"), ("切换原生 / 网页", #selector(toggle), "w"),
                                     ("滚动 3 秒后移动测试窗口", #selector(scheduleMove), ""), ("滚动 3 秒后隐藏测试窗口", #selector(scheduleHide), "")] {
            let item = testMenu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        testItem.title = "测试"; testItem.submenu = testMenu; menu.addItem(testItem); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        writeState()
    }
    @objc func top() {
        window.setFrameOrigin(CGPoint(x: 120, y: 100))
        present()
        if webMode { web.evaluateJavaScript("window.scrollTo(0,0)") }
        else { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    @objc func bottom() {
        present()
        if webMode { web.evaluateJavaScript("window.scrollTo(0,document.body.scrollHeight)") }
        else { scroll.contentView.scroll(to: CGPoint(x: 0, y: 1490)); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    @objc func toggle() {
        webMode.toggle(); scroll.isHidden = webMode
        if webMode { root.addSubview(web) } else { web.removeFromSuperview() }
        top(); writeState()
    }
    func present() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func scheduleMove() { pendingMove = true }
    @objc func scheduleHide() { pendingHide = true }
    func wheelReceived() {
        let move = pendingMove, hide = pendingHide
        pendingMove = false; pendingHide = false
        guard move || hide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if move { self.window.setFrameOrigin(CGPoint(x: self.window.frame.minX + 40, y: self.window.frame.minY)) }
            if hide { NSApp.hide(nil) }
            self.writeState()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { writeState() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        webOffset = (message.body as? NSNumber)?.doubleValue ?? 0; writeState()
    }
    func writeState() {
        guard let window, window.isVisible, let screen = window.screen else { return }
        let directory = ProcessInfo.processInfo.environment["SCROLLCAP_FIXTURE_DIR"] ?? Bundle.main.bundleURL.deletingLastPathComponent().path
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
        let global = window.convertToScreen(root.bounds), bounds = CGDisplayBounds(id)
        let state: [String: Any] = ["x": bounds.minX + global.minX - screen.frame.minX, "y": bounds.minY + screen.frame.maxY - global.maxY,
            "width": 640, "height": 580, "header": 60, "footer": 70, "body": 450, "document": 1940,
            "scale": screen.backingScaleFactor, "display": id, "pid": ProcessInfo.processInfo.processIdentifier, "web": webMode]
        var values = state; values["offset"] = webMode ? webOffset : scroll.contentView.bounds.minY
        if let source = scroll as? FixtureScroll { values["wheelDeltas"] = source.deltas; values["wheelFlags"] = source.flags }
        try? JSONSerialization.data(withJSONObject: values, options: .prettyPrinted).write(to: URL(fileURLWithPath: directory).appendingPathComponent("fixture.json"), options: .atomic)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = FixtureDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}
