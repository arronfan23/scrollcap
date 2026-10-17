import AppKit
import SwiftUI

/// Semantic colors keep the blue-green identity readable in both macOS appearances.
enum ScrollCapStyle {
    static let accent = Color(red: 0.025, green: 0.43, blue: 0.46)
    static let emphasis = Color(nsColor: NSColor(name: "ScrollCapEmphasis") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.39, green: 0.83, blue: 0.81, alpha: 1)
            : NSColor(red: 0.025, green: 0.39, blue: 0.42, alpha: 1)
    })
    static let canvasColor = NSColor(name: "ScrollCapCanvas") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.09, green: 0.115, blue: 0.135, alpha: 1)
            : NSColor(red: 0.953, green: 0.965, blue: 0.969, alpha: 1)
    }
    static let canvas = Color(nsColor: canvasColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
}

enum GitHubAssets {
    static let mark: NSImage = {
        let image = Bundle.main.url(forResource: "GitHubMark", withExtension: "svg")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()
}

struct CaptureHUD: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
                    Text(model.automatic ? "自动采集中" : "手动采集中").fontWeight(.semibold)
                    Text("\(model.elapsed)s").monospacedDigit().foregroundStyle(.secondary)
                }.font(.callout)
                Text(model.autoStatus.isEmpty ? "等待采集画面…" : model.autoStatus)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if model.automatic {
                    Text("勿切换窗口，移开鼠标可停止").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: model.stop) {
                Label("结束并生成", systemImage: "stop.fill").font(.callout.weight(.semibold))
            }.buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent)
                .help("结束采集并生成长截图，也可使用菜单栏中的结束操作")
        }.padding(16).frame(width: 360, height: 90)
    }
}

