import AppKit
import SwiftUI

struct CaptureHUD: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("连续采集 · \(model.elapsed) 秒").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("正文慢慢滚动，完成后点击结束").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("结束并生成") { model.stop() }.buttonStyle(.borderedProminent).tint(.teal)
        }.padding(16).frame(width: 360, height: 90)
    }
}

struct MainView: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("ScrollCap").font(.system(size: 25, weight: .bold))
                    Text("ScrollCap  /  固定部分保留一次 · 滚动正文自然拼接").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("固定区域也能截").font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.teal.opacity(0.10), in: Capsule()).foregroundStyle(Color.teal)
            }.padding(.horizontal, 28).padding(.vertical, 22)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ScrollView { settings.frame(width: 300).padding(24) }
                    Divider()
                    startControls.padding(20)
                }.frame(width: 348)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            }
            Divider()
            HStack(spacing: 9) {
                Image(systemName: model.capturing ? "record.circle" : "info.circle").foregroundStyle(.teal)
                Text(model.status).font(.system(size: 12)).lineLimit(3)
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).padding(.vertical, 14).frame(minHeight: 54)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 880, minHeight: 710)
        .alert("暂时无法完成", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("知道了") { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整窗口长截图").font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                Label("框选完整窗口", systemImage: "1.circle.fill")
                Label("标记会滚动的正文", systemImage: "2.circle.fill")
                Label("结束并生成长图", systemImage: "3.circle.fill")
            }.font(.system(size: 13)).foregroundStyle(.teal)
            Text("不动的标题栏、底部输入框各保留一次，中间正文连续拼接。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                label("滚动方式", symbol: "cursorarrow.motionlines")
                Picker("滚动方式", selection: $model.automatic) {
                    Text("手动滚动").tag(false); Text("自动滚动").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                Text(model.automatic ? "工具会缓慢滚动正文区域，到底后结束。" : "你缓慢滚动聊天正文，完成后点击结束。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                label("截取方向", symbol: "arrow.up.arrow.down")
                Picker("截取方向", selection: $model.upward) {
                    Text("向下").tag(false); Text("向上 · 历史聊天").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            Toggle("高保真采集", isOn: $model.highQuality).font(.system(size: 12))
            Text("文字细节更清晰，原视频文件较大。全程在本机处理。").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Stepper(value: $model.maximumSeconds, in: 30...300, step: 30) {
                HStack { Text("最长采集"); Spacer(); Text("\(model.maximumSeconds) 秒").foregroundStyle(.secondary).monospacedDigit() }
            }.font(.system(size: 12))
            Divider()
            permission("屏幕录制", allowed: model.screenGranted, action: model.requestScreen)
            permission("自动滚动权限", allowed: model.accessGranted, action: model.requestAccess)
            Text("手动模式只需屏幕录制权限。结束按钮始终可用。").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.disabled(model.busy)
    }
    var startControls: some View {
        VStack(spacing: 10) {
            Button(action: model.start) {
                Label("框选窗口并开始", systemImage: "viewfinder").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
            Button(action: model.importVideo) { Label("导入已有窗口视频", systemImage: "film").frame(maxWidth: .infinity) }.controlSize(.large)
        }.disabled(model.busy)
    }
    func label(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .medium))
    }
    func permission(_ name: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(allowed ? Color.teal : Color.secondary)
            Text(name).font(.system(size: 12))
            Spacer()
            if allowed { Text("已开启").font(.system(size: 11)).foregroundStyle(.secondary) }
            else { Button("开启", action: action).controlSize(.small) }
        }
    }
    var preview: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("长图预览").font(.system(size: 16, weight: .semibold))
                Spacer()
                if !model.imageSize.isEmpty { Text(model.imageSize).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
            }
            GeometryReader { geometry in
                if let image = model.image {
                    ScrollView([.vertical, .horizontal]) {
                        let width = min(geometry.size.width - 28, image.size.width)
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: width, height: width * image.size.height / image.size.width)
                            .background(.white).shadow(color: .black.opacity(0.12), radius: 8, y: 3).padding(14)
                    }.background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    emptyState.frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.17), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                }
            }
            if model.processing {
                HStack { ProgressView(value: model.progress); Button("取消处理") { model.stop() } }.padding(.vertical, 4)
            }
            HStack(spacing: 9) {
                Button(action: model.save) { Label("保存 PNG", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(.teal).disabled(model.image == nil || model.busy)
                Button(action: model.copy) { Label("复制", systemImage: "doc.on.doc") }.disabled(model.image == nil || model.busy)
                Spacer()
                Button("保存关键帧", action: model.exportFrames).disabled(!model.hasFrames || model.busy)
            }.controlSize(.large)
            HStack {
                Text("识别文字位置，优先在空白处接缝。开始下一次前请先保存结果。")
                Spacer()
                Button("保存原视频", action: model.saveVideo).disabled(!model.hasVideo || model.busy)
            }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("若某段无法确认，会只生成可确认部分，并保留原视频。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.teal.opacity(0.07)).frame(width: 164, height: 192)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(0..<5) { row in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(row == 2 ? 0.5 : 0.18)).frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 5) {
                                Capsule().fill(Color.secondary.opacity(0.17)).frame(width: row % 2 == 0 ? 80 : 66, height: 5)
                                Capsule().fill(Color.secondary.opacity(0.10)).frame(width: 52, height: 5)
                            }
                        }
                    }
                }
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.teal.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])).frame(width: 184, height: 90)
            }
            VStack(spacing: 7) {
                Text("把完整聊天窗口留下来").font(.system(size: 16, weight: .semibold))
                Text("固定标题  +  滚动正文  +  固定输入框\n会动的部分拼接，不动的部分只留一次")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CaptureModel()
    var window: NSWindow!
    var statusItem: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let frame = NSRect(x: 0, y: 0, width: 1040, height: 780)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ScrollCap · 完整窗口"
        window.minSize = NSSize(width: 900, height: 750)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(model: model))
        model.mainWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        buildMenus()
        model.monitorPermissions()
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--render-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.window.contentView?.layoutSubtreeIfNeeded()
                if let view = self.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]), let path = CommandLine.arguments.last {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }
    func buildMenus() {
        let menu = NSMenu()
        let appRoot = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 ScrollCap", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 ScrollCap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 ScrollCap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appRoot.submenu = appMenu; menu.addItem(appRoot)
        let shotRoot = NSMenuItem(); shotRoot.title = "截图"; let shotMenu = NSMenu(title: "截图")
        for (title, action, key) in [("框选并开始", #selector(start), "n"), ("结束截图", #selector(stop), "."), ("保存长图", #selector(save), "s"), ("复制长图", #selector(copyImage), "c"), ("显示主窗口", #selector(show), "0")] {
            let item = shotMenu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        shotRoot.submenu = shotMenu; menu.addItem(shotRoot)
        let editRoot = NSMenuItem(); editRoot.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = editMenu; menu.addItem(editRoot)
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "ScrollCap")
        let statusMenu = NSMenu()
        for (title, action) in [("打开 ScrollCap", #selector(show)), ("结束并生成长图", #selector(stop))] {
            let item = statusMenu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        statusItem?.menu = statusMenu
    }
    @objc func start() { model.start() }
    @objc func stop() { model.stop() }
    @objc func save() { model.save() }
    @objc func copyImage() { model.copy() }
    @objc func show() { model.showMain() }
    @objc func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.1.0"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "ScrollCap", .applicationVersion: version, .credits: NSAttributedString(string: "完整窗口长截图：固定顶部、滚动正文、固定底部。\n连续视频采集与 Vision 辅助拼接均在本机完成。\nMIT License · github.com/arronfan23/scrollcap")])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { model.showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.capturing || model.processing { model.stop(); model.showMain(); return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model.cleanUp() }
}
