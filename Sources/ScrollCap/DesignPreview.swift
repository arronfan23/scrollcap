import AppKit
import SwiftUI

#if DESIGN_PREVIEW
@MainActor
func traceEditorWindows(_ event: String) {
    let text = "\(Date().timeIntervalSince1970) \(event): " + NSApp.windows.map { "\($0.title)=\($0.isVisible)" }.joined(separator: ", ") + "\n"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollCap-editor-lifecycle.log")
    if let data = text.data(using: .utf8), let stream = try? FileHandle(forWritingTo: url) {
        defer { try? stream.close() }; _ = try? stream.seekToEnd(); try? stream.write(contentsOf: data)
    } else { try? text.write(to: url, atomically: true, encoding: .utf8) }
}
#endif

// This fixture is enabled only by a separate, explicitly identified design build.
// Production builds include only the empty configure entry point below.
#if DESIGN_PREVIEW
@MainActor
enum DesignPreview {
    static var isActive: Bool { Bundle.main.bundleIdentifier == "io.github.arronfan23.scrollcap.designpreview" }
    private static var controller: DesignPreviewController?
    static func configure(model: CaptureModel, window: NSWindow) {
        guard isActive else { return }
        let demo = DesignPreviewController(model: model, window: window)
        controller = demo; demo.configure()
    }
    static func start(model: CaptureModel, importing: Bool = false) { controller?.begin(importing: importing) }
    static func stop(model: CaptureModel) { controller?.stop() }
}

@MainActor
private final class DesignPreviewController: NSObject {
    let model: CaptureModel
    weak var window: NSWindow?
    private var picker: ChromePicker?
    private var timer: Timer?
    private var hud: NSPanel?
    private var target: NSWindow?
    private var demoScroll: NSScrollView?
    private lazy var longImage = Self.chatImage(long: true)
    private lazy var viewport = Self.chatImage(long: false)