struct MainView: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject private var history = ScreenshotHistoryStore.shared
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(showingHistory: $model.showingHistory, historyCount: history.entries.count, busy: model.busy, openSettings: model.openSettings)
            Divider()
            if model.showingHistory {
                ScreenshotHistoryView(model: model, history: history, preferences: model.preferences)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { HStack(spacing: 0) {
                CaptureSetupPane(model: model).frame(width: 300)
                Divider()
                CaptureWorkspace(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            } }
            Divider()
            GitHubSupportFooter(busy: model.busy)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(ScrollCapStyle.accent)
        .onChange(of: model.showingHistory) { _, visible in if visible { history.reload() } }
        .frame(minWidth: 880, minHeight: 690)
        .alert(model.permissionIssue?.title ?? "暂时无法完成", isPresented: Binding(
            get: { model.permissionIssue != nil || model.errorText != nil },
            set: { if !$0 { model.permissionIssue = nil; model.errorText = nil } }
        )) {
            if let issue = model.permissionIssue {
                Button("打开系统设置") { model.openSetting(issue.settingsPane) }
                Button("稍后", role: .cancel) { model.permissionIssue = nil }
            } else {
                Button("知道了") { model.errorText = nil }
            }
        } message: { Text(model.permissionIssue?.message ?? model.errorText ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if Bundle.main.bundleIdentifier != "io.github.arronfan23.scrollcap.designpreview" { model.refreshPermissions() }
        }
    }
}

private struct WorkspaceHeader: View {
    @Binding var showingHistory: Bool
    let historyCount: Int
    let busy: Bool
    let openSettings: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("ScrollCap").font(.system(size: 19, weight: .semibold))
                Text("SMO 出品 · 截图与长图工具").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("工作区", selection: $showingHistory) {
                Text("截图工作台").tag(false)
                Text("历史截图 · \(historyCount)").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260).disabled(busy)
            Spacer().frame(width: 20)
            Label("本机处理", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .help("采集的视频和截图在本机处理，无需上传")
            Button(action: openSettings) { Label("设置", systemImage: "gearshape") }
                .buttonStyle(.bordered).controlSize(.small).disabled(busy)
                .help("设置全局快捷键与截图偏好，快捷键 Command + 逗号")
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
}

private struct CaptureSetupPane: View {
    @ObservedObject var model: CaptureModel
    @State private var advanced = false
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.captureKind == .scrolling ? "新建长截图" : "新建普通截图").font(.title3.weight(.semibold))
                        Text(model.captureKind == .scrolling ? "聊天、网页，都能完整留下。" : "框选屏幕区域，随手保存或置顶。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("截图类型")
                        Picker("截图类型", selection: $model.captureKind) {
                            ForEach(CaptureKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if model.captureKind == .scrolling {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("滚动方式")
                            Picker("滚动方式", selection: $model.automatic) {
                                Text("手动滚动").tag(false)
                                Text("自动滚动").tag(true)
                            }.pickerStyle(.segmented).labelsHidden()
                            if model.automatic {
                                Picker("滚动速度", selection: $model.autoPace) {
                                    ForEach(AutoScrollPace.allCases, id: \.self) { pace in Text(pace.rawValue).tag(pace) }
                                }.font(.callout)
                            }
                            Label(model.automatic ? "小步滚动，到底自动结束。" : "每次滚动 1/4～1/3 屏，停半秒。",
                                  systemImage: model.automatic ? "wand.and.stars" : "hand.draw")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("截取方向")
                            Picker("截取方向", selection: $model.upward) {
                                Text("向下").tag(false)
                                Text("向上 · 历史聊天").tag(true)
                            }.pickerStyle(.segmented).labelsHidden()
                            Text(model.upward ? "先停在对话底部，再向上采集历史记录。" : "先停在需要的起点，再向下采集。")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("开始前检查")
                        PermissionRow(name: "屏幕录制", allowed: model.screenGranted, action: model.requestScreen)
                        if model.requiresAutomation {
                            PermissionRow(name: "辅助功能", allowed: model.accessGranted, action: model.requestAccess)
                        }
                        if !model.screenGranted || (model.requiresAutomation && !model.accessGranted) {
                            Text("在系统设置中开启后，回到这里会自动检查。")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("重新检查权限", action: model.refreshPermissions)
                                .font(.caption).buttonStyle(.link)
                        }
                    }
                    if model.captureKind == .scrolling {
                        DisclosureGroup("更多采集设置", isExpanded: $advanced) {
                            VStack(alignment: .leading, spacing: 13) {
                                Toggle("高保真采集", isOn: $model.highQuality).font(.callout)
                                Text("保留更清晰的文字，原视频会更大。")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                Stepper(value: $model.maximumSeconds, in: 30...300, step: 30) {
                                    HStack {
                                        Text("最长采集")
                                        Spacer()
                                        Text("\(model.maximumSeconds) 秒").foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }.font(.callout)
                            }.padding(.top, 10)
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("接下来").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if model.captureKind == .scrolling {
                            nextStep("1", "框选整个目标窗口")
                            nextStep("2", "标出会滚动的正文")
                            nextStep("3", model.automatic ? "保持窗口，等待采集完成" : "缓慢滚动，结束后生成长图")
                        } else {
                            nextStep("1", "框选需要的屏幕区域")
                            nextStep("2", "检查画面，按需调整裁剪")
                            nextStep("3", "右键标注、保存；Esc 关闭")
                        }
                    }
                }.padding(24)
            }.disabled(model.busy)
            Divider()
            CaptureStartControls(model: model).padding(20)
        }.background(ScrollCapStyle.surface.opacity(0.45))
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
    }
    private func nextStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 10, weight: .medium)).frame(width: 17, height: 17)
                .background(Color.secondary.opacity(0.1), in: Circle()).foregroundStyle(.secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let name: String
    let allowed: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(allowed ? ScrollCapStyle.emphasis : Color.orange)
                .accessibilityHidden(true)
            Text(name).font(.callout)
            Spacer(minLength: 4)
            if allowed {
                Text("已开启").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("开启", action: action).controlSize(.small).help("打开系统设置中的\(name)权限")
            }
        }.accessibilityElement(children: .contain)
            .accessibilityLabel("\(name)，\(allowed ? "已开启" : "需要开启")")
    }
}

