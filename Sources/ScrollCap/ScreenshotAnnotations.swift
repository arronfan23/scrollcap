import AppKit

/// Annotation geometry uses original image pixels, with a bottom-left origin.
enum ScreenshotTool: String, CaseIterable {
    case move, select, pen, arrow, rectangle, ellipse, mosaic, text
    var symbol: String {
        switch self {
        case .move: return "hand.draw"
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }
    var help: String {
        switch self {
        case .move: return "移动截图：拖动图片任意位置；滚轮缩放"
        case .select: return "选择标注：拖动移动；箭头两端可调整；Delete 删除"
        case .pen: return "画笔：按住拖动绘制；空格拖动可移动截图"
        case .arrow: return "箭头：拖出方向；用选择工具调整两端或移动"
        case .rectangle: return "矩形：拖动绘制；按 Shift 绘制正方形"
        case .ellipse: return "圆圈：拖动绘制；按 Shift 绘制正圆"
        case .mosaic: return "马赛克画笔：拖动涂抹需要遮挡的内容"
        case .text: return "文字：点击位置输入，Return 完成；用选择工具移动"
        }
    }
}

struct ScreenshotMark: Equatable {
    var id = UUID()
    var tool: ScreenshotTool
    var points: [CGPoint]
    var color: NSColor = .systemRed
    var width: CGFloat = 6
    var text = ""
    var fontSize: CGFloat = 32
    var bounds: CGRect {
        if tool == .text, let p = points.first {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            return CGRect(origin: p, size: CGSize(width: max(1, size.width), height: max(1, size.height)))
        }
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { r, p in
            CGRect(x: min(r.minX, p.x), y: min(r.minY, p.y), width: max(r.maxX, p.x) - min(r.minX, p.x), height: max(r.maxY, p.y) - min(r.minY, p.y))
        }
    }
    func translated(_ delta: CGPoint) -> ScreenshotMark {
        var copy = self; copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }; return copy
    }
    func hit(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        if tool == .text { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) }
        if tool == .rectangle || tool == .ellipse { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) }
        guard let first = points.first else { return false }
        if points.count == 1 { return hypot(p.x - first.x, p.y - first.y) <= width / 2 + tolerance }
        return zip(points, points.dropFirst()).contains { a, b in
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.001, dx * dx + dy * dy)))
            return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) <= width / 2 + tolerance
        }
    }
}

@MainActor
final class ScreenshotDocument {
    let original: CGImage
    private(set) var marks: [ScreenshotMark] = []
    private var past: [[ScreenshotMark]] = []
    private var future: [[ScreenshotMark]] = []
    private var cached: CGImage?
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    init(_ image: CGImage, marks: [ScreenshotMark] = []) { original = image; self.marks = marks }
    func commit(_ marks: [ScreenshotMark]) {
        guard self.marks != marks else { return }
        past.append(self.marks)
        if past.count > 60 { past.removeFirst() }
        self.marks = marks; future.removeAll(); cached = nil
    }
    func append(_ mark: ScreenshotMark) { commit(marks + [mark]) }
    func undo() { guard let prior = past.popLast() else { return }; future.append(marks); marks = prior; cached = nil }
    func redo() { guard let next = future.popLast() else { return }; past.append(marks); marks = next; cached = nil }
    func rendered() -> CGImage? {
        if marks.isEmpty { return original }
        if let cached { return cached }
        cached = ScreenshotRenderer.render(original, marks: marks); return cached
    }
}

enum ScreenshotGeometry {
    static func maximumZoom(imageWidth: Int, initialWidth: CGFloat) -> CGFloat {
        max(4, CGFloat(imageWidth) / max(1, initialWidth))
    }
    static func cocoaRect(quartz: CGRect, displayBounds: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + quartz.minX - displayBounds.minX,
               y: screenFrame.maxY - quartz.maxY + displayBounds.minY, width: quartz.width, height: quartz.height)
    }
    /// Keep the pixel under the cursor fixed while resizing the floating image.
    static func zoomed(_ rect: CGRect, factor: CGFloat, anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x - (anchor.x - rect.minX) * factor, y: anchor.y - (anchor.y - rect.minY) * factor,
               width: rect.width * factor, height: rect.height * factor)
    }
    static func endpoint(from start: CGPoint, to end: CGPoint, square: Bool) -> CGPoint {
        guard square else { return end }
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        return CGPoint(x: start.x + (end.x >= start.x ? side : -side), y: start.y + (end.y >= start.y ? side : -side))
    }
}

enum ScreenshotRenderer {
    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    static func pixelated(_ image: CGImage, block: CGFloat = 14) -> CGImage? {
        let w = max(1, Int(ceil(CGFloat(image.width) / block))), h = max(1, Int(ceil(CGFloat(image.height) / block)))
        guard let ctx = context(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
    static func render(_ image: CGImage, marks: [ScreenshotMark]) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: rect)
        for mark in marks {
            // Mosaic samples the flattened content below it, including previous annotations.
            let mosaic = mark.tool == .mosaic ? ctx.makeImage().flatMap { pixelated($0) } : nil
            draw(mark, in: ctx, imageRect: rect, mosaic: mosaic)
        }
        return ctx.makeImage()
    }
    static func draw(_ mark: ScreenshotMark, in ctx: CGContext, imageRect: CGRect, mosaic: CGImage? = nil) {
        guard let first = mark.points.first else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(mark.width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        switch mark.tool {
        case .move, .select: break
        case .text:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (mark.text as NSString).draw(at: first, withAttributes: [.font: NSFont.systemFont(ofSize: mark.fontSize, weight: .medium), .foregroundColor: mark.color])
            NSGraphicsContext.restoreGraphicsState()
        case .rectangle: ctx.stroke(mark.bounds)
        case .ellipse: ctx.strokeEllipse(in: mark.bounds)
        case .pen, .arrow, .mosaic:
            let path = CGMutablePath(); path.move(to: first)
            for point in mark.points.dropFirst() { path.addLine(to: point) }
            if mark.tool == .mosaic {
                guard let mosaic else { return }
                if mark.points.count == 1 { ctx.addEllipse(in: CGRect(x: first.x - mark.width / 2, y: first.y - mark.width / 2, width: mark.width, height: mark.width)) }
                else { ctx.addPath(path.copy(strokingWithWidth: mark.width, lineCap: .round, lineJoin: .round, miterLimit: 10)) }
                ctx.clip(); ctx.interpolationQuality = .none; ctx.draw(mosaic, in: imageRect)
            } else if mark.points.count == 1 {
                ctx.fillEllipse(in: CGRect(x: first.x - mark.width / 2, y: first.y - mark.width / 2, width: mark.width, height: mark.width))
            } else {
                ctx.addPath(path); ctx.strokePath()
                if mark.tool == .arrow, let end = mark.points.last {
                    let angle = atan2(end.y - first.y, end.x - first.x)
                    let length = min(hypot(end.x - first.x, end.y - first.y) * 0.5, max(16, mark.width * 3.5))
                    ctx.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                    ctx.addLine(to: end)
                    ctx.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
                    ctx.strokePath()
                }
            }
        }
    }
}