    init(model: CaptureModel, window: NSWindow) { self.model = model; self.window = window }
    func configure() {
        window?.title = "ScrollCap 设计预览"
        model.screenGranted = true; model.accessGranted = true
        let menu = NSMenu(title: "界面预览")
        let items = [("准备截图", 0), ("演示采集流程", 1), ("正在合成", 2), ("裁剪与导出", 3), ("部分结果提示", 4), ("权限待开启", 5),
                     ("浅色界面", 6), ("深色界面", 7), ("最小窗口", 8), ("默认窗口", 9), ("标记滚动区域", 10)]
        for (title, tag) in items {
            if [6, 8, 10].contains(tag) { menu.addItem(.separator()) }
            let item = menu.addItem(withTitle: title, action: #selector(selectScene(_:)), keyEquivalent: "")
            item.tag = tag; item.target = self
        }
        let root = NSMenuItem(title: "界面预览", action: nil, keyEquivalent: ""); root.submenu = menu
        NSApp.mainMenu?.addItem(root)
    }
    @objc private func selectScene(_ sender: NSMenuItem) {
        if sender.tag == 6 || sender.tag == 7 {
            window?.appearance = NSAppearance(named: sender.tag == 6 ? .aqua : .darkAqua); return
        }
        if sender.tag == 8 || sender.tag == 9 {
            if sender.tag == 8, let window {
                window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 900, height: 750)), display: true)
            } else { window?.setContentSize(NSSize(width: 1040, height: 780)) }
            return
        }
        reset()
        switch sender.tag {
        case 1, 10: begin(importing: false)
        case 2:
            model.processing = true; model.progress = 0.62
            model.status = "正在匹配清晰画面，拼接滚动正文…"
        case 3, 4: result(partial: sender.tag == 4)
        case 5:
            model.screenGranted = false; model.accessGranted = false; model.automatic = true
            model.status = "开启屏幕录制后，即可框选网页或聊天窗口。"
        default: break
        }
    }
    private func reset() {
        timer?.invalidate(); timer = nil
        hud?.orderOut(nil); hud = nil; target?.orderOut(nil); target = nil; demoScroll = nil
        model.resetDesignState(); model.screenGranted = true; model.accessGranted = true
        model.showMain()
    }
    func begin(importing: Bool) {
        guard !model.busy else { return }
        if !importing && !model.applyStartPermissions(CapturePermissions(screen: model.screenGranted, automation: model.accessGranted)) { return }
        reset(); model.preparing = true
        if !importing && model.captureKind == .single {
            model.setResultImage(viewport, kind: .single); model.preparing = false
            model.status = "普通截图演示已生成，可直接标注。"
            window?.orderOut(nil)
            model.presentResultEditor(pinned: model.preferences.autoPinSingle)
            return
        }
        model.status = importing ? "正在载入演示视频…" : "正在标记演示窗口…"
        window?.orderOut(nil)
        let selector = ChromePicker(); picker = selector
        selector.begin(image: viewport) { [weak self] selection in
            guard let self else { return }; self.picker = nil
            guard selection != nil else { self.reset(); return }
            if importing { self.process() } else { self.record() }
        }
    }
    private func record() {
        model.preparing = false; model.capturing = true; model.elapsed = 0
        model.autoStatus = model.automatic ? "演示自动滚动，请等待采集完成" : "演示采集中，点击结束并生成"
        let frame = NSRect(x: 0, y: 0, width: 560, height: 620)
        let panel = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "演示聊天窗口 · 不会录制屏幕"; panel.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: frame); scroll.hasVerticalScroller = true
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 560, height: 1460))
        imageView.image = NSImage(cgImage: longImage, size: imageView.frame.size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        scroll.documentView = imageView; panel.contentView = scroll
        panel.center(); panel.makeKeyAndOrderFront(nil)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: imageView.frame.height - scroll.contentSize.height))
        target = panel; demoScroll = scroll
        let floating = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        floating.title = "长截图进行中 · 交互演示"; floating.level = .floating; floating.hidesOnDeactivate = false
        floating.contentView = NSHostingView(rootView: CaptureHUD(model: model))
        if let screen = window?.screen {
            floating.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.maxY - 50))
        }
        floating.orderFrontRegardless(); hud = floating
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        model.elapsed += 1; model.count = model.elapsed * 30
        if model.automatic, let scroll = demoScroll {
            let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, maxY - CGFloat(model.elapsed) * 90)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if model.automatic && model.elapsed >= 8 { process() }
    }
    func stop() {
        if model.capturing { process() }
        else if model.processing { reset(); model.status = "已取消演示处理。" }
        else if model.preparing { picker?.cancel(); picker = nil; reset() }
    }
    private func process() {
        timer?.invalidate(); timer = nil
        hud?.orderOut(nil); hud = nil; target?.orderOut(nil); target = nil
        model.capturing = false; model.preparing = false; model.processing = true; model.progress = 0
        model.status = "正在分析演示内容…"; model.showMain()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.progress = min(1, self.model.progress + 0.05)
                if self.model.progress >= 1 {
                    self.timer?.invalidate(); self.timer = nil; self.result(partial: false)
                }
            }
        }
    }
    private func result(partial: Bool) {
        model.processing = false; model.preparing = false
        model.setResultImage(longImage, kind: .scrolling); model.count = 12
        model.resultWarning = partial ? "有一段滚动过快，无法确认接缝。当前预览包含已确认的部分。" : nil
        model.status = partial ? "部分内容需要检查，请核对预览后保存。" : "长图已生成，可以拖动四边裁剪后保存。"
        model.showMain()
    }
    private static func chatImage(long: Bool) -> CGImage {
        let width = 1120, height = long ? 2920 : 1080
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill(); rect.fill()
            func text(_ string: String, _ rect: CGRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
                (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }
            let ink = NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.25, alpha: 1)
            let muted = NSColor(calibratedRed: 0.40, green: 0.47, blue: 0.51, alpha: 1)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: 130).fill()
            NSColor.systemTeal.withAlphaComponent(0.15).setFill(); NSBezierPath(roundedRect: NSRect(x: 42, y: 32, width: 64, height: 64), xRadius: 18, yRadius: 18).fill()
            text("S", NSRect(x: 62, y: 44, width: 38, height: 42), size: 30, color: .systemTeal, weight: .semibold)
            text("产品设计讨论", NSRect(x: 130, y: 32, width: 620, height: 40), size: 30, color: ink, weight: .semibold)
            text("ScrollCap · 演示内容", NSRect(x: 130, y: 80, width: 620, height: 30), size: 20, color: muted)
            let messages = ["新版的长截图体验，我们先从哪里开始？", "先把最常用的流程做清楚：选择、采集、裁剪、保存。", "标题和输入框也要保留下来。", "会滚动的正文连续拼接，固定部分只保留一次。", "手动滚动时，怎样才能少漏内容？", "每次滚动约四分之一屏，停半秒，让文字保持清晰。", "采集结束后，我想调整四周的边界。", "可以直接拖动四边或四角，也能移动整个裁剪选区。", "浅色和深色模式都需要好用。", "按钮、文字和选区会跟随系统外观保持清晰。", "这样就能把一整段对话留下来了。", "对，一张完整的长图，随时保存或复制。"]
            let rows = long ? messages.count : 4
            for index in 0..<rows {
                let outgoing = index % 2 == 1
                let y = 180 + index * 210
                let bubble = NSRect(x: outgoing ? 250 : 100, y: y, width: 760, height: 142)
                (outgoing ? NSColor(calibratedRed: 0.79, green: 0.93, blue: 0.90, alpha: 1) : NSColor.white).setFill()
                NSBezierPath(roundedRect: bubble, xRadius: 22, yRadius: 22).fill()
                text(outgoing ? "我" : "设计同事", NSRect(x: bubble.minX + 25, y: bubble.minY + 20, width: 500, height: 30), size: 20, color: muted)
                text(messages[index], NSRect(x: bubble.minX + 25, y: bubble.minY + 62, width: bubble.width - 50, height: 70), size: 26, color: ink)
            }
            NSColor.white.setFill(); NSRect(x: 0, y: height - 138, width: width, height: 138).fill()
            NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 42, y: height - 108, width: 890, height: 74), xRadius: 18, yRadius: 18).fill()
            text("输入消息…", NSRect(x: 66, y: height - 88, width: 700, height: 38), size: 25, color: muted)
            text("发送", NSRect(x: 968, y: height - 88, width: 120, height: 38), size: 25, color: .systemTeal, weight: .semibold)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
#else
@MainActor
enum DesignPreview {
    static func configure(model: CaptureModel, window: NSWindow) {}
}
#endif
