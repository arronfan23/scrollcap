import AppKit
import CoreGraphics

struct CaptureRegion {
    let displayID: CGDirectDisplayID
    let rect: CGRect // Quartz global coordinates, in points.
    let displayBounds: CGRect
    let scale: CGFloat
    let targetPID: pid_t?
    var targetWindowID: CGWindowID? = nil
    var targetWindowBounds: CGRect? = nil
    var sourceRect: CGRect { CGRect(x: rect.minX - displayBounds.minX, y: rect.minY - displayBounds.minY, width: rect.width, height: rect.height) }
}

@MainActor
final class RegionPicker {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureRegion?) -> Void)?
    private var previousApp: NSRunningApplication?
    private var kind: CaptureKind = .scrolling
    func begin(kind: CaptureKind = .scrolling, _ completion: @escaping (CaptureRegion?) -> Void) {
        self.kind = kind
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.kind = kind
            view.finished = { [weak self] rect in self?.finish(rect, on: screen) }
            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func cancel() {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        let callback = completion; completion = nil; callback?(nil)
    }
    private func finish(_ local: CGRect?, on screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        var result: CaptureRegion?
        let minimum = kind == .single ? CGSize(width: 8, height: 8) : CGSize(width: 160, height: 140)
        if let local = local, local.width >= minimum.width, local.height >= minimum.height,
           let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
            let bounds = CGDisplayBounds(id)
            let rect = CGRect(x: bounds.minX + local.minX, y: bounds.minY + screen.frame.height - local.maxY,
                              width: local.width, height: local.height).integral
            var pid: pid_t?
            var windowID: CGWindowID?, windowBounds: CGRect?
            if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                for window in list {
                    guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                          owner != ProcessInfo.processInfo.processIdentifier,
                          (window[kCGWindowLayer as String] as? Int) == 0,
                          let data = window[kCGWindowBounds as String] as? [String: CGFloat],
                          let x = data["X"], let y = data["Y"], let w = data["Width"], let h = data["Height"] else { continue }
                    if CGRect(x: x, y: y, width: w, height: h).contains(CGPoint(x: rect.midX, y: rect.midY)) {
                        pid = pid_t(owner); windowID = window[kCGWindowNumber as String] as? CGWindowID
                        windowBounds = CGRect(x: x, y: y, width: w, height: h); break
                    }
                }
            }
            if pid == nil, previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { pid = previousApp?.processIdentifier }
            result = CaptureRegion(displayID: id, rect: rect, displayBounds: bounds, scale: screen.backingScaleFactor, targetPID: pid,
                                   targetWindowID: windowID, targetWindowBounds: windowBounds)
        }
        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionView: NSView {
    var kind: CaptureKind = .scrolling
    var finished: ((CGRect?) -> Void)?
    private var anchor: CGPoint?
    private var selected: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) { anchor = convert(event.locationInWindow, from: nil); selected = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let p = convert(event.locationInWindow, from: nil)
        selected = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(anchor.x - p.x), height: abs(anchor.y - p.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { finished?(selected) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finished?(nil) } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.40).setFill()
        bounds.fill()
        if let selected {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            selected.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.systemTeal.setStroke()
            let border = NSBezierPath(rect: selected.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
        }
        let text = selected.map { "\(Int($0.width)) × \(Int($0.height))  ·  \(kind == .single ? "松开完成截图" : "松开标记正文")" }
            ?? (kind == .single ? "SMO · 普通截图  ·  拖动框选需要的区域  ·  松开完成截图  ·  Esc 取消"
                : "SMO · 长截图  ·  框选完整窗口（包含标题、输入框）  ·  下一步标记正文  ·  Esc 取消")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let labelRect = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - 88, width: size.width, height: 26)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: labelRect.insetBy(dx: -18, dy: -10), xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(in: labelRect, withAttributes: attributes)
    }
}
