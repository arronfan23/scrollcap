import AppKit
import UniformTypeIdentifiers

@MainActor
final class PinnedScreenshotManager {
    static let shared = PinnedScreenshotManager()
    private var windows: [UUID: ScreenshotEditorWindow] = [:]
    var count: Int { windows.count }
    @discardableResult
    func pin(_ image: CGImage) -> UUID { show(image, pinned: true) }
    @discardableResult
    func show(_ image: CGImage, region: CaptureRegion? = nil, pinned: Bool = false, warning: String? = nil,
              historyID: UUID = UUID(), kind: CaptureKind = .single, history: ScreenshotHistoryStore? = nil,
              onClose: (() -> Void)? = nil) -> UUID {
        showDocument(ScreenshotDocument(image), region: region, pinned: pinned, warning: warning,
                     historyID: historyID, kind: kind, history: history ?? .shared, onClose: onClose)
    }
    @discardableResult
    func showDocument(_ document: ScreenshotDocument, region: CaptureRegion? = nil, pinned: Bool = false, warning: String? = nil,
                      historyID: UUID, kind: CaptureKind, history: ScreenshotHistoryStore, editingHistory: Bool = false,
                      onClose: (() -> Void)? = nil) -> UUID {
        if let existing = windows.first(where: { $0.value.historyID == historyID }) {
            if pinned { existing.value.performMenuAction("pin") }
            if editingHistory { existing.value.editFromHistory() } else { existing.value.focus() }
            return existing.key
        }
        let id = UUID()
        let editor = ScreenshotEditorWindow(document: document, region: region, pinned: pinned, warning: warning,
                                            historyID: historyID, kind: kind, history: history, editingHistory: editingHistory) { [weak self] in
            self?.windows[id] = nil
            onClose?()
        }
        windows[id] = editor; editor.show()
        return id
    }
    @discardableResult
    func closeAll() -> Bool { let current = Array(windows.values); current.forEach { $0.close() }; return windows.isEmpty }
    func closeHistory(_ ids: Set<UUID>) { Array(windows.values).filter { ids.contains($0.historyID) }.forEach { $0.close(retainAutomatically: false) } }
    func bringForward() { windows.values.forEach { $0.focus() } }
    func handleMenuAction(_ action: String, fallbackToVisible: Bool) -> Bool {
        let editor = windows.values.first { $0.owns(NSApp.keyWindow) }
            ?? (fallbackToVisible ? NSApp.orderedWindows.compactMap { window in windows.values.first { $0.owns(window) } }.first : nil)
        guard let editor else { return false }
        editor.performMenuAction(action); return true
    }
}

private final class ScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotEditorWindow: NSObject, NSWindowDelegate {
    private let document: ScreenshotDocument
    private let panel: ScreenshotPanel
    private let toolbox: ScreenshotPanel
    private let canvas: ScreenshotCanvas
    private var buttons: [String: NSButton] = [:]
    private var pinned: Bool
    private var closed: (() -> Void)?
    private var eventMonitor: Any?
    private var popover: NSPopover?
    private var closing = false
    private var zoomScale: CGFloat = 1
    private let initialSize: CGSize
    private let warning: String?
    let historyID: UUID
    private let kind: CaptureKind
    private let history: ScreenshotHistoryStore
    private var editingHistory: Bool
    private var automaticallyRetain: Bool
    private var archivedMarks: [ScreenshotMark]?

