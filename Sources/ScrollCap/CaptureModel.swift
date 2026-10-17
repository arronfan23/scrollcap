import AppKit
import SwiftUI
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class CaptureModel: ObservableObject {
    @Published var captureKind: CaptureKind = .scrolling
    @Published private(set) var resultKind: CaptureKind = .scrolling
    let preferences = AppPreferences.shared
    let history = ScreenshotHistoryStore.shared
    @Published var showingHistory = false
    var settingsAction: (() -> Void)?
    var hideAuxiliaryWindows: (() -> Void)?
    var requiresAutomation: Bool { captureKind == .scrolling && automatic }
    @Published var automatic = false
    @Published var autoPace: AutoScrollPace = .careful
    @Published var autoStatus = ""
    @Published var upward = false
    @Published var highQuality = true
    @Published var maximumSeconds = 120
    @Published var capturing = false
    @Published var processing = false
    @Published var preparing = false
    @Published var status = "框选整个聊天窗口，固定标题和输入框也可以一起截进来。"
    @Published var errorText: String?
    @Published var permissionIssue: CapturePermissionIssue?
    @Published var resultWarning: String?
    @Published var resultNotice: String?
    @Published var image: NSImage?
    @Published var imageSize = ""
    @Published private(set) var cropRect = CGRect.zero
    @Published private(set) var croppedImage: CGImage?
    @Published var cropEditing = true
    @Published var cropScale: CropScale = .width
    @Published var count = 0
    @Published var elapsed = 0
    @Published var progress = 0.0
    @Published var hasFrames = false
    @Published var hasVideo = false
    @Published var screenGranted = CGPreflightScreenCaptureAccess()
    @Published var accessGranted = CGPreflightPostEventAccess()
    var mainWindow: NSWindow?
    var busy: Bool { capturing || preparing || processing }
    private var regionPicker: RegionPicker?
    private var chromePicker: ChromePicker?
    private var hud: NSPanel?
    private var localMonitor: Any?
    private var task: Task<Void, Never>?
    private var cancel = CancelFlag()
    private var stopRequested = false
    private var dismissingCapture = false
    private var resultRegion: CaptureRegion?
    private(set) var resultID: UUID?
    private var cropHistoryID: UUID?
    // Workbench crop exports and floating annotations are independent documents.
    private var workbenchHistoryID: UUID?
    private var sessionUpward = false
    private var sessionAutomatic = false
    private var sessionPace: AutoScrollPace = .careful
    private var sessionHighQuality = true
    private var sessionScale: CGFloat = 1
    private var sessionLimit = 120
    private var videoURL: URL?
    private var directory: URL?
    private var frameDirectory: URL?
    private var finalImage: CGImage?
    private var cover: CGImage?
    private var selection: ChromeSelection?
    private var permissionTimer: Timer?
    private var refreshingPermissions = false
    private let automation = AutoScrollClient()

    var previewImage: CGImage? { cropEditing ? finalImage : croppedImage }
    var previewSelection: CGRect {
        guard !cropEditing, let croppedImage else { return cropRect }
        return CGRect(x: 0, y: 0, width: croppedImage.width, height: croppedImage.height)
    }
    var isCropped: Bool {
        guard let finalImage else { return false }
        return cropRect != CGRect(x: 0, y: 0, width: finalImage.width, height: finalImage.height)
    }
    var outputSize: String {
        guard let croppedImage else { return "" }
        return "\(croppedImage.width) × \(croppedImage.height) px"
    }
    func setResultImage(_ result: CGImage, kind: CaptureKind? = nil) {
        resultID = UUID()
        cropHistoryID = resultID
        workbenchHistoryID = UUID()
        if let kind { resultKind = kind }
        resultWarning = nil
        resultNotice = nil
        finalImage = result
        image = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
        imageSize = "\(result.width) × \(result.height) px"
        cropRect = CGRect(x: 0, y: 0, width: result.width, height: result.height)
        croppedImage = result; cropEditing = true; cropScale = .width
    }
    func presentResultEditor(pinned: Bool = false, region: CaptureRegion? = nil, warning: String? = nil) {
        guard let croppedImage, let resultID else { return }
        mainWindow?.orderOut(nil)
        PinnedScreenshotManager.shared.show(croppedImage, region: region, pinned: pinned, warning: warning,
                                            historyID: cropHistoryID ?? resultID, kind: resultKind, history: history) { [weak self] in
            self?.dismissResult(resultID)
        }
    }
    func openHistory(_ entry: ScreenshotHistoryEntry) {
        guard !busy else { return }
        do {
            let document = try history.load(entry.id)
            // Once a raw export becomes editable, later workbench exports are a new snapshot.
            if workbenchHistoryID == entry.id { workbenchHistoryID = UUID() }
            mainWindow?.orderOut(nil)
            PinnedScreenshotManager.shared.showDocument(document, historyID: entry.id, kind: entry.kind, history: history, editingHistory: true)
        } catch { errorText = error.localizedDescription }
    }
    func showHistory() { guard !busy else { return }; history.reload(); showingHistory = true; showMain() }
    func deleteHistory(_ entry: ScreenshotHistoryEntry) {
        do { try history.delete(entry.id); PinnedScreenshotManager.shared.closeHistory([entry.id]) }
        catch { errorText = error.localizedDescription }
    }
    func deleteAllHistory() {
        let before = Set(history.entries.map(\.id))
        do { try history.deleteAll() } catch { errorText = error.localizedDescription }
        PinnedScreenshotManager.shared.closeHistory(before.subtracting(history.entries.map(\.id)))
    }
    func copyHistory(_ entry: ScreenshotHistoryEntry) {
        do {
            let document = try history.load(entry.id)
            guard let image = document.rendered(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CaptureError.message("无法生成截图。") }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setData(png, forType: .png) else { throw CaptureError.message("无法复制截图。") }
            status = "历史截图已复制。"
        } catch { errorText = error.localizedDescription }
    }
    func exportHistory(_ entry: ScreenshotHistoryEntry) {
        do {
            guard let image = try history.load(entry.id).rendered() else { throw CaptureError.message("无法生成截图。") }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "ScrollCap-\(entry.kind.title).png"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try Stitcher.png(image, to: destination)
        } catch { errorText = error.localizedDescription }
    }
    private func archiveCurrentResult(_ image: CGImage) {
        guard let workbenchHistoryID else { return }
        do { _ = try history.save(document: ScreenshotDocument(image), kind: resultKind, id: workbenchHistoryID) }
        catch { errorText = "图片已导出，但保存历史失败：\(error.localizedDescription)" }
    }
    func dismissResult(_ id: UUID) {
        // An older floating image may be closed while a later capture is in progress.
        guard resultID == id, !busy else { return }
        resetResult()
        status = "截图已关闭。按截图快捷键可开始新的框选。"
    }
    private func resetResult() {
        resultID = nil; cropHistoryID = nil; workbenchHistoryID = nil; resultRegion = nil
        image = nil; finalImage = nil; croppedImage = nil; cropRect = .zero; imageSize = ""
        resultWarning = nil; resultNotice = nil; errorText = nil
        cropEditing = true; cropScale = .width
        cover = nil; selection = nil
        videoURL = nil; frameDirectory = nil; hasVideo = false; hasFrames = false
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil; count = 0; elapsed = 0; progress = 0
    }
    func updateCrop(_ rect: CGRect) {
        guard !busy, let finalImage else { return }
        let bounded = CropGeometry.bounded(rect, in: CGSize(width: finalImage.width, height: finalImage.height))
        guard bounded != cropRect, let cropped = CropGeometry.cropped(finalImage, to: bounded) else { return }
        cropRect = bounded; croppedImage = cropped
        cropHistoryID = UUID()
        workbenchHistoryID = UUID()
    }
    func resetCrop() {
        guard let finalImage else { return }
        updateCrop(CGRect(x: 0, y: 0, width: finalImage.width, height: finalImage.height))
        cropEditing = true
    }
    func loadPreview(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let result = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        setResultImage(result); status = "预览图片已载入，可拖动四边或四角裁剪。"
    }

    func monitorPermissions() {
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }
    func refreshPermissions() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { status = "演示权限状态已检查。"; return }
#endif
        guard !busy, !refreshingPermissions, NSApplication.shared.isActive else { return }
        refreshingPermissions = true
        Task {
            if let fresh = try? await automation.permissions() {
                if screenGranted != fresh.screen { screenGranted = fresh.screen }
                if accessGranted != fresh.automation { accessGranted = fresh.automation }
            }
            refreshingPermissions = false
        }
    }
    func requestScreen() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { screenGranted = true; status = "演示：屏幕录制已开启。"; return }