private struct CaptureStartControls: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        VStack(spacing: 10) {
            if model.capturing {
                Button(action: model.stop) {
                    Label("结束并生成长图", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent)
            } else if model.processing {
                Button("取消处理", action: model.stop).frame(maxWidth: .infinity).controlSize(.large)
            } else {
                Button(action: model.start) {
                    Label(model.preparing ? "正在准备…" : (model.captureKind == .single ? "框选普通截图" : "框选窗口并开始"), systemImage: "viewfinder")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent).disabled(model.preparing)
                if model.captureKind == .scrolling {
                    Button(action: model.importVideo) {
                        Label("导入已有视频", systemImage: "film").frame(maxWidth: .infinity)
                    }.disabled(model.busy)
                }
            }
            if model.image != nil && !model.busy {
                Text("开始新截图前，请先保存当前图片。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.controlSize(.large)
    }
}

private struct CaptureWorkspace: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.busy ? "截图工作台" : (model.image == nil ? "截图预览" : (model.resultKind == .single ? "普通截图预览" : "长图预览"))).font(.title3.weight(.semibold))
                Spacer()
                if model.image != nil && !model.busy {
                    Text(model.outputSize).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            if let warning = model.resultWarning, !model.busy {
                ResultMessage(title: "长图仅包含已确认的部分", message: warning + "\n建议保存原视频，保留完整采集记录。", warning: true)
            }
            if let notice = model.resultNotice, !model.busy {
                ResultMessage(title: nil, message: notice, warning: false)
            }
            if model.image != nil && !model.busy { CropToolbar(model: model) }
            WorkspaceCanvas(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            WorkspaceStatus(model: model)
            if !model.busy && (model.image != nil || model.hasVideo || model.hasFrames) {
                Divider()
                HStack(spacing: 10) {
                    Button(action: model.save) { Label("保存 PNG", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent).disabled(model.image == nil)
                    Button(action: model.copy) { Label("复制", systemImage: "doc.on.doc") }.disabled(model.image == nil)
                    Button(action: model.pinCurrent) { Label("钉在最上层", systemImage: "pin") }
                        .disabled(model.image == nil).help("将当前裁剪结果作为独立浮窗置顶")
                    Spacer(minLength: 0)
                    if model.hasVideo || model.hasFrames {
                        Menu {
                            Button("保存原视频", action: model.saveVideo).disabled(!model.hasVideo)
                            Button("保存关键帧", action: model.exportFrames).disabled(!model.hasFrames)
                        } label: { Label("更多", systemImage: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }
                }.controlSize(.large)
            }
        }.padding(24)
    }
}

private struct WorkspaceCanvas: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        ZStack {
            ScrollCapStyle.canvas
            if model.busy {
                CaptureActivityState(model: model)
            } else if let image = model.previewImage {
                CropPreview(image: image, selection: model.previewSelection, editing: model.cropEditing,
                            scale: model.cropScale, changed: model.updateCrop)
            } else {
                CaptureEmptyState(kind: model.captureKind)
            }
        }.compositingGroup().clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ScrollCapStyle.separator.opacity(0.7), lineWidth: 1))
    }
}

private struct CaptureActivityState: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(ScrollCapStyle.emphasis.opacity(0.08)).frame(width: 76, height: 76)
                if model.capturing {
                    Image(systemName: "record.circle").font(.system(size: 32)).foregroundStyle(.red)
                } else {
                    ProgressView().controlSize(.large)
                }
            }.accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(model.capturing ? (model.automatic ? "正在自动采集" : "请缓慢滚动目标窗口") : (model.processing ? "正在生成长截图" : "准备框选窗口"))
                    .font(.title3.weight(.semibold))
                if model.capturing {
                    Text("已采集 \(model.elapsed) 秒").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    Text(model.automatic ? "保持目标窗口在前台，不要移动窗口或鼠标。" : "每次滚动 1/4～1/3 屏，停半秒；结束前停 1 秒。")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if model.processing {
                    Text("正在整理内容并寻找自然接缝，请稍候。")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: model.progress).frame(maxWidth: 260).padding(.top, 8)
                    Text("\(Int(max(0, min(1, model.progress)) * 100))%")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(model.captureKind == .single ? "拖动框选需要的屏幕区域，松开鼠标后生成截图。" : "拖动框选完整窗口，再标记滚动正文。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }.padding(32).frame(maxWidth: 430)
    }
}