    init(document: ScreenshotDocument, region: CaptureRegion?, pinned: Bool, warning: String?,
         historyID: UUID, kind: CaptureKind, history: ScreenshotHistoryStore, editingHistory: Bool, closed: @escaping () -> Void) {
        self.document = document; canvas = ScreenshotCanvas(document: document)
        self.historyID = historyID; self.kind = kind; self.history = history; self.editingHistory = editingHistory
        automaticallyRetain = !editingHistory && AppPreferences.shared.historyRetention == .all
        archivedMarks = editingHistory ? document.marks : nil
        let image = document.original
        self.pinned = pinned; self.warning = warning; self.closed = closed
        let screen = region.flatMap { region in NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == region.displayID } } ?? NSScreen.main ?? NSScreen.screens[0]
        let native = CGSize(width: CGFloat(image.width) / (region?.scale ?? screen.backingScaleFactor), height: CGFloat(image.height) / (region?.scale ?? screen.backingScaleFactor))
        var rect: CGRect
        if let region {
            rect = ScreenshotGeometry.cocoaRect(quartz: region.rect, displayBounds: region.displayBounds, screenFrame: screen.frame)
            if image.height != Int((region.rect.height * region.scale).rounded()) {
                let scale = min(1, screen.visibleFrame.height * 0.82 / native.height, screen.visibleFrame.width * 0.9 / native.width)
                let size = CGSize(width: native.width * scale, height: native.height * scale)
                rect = CGRect(x: rect.minX, y: rect.maxY - size.height, width: size.width, height: size.height)
                rect.origin.y = max(screen.visibleFrame.minY, rect.minY)
            }
        } else {
            let scale = min(1, screen.visibleFrame.height * 0.8 / native.height, screen.visibleFrame.width * 0.8 / native.width)
            let size = CGSize(width: native.width * scale, height: native.height * scale)
            rect = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
        }
        initialSize = rect.size
        panel = ScreenshotPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbox = ScreenshotPanel(contentRect: CGRect(x: 0, y: 0, width: 308, height: warning == nil ? 88 : 122), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        for window in [panel, toolbox] {
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.level = pinned ? .floating : .normal
            window.hasShadow = true; window.isOpaque = false; window.backgroundColor = .clear
        }
        panel.title = "ScrollCap 截图"; toolbox.title = "ScrollCap 标注工具"
        panel.delegate = self; panel.contentView = canvas
        panel.setFrame(rect, display: false)
        buildTools()
        canvas.changed = { [weak self] in self?.updateTools() }
        canvas.showTools = { [weak self] in self?.showTools() }
        canvas.zoom = { [weak self] factor, anchor in self?.zoom(factor, anchor: anchor) }
        canvas.closeEditor = { [weak self] in self?.close() }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.panel || event.window === self.toolbox || event.window === self.popover?.contentViewController?.view.window else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.close(); return nil }
            guard event.type == .keyDown, event.modifierFlags.contains(.command), !(self.panel.firstResponder is NSTextView) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": self.copyImage(); return nil
            case "s": self.saveImage(exportPNG: event.modifierFlags.contains(.option)); return nil
            case "z": event.modifierFlags.contains(.shift) ? self.canvas.redo() : self.canvas.undo(); return nil
            case "w": self.close(); return nil
            default: return event
            }
        }
        updateTools()
    }
    func show() {
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas); showTools()
        if automaticallyRetain { archiveHistory() }
#if DESIGN_PREVIEW
        traceEditorWindows("editor-show")
