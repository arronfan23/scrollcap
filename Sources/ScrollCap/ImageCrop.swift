import AppKit
import SwiftUI

enum CropHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, move
}

enum CropScale: String, CaseIterable {
    case width = "适合宽度", fit = "全图", actual = "100%"
}

enum CropGeometry {
    static func bounded(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let full = CGRect(origin: .zero, size: size)
        guard [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy({ $0.isFinite }) else { return full }
        let x = min(size.width - 1, max(0, rect.minX.rounded()))
        let y = min(size.height - 1, max(0, rect.minY.rounded()))
        let right = max(x + 1, min(size.width, rect.maxX.rounded()))
        let bottom = max(y + 1, min(size.height, rect.maxY.rounded()))
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    static func dragged(_ rect: CGRect, handle: CropHandle, delta: CGSize, in size: CGSize) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return bounded(rect, in: size) }
        let start = bounded(rect, in: size)
        let minWidth = min(16, size.width), minHeight = min(16, size.height)
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(high, max(low, value)) }
        if handle == .move {
            return bounded(CGRect(x: clamp(start.minX + delta.width, 0, size.width - start.width),
                                  y: clamp(start.minY + delta.height, 0, size.height - start.height),
                                  width: start.width, height: start.height), in: size)
        }
        var left = start.minX, top = start.minY, right = start.maxX, bottom = start.maxY
        if [.left, .topLeft, .bottomLeft].contains(handle) { left = clamp(left + delta.width, 0, right - min(minWidth, start.width)) }
        if [.right, .topRight, .bottomRight].contains(handle) { right = clamp(right + delta.width, left + min(minWidth, start.width), size.width) }
        if [.top, .topLeft, .topRight].contains(handle) { top = clamp(top + delta.height, 0, bottom - min(minHeight, start.height)) }
        if [.bottom, .bottomLeft, .bottomRight].contains(handle) { bottom = clamp(bottom + delta.height, top + min(minHeight, start.height), size.height) }
        return bounded(CGRect(x: left, y: top, width: right - left, height: bottom - top), in: size)
    }

    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounded = bounded(rect, in: CGSize(width: image.width, height: image.height))
        if bounded == CGRect(x: 0, y: 0, width: image.width, height: image.height) { return image }
        return image.cropping(to: bounded)
    }
}

struct CropPreview: NSViewRepresentable {
    let image: CGImage
    let selection: CGRect
    let editing: Bool
    let scale: CropScale
    let changed: (CGRect) -> Void

    func makeNSView(context: Context) -> CropScrollView { CropScrollView() }
    func updateNSView(_ view: CropScrollView, context: Context) {
        let imageChanged = view.canvas.image !== image
        let scaleChanged = view.mode != scale
        view.canvas.configure(image: image, selection: selection, editing: editing, changed: changed)
        view.mode = scale
        view.layoutCanvas()
        if imageChanged || scaleChanged {
            view.contentView.scroll(to: .zero)
            view.reflectScrolledClipView(view.contentView)
        }
    }
}

final class CropScrollView: NSScrollView {
    let canvas = CropCanvas()
    var mode: CropScale = .width
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true; hasHorizontalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay; borderType = .noBorder
        drawsBackground = true; backgroundColor = ScrollCapStyle.canvasColor
        documentView = canvas
        setAccessibilityLabel("长图裁剪预览")
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); layoutCanvas() }
    override func tile() { super.tile(); layoutCanvas() }
    func layoutCanvas() {
        canvas.layoutImage(viewport: contentView.bounds.size, mode: mode, backing: window?.backingScaleFactor ?? 2)
    }
}