private struct CaptureEmptyState: View {
    let kind: CaptureKind
    var body: some View {
        VStack(spacing: 28) {
            if kind == .scrolling {
                WindowAnatomyIllustration().frame(width: 260, height: 230).accessibilityHidden(true)
            } else {
                SingleCaptureIllustration().frame(width: 260, height: 230).accessibilityHidden(true)
            }
            VStack(spacing: 9) {
                Text(kind == .scrolling ? "从完整窗口开始" : "框选，留住此刻画面").font(.system(size: 20, weight: .semibold))
                Text(kind == .scrolling ? "把标题栏、滚动正文和输入框一起框进来。\n不动的部分保留一次，会动的内容拼成长图。" : "选择屏幕上的任意区域，截图原地停留。\n拖动移动、滚轮缩放，右键标注，Esc 关闭。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }
        }.padding(28)
    }
}

private struct SingleCaptureIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(ScrollCapStyle.surface).frame(width: 242, height: 174)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScrollCapStyle.separator, lineWidth: 1))
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.18)).frame(width: 132, height: 7)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7).fill(ScrollCapStyle.emphasis.opacity(0.13)).frame(width: 65, height: 62)
                        .overlay(Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(ScrollCapStyle.emphasis))
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(0..<3) { row in
                            Capsule().fill(Color.secondary.opacity(0.16)).frame(width: row == 2 ? 62 : 88, height: 5)
                        }
                    }
                }
                Capsule().fill(Color.secondary.opacity(0.1)).frame(width: 178, height: 5)
            }
            RoundedRectangle(cornerRadius: 4).strokeBorder(ScrollCapStyle.emphasis, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: 208, height: 137)
            Image(systemName: "plus.viewfinder").font(.system(size: 25, weight: .light)).foregroundStyle(ScrollCapStyle.emphasis)
                .offset(x: 103, y: 69)
        }
    }
}

private struct WindowAnatomyIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in Circle().fill(Color.secondary.opacity(0.3)).frame(width: 5, height: 5) }
                Spacer()
                Text("固定顶部").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).frame(height: 36).background(ScrollCapStyle.surface)
            VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 5).fill(ScrollCapStyle.emphasis.opacity(0.2)).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.23)).frame(width: row == 1 ? 94 : 118, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.12)).frame(width: row == 2 ? 105 : 72, height: 5)
                        }.padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity)
                .background(ScrollCapStyle.emphasis.opacity(0.035))
                .overlay(alignment: .trailing) {
                    Image(systemName: "arrow.down").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ScrollCapStyle.emphasis).padding(.trailing, 13)
                }
                .overlay(alignment: .top) { Rectangle().fill(ScrollCapStyle.emphasis.opacity(0.55)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(ScrollCapStyle.emphasis.opacity(0.55)).frame(height: 1) }
            HStack {
                RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.15)).frame(height: 20)
                    .overlay(alignment: .leading) { Text("固定输入框").font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 8) }
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).frame(height: 40).background(ScrollCapStyle.surface)
        }
        .compositingGroup().clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScrollCapStyle.separator, lineWidth: 1))
        .overlay(alignment: .bottom) {
            Text("滚动正文 · 连续拼接").font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScrollCapStyle.emphasis).padding(.horizontal, 10).padding(.vertical, 5)
                .background(ScrollCapStyle.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(ScrollCapStyle.separator.opacity(0.6), lineWidth: 1))
                .offset(y: 14)
        }
    }
}

private struct CropToolbar: View {
    @ObservedObject var model: CaptureModel
    @State private var preciseCrop = false
    // The presenter owns the transaction so system-driven sheet dismissal also rolls back.
    @State private var originalCrop: CGRect?
    @State private var originalEditing = true
    @State private var cropCommitted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("预览缩放", selection: $model.cropScale) {
                    ForEach(CropScale.allCases, id: \.self) { scale in Text(scale.rawValue).tag(scale) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                Spacer(minLength: 4)
                Button(model.cropEditing ? "完成裁剪" : "调整裁剪") { model.cropEditing.toggle() }
                Menu {
                    Button("恢复原图", action: model.resetCrop).disabled(!model.isCropped)
                    Button("精确调整四边…", action: beginPreciseCrop)
                } label: { Image(systemName: "ellipsis").accessibilityLabel("裁剪选项") }
                    .menuStyle(.borderlessButton).fixedSize().help("恢复原图或用数值调整四边")
            }.controlSize(.small)
            Label(model.cropEditing ? "拖动四边或四角裁剪；切换「全图」可同时调整上下边。" : "已应用裁剪，保存和复制均使用当前选区。",
                  systemImage: model.cropEditing ? "crop" : "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.sheet(isPresented: $preciseCrop, onDismiss: finishPreciseCrop) {
            PreciseCropSheet(model: model) { cropCommitted = true }
        }
    }
    private func beginPreciseCrop() {
        originalCrop = model.cropRect
        originalEditing = model.cropEditing
        cropCommitted = false
        preciseCrop = true
    }
    private func finishPreciseCrop() {
        if !cropCommitted, let originalCrop {
            model.updateCrop(originalCrop)
            model.cropEditing = originalEditing
        }
        originalCrop = nil
        cropCommitted = false
    }
}

