import AppKit
import SwiftUI

struct ChromeSelection {
    let body: CGRect // image coordinates with origin at top left; full width
    let includeFixed: Bool
}

@MainActor
final class ChromePicker: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var completion: ((ChromeSelection?) -> Void)?
    func begin(image: CGImage, completion: @escaping (ChromeSelection?) -> Void) {
        self.completion = completion
        let scale = min(780 / CGFloat(image.width), 480 / CGFloat(image.height))
        let width = max(680, CGFloat(image.width) * scale + 48)
        let height = CGFloat(image.height) * scale + 288
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "标记滚动正文"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ChromeSelectionView(image: image) { [weak self] selection in self?.finish(selection) })
        panel.center(); panel.makeKeyAndOrderFront(nil)
        window = panel
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finish(_ result: ChromeSelection?) {
        let callback = completion; completion = nil
        window?.orderOut(nil); window = nil; callback?(result)
    }
    func cancel() { finish(nil) }
    func windowWillClose(_ notification: Notification) { finish(nil) }
}

private enum WindowContentLayout: Hashable { case fixedBands, whole }

struct ChromeSelectionView: View {
    let image: CGImage
    let done: (ChromeSelection?) -> Void
    @State private var top = 0.13
    @State private var bottom = 0.83
    @State private var includeFixed = true
    private var wholeWindow: Bool { top == 0 && bottom == 1 }
    private var minimumBody: Int { min(140, image.height) }
    private var topPixels: Int { Int((top * Double(image.height)).rounded()) }
    private var bottomPixels: Int { Int(((1 - bottom) * Double(image.height)).rounded()) }
    private var bodyPixels: Int { image.height - topPixels - bottomPixels }
    private var layout: Binding<WindowContentLayout> {
        Binding(get: { wholeWindow ? .whole : .fixedBands }, set: { value in
            if value == .whole { top = 0; bottom = 1 }
            else { top = 0.13; bottom = 0.83; constrainBands() }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(ScrollCapStyle.emphasis.opacity(0.4)).frame(width: 22, height: 4)
                    RoundedRectangle(cornerRadius: 1).strokeBorder(ScrollCapStyle.emphasis, lineWidth: 1.5).frame(width: 22, height: 10)
                    RoundedRectangle(cornerRadius: 1).fill(ScrollCapStyle.emphasis.opacity(0.4)).frame(width: 22, height: 4)
                }.frame(width: 36, height: 36).background(ScrollCapStyle.emphasis.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("哪一部分会滚动？").font(.title3.weight(.semibold))
                    Text("拖动两条边界，把会滚动的正文留在中间。标题栏和输入框放在两侧。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("窗口内容", selection: layout) {
                Text("有固定标题栏 / 输入框").tag(WindowContentLayout.fixedBands)
                Text("整个区域都滚动").tag(WindowContentLayout.whole)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)
            BandPreview(image: image, top: $top, bottom: $bottom, includeFixed: includeFixed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .compositingGroup().clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ScrollCapStyle.separator, lineWidth: 1))
                .accessibilityLabel("滚动区域预览，可使用下方数值调整边界")
            HStack(spacing: 20) {
                bandAdjustment("顶部固定", value: Binding(get: { topPixels }, set: { top = Double(min(max(0, $0), image.height - bottomPixels - minimumBody)) / Double(image.height) }))
                bandAdjustment("底部固定", value: Binding(get: { bottomPixels }, set: { bottom = 1 - Double(min(max(0, $0), image.height - topPixels - minimumBody)) / Double(image.height) }))
                Spacer(minLength: 0)
                Text("正文 \(bodyPixels) px").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Divider()
            HStack(spacing: 12) {
                if !wholeWindow {
                    Toggle("固定部分保留一次", isOn: $includeFixed).font(.callout)
                } else {
                    Label("整个选区连续拼接", systemImage: "arrow.down.to.line")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("取消") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("确认并开始") { confirm() }
                    .buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent).keyboardShortcut(.defaultAction)
                    .disabled(bodyPixels < minimumBody || bodyPixels == 0)
            }.controlSize(.large)
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { constrainBands() }
    }
    private func bandAdjustment(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 52).multilineTextAlignment(.trailing)
                .accessibilityLabel("\(title)像素")
            Text("px").font(.caption).foregroundStyle(.secondary)
            Stepper(title, value: value, in: 0...max(0, image.height - minimumBody)).labelsHidden().controlSize(.small)
        }
    }
    private func constrainBands() {
        if image.height < 200 { top = 0; bottom = 1; return }
        let gap = Double(minimumBody) / Double(image.height)
        top = min(max(0, top), 1 - gap)
        bottom = max(top + gap, min(1, bottom))
    }
    private func confirm() {
        done(ChromeSelection(body: CGRect(x: 0, y: topPixels, width: image.width, height: bodyPixels),
                             includeFixed: !wholeWindow && includeFixed))
    }
}

