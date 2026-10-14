import AppKit
import SwiftUI
import ScreenCaptureKit
import ApplicationServices
import UniformTypeIdentifiers

@MainActor
final class CaptureModel: ObservableObject {
    @Published var automatic = false
    @Published var upward = false
    @Published var highQuality = true
    @Published var maximumSeconds = 120
    @Published var capturing = false
    @Published var processing = false
    @Published var preparing = false
    @Published var status = "框选整个聊天窗口，固定标题和输入框也可以一起截进来。"
    @Published var errorText: String?
    @Published var image: NSImage?
    @Published var imageSize = ""
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
    private var escapeMonitor: Any?
    private var localMonitor: Any?
    private var task: Task<Void, Never>?
    private var cancel = CancelFlag()
    private var stopRequested = false
    private var sessionAutomatic = false
    private var sessionUpward = false
    private var sessionHighQuality = true
    private var sessionLimit = 120
    private var videoURL: URL?
    private var directory: URL?
    private var frameDirectory: URL?
    private var finalImage: CGImage?
    private var cover: CGImage?
    private var selection: ChromeSelection?
    private var permissionTimer: Timer?

    func monitorPermissions() {
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }
    func refreshPermissions() { screenGranted = CGPreflightScreenCaptureAccess(); accessGranted = CGPreflightPostEventAccess() }
    func requestScreen() {
        CGRequestScreenCaptureAccess(); refreshPermissions()
        if !screenGranted { openSetting("Privacy_ScreenCapture") }
    }
    func requestAccess() {
        _ = CGRequestPostEventAccess(); refreshPermissions()
        if !accessGranted { openSetting("Privacy_Accessibility") }
    }
    func openSetting(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func start() {
        guard !busy else { return }
        refreshPermissions()
        guard screenGranted else { requestScreen(); status = "请允许当前版本录制屏幕，再回到应用开始。若更新后开关已开但不生效，请移除旧授权记录后重新添加。"; return }
        guard !automatic || accessGranted else { requestAccess(); status = "自动滚动需要辅助功能权限；也可直接使用手动滚动。"; return }
        sessionAutomatic = automatic; sessionUpward = upward; sessionHighQuality = highQuality; sessionLimit = maximumSeconds
        preparing = true; mainWindow?.orderOut(nil)
        regionPicker = RegionPicker()
        regionPicker?.begin { [weak self] region in
            guard let self else { return }
            self.regionPicker = nil
            guard let region else { self.preparing = false; self.showMain(); return }
            self.task = Task {
                do {
                    if let pid = region.targetPID { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
                    try await Task.sleep(nanoseconds: 400_000_000)
                    let photo = try await self.snapshot(region)
                    self.chromePicker = ChromePicker()
                    self.chromePicker?.begin(image: photo) { [weak self] selected in
                        guard let self else { return }
                        self.chromePicker = nil
                        guard let selected else { self.preparing = false; self.showMain(); return }
                        self.task = Task { await self.record(region, photo: photo, selected: selected) }
                    }
                } catch { self.errorText = error.localizedDescription; self.preparing = false; self.showMain() }
            }
        }
    }
    private func snapshot(_ region: CaptureRegion) async throws -> CGImage {
        let content = try await ShareableScreen.content(for: region.displayID)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else { throw CaptureError.message("显示器已断开") }
        let apps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let config = SCStreamConfiguration(); config.sourceRect = region.sourceRect
        config.width = Int(region.rect.width * region.scale) / 2 * 2; config.height = Int(region.rect.height * region.scale) / 2 * 2
        config.showsCursor = false; config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    private func newSession() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollCapVideo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder; frameDirectory = nil; videoURL = nil; hasVideo = false; hasFrames = false
        image = nil; finalImage = nil; imageSize = ""; count = 0; elapsed = 0; progress = 0; cancel = CancelFlag()
    }
    private func record(_ region: CaptureRegion, photo: CGImage, selected: ChromeSelection) async {
        preparing = false; capturing = true; stopRequested = false
        cover = photo; selection = selected
        var recorder: VideoRecorder?
        var finishReason = ""
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
            await sleep(0.65)
            var lastSample: SampleFrame?
            var idle = 0
            var nextScroll = Date()
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
                status = "连续采集中 · \(elapsed) 秒 · \(count) 帧 · \(sessionAutomatic ? "自动滚动" : "请缓慢滚动正文")"
                if sessionAutomatic && Date() >= nextScroll {
                    let shot = try await snapshot(region)
                    if let body = shot.cropping(to: selected.body), let small = VideoVision.resize(body, maxHeight: 320), let sample = SampleFrame(small) {
                        if let lastSample, VideoVision.difference(lastSample, sample) < 0.9 { idle += 1 } else { idle = 0 }
                        lastSample = sample
                    }
                    if idle >= 3 { finishReason = "画面连续三次未移动，已结束采集。"; break }
                    await scroll(region, body: selected.body)
                    nextScroll = Date().addingTimeInterval(0.8)
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
        capturing = false; closeHUD()
        if hasVideo { await processCurrent(prefix: finishReason) }
        else { preparing = false; status = finishReason; showMain() }
    }
    private func scroll(_ region: CaptureRegion, body: CGRect) async {
        let center = CGPoint(x: region.rect.midX, y: region.rect.minY + body.midY / region.scale)
        CGWarpMouseCursorPosition(center)
        let source = CGEventSource(stateID: .hidSystemState)
        var remaining = Int(body.height / region.scale * 0.30)
        while remaining > 0 && !stopRequested {
            let pulse = min(10, remaining)
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                wheel1: Int32(sessionUpward ? pulse : -pulse), wheel2: 0, wheel3: 0)
            event?.location = center; event?.post(tap: .cghidEventTap)
            remaining -= pulse; await sleep(0.018)
        }
    }
    func importVideo() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsMultipleSelection = false
        panel.message = "选择已录制的窗口视频（不超过 5 分钟），随后标记固定顶部、正文和固定底部。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preparing = true
        task = Task {
            do {
                let photo = try await VideoEngine.firstImage(url)
                chromePicker = ChromePicker()
                chromePicker?.begin(image: photo) { [weak self] selected in
                    guard let self else { return }; self.chromePicker = nil
                    guard let selected else { self.preparing = false; return }
                    do {
                        try self.newSession(); self.cover = photo; self.selection = selected; self.videoURL = url; self.hasVideo = true
                        self.sessionUpward = self.upward
                        self.task = Task { await self.processCurrent(prefix: "") }
                    } catch { self.preparing = false; self.errorText = error.localizedDescription }
                }
            } catch { preparing = false; errorText = error.localizedDescription }
        }
    }
    private func processCurrent(prefix: String) async {
        guard let videoURL, let directory, let selection else { return }
        processing = true; preparing = false; progress = 0; status = "正在分析滚动内容…"; showMain()
        let output = directory.appendingPathComponent("关键帧", isDirectory: true)
        frameDirectory = output
        let upward = sessionUpward, cover = self.cover, cancel = self.cancel
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await VideoEngine.process(url: videoURL, crop: selection.body, upward: upward, directory: output, cancel: cancel,
                    progress: { [weak self] value, text in Task { @MainActor in self?.progress = value; self?.status = text } },
                    fixedCover: cover, includeFixed: selection.includeFixed)
            }.value
            finalImage = result.image
            image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
            imageSize = "\(result.image.width) × \(result.image.height) px"
            count = result.report.keyFrames.count
            status = result.report.warning ?? "\(prefix)已合成长图：\(count) 个清晰关键帧\(selection.includeFixed ? "，固定部分各保留一次。" : "。")"
        } catch is CancellationError { status = "已取消处理，仍可保存原视频。" }
        catch { status = "拼接未完成：\(error.localizedDescription)"; errorText = status }
        hasFrames = ((try? FileManager.default.contentsOfDirectory(atPath: output.path).count) ?? 0) > 0
        processing = false; preparing = false; task = nil
    }
    func stop() {
        if capturing { stopRequested = true; status = "正在结束采集，随后生成长图…" }
        else if processing { cancel.cancel(); status = "正在取消处理…" }
    }
    private func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func installEscape() {
        if AXIsProcessTrusted() { escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in if event.keyCode == 53 { Task { @MainActor in self?.stop() } } } }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in if event.keyCode == 53 { self?.stop(); return nil }; return event }
    }
    private func closeHUD() {
        hud?.orderOut(nil); hud = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
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
        guard !busy, let finalImage else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "长截图-\(timestamp()).png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Stitcher.png(finalImage, to: url); status = "已保存长图。"; NSWorkspace.shared.activateFileViewerSelecting([url]) }
            catch { errorText = error.localizedDescription }
        }
    }
    func copy() {
        guard !busy, let finalImage else { return }
        let rep = NSBitmapImageRep(cgImage: finalImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let item = NSPasteboardItem(); item.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: finalImage, size: .zero).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([item]); status = "长图已复制。"
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
    func cleanUp() { stopRequested = true; cancel.cancel(); permissionTimer?.invalidate(); if let directory { try? FileManager.default.removeItem(at: directory) } }
}