/// Numeric controls provide a keyboard alternative to dragging the four crop edges.
private struct PreciseCropSheet: View {
    @ObservedObject var model: CaptureModel
    let commit: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("精确调整裁剪").font(.title3.weight(.semibold))
            Text("设置四边裁去的像素，预览会即时更新。")
                .font(.callout).foregroundStyle(.secondary)
            cropEdge("上", edge: .top)
            cropEdge("下", edge: .bottom)
            cropEdge("左", edge: .left)
            cropEdge("右", edge: .right)
            HStack {
                Button("恢复原图", action: model.resetCrop).disabled(!model.isCropped)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("完成") { commit(); dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(ScrollCapStyle.accent)
            }
        }.padding(24).frame(width: 380)
    }
    private func cropEdge(_ name: String, edge: CropHandle) -> some View {
        HStack {
            Text("\(name)边").frame(width: 34, alignment: .leading)
            TextField("\(name)边裁去像素", value: Binding(get: { edgeValue(edge) }, set: { setEdge(edge, value: $0) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 90).multilineTextAlignment(.trailing)
            Text("px").foregroundStyle(.secondary)
            Stepper("\(name)边裁去像素", value: Binding(get: { edgeValue(edge) }, set: { setEdge(edge, value: $0) }), in: 0...edgeMaximum(edge))
                .labelsHidden()
        }.font(.callout)
    }
    private var fullSize: CGSize { model.image?.size ?? .zero }
    private func edgeMaximum(_ edge: CropHandle) -> Int {
        let r = model.cropRect
        switch edge {
        case .top: return max(0, Int(r.maxY) - 1)
        case .bottom: return max(0, Int(fullSize.height - r.minY) - 1)
        case .left: return max(0, Int(r.maxX) - 1)
        default: return max(0, Int(fullSize.width - r.minX) - 1)
        }
    }
    private func edgeValue(_ edge: CropHandle) -> Int {
        switch edge {
        case .top: return Int(model.cropRect.minY)
        case .bottom: return Int(fullSize.height - model.cropRect.maxY)
        case .left: return Int(model.cropRect.minX)
        default: return Int(fullSize.width - model.cropRect.maxX)
        }
    }
    private func setEdge(_ edge: CropHandle, value: Int) {
        let value = CGFloat(min(edgeMaximum(edge), max(0, value)))
        var r = model.cropRect
        switch edge {
        case .top: r = CGRect(x: r.minX, y: value, width: r.width, height: r.maxY - value)
        case .bottom: r.size.height = fullSize.height - value - r.minY
        case .left: r = CGRect(x: value, y: r.minY, width: r.maxX - value, height: r.height)
        default: r.size.width = fullSize.width - value - r.minX
        }
        model.cropEditing = true
        model.updateCrop(r)
    }
}

private struct ResultMessage: View {
    let title: String?
    let message: String
    let warning: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "checkmark.viewfinder")
                .foregroundStyle(warning ? Color.orange : ScrollCapStyle.emphasis).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).fontWeight(.semibold) }
                Text(message).foregroundStyle(.secondary)
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(12).background(warning ? Color.orange.opacity(0.07) : ScrollCapStyle.emphasis.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WorkspaceStatus: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: model.capturing ? "record.circle" : (model.image == nil ? "info.circle" : "checkmark.circle"))
                .foregroundStyle(ScrollCapStyle.emphasis).accessibilityHidden(true)
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }.frame(minHeight: 28, alignment: .top)
    }
}

