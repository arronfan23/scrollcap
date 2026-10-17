import AppKit

@MainActor
final class ScreenshotCanvas: NSView, NSTextFieldDelegate {
    let document: ScreenshotDocument
    var tool: ScreenshotTool = .move { didSet { finishText(); resetMoveModifier(); selectedID = nil; needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var ink: NSColor = .systemRed
    var lineWidth: CGFloat = 6
    var mosaicWidth: CGFloat = 48
    var fontSize: CGFloat = 32
    var changed: (() -> Void)?
    var showTools: (() -> Void)?
    var zoom: ((CGFloat, CGPoint) -> Void)?
    var closeEditor: (() -> Void)?
    private(set) var selectedID: UUID?
    private var anchor: CGPoint?
    private var draft: ScreenshotMark?
    private var movingOriginal: ScreenshotMark?
    private var endpointIndex: Int?
    private var gestureBase: CGImage?
    private var mosaicPreview: CGImage?
    private var spaceHeld = false
    private var textField: NSTextField?
    private var textPoint: CGPoint?
    var imageScale: CGFloat { bounds.width / CGFloat(document.original.width) }
    var selected: ScreenshotMark? { document.marks.first { $0.id == selectedID } }
    init(document: ScreenshotDocument) {
        self.document = document; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("截图编辑画布")
        setAccessibilityHelp("默认拖动任意位置移动截图，滚轮缩放，右键打开标注工具，Escape 关闭。标注时按住空格拖动可移动截图。")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    func resetMoveModifier() { spaceHeld = false; window?.invalidateCursorRects(for: self) }
    override func resignFirstResponder() -> Bool { resetMoveModifier(); return super.resignFirstResponder() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: tool == .move || spaceHeld ? .openHand : tool == .select ? .arrow : .crosshair) }
    func refresh() {
        setAccessibilityValue("\(document.original.width) × \(document.original.height) 像素；\(document.marks.count) 个标注")
        needsDisplay = true; changed?()
    }
    func pixel(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(CGFloat(document.original.width), max(0, p.x / imageScale)), y: min(CGFloat(document.original.height), max(0, p.y / imageScale)))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.scaleBy(x: imageScale, y: imageScale)
        let rect = CGRect(x: 0, y: 0, width: document.original.width, height: document.original.height)
        if let base = gestureBase ?? document.rendered() { context.draw(base, in: rect) }
        if let draft { ScreenshotRenderer.draw(draft, in: context, imageRect: rect, mosaic: mosaicPreview) }
        if let mark = draft ?? selected, tool == .select {
            let r = mark.bounds.insetBy(dx: -5 / imageScale, dy: -5 / imageScale)
            context.setStrokeColor(NSColor.systemTeal.cgColor); context.setLineWidth(1 / imageScale)
            context.setLineDash(phase: 0, lengths: [4 / imageScale, 3 / imageScale]); context.stroke(r)
            context.setLineDash(phase: 0, lengths: [])
            if mark.tool == .arrow {
                for p in [mark.points.first, mark.points.last].compactMap({ $0 }) {
                    let r = CGRect(x: p.x - 4 / imageScale, y: p.y - 4 / imageScale, width: 8 / imageScale, height: 8 / imageScale)
                    context.setFillColor(NSColor.white.cgColor); context.fillEllipse(in: r); context.strokeEllipse(in: r)
                }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        finishText(); window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) { showTools?(); return }
        if tool == .move || spaceHeld {
            window?.performDrag(with: event); return
        }
        let point = pixel(event); anchor = point
        if tool == .text { beginText(at: point); return }
        if tool == .select {
            let hit = document.marks.last { $0.hit(point, tolerance: 9 / imageScale) }
            selectedID = hit?.id; movingOriginal = hit; draft = hit
            if let hit {
                if hit.tool == .arrow, let first = hit.points.first, let last = hit.points.last {
                    if hypot(point.x - first.x, point.y - first.y) <= 12 / imageScale { endpointIndex = 0 }
                    else if hypot(point.x - last.x, point.y - last.y) <= 12 / imageScale { endpointIndex = hit.points.count - 1 }
                }
                gestureBase = ScreenshotRenderer.render(document.original, marks: document.marks.filter { $0.id != hit.id })
                if hit.tool == .mosaic { mosaicPreview = gestureBase.flatMap { ScreenshotRenderer.pixelated($0) } }
            }
        } else {
            selectedID = nil
            draft = ScreenshotMark(tool: tool, points: [point], color: ink, width: tool == .mosaic ? mosaicWidth : lineWidth, fontSize: fontSize)
            if tool == .mosaic { mosaicPreview = document.rendered().flatMap { ScreenshotRenderer.pixelated($0) } }
        }
        refresh()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, var mark = draft else { return }
        var point = pixel(event)
        if let original = movingOriginal {
            if let index = endpointIndex { mark = original; mark.points[index] = point }
            else { mark = original.translated(CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)) }
        } else if mark.tool == .pen || mark.tool == .mosaic {
            if mark.points.count < 20_000, let last = mark.points.last, hypot(last.x - point.x, last.y - point.y) >= 0.5 { mark.points.append(point) }
        } else {
            point = ScreenshotGeometry.endpoint(from: anchor, to: point, square: event.modifierFlags.contains(.shift) && (tool == .rectangle || tool == .ellipse))
            mark.points = [anchor, point]
        }
        draft = mark; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let mark = draft else { return }
        if movingOriginal != nil {
            document.commit(document.marks.map { $0.id == mark.id ? mark : $0 })
        } else if mark.tool == .pen || mark.tool == .mosaic || mark.bounds.width + mark.bounds.height > 2 {
            document.append(mark)
        }
        anchor = nil; draft = nil; movingOriginal = nil; endpointIndex = nil; gestureBase = nil; mosaicPreview = nil
        refresh()
    }
    override func rightMouseDown(with event: NSEvent) { finishText(); showTools?() }
    override func scrollWheel(with event: NSEvent) {
        finishText()
        guard event.scrollingDeltaY != 0 else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.008 : 0.065)
        let factor = exp(max(-0.18, min(0.18, delta)))
        if let window { zoom?(factor, window.convertPoint(toScreen: event.locationInWindow)) }
    }
    override func magnify(with event: NSEvent) {
        finishText()
        if let window { zoom?(max(0.8, min(1.2, 1 + event.magnification)), window.convertPoint(toScreen: event.locationInWindow)) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closeEditor?(); return }
        if event.keyCode == 49 { spaceHeld = true; window?.invalidateCursorRects(for: self); return }
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelected(); return }
        if [123, 124, 125, 126].contains(event.keyCode) {
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta = CGPoint(x: event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0,
                                y: event.keyCode == 125 ? -amount : event.keyCode == 126 ? amount : 0)
            if let selected { document.commit(document.marks.map { $0.id == selected.id ? selected.translated(delta) : $0 }); refresh() }
            else if let window { window.setFrameOrigin(CGPoint(x: window.frame.minX + delta.x, y: window.frame.minY + delta.y)) }
            return
        }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false; window?.invalidateCursorRects(for: self) }
        else { super.keyUp(with: event) }
    }
    func deleteSelected() {
        guard let selectedID else { return }
        document.commit(document.marks.filter { $0.id != selectedID }); self.selectedID = nil; refresh()
    }
    func undo() { finishText(); document.undo(); selectedID = nil; refresh() }
    func redo() { finishText(); document.redo(); selectedID = nil; refresh() }
    func setColor(_ color: NSColor) {
        ink = color
        if var mark = selected, mark.tool != .mosaic { mark.color = color; document.commit(document.marks.map { $0.id == mark.id ? mark : $0 }) }
        refresh()
    }
    func setSize(_ value: CGFloat) {
        let kind = selected?.tool ?? tool
        if kind == .text { fontSize = value }
        else if kind == .mosaic { mosaicWidth = value }
        else { lineWidth = value }
        if var mark = selected {
            if kind == .text { mark.fontSize = value } else { mark.width = value }
            document.commit(document.marks.map { $0.id == mark.id ? mark : $0 })
        }
        refresh()
    }
    private func beginText(at point: CGPoint) {
        let x = min(max(0, point.x * imageScale), max(0, bounds.width - 120))
        let height = max(32, fontSize * imageScale + 10)
        let y = min(max(0, point.y * imageScale), max(0, bounds.height - height))
        textPoint = CGPoint(x: x / imageScale, y: y / imageScale)
        let field = NSTextField(frame: CGRect(x: x, y: y, width: min(320, max(80, bounds.width - x)), height: height))
        field.placeholderString = "输入文字，Return 完成"; field.font = .systemFont(ofSize: max(12, fontSize * imageScale), weight: .medium)
        field.textColor = ink; field.backgroundColor = .textBackgroundColor; field.isBordered = true
        field.delegate = self; field.target = self; field.action = #selector(commitText)
        field.setAccessibilityLabel("截图文字"); addSubview(field); textField = field; field.selectText(nil)
    }
    @objc private func commitText() { finishText(); window?.makeFirstResponder(self) }
    func controlTextDidEndEditing(_ obj: Notification) { finishText() }
    func finishText() {
        guard let field = textField else { return }
        textField = nil
        let value = field.stringValue; field.removeFromSuperview()
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let textPoint {
            document.append(ScreenshotMark(tool: .text, points: [textPoint], color: ink, width: lineWidth, text: value, fontSize: fontSize))
        }
        textPoint = nil; refresh()
    }
}