#endif
    }
    func focus() { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas); showTools() }
    func editFromHistory() {
        editingHistory = true; automaticallyRetain = false
        let help = "保存修改到历史（Command + S）；Option + Command + S 另存 PNG"
        buttons["save"]?.toolTip = help; buttons["save"]?.setAccessibilityLabel(help)
        focus()
    }
    func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === panel || window === toolbox || window === popover?.contentViewController?.view.window
    }
    func performMenuAction(_ action: String) {
        switch action {
        case "save": saveImage()
        case "copy": copyImage()
        case "pin": pinned = true; panel.level = .floating; toolbox.level = .floating; updateTools()
        default: break
        }
    }
    func close(retainAutomatically: Bool = true) {
        guard !closing else { return }
        canvas.finishText()
        if retainAutomatically && automaticallyRetain && !archiveHistory() { return }
        closing = true
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        popover?.close(); popover = nil
        panel.removeChildWindow(toolbox); toolbox.close(); panel.close()
        let callback = closed; closed = nil; callback?()
#if DESIGN_PREVIEW
        traceEditorWindows("editor-close")
#endif
    }
    func windowWillClose(_ notification: Notification) { if !closing { close() } }
    func windowDidMove(_ notification: Notification) { placeTools() }
    func windowDidResize(_ notification: Notification) { placeTools() }
    func windowDidResignKey(_ notification: Notification) { canvas.resetMoveModifier() }
    private func zoom(_ factor: CGFloat, anchor: CGPoint) {
        let minScale = max(0.08, 16 / max(1, min(initialSize.width, initialSize.height)))
        let maxScale = max(minScale, ScreenshotGeometry.maximumZoom(imageWidth: document.original.width, initialWidth: initialSize.width))
        let next = min(maxScale, max(minScale, zoomScale * factor))
        let rect = ScreenshotGeometry.zoomed(panel.frame, factor: next / zoomScale, anchor: anchor)
        zoomScale = next; panel.setFrame(rect, display: true); placeTools()
    }
    private func buildTools() {
        let background = NSVisualEffectView(); background.material = .popover; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
        toolbox.contentView = background
        let tools = ScreenshotTool.allCases
        for (index, tool) in tools.enumerated() {
            addButton(tool.rawValue, symbol: tool.symbol, help: tool.help, column: index, row: 0, in: background)
        }
        let actions: [(String, String, String)] = [
            ("color", "paintpalette", "颜色：设置画笔、箭头、形状与文字颜色"),
            ("size", "lineweight", "粗细 / 字号：调整线条、马赛克笔刷或文字大小"),
            ("undo", "arrow.uturn.backward", "撤销（Command + Z）"),
            ("redo", "arrow.uturn.forward", "重做（Command + Shift + Z）"),
            ("copy", "doc.on.doc", "复制截图：包含所有标注（Command + C）"),
            ("pin", "pin", "钉在最上层 / 取消置顶"),
            ("save", "square.and.arrow.down", editingHistory ? "保存修改到历史（Command + S）；Option + Command + S 另存 PNG" : "保存 PNG 并加入历史（Command + S）"),
            ("close", "xmark", "关闭截图（Esc），不返回主界面")]
        for (index, action) in actions.enumerated() { addButton(action.0, symbol: action.1, help: action.2, column: index, row: 1, in: background) }
        if let warning {
            let label = NSTextField(wrappingLabelWithString: "⚠︎ \(warning)")
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor; label.toolTip = warning
            label.frame = CGRect(x: 12, y: 5, width: 284, height: 30); background.addSubview(label)
        }
    }
    private func addButton(_ key: String, symbol: String, help: String, column: Int, row: Int, in view: NSView) {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(action(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(key); button.imagePosition = .imageOnly
        button.isBordered = false; button.bezelStyle = .regularSquare
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        button.setButtonType(.momentaryPushIn); button.toolTip = help; button.setAccessibilityLabel(help)
        button.frame = CGRect(x: 10 + column * 36, y: Int(toolbox.frame.height) - 42 - row * 36, width: 34, height: 32)
        button.wantsLayer = true; button.layer?.cornerRadius = 7
        view.addSubview(button); buttons[key] = button
    }
    private func updateTools() {
        for tool in ScreenshotTool.allCases {
            let button = buttons[tool.rawValue]
            button?.layer?.backgroundColor = tool == canvas.tool ? NSColor.systemTeal.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
            button?.contentTintColor = tool == canvas.tool ? .systemTeal : .labelColor
            button?.setAccessibilityValue(tool == canvas.tool ? "已选择" : "")
        }
        buttons["undo"]?.isEnabled = document.canUndo; buttons["redo"]?.isEnabled = document.canRedo
        buttons["color"]?.image = Self.colorSwatch(canvas.selected?.color ?? canvas.ink)
        buttons["pin"]?.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        buttons["pin"]?.contentTintColor = pinned ? .systemTeal : .labelColor
        buttons["pin"]?.setAccessibilityValue(pinned ? "已置顶" : "未置顶")
    }
    private func placeTools() {
        guard !closing else { return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0], area = screen.visibleFrame
        var point = CGPoint(x: panel.frame.maxX - toolbox.frame.width, y: panel.frame.minY - toolbox.frame.height - 8)
        if point.y < area.minY { point.y = min(area.maxY - toolbox.frame.height, panel.frame.maxY + 8) }
        point.x = max(area.minX + 4, min(point.x, area.maxX - toolbox.frame.width - 4))
        point.y = max(area.minY + 4, min(point.y, area.maxY - toolbox.frame.height - 4))
        toolbox.setFrameOrigin(point)
    }
    private func showTools() {
        if toolbox.parent == nil { panel.addChildWindow(toolbox, ordered: .above) }
        // Attaching a child can adjust its frame. Position it after attachment.
        placeTools()
        toolbox.makeKeyAndOrderFront(nil)
    }
    @objc private func action(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        canvas.finishText()
        if let tool = ScreenshotTool(rawValue: key) { canvas.tool = tool; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas); updateTools(); return }
        switch key {
        case "color": showPalette(relativeTo: sender)
        case "size": showSizes(relativeTo: sender)
        case "undo": canvas.undo()
        case "redo": canvas.redo()
        case "copy": copyImage()
        case "pin":
            pinned.toggle(); panel.level = pinned ? .floating : .normal; toolbox.level = panel.level; updateTools()
        case "save": saveImage(exportPNG: NSEvent.modifierFlags.contains(.option))
        case "close": close()
        default: break
        }
        if key != "color" && key != "size" && key != "close" { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas) }
    }
    private func showPopover(_ view: NSView, relativeTo button: NSButton) {
        popover?.close()
        let controller = NSViewController(); controller.view = view
        let popover = NSPopover(); popover.contentViewController = controller; popover.behavior = .transient
        popover.contentSize = view.frame.size; self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }
    private let colors: [(String, NSColor)] = [("红色", .systemRed), ("橙色", .systemOrange), ("黄色", .systemYellow), ("绿色", .systemGreen), ("蓝色", .systemBlue), ("紫色", .systemPurple), ("黑色", .black), ("白色", .white)]
    private static func colorSwatch(_ color: NSColor, selected: Bool = false) -> NSImage {
        // Template symbols can be recolored by NSButton. Draw the actual color pixels instead.
        let image = NSImage(size: NSSize(width: 26, height: 26), flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 18, height: 18))
            color.setFill(); circle.fill()
            NSColor.gray.withAlphaComponent(0.7).setStroke(); circle.lineWidth = 1; circle.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 24, height: 24))
                NSColor.controlAccentColor.setStroke(); ring.lineWidth = 2; ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
    private func showPalette(relativeTo button: NSButton) {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 304, height: 48))
        for (i, entry) in colors.enumerated() {
            let selected = entry.1.isEqual(canvas.selected?.color ?? canvas.ink)
            let item = NSButton(image: Self.colorSwatch(entry.1, selected: selected), target: self, action: #selector(pickColor(_:)))
            item.frame = CGRect(x: 8 + 36 * i, y: 8, width: 32, height: 32); item.tag = i
            item.isBordered = false; item.imageScaling = .scaleNone
            item.setAccessibilityValue(selected ? "已选择" : "")
            item.toolTip = entry.0; item.setAccessibilityLabel(entry.0); view.addSubview(item)
        }
        showPopover(view, relativeTo: button)
    }
    @objc private func pickColor(_ sender: NSButton) { canvas.setColor(colors[sender.tag].1); popover?.close(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas) }
    private func showSizes(relativeTo button: NSButton) {
        let kind = canvas.selected?.tool ?? canvas.tool
        let sizes: [Int] = kind == .mosaic ? [16, 32, 48, 80] : kind == .text ? [16, 24, 36, 48] : [2, 4, 8, 12]
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 176, height: 48))
        for (i, size) in sizes.enumerated() {
            let symbol = kind == .text ? "textformat.size" : kind == .mosaic ? "square.grid.3x3.fill" : "circle.fill"
            let item = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: #selector(pickSize(_:)))
            item.frame = CGRect(x: 8 + 42 * i, y: 8, width: 34, height: 32); item.tag = size
            item.image = item.image?.withSymbolConfiguration(.init(pointSize: CGFloat(7 + i * 4), weight: .regular))
            item.bezelStyle = .regularSquare; item.toolTip = "\(size) 像素"; item.setAccessibilityLabel("\(size) 像素")
            view.addSubview(item)
        }
        showPopover(view, relativeTo: button)
    }
    @objc private func pickSize(_ sender: NSButton) { canvas.setSize(CGFloat(sender.tag)); popover?.close(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(canvas) }
    private func copyImage() {
        canvas.finishText()
        guard let image = document.rendered(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { showError("无法生成截图，请重试。"); return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(png, forType: .png) else { showError("无法复制截图，请重试。"); return }
        archiveHistory()
        buttons["copy"]?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.buttons["copy"]?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) }
    }
    private func saveImage(exportPNG: Bool = false) {
        canvas.finishText()
        if editingHistory && !exportPNG {
            if archiveHistory() {
                buttons["save"]?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.buttons["save"]?.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) }
            }
            return
        }
        guard let image = document.rendered() else { showError("无法生成截图，请重试。"); return }
        let save = NSSavePanel(); save.allowedContentTypes = [.png]; save.nameFieldStringValue = "ScrollCap-截图.png"
        guard save.runModal() == .OK, let destination = save.url else { return }
        do { try Stitcher.png(image, to: destination); archiveHistory() } catch { showError(error.localizedDescription) }
    }
    @discardableResult
    private func archiveHistory() -> Bool {
        guard archivedMarks != document.marks else { return true }
        do { _ = try history.save(document: document, kind: kind, id: historyID); archivedMarks = document.marks; return true }
        catch { showError("无法保存到历史截图：\(error.localizedDescription)"); return false }
    }
    private func showError(_ text: String) { let alert = NSAlert(); alert.messageText = "截图操作未完成"; alert.informativeText = text; alert.runModal() }
}