private struct GitHubSupportFooter: View {
    let busy: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text("如果ScrollCap帮助到了你，请在GitHub点个star，这对我们意义重大")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Link(destination: URL(string: "https://github.com/arronfan23/scrollcap")!) {
                Label { Text("去点 Star") } icon: {
                    Image(nsImage: GitHubAssets.mark).resizable().scaledToFit().frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
            }.buttonStyle(.bordered).controlSize(.small).disabled(busy)
                .help(busy ? "采集结束后可打开 GitHub" : "打开 ScrollCap 的 GitHub 仓库")
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CaptureModel()
    var window: NSWindow!
    var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private lazy var hotkeys = GlobalHotKeyManager(preferences: model.preferences)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let frame = NSRect(x: 0, y: 0, width: 1040, height: 780)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ScrollCap"
        window.minSize = NSSize(width: 900, height: 750)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(model: model))
        model.mainWindow = window
        model.settingsAction = { [weak self] in self?.settings() }
        model.hideAuxiliaryWindows = { [weak self] in self?.settingsWindow?.orderOut(nil) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        buildMenus()
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .single: self.model.startSingle()
            case .scrolling: self.model.startScrolling()
            case .stop: self.model.stop()
            }
        }
        if Bundle.main.bundleIdentifier == "io.github.arronfan23.scrollcap.designpreview" {
            DesignPreview.configure(model: model, window: window)
        } else {
            model.monitorPermissions()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--preview-image"), CommandLine.arguments.indices.contains(index + 1) {
            model.loadPreview(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
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
        let settingsItem = appMenu.addItem(withTitle: "设置…", action: #selector(settings), keyEquivalent: ","); settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 ScrollCap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 ScrollCap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appRoot.submenu = appMenu; menu.addItem(appRoot)
        let shotRoot = NSMenuItem(); shotRoot.title = "截图"; let shotMenu = NSMenu(title: "截图")
        for (title, action, key) in [("普通截图", #selector(single), ""), ("长截图", #selector(start), "n"), ("结束采集", #selector(stop), "."), ("保存截图", #selector(save), "s"), ("复制截图", #selector(copyImage), "c"), ("钉在最上层", #selector(pin), ""), ("显示主窗口", #selector(show), "0")] {
            let item = shotMenu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        shotRoot.submenu = shotMenu; menu.addItem(shotRoot)
        let editRoot = NSMenuItem(); editRoot.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = editMenu; menu.addItem(editRoot)
        let windowRoot = NSMenuItem(); windowRoot.title = "窗口"
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let pinnedItem = windowMenu.addItem(withTitle: "显示置顶截图", action: #selector(showPinned), keyEquivalent: ""); pinnedItem.target = self
        windowRoot.submenu = windowMenu; menu.addItem(windowRoot)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "ScrollCap")
        let statusMenu = NSMenu()
        for (title, action) in [("打开 ScrollCap", #selector(show)), ("历史截图", #selector(history)), ("普通截图", #selector(single)), ("长截图", #selector(start)), ("结束并生成长图", #selector(stop)), ("设置…", #selector(settings))] {
            let item = statusMenu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        statusItem?.menu = statusMenu
    }
    @objc func single() { model.startSingle() }
    @objc func start() { model.startScrolling() }
    @objc func stop() { model.stop() }
    @objc func save() { if !PinnedScreenshotManager.shared.handleMenuAction("save", fallbackToVisible: !window.isVisible) { model.save() } }
    @objc func copyImage() { if !PinnedScreenshotManager.shared.handleMenuAction("copy", fallbackToVisible: !window.isVisible) { model.copy() } }
    @objc func pin() { if !PinnedScreenshotManager.shared.handleMenuAction("pin", fallbackToVisible: !window.isVisible) { model.pinCurrent() } }
    @objc func showPinned() { PinnedScreenshotManager.shared.bringForward() }
    @objc func settings() {
        guard !model.busy else { return }
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "ScrollCap 设置"; panel.minSize = NSSize(width: 620, height: 500); panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AppSettingsView(preferences: model.preferences, hotkeys: hotkeys))
        panel.center(); panel.makeKeyAndOrderFront(nil); settingsWindow = panel
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func show() { model.showMain() }
    @objc func history() { model.showHistory() }
    @objc func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.6.0"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "ScrollCap · SMO", .applicationVersion: version, .credits: NSAttributedString(string: "SMO 出品\n普通截图、长截图与置顶参考图。\n截图及视频拼接均在本机完成。\nMIT License · github.com/arronfan23/scrollcap")])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
#if DESIGN_PREVIEW
        traceEditorWindows("application-reopen")
#endif
        // Reactivating a floating editor must not reopen the workbench behind it.
        if !model.busy && PinnedScreenshotManager.shared.count == 0 { model.showMain() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.capturing || model.processing { model.stop(); model.showMain(); return .terminateCancel }
        if !PinnedScreenshotManager.shared.closeAll() { return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { hotkeys.shutdown(); model.cleanUp() }
}