#endif
        CGRequestScreenCaptureAccess(); refreshPermissions()
        if !screenGranted { openSetting("Privacy_ScreenCapture") }
    }
    func requestAccess() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { accessGranted = true; status = "演示：辅助功能已开启。"; return }
#endif
        _ = CGRequestPostEventAccess()
        openSetting("Privacy_Accessibility")
        refreshPermissions()
    }
    func openSetting(_ pane: String) {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { status = "设计预览使用演示权限，不会修改系统设置。"; return }
#endif
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func openSettings() { settingsAction?() }
    func startSingle() { guard !busy else { return }; captureKind = .single; start() }
    func startScrolling() { guard !busy else { return }; captureKind = .scrolling; start() }
    func pinCurrent() {
        guard !busy, croppedImage != nil else { return }
        presentResultEditor(pinned: true)
        status = "截图已置顶。拖动图片移动，滚轮缩放，右键标注，Esc 关闭。"
    }
    func start() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { DesignPreview.start(model: self); return }
#endif
        guard !busy else { return }
        showingHistory = false
        resetResult()
        dismissingCapture = false; resultRegion = nil
        preparing = true
        status = "正在检查截图权限…"
        task = Task {
            do {
                let fresh = try await automation.permissions()
                try Task.checkCancellation()
                guard applyStartPermissions(fresh) else { showMain(); return }
                sessionAutomatic = requiresAutomation; sessionPace = autoPace
                sessionUpward = upward; sessionHighQuality = highQuality; sessionLimit = maximumSeconds
                beginSelection()
            } catch is CancellationError { preparing = false; status = "已取消框选。" }
            catch { preparing = false; errorText = "权限状态读取失败：\(error.localizedDescription)" }
        }
    }
    @discardableResult
    func applyStartPermissions(_ fresh: CapturePermissions) -> Bool {
        screenGranted = fresh.screen; accessGranted = fresh.automation
        permissionIssue = fresh.missingRequirement(automatic: requiresAutomation)
        if let issue = permissionIssue {
            preparing = false; status = issue.title
            return false
        }
        return true
    }
    private func beginSelection() {
        mainWindow?.orderOut(nil)
        hideAuxiliaryWindows?()
        regionPicker = RegionPicker()
        let kind = captureKind
        regionPicker?.begin(kind: kind) { [weak self] region in
            guard let self else { return }
            self.regionPicker = nil
            guard let region else { self.preparing = false; self.status = "已取消框选。"; return }
            self.resultRegion = region
            self.task = Task {
                do {
                    if let pid = region.targetPID { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
                    try await Task.sleep(nanoseconds: 400_000_000)
                    let photo = try await self.snapshot(region, forVideo: kind == .scrolling)
                    try Task.checkCancellation()
                    if kind == .single {
                        try self.newSession()
                        self.resultKind = .single
                        self.setResultImage(photo)
                        self.preparing = false
                        self.status = "截图停留在原位置。拖动移动，滚轮缩放，右键标注，Esc 关闭。"
                        self.presentResultEditor(pinned: self.preferences.autoPinSingle, region: region)
                        return
                    }
                    self.chromePicker = ChromePicker()
                    self.chromePicker?.begin(image: photo) { [weak self] selected in
                        guard let self else { return }
                        self.chromePicker = nil
                        guard let selected else { self.preparing = false; return }
                        self.task = Task { await self.record(region, photo: photo, selected: selected) }
                    }
                } catch is CancellationError { self.preparing = false; self.status = "已取消框选。" }
                catch { self.errorText = error.localizedDescription; self.preparing = false; self.showMain() }
            }
        }
    }
    private func snapshot(_ region: CaptureRegion, forVideo: Bool = true) async throws -> CGImage {
        let content = try await ShareableScreen.content(for: region.displayID)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else { throw CaptureError.message("显示器已断开") }
        let apps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let config = SCStreamConfiguration(); config.sourceRect = region.sourceRect
        let width = max(1, Int((region.rect.width * region.scale).rounded()))
        let height = max(1, Int((region.rect.height * region.scale).rounded()))
        config.width = forVideo ? width / 2 * 2 : width
        config.height = forVideo ? height / 2 * 2 : height
        config.showsCursor = false; config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    private func newSession() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollCapVideo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder; frameDirectory = nil; videoURL = nil; hasVideo = false; hasFrames = false
        image = nil; finalImage = nil; imageSize = ""; count = 0; elapsed = 0; progress = 0; cancel = CancelFlag()
        croppedImage = nil; cropRect = .zero
        resultWarning = nil
        resultNotice = nil
    }
    private func record(_ region: CaptureRegion, photo: CGImage, selected: ChromeSelection) async {
        resultKind = .scrolling
        preparing = false; capturing = true; stopRequested = false
        cover = photo; selection = selected
        sessionScale = region.scale
        var recorder: VideoRecorder?
        var finishReason = ""
        var movement = AutoScrollProgress()
        var firstScroll = true
        do {
            try newSession()
            let url = directory!.appendingPathComponent("滚动原视频.mov")
            let capture = VideoRecorder(url: url); recorder = capture
            showHUD(region); installEscape()
            if let pid = region.targetPID { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
            try await Task.sleep(nanoseconds: 400_000_000)
            try await capture.start(region: region, highQuality: sessionHighQuality)
            let began = Date()
            // Hold the initial viewport before the first scroll so a sharp beginning is recorded.
            autoStatus = sessionAutomatic ? "准备自动滚动，请勿移动鼠标" : "每次滚动 1/4～1/3 屏，停半秒"
            await waitDuringCapture(1.0)
            while !stopRequested {
                elapsed = Int(Date().timeIntervalSince(began)); count = capture.frameCount
                if let failure = capture.recordingError { throw failure }
                if elapsed >= sessionLimit { finishReason = "达到录制时间上限。"; break }
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if bytes > 2_000_000_000 { finishReason = "原视频达到 2 GB 上限。"; break }
                if let pid = region.targetPID, let front = NSWorkspace.shared.frontmostApplication,
                   front.processIdentifier != pid && front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    finishReason = "切换了应用，已结束采集。"; break
                }
                status = "连续采集中 · \(elapsed) 秒 · \(count) 帧 · \(sessionAutomatic ? "自动滚动中" : "请缓慢滚动正文")"
                if sessionAutomatic {
                    guard let pid = region.targetPID else { finishReason = "未能识别目标窗口，请重新框选。"; break }
                    guard let before = try await snapshot(region).cropping(to: selected.body) else { throw AutoScrollStop.invalid }
                    autoStatus = "自动小步滚动中，移动鼠标可停止"
                    let center = CGPoint(x: region.rect.midX, y: region.rect.minY + selected.body.midY / region.scale)
                    do {
                        try await automation.scroll(ScrollStep(pid: pid, center: center,
                            points: sessionPace.points(bodyHeight: selected.body.height, scale: region.scale), upward: sessionUpward,
                            first: firstScroll, windowID: region.targetWindowID, windowBounds: region.targetWindowBounds))
                    } catch let reason as AutoScrollStop { finishReason = reason.localizedDescription; break }
                    firstScroll = false
                    autoStatus = "等待画面停稳…"
                    await waitDuringCapture(sessionPace.pause)
                    if stopRequested { break }
                    guard let after = try await snapshot(region).cropping(to: selected.body) else { throw AutoScrollStop.invalid }
                    let maximumStep = max(16, sessionPace.points(bodyHeight: selected.body.height, scale: region.scale) * Int(ceil(region.scale)) * 2)
                    var observation = movement.observe(before, after, upward: sessionUpward, maximumShift: maximumStep)
                    if observation == .unstable {
                        autoStatus = "等待加载完成…"
                        await waitDuringCapture(1.0)
                        if stopRequested { break }
                        if let settled = try await snapshot(region).cropping(to: selected.body) {
                            observation = movement.observe(before, settled, upward: sessionUpward, maximumShift: maximumStep)
                        }
                        if observation == .unstable { finishReason = "画面变化较大，已停止自动滚动，请检查长图或保存原视频。"; break }
                    }
                    if observation == .finished {
                        finishReason = movement.hasMoved ? (sessionUpward ? "已到达顶部。" : "已到达底部。")
                            : "未检测到滚动：可能已在边界，或正文没有接收到滚轮。请检查滚动区域。"
                        break
                    }
                    if observation == .unchanged { autoStatus = "正在确认是否到底…（\(movement.unchanged)/3）" }
                }
                await sleep(0.2)
            }
            await sleep(0.4)
            let recorded = try await capture.finish(); recorder = nil
            videoURL = recorded; hasVideo = true
        } catch {
            if let recorder, let recorded = try? await recorder.finish() { videoURL = recorded; hasVideo = true }
            finishReason = "采集中断：\(error.localizedDescription)"
            if !hasVideo { errorText = finishReason }
        }
        automation.cancel(); capturing = false; closeHUD()
        if dismissingCapture { preparing = false; status = "已退出截图。"; mainWindow?.orderOut(nil); return }
        if hasVideo { await processCurrent(prefix: finishReason) }
        else { preparing = false; status = finishReason; showMain() }
    }
    func importVideo() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { DesignPreview.start(model: self, importing: true); return }
#endif
        guard !busy else { return }
        resetResult()
        dismissingCapture = false; resultRegion = nil
        captureKind = .scrolling
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsMultipleSelection = false
        panel.message = "选择已录制的窗口视频（不超过 5 分钟），随后标记固定顶部、正文和固定底部。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preparing = true
        task = Task {
            do {
                let photo = try await VideoEngine.firstImage(url)
                try Task.checkCancellation()
                chromePicker = ChromePicker()
                chromePicker?.begin(image: photo) { [weak self] selected in
                    guard let self else { return }; self.chromePicker = nil
                    guard let selected else { self.preparing = false; return }
                    do {
                        try self.newSession(); self.cover = photo; self.selection = selected; self.videoURL = url; self.hasVideo = true
                        self.resultKind = .scrolling
                        self.sessionUpward = self.upward
                        self.sessionAutomatic = false
                        self.task = Task { await self.processCurrent(prefix: "") }
                    } catch { self.preparing = false; self.errorText = error.localizedDescription }
                }
            } catch is CancellationError { preparing = false; status = "已取消视频导入。" }
            catch { preparing = false; errorText = error.localizedDescription }
        }
    }
    private func processCurrent(prefix: String) async {
        guard let videoURL, let directory, let selection else { return }
        processing = true; preparing = false; progress = 0; status = "正在分析滚动内容…"; showMain(); installEscape()
        let output = directory.appendingPathComponent("关键帧", isDirectory: true)
        frameDirectory = output
        let upward = sessionUpward, cover = self.cover, cancel = self.cancel
        let motionLimit = sessionAutomatic ? Double(sessionScale) * 1200 : nil
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await VideoEngine.process(url: videoURL, crop: selection.body, upward: upward, directory: output, cancel: cancel,
                    progress: { [weak self] value, text in Task { @MainActor in self?.progress = value; self?.status = text } },
                    fixedCover: cover, includeFixed: selection.includeFixed, maximumPixelsPerSecond: motionLimit)
            }.value
            try cancel.check()
            if dismissingCapture { throw CancellationError() }
            setResultImage(result.image)
            resultWarning = result.report.warning
            resultNotice = result.report.cropAdjustment
            count = result.report.keyFrames.count
            let hasFixed = result.report.fixedTopHeight + result.report.fixedBottomHeight > 0
            status = result.report.warning ?? "\(prefix)已合成长图：\(count) 个清晰关键帧\(hasFixed ? "，固定部分各保留一次。" : "。")"
            if !dismissingCapture {
                mainWindow?.orderOut(nil)
                presentResultEditor(region: resultRegion, warning: result.report.warning)
            }
        } catch is CancellationError { status = "已取消处理，仍可保存原视频。" }
        catch { status = "拼接未完成：\(error.localizedDescription)"; errorText = status }
        hasFrames = ((try? FileManager.default.contentsOfDirectory(atPath: output.path).count) ?? 0) > 0
        processing = false; preparing = false; task = nil
        closeHUD()
    }
    func stop() {
#if DESIGN_PREVIEW
        if DesignPreview.isActive { DesignPreview.stop(model: self); return }
#endif
        if capturing { stopRequested = true; automation.cancel(); status = "正在结束采集，随后生成长图…" }
        else if processing { cancel.cancel(); status = "正在取消处理…" }
        else if preparing {
            task?.cancel(); regionPicker?.cancel(); chromePicker?.cancel()
            regionPicker = nil; chromePicker = nil; preparing = false
            status = "已取消框选。"
        }
    }
    func dismissCapture() {
        dismissingCapture = true
        mainWindow?.orderOut(nil); hideAuxiliaryWindows?()
        stop()
    }
    private func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func waitDuringCapture(_ seconds: Double) async {
        let until = Date().addingTimeInterval(seconds)
        while !stopRequested && Date() < until { await sleep(min(0.1, max(0, until.timeIntervalSinceNow))) }
    }
    private func installEscape() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in if event.keyCode == 53 { self?.dismissCapture(); return nil }; return event }
    }
    private func closeHUD() {
        hud?.orderOut(nil); hud = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
    private func showHUD(_ region: CaptureRegion) {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "长截图进行中"; panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CaptureHUD(model: self))
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == region.displayID }) {
            let f = screen.visibleFrame
            let selected = CGRect(x: screen.frame.minX + region.rect.minX - region.displayBounds.minX,
                                  y: screen.frame.maxY - region.rect.maxY + region.displayBounds.minY, width: region.rect.width, height: region.rect.height)
            let positions = [CGRect(x: f.minX + 16, y: f.maxY - 132, width: 360, height: 116), CGRect(x: f.maxX - 376, y: f.maxY - 132, width: 360, height: 116),
                             CGRect(x: f.minX + 16, y: f.minY + 16, width: 360, height: 116), CGRect(x: f.maxX - 376, y: f.minY + 16, width: 360, height: 116)]
            let rect = positions.first { !$0.intersects(selected) } ?? positions.first { !$0.contains(CGPoint(x: selected.midX, y: selected.midY)) } ?? positions[0]
            panel.setFrameTopLeftPoint(CGPoint(x: rect.minX, y: rect.maxY))
        }
        panel.orderFrontRegardless(); hud = panel
    }
    func showMain() {
        if capturing { hud?.orderFrontRegardless(); return }
        mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func save() {
        guard !busy, let finalImage = croppedImage else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "\(resultKind == .single ? "截图" : "长截图")-\(timestamp()).png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Stitcher.png(finalImage, to: url); archiveCurrentResult(finalImage); status = "已保存\(resultKind.title)（\(outputSize)）。"; NSWorkspace.shared.activateFileViewerSelecting([url]) }
            catch { errorText = error.localizedDescription }
        }
    }
    func copy() {
        guard !busy, let finalImage = croppedImage else { return }
        let rep = NSBitmapImageRep(cgImage: finalImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let item = NSPasteboardItem(); item.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: finalImage, size: .zero).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { errorText = "无法复制截图。"; return }
        archiveCurrentResult(finalImage); status = "\(resultKind.title)已复制。"
    }
    func saveVideo() {
        guard !busy, let source = videoURL else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: source.pathExtension) ?? .movie]
        panel.nameFieldStringValue = "滚动原视频-\(timestamp()).\(source.pathExtension)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if destination.standardizedFileURL == source.standardizedFileURL { return }
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".ScrollCap-\(UUID().uuidString).\(source.pathExtension)")
        do {
            try FileManager.default.copyItem(at: source, to: temp)
            if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp) }
            else { try FileManager.default.moveItem(at: temp, to: destination) }
            status = "已保存原视频。"; NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { try? FileManager.default.removeItem(at: temp); errorText = error.localizedDescription }
    }
    func exportFrames() {
        guard !busy, let frameDirectory else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "保存到此文件夹"
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let out = base.appendingPathComponent("关键帧与接缝-\(timestamp())-\(UUID().uuidString.prefix(4))", isDirectory: true)
        do { try FileManager.default.copyItem(at: frameDirectory, to: out); NSWorkspace.shared.activateFileViewerSelecting([out]) }
        catch { errorText = error.localizedDescription }
    }
    private func timestamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }
#if DESIGN_PREVIEW
    func resetDesignState() {
        capturing = false; processing = false; preparing = false
        resetResult()
        image = nil; finalImage = nil; croppedImage = nil; cropRect = .zero; imageSize = ""
        resultWarning = nil; resultNotice = nil; errorText = nil; permissionIssue = nil
        hasVideo = false; hasFrames = false; elapsed = 0; count = 0; progress = 0
        cropEditing = true; cropScale = .width
        status = "框选网页或聊天窗口，固定部分只保留一次。"
    }
#endif
    func cleanUp() { stopRequested = true; automation.cancel(); cancel.cancel(); permissionTimer?.invalidate(); if let directory { try? FileManager.default.removeItem(at: directory) } }
}