struct BandPreview: NSViewRepresentable {
    let image: CGImage
    @Binding var top: Double
    @Binding var bottom: Double
    let includeFixed: Bool
    func makeNSView(context: Context) -> BandSelectionView {
        let view = BandSelectionView(); view.image = image
        view.changed = { t, b in top = t; bottom = b }; return view
    }
    func updateNSView(_ view: BandSelectionView, context: Context) {
        view.top = top; view.bottom = bottom; view.includeFixed = includeFixed; view.needsDisplay = true
    }
}

final class BandSelectionView: NSView {
    var image: CGImage?
    var top = 0.13, bottom = 0.83
    var includeFixed = true
    var changed: ((Double, Double) -> Void)?
    private var draggedTop = true
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var imageRect: CGRect {
        guard let image else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    override func resetCursorRects() {
        let r = imageRect
        for fraction in [top, bottom] {
            addCursorRect(CGRect(x: r.minX, y: r.minY + r.height * fraction - 10, width: r.width, height: 20), cursor: .resizeUpDown)
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard r.insetBy(dx: 0, dy: -12).contains(p) else { return }
        window?.makeFirstResponder(self)
        draggedTop = abs(p.y - (r.minY + r.height * top)) < abs(p.y - (r.minY + r.height * bottom))
        update(event)
    }
    override func mouseDragged(with event: NSEvent) { update(event) }
    override func mouseUp(with event: NSEvent) { window?.invalidateCursorRects(for: self) }
    override func keyDown(with event: NSEvent) {
        // Click a boundary, then use arrow keys. Shift adjusts ten source pixels.
        guard event.keyCode == 125 || event.keyCode == 126, let image else { super.keyDown(with: event); return }
        let step = (event.modifierFlags.contains(.shift) ? 10.0 : 1.0) / Double(image.height)
        setBoundary((draggedTop ? top : bottom) + (event.keyCode == 125 ? step : -step))
    }
    private func update(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard r.height > 0 else { return }
        setBoundary(Double((p.y - r.minY) / r.height))
    }
    private func setBoundary(_ newValue: Double) {
        guard let image else { return }
        let value = min(1, max(0, newValue))
        let gap = Double(min(140, image.height)) / Double(image.height)
        if draggedTop { top = min(bottom - gap, value) } else { bottom = max(top + gap, value) }
        top = max(0, top); bottom = min(1, bottom)
        changed?(top, bottom); needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        ScrollCapStyle.canvasColor.setFill(); bounds.fill()
        guard let image else { return }
        let r = imageRect
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.26).setFill()
        CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * top).fill()
        CGRect(x: r.minX, y: r.minY + r.height * bottom, width: r.width, height: r.height * (1 - bottom)).fill()
        let accent = NSColor(red: 0.025, green: 0.43, blue: 0.46, alpha: 1)
        for fraction in [top, bottom] {
            let y = r.minY + r.height * fraction
            accent.setStroke()
            let path = NSBezierPath(); path.move(to: CGPoint(x: r.minX, y: y)); path.line(to: CGPoint(x: r.maxX, y: y)); path.lineWidth = 2; path.stroke()
            let handleY = min(r.maxY - 18, max(r.minY, y - 9))
            accent.setFill(); NSBezierPath(roundedRect: CGRect(x: r.midX - 27, y: handleY, width: 54, height: 18), xRadius: 9, yRadius: 9).fill()
            NSColor.white.setStroke()
            for dy in [-2.0, 2.0] {
                let grip = NSBezierPath(); grip.move(to: CGPoint(x: r.midX - 9, y: handleY + 9 + dy)); grip.line(to: CGPoint(x: r.midX + 9, y: handleY + 9 + dy)); grip.lineWidth = 1; grip.stroke()
            }
        }
        if r.height * top > 32 { drawLabel(includeFixed ? "固定顶部 · 保留一次" : "固定顶部 · 不截入", at: CGPoint(x: r.minX + 10, y: r.minY + 10), color: .white, fill: NSColor.black.withAlphaComponent(0.55)) }
        if r.height * (1 - bottom) > 32 { drawLabel(includeFixed ? "固定底部 · 保留一次" : "固定底部 · 不截入", at: CGPoint(x: r.minX + 10, y: r.maxY - 28), color: .white, fill: NSColor.black.withAlphaComponent(0.55)) }
        if r.height * (bottom - top) > 40 { drawLabel("滚动正文", at: CGPoint(x: r.minX + 10, y: r.minY + r.height * top + 10), color: .white, fill: accent) }
    }
    private func drawLabel(_ title: String, at origin: CGPoint, color: NSColor, fill: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attributes)
        fill.setFill(); NSBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: size.width + 12, height: 20)), xRadius: 4, yRadius: 4).fill()
        (title as NSString).draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: attributes)
    }
}