final class CropCanvas: NSView {
    private(set) var image: CGImage?
    private var displayImage: NSImage?
    private var selection = CGRect.zero
    private var editing = true
    private var changed: ((CGRect) -> Void)?
    private var imageRect = CGRect.zero
    private var imageScale: CGFloat = 1
    private var dragHandle: CropHandle?
    private var dragStart = CGPoint.zero
    private var dragSelection = CGRect.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(image: CGImage, selection: CGRect, editing: Bool, changed: @escaping (CGRect) -> Void) {
        if self.image !== image {
            self.image = image
            displayImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            dragHandle = nil
        }
        self.selection = selection; self.editing = editing; self.changed = changed
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(editing ? "拖动四边或四角裁剪，拖动选区移动" : "裁剪后的长图")
        setAccessibilityValue("位置 \(Int(selection.minX)), \(Int(selection.minY))；\(Int(selection.width)) × \(Int(selection.height)) 像素")
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func layoutImage(viewport: CGSize, mode: CropScale, backing: CGFloat) {
        guard let image, viewport.width > 0, viewport.height > 0 else { return }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let available = CGSize(width: max(20, viewport.width - 40), height: max(20, viewport.height - 40))
        let scale: CGFloat
        switch mode {
        case .width: scale = min(1, available.width / w)
        case .fit: scale = min(1, min(available.width / w, available.height / h))
        case .actual: scale = 1 / max(1, backing)
        }
        imageScale = scale
        let size = CGSize(width: w * scale, height: h * scale)
        let nextSize = CGSize(width: max(viewport.width, size.width + 40), height: max(viewport.height, size.height + 40))
        let nextRect = CGRect(x: max(20, (nextSize.width - size.width) / 2), y: 20, width: size.width, height: size.height)
        let layoutChanged = frame.size != nextSize || imageRect != nextRect
        if frame.size != nextSize { setFrameSize(nextSize) }
        imageRect = nextRect
        if layoutChanged { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }

    private var selectedRect: CGRect {
        CGRect(x: imageRect.minX + selection.minX * imageScale, y: imageRect.minY + selection.minY * imageScale,
               width: selection.width * imageScale, height: selection.height * imageScale)
    }
    private var handles: [(CropHandle, CGPoint)] {
        let r = selectedRect
        return [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
                (.top, CGPoint(x: r.midX, y: r.minY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                (.left, CGPoint(x: r.minX, y: r.midY)), (.right, CGPoint(x: r.maxX, y: r.midY))]
    }
    private func hitHandle(_ point: CGPoint) -> CropHandle? {
        guard editing else { return nil }
        for (handle, center) in handles where abs(point.x - center.x) <= 9 && abs(point.y - center.y) <= 9 { return handle }
        let r = selectedRect
        if point.y >= r.minY - 8 && point.y <= r.maxY + 8 {
            if abs(point.x - r.minX) <= 8 { return .left }
            if abs(point.x - r.maxX) <= 8 { return .right }
        }
        if point.x >= r.minX - 8 && point.x <= r.maxX + 8 {
            if abs(point.y - r.minY) <= 8 { return .top }
            if abs(point.y - r.maxY) <= 8 { return .bottom }
        }
        return r.contains(point) ? .move : nil
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let handle = hitHandle(point) else { return }
        window?.makeFirstResponder(self)
        dragStart = point; dragSelection = selection; dragHandle = handle
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let handle = dragHandle, let image else { return }
        _ = autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: (point.x - dragStart.x) / imageScale, height: (point.y - dragStart.y) / imageScale)
        selection = CropGeometry.dragged(dragSelection, handle: handle, delta: delta, in: CGSize(width: image.width, height: image.height))
        changed?(selection); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragHandle = nil; needsDisplay = true; window?.invalidateCursorRects(for: self) }
    override func resetCursorRects() {
        guard editing else { return }
        let r = selectedRect
        addCursorRect(r, cursor: .openHand)
        for x in [r.minX, r.maxX] { addCursorRect(CGRect(x: x - 7, y: r.minY, width: 14, height: r.height), cursor: .resizeLeftRight) }
        for y in [r.minY, r.maxY] { addCursorRect(CGRect(x: r.minX, y: y - 7, width: r.width, height: 14), cursor: .resizeUpDown) }
        for (_, p) in handles.prefix(4) { addCursorRect(CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16), cursor: .crosshair) }
    }
    override func draw(_ dirtyRect: NSRect) {
        ScrollCapStyle.canvasColor.setFill(); dirtyRect.fill()
        guard let displayImage else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        displayImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard editing else { return }
        let r = selectedRect, full = imageRect
        NSColor.black.withAlphaComponent(0.48).setFill()
        CGRect(x: full.minX, y: full.minY, width: full.width, height: max(0, r.minY - full.minY)).fill()
        CGRect(x: full.minX, y: r.maxY, width: full.width, height: max(0, full.maxY - r.maxY)).fill()
        CGRect(x: full.minX, y: r.minY, width: max(0, r.minX - full.minX), height: r.height).fill()
        CGRect(x: r.maxX, y: r.minY, width: max(0, full.maxX - r.maxX), height: r.height).fill()
        let border = NSBezierPath(rect: r)
        NSColor.white.setStroke(); border.lineWidth = 3; border.stroke()
        NSColor.systemTeal.setStroke(); border.lineWidth = 1; border.stroke()
        if dragHandle != nil {
            let grid = NSBezierPath()
            for part in [CGFloat(1) / 3, CGFloat(2) / 3] {
                grid.move(to: CGPoint(x: r.minX + r.width * part, y: r.minY)); grid.line(to: CGPoint(x: r.minX + r.width * part, y: r.maxY))
                grid.move(to: CGPoint(x: r.minX, y: r.minY + r.height * part)); grid.line(to: CGPoint(x: r.maxX, y: r.minY + r.height * part))
            }
            NSColor.white.withAlphaComponent(0.65).setStroke(); grid.lineWidth = 0.6; grid.stroke()
        }
        for (_, point) in handles {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9), xRadius: 2, yRadius: 2)
            NSColor.white.setFill(); handle.fill(); NSColor.systemTeal.setStroke(); handle.lineWidth = 1.5; handle.stroke()
        }
    }
}
