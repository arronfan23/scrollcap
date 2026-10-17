import AppKit
import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var hotkeys: GlobalHotKeyManager
    @State private var defaultsError: String?
    @State private var defaultsRestored = false
    @State private var resetRevision = 0

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ScrollCap 设置").font(.title3.weight(.semibold))
                    Text("SMO 出品 · 让截图顺手一些").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("全局快捷键", systemImage: "keyboard").font(.callout.weight(.semibold))
                    Spacer()
                    Button("恢复默认") {
                        defaultsError = hotkeys.restoreDefaults()
                        defaultsRestored = defaultsError == nil
                        if defaultsError == nil { resetRevision += 1 }
                    }.controlSize(.small)
                }
                Text("在其他应用中也能快速截图。点击右侧录入框，再按下一组快捷键。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(ShortcutAction.allCases) { action in
                        ShortcutSettingsRow(action: action, preferences: preferences, hotkeys: hotkeys)
                        if action != ShortcutAction.allCases.last { Divider().padding(.horizontal, 16) }
                    }
                }.id(resetRevision).background(ScrollCapStyle.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ScrollCapStyle.separator.opacity(0.7), lineWidth: 1))
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text("录入时按 Esc 取消，按 Delete 清除。快捷键立即生效，无需辅助功能权限。")
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let defaultsError {
                    Label(defaultsError, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                } else if defaultsRestored {
                    Label("已恢复默认快捷键。", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(ScrollCapStyle.emphasis)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label("普通截图", systemImage: "viewfinder").font(.callout.weight(.semibold))
                Toggle("截图完成后自动钉在最上层", isOn: $preferences.autoPinSingle)
                    .font(.callout)
                Text("截图始终原地停留；开启此项会保持在其他应用上方。也可右键点击图钉图标切换。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label("历史截图", systemImage: "clock.arrow.circlepath").font(.callout.weight(.semibold))
                Picker("保留方式", selection: $preferences.historyRetention) {
                    ForEach(HistoryRetention.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text(preferences.historyRetention == .exported
                     ? "保存或复制成功后进入历史。直接按 Esc 或叉号关闭的截图不保留。"
                     : "截图完成后自动进入历史，关闭时保留当前标注。可在历史截图中删除。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("历史仅保存在本机，包含原图及可编辑标注；导出的 PNG 仍为合成图片。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("截图与设置均保留在此 Mac。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("SMO / ScrollCap").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }.padding(24)
        }.frame(width: 620)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(ScrollCapStyle.accent)
    }
}

private struct ShortcutSettingsRow: View {
    let action: ShortcutAction
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var hotkeys: GlobalHotKeyManager
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.callout.weight(.medium))
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ShortcutRecorder(shortcut: preferences.shortcut(for: action), title: action.title,
                                 recordingChanged: hotkeys.suspendRecording) { shortcut in
                    localError = hotkeys.update(action, to: shortcut)
                }.frame(width: 184, height: 32)
                Button {
                    localError = hotkeys.update(action, to: nil)
                } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 14))
                }.buttonStyle(.borderless).disabled(preferences.shortcut(for: action) == nil)
                    .accessibilityLabel("清除\(action.title)快捷键").help("清除此快捷键")
            }
            if let error = localError ?? hotkeys.errors[action] {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .onChange(of: preferences.shortcut(for: action)) { _, _ in localError = nil }
    }
}

/// Receives keys only while this native view is focused and explicitly recording.
/// No local/global NSEvent monitor is installed.
private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyShortcut?
    let title: String
    let recordingChanged: (Bool) -> Void
    let changed: (KeyShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.recordingChanged = recordingChanged
        view.changed = changed
        view.shortcut = shortcut
        view.actionTitle = title
        return view
    }
    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.actionTitle = title
        view.recordingChanged = recordingChanged
        view.changed = changed
    }
    static func dismantleNSView(_ view: ShortcutRecorderView, coordinator: ()) {
        view.finishRecording()
    }
}

private final class ShortcutRecorderView: NSView {
    var shortcut: KeyShortcut? { didSet { updateAccessibility(); needsDisplay = true } }
    var actionTitle = "快捷键" { didSet { updateAccessibility() } }
    var recordingChanged: ((Bool) -> Void)?
    var changed: ((KeyShortcut?) -> Void)?
    private var recording = false
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        focusRingType = .exterior
        updateAccessibility()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { windowObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill() }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }
    override func resignFirstResponder() -> Bool {
        finishRecording()
        needsDisplay = true
        return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { finishRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishRecording() }
                })
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }
    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        beginRecording()
        return true
    }
    override func keyDown(with event: NSEvent) {
        if recording { receive(event) }
        else if event.keyCode == 36 || event.keyCode == 49 { beginRecording() }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return false }
        receive(event)
        return true
    }
    private func beginRecording() {
        guard !recording else { return }
        recording = true
        recordingChanged?(true)
        updateAccessibility()
        needsDisplay = true
    }
    func finishRecording() {
        guard recording else { return }
        recording = false
        recordingChanged?(false)
        updateAccessibility()
        needsDisplay = true
    }
    private func receive(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        switch event.keyCode {
        case 53:
            finishRecording()
        case 48:
            finishRecording()
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        case 51, 117:
            // Clear only when recording; the adjacent button is also keyboard-accessible.
            finishRecording()
            changed?(nil)
        default:
            let captured = KeyShortcut(event: event)
            finishRecording()
            changed?(captured)
        }
    }
    private func updateAccessibility() {
        setAccessibilityLabel("录入\(actionTitle)快捷键")
        setAccessibilityValue(recording ? "正在录入，请按下一组快捷键" : (shortcut?.display ?? "未设置"))
        setAccessibilityHelp("点击或按空格开始录入，Escape 取消，Delete 清除")
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (recording ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 1.5 : 1
        path.stroke()
        let text = recording ? "按下新的快捷键…" : (shortcut?.display ?? "点击录入快捷键")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording ? NSColor.labelColor : (shortcut == nil ? NSColor.secondaryLabelColor : NSColor.labelColor)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}
