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
        let scale = min(780 / CGFloat(image.width), 520 / CGFloat(image.height))
        let width = max(640, CGFloat(image.width) * scale + 48)
        let height = CGFloat(image.height) * scale + 178
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "标记滚动区域 · 固定部分保留一次"
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
    func windowWillClose(_ notification: Notification) { finish(nil) }
}

struct ChromeSelectionView: View {
    let image: CGImage
    let done: (ChromeSelection?) -> Void
    @State private var top = 0.13
    @State private var bottom = 0.83
    @State private var includeFixed = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拖动上下两条线，只把会滚动的聊天正文留在中间。").font(.system(size: 14, weight: .semibold))
            Text("顶部标题栏和底部输入框将各保留一次。录制时保持窗口位置不变。").font(.system(size: 12)).foregroundStyle(.secondary)
            BandPreview(image: image, top: $top, bottom: $bottom).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("固定顶部 \(Int(top * Double(image.height))) px · 正文 \(Int((bottom - top) * Double(image.height))) px · 固定底部 \(Int((1 - bottom) * Double(image.height))) px")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Toggle("把固定部分截进长图", isOn: $includeFixed).font(.system(size: 12))
                Button("整个区域都滚动") { top = 0; bottom = 1 }
                Spacer()
                Button("取消") { done(nil) }
                Button("确认并开始") {
                    let y = Int((top * Double(image.height)).rounded())
                    let end = Int((bottom * Double(image.height)).rounded())
                    done(ChromeSelection(body: CGRect(x: 0, y: y, width: image.width, height: end - y), includeFixed: includeFixed))
                }.buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(Int((bottom - top) * Double(image.height)) < 140)
            }
        }.padding(24)
    }
}
struct BandPreview: NSViewRepresentable {
    let image: CGImage
    @Binding var top: Double
    @Binding var bottom: Double
    func makeNSView(context: Context) -> BandSelectionView {
        let view = BandSelectionView(); view.image = image
        view.changed = { t, b in top = t; bottom = b }; return view
    }
    func updateNSView(_ view: BandSelectionView, context: Context) { view.top = top; view.bottom = bottom; view.needsDisplay = true }
}
final class BandSelectionView: NSView {
    var image: CGImage?
    var top = 0.13, bottom = 0.83
    var changed: ((Double, Double) -> Void)?
    private var draggedTop = true
    override var isFlipped: Bool { true }
    private var imageRect: CGRect {
        guard let image else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        draggedTop = abs(p.y - (r.minY + r.height * top)) < abs(p.y - (r.minY + r.height * bottom))
        update(event)
    }
    override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard r.height > 0, let image else { return }
        let value = min(1, max(0, Double((p.y - r.minY) / r.height)))
        let gap = max(0.08, 140.0 / Double(image.height))
        if draggedTop { top = min(bottom - gap, value) } else { bottom = max(top + gap, value) }
        top = max(0, top); bottom = min(1, bottom)
        changed?(top, bottom); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard let image else { return }
        let r = imageRect
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.systemTeal.withAlphaComponent(0.23).setFill()
        CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * top).fill()
        CGRect(x: r.minX, y: r.minY + r.height * bottom, width: r.width, height: r.height * (1 - bottom)).fill()
        for fraction in [top, bottom] {
            let y = r.minY + r.height * fraction
            NSColor.systemTeal.setStroke()
            let path = NSBezierPath(); path.move(to: CGPoint(x: r.minX, y: y)); path.line(to: CGPoint(x: r.maxX, y: y)); path.lineWidth = 3; path.stroke()
            NSColor.systemTeal.setFill(); NSBezierPath(roundedRect: CGRect(x: r.midX - 23, y: y - 5, width: 46, height: 10), xRadius: 5, yRadius: 5).fill()
        }
    }
}
