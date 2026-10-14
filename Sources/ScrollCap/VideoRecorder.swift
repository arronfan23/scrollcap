import AppKit
import AVFoundation
import ScreenCaptureKit

enum ShareableScreen {
    static func content(for displayID: CGDirectDisplayID) async throws -> SCShareableContent {
        for attempt in 0..<3 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if content.displays.contains(where: { $0.displayID == displayID }) { return content }
            if attempt < 2 { try await Task.sleep(nanoseconds: 250_000_000) }
        }
        throw CaptureError.message("无法采集所选显示器，请确认当前版本的屏幕录制权限；授权后重新打开应用再试")
    }
}

final class VideoRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ScrollCap.video.writer")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var stream: SCStream?
    private var firstTime: CMTime?
    private var lastTime: CMTime?
    private var frames = 0
    private var failure: Error?
    private var closing = false
    let url: URL
    init(url: URL) { self.url = url }
    var frameCount: Int { queue.sync { frames } }
    var recordingError: Error? { queue.sync { failure } }

    func start(region: CaptureRegion, highQuality: Bool) async throws {
        let content = try await ShareableScreen.content(for: region.displayID)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureError.message("所选显示器已断开")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        config.width = max(2, Int(region.rect.width * region.scale) / 2 * 2)
        config.height = max(2, Int(region.rect.height * region.scale) / 2 * 2)
        guard config.width * config.height <= 8_000_000 else { throw CaptureError.message("选区过大，请缩小到 800 万像素以内") }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .best
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [AVVideoCodecKey: highQuality ? AVVideoCodecType.proRes4444 : AVVideoCodecType.hevc,
                                      AVVideoWidthKey: config.width, AVVideoHeightKey: config.height]
        if !highQuality {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: max(8_000_000, min(80_000_000, config.width * config.height * 14)),
                                                         AVVideoExpectedSourceFrameRateKey: 20, AVVideoMaxKeyFrameIntervalKey: 20]
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw CaptureError.message("此 Mac 无法使用所选编码，请关闭高保真模式后重试")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.message("无法创建视频编码器") }
        writer.add(input)
        self.writer = writer; self.input = input
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !closing, failure == nil, CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil, let writer, let input else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           raw != SCFrameStatus.complete.rawValue && raw != SCFrameStatus.started.rawValue { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstTime == nil {
            guard writer.startWriting() else { failure = writer.error ?? CaptureError.message("无法开始写入视频"); return }
            writer.startSession(atSourceTime: time)
            firstTime = time
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) { frames += 1; lastTime = time }
        else { failure = writer.error ?? CaptureError.message("视频写入失败") }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.failure = error } }
    func finish() async throws -> URL {
        var stopFailure: Error?
        if let stream { do { try await stream.stopCapture() } catch { stopFailure = error } }
        self.stream = nil
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.closing = true
                guard let writer = self.writer, let input = self.input, self.firstTime != nil, self.frames > 0 else {
                    self.writer?.cancelWriting()
                    continuation.resume(throwing: self.failure ?? stopFailure ?? CaptureError.message("没有录到画面，请检查屏幕录制权限")); return
                }
                if let error = self.failure { writer.cancelWriting(); continuation.resume(throwing: error); return }
                if let last = self.lastTime { writer.endSession(atSourceTime: last + CMTime(value: 1, timescale: 20)) }
                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume(returning: self.url) }
                    else { continuation.resume(throwing: writer.error ?? CaptureError.message("视频封装失败")) }
                }
            }
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func check() throws { if cancelled { throw CancellationError() } }
}
