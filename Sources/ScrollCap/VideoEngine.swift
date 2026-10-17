import AppKit
import AVFoundation
import CoreImage
import Vision

struct VideoKey: Codable {
    let file: String
    let seconds: Double
    let position: Int
    let sharpness: Double
}
struct VideoReport: Codable {
    var version = 4
    var engine = "original-resolution pixel alignment + Apple Vision OCR + verified original-frame seams"
    var direction: String
    var sourceDuration: Double
    var analyzedFrames: Int
    var keyFrames: [VideoKey]
    var seamRows: [Int]
    var recognizedTextRegions: Int
    var width: Int
    var height: Int
    var warning: String?
    var fixedTopHeight: Int = 0
    var fixedBottomHeight: Int = 0
    var scrollingCrop: CGRect? = nil
    var verifiedThrough: Double? = nil
    var cropAdjustment: String? = nil
    var maximumPixelsPerSecond: Double? = nil
}
struct VideoResult {
    let image: CGImage
    let report: VideoReport
    let directory: URL
}

struct VideoFrame {
    let image: CGImage
    let fine: SampleFrame
    let seconds: Double
    let sharpness: Double
    init?(_ image: CGImage, seconds: Double) {
        guard let fine = SampleFrame(image) else { return nil }
        self.image = image; self.fine = fine; self.seconds = seconds
        var sum = 0.0, count = 0
        for y in stride(from: 2, to: fine.height - 2, by: max(1, fine.height / 250)) {
            for x in stride(from: 8, to: 86, by: 2) {
                sum += Double(abs(Int(fine.pixels[y * 96 + x]) - Int(fine.pixels[(y - 1) * 96 + x])))
                count += 1
            }
        }
        sharpness = sum / Double(max(1, count))
    }
}

enum VideoVision {
    static func resize(_ image: CGImage, maxHeight: Int) -> CGImage? {
        let h = min(image.height, maxHeight), w = max(1, Int(Double(image.width) * Double(h) / Double(image.height)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.makeImage()
    }
    static func difference(_ a: SampleFrame, _ b: SampleFrame) -> Double {
        guard a.height == b.height else { return .infinity }
        var error = 0.0, count = 0
        for y in stride(from: 0, to: a.height, by: max(1, a.height / 160)) {
            for x in stride(from: 6, to: 88, by: 2) { error += Double(abs(Int(a.pixels[y * 96 + x]) - Int(b.pixels[y * 96 + x]))); count += 1 }
        }
        return error / Double(max(1, count))
    }
    static func shiftScore(_ a: SampleFrame, _ b: SampleFrame, shift: Int, upward: Bool) -> Double {
        let h = a.height, overlap = h - shift
        guard b.height == h, shift >= 0, overlap > h / 5 else { return .infinity }
        var rowErrors: [Double] = []
        for row in stride(from: 4, to: overlap - 4, by: max(1, overlap / 150)) {
            let py = upward ? row : row + shift, cy = upward ? row + shift : row
            // A heading aligned with whitespace is evidence against a match.
            // Ignoring either low-texture side lets repeated separators win.
            if a.texture[py] < 20 && b.texture[cy] < 20 { continue }
            var e = 0.0
            for x in stride(from: 6, to: 88, by: 2) { e += Double(abs(Int(a.pixels[py * 96 + x]) - Int(b.pixels[cy * 96 + x]))) }
            rowErrors.append(e / 41)
        }
        guard rowErrors.count >= 6 else { return .infinity }
        // Sparse layouts may put all distinguishing text in the worst 20% of
        // rows. Those rows must not be discarded as outliers.
        return rowErrors.reduce(0, +) / Double(rowErrors.count)
    }
    static func refine(_ a: SampleFrame, _ b: SampleFrame, expected: Int, radius: Int, upward: Bool) -> Int? {
        let low = max(0, expected - radius), high = min(a.height * 78 / 100, expected + radius)
        guard low <= high else { return nil }
        var best = (shift: 0, score: Double.infinity)
        for shift in low...high {
            let score = shiftScore(a, b, shift: shift, upward: upward)
            if score < best.score { best = (shift, score) }
        }
        return best.score < 7.5 ? best.shift : nil
    }
    static func alignment(_ a: VideoFrame, _ b: VideoFrame, upward: Bool, maximumShift: Int? = nil) -> MatchResult {
        if difference(a.fine, b.fine) < 0.45 { return .unchanged }
        // Reduced-height matching can choose another copy of a separator and
        // then trap local refinement around that wrong displacement. Search all
        // original-resolution displacements before accepting any local match.
        let match = Stitcher.match(a.fine, b.fine, upward: upward, maximumShift: maximumShift)
        if case .shifted(let shift) = match {
            if let exact = refine(a.fine, b.fine, expected: shift, radius: 2, upward: upward) {
                return exact > 0 ? .shifted(exact) : .unchanged
            }
        }
        if case .unchanged = match, let tiny = refine(a.fine, b.fine, expected: 2, radius: 6, upward: upward) {
            return tiny > 0 ? .shifted(tiny) : .unchanged
        }
        return .uncertain("视频画面缺少可靠重叠，或滚动方向发生变化")
    }
    static func textBoxes(_ image: CGImage) throws -> [CGRect] {
        let h = min(image.height, max(480, Int(Double(image.height) * min(1.0, 1600.0 / Double(image.width)))))
        let input = resize(image, maxHeight: h) ?? image
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])
        return (request.results ?? []).map { observation in
            let r = observation.boundingBox
            return CGRect(x: r.minX * CGFloat(image.width), y: (1 - r.maxY) * CGFloat(image.height),
                          width: r.width * CGFloat(image.width), height: r.height * CGFloat(image.height))
        }
    }
    static func chooseSeam(previous: SampleFrame, current: SampleFrame, previousStart: Int, currentStart: Int,
                           textPrevious: [CGRect], textCurrent: [CGRect], minimum: Int) throws -> Int {
        let low = max(currentStart + 8, minimum), high = previousStart + previous.height - 8
        guard low <= high else { throw CaptureError.message("关键帧之间没有足够重叠，无法选择自然接缝") }
        let center = (low + high) / 2
        var best = center, bestCost = Double.infinity
        let previousText = textPrevious.map { (Int($0.minY) + previousStart - 4)...(Int($0.maxY) + previousStart + 4) }
        let currentText = textCurrent.map { (Int($0.minY) + currentStart - 4)...(Int($0.maxY) + currentStart + 4) }
        for global in low...high {
            let py = global - previousStart, cy = global - currentStart
            var diff = 0.0, edge = 0.0
            for x in stride(from: 6, to: 88, by: 2) {
                let p = previous.pixels[py * 96 + x], c = current.pixels[cy * 96 + x]
                diff += Double(abs(Int(p) - Int(c)))
                edge += Double(abs(Int(previous.pixels[(py - 1) * 96 + x]) - Int(p)))
                edge += Double(abs(Int(current.pixels[(cy - 1) * 96 + x]) - Int(c)))
            }
            let textPenalty = previousText.contains(where: { $0.contains(global) }) || currentText.contains(where: { $0.contains(global) }) ? 1000.0 : 0.0
            let cost = diff / 41 * 3 + edge / 82 + (previous.texture[py] + current.texture[cy]) * 0.08
                + Double(abs(global - center)) / Double(previous.height) * 6 + textPenalty
            if cost < bestCost { bestCost = cost; best = global }
        }
        return best
    }
}

enum VideoEngine {
    static func firstImage(_ url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: .zero)
        return result.image
    }
    static func resolveFixedCrop(asset: AVAsset, duration: Double, crop: CGRect, cover: CGImage, cancel: CancelFlag) async throws -> (CGRect, String?) {
        guard crop.minX == 0, Int(crop.width) == cover.width else { return (crop, nil) }
        let top = CGRect(x: 0, y: 0, width: CGFloat(cover.width), height: crop.minY)
        let bottom = CGRect(x: 0, y: crop.maxY, width: CGFloat(cover.width), height: CGFloat(cover.height) - crop.maxY)
        guard top.height > 0 || bottom.height > 0 else { return (crop, nil) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        func changed(_ image: CGImage, rect: CGRect) -> Bool {
            guard rect.height > 0, let a = cover.cropping(to: rect), let b = image.cropping(to: rect),
                  let before = SampleFrame(a), let after = SampleFrame(b) else { return false }
            // Ignore a blinking caret or small spinner in a genuinely fixed bar.
            return AutoScrollProgress.stillDifference(before, after) > 3.0
        }
        var topChanges = 0, bottomChanges = 0
        for fraction in [0.3, 0.6, 0.9] {
            try cancel.check()
            guard let sample = try? await generator.image(at: CMTime(seconds: duration * fraction, preferredTimescale: 600)),
                  sample.image.width == cover.width, sample.image.height == cover.height else { continue }
            if changed(sample.image, rect: top) { topChanges += 1 }
            if changed(sample.image, rect: bottom) { bottomChanges += 1 }
        }
        guard topChanges >= 2 || bottomChanges >= 2 else { return (crop, nil) }
        let start = topChanges >= 2 ? 0 : crop.minY
        let end = bottomChanges >= 2 ? CGFloat(cover.height) : crop.maxY
        let parts = topChanges >= 2 && bottomChanges >= 2 ? "顶部和底部" : (topChanges >= 2 ? "顶部" : "底部")
        return (CGRect(x: 0, y: start, width: crop.width, height: end - start), "检测到标记的\(parts)也在滚动，已自动纳入正文，避免首尾重复。")
    }
    static func process(url: URL, crop: CGRect?, upward: Bool, directory: URL, cancel: CancelFlag,
                        progress: @Sendable (Double, String) -> Void, fixedCover: CGImage? = nil, includeFixed: Bool = false,
                        maximumPixelsPerSecond: Double? = nil) async throws -> VideoResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 305 else { throw CaptureError.message("请导入 5 分钟以内的视频，较长录制请先分段") }
        var crop = crop
        var cropAdjustment: String?
        if includeFixed, let selection = crop, let cover = fixedCover {
            progress(0.005, "检查固定区域是否随页面滚动…")
            (crop, cropAdjustment) = try await resolveFixedCrop(asset: asset, duration: duration, crop: selection, cover: cover, cancel: cancel)
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CaptureError.message("此文件没有视频画面") }
        let transform = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CaptureError.message("无法读取视频") }
        defer { reader.cancelReading() }
        let context = CIContext(options: [.cacheIntermediates: false])
        var keys: [VideoKey] = []
        var last: VideoFrame?
        var anchor: VideoFrame?
        var anchorTrack = 0
        var position = 0
        var pending: (frame: VideoFrame, position: Int)?
        var finalCandidate: (frame: VideoFrame, position: Int)?
        var frameCount = 0
        var lastGoodTime = 0.0
        var warning: String?
        var stoppedForGap = false
        var unresolvedSince: Double?
        func commit(_ frame: VideoFrame, trackPosition: Int) throws {
            try cancel.check()
            var keyPosition = 0
            if let anchor, let key = keys.last {
                let expected = trackPosition - anchorTrack
                guard expected > 0 else { return }
                guard let shift = VideoVision.refine(anchor.fine, frame.fine, expected: expected, radius: 48, upward: upward), shift > 0 else {
                    throw CaptureError.message("关键帧再次校准失败；请保存原视频后放慢滚动重试")
                }
                keyPosition = key.position + shift
            }
            guard frame.image.width * (keyPosition + frame.image.height) <= 40_000_000, keyPosition + frame.image.height <= 60_000 else {
                throw CaptureError.message("达到长图尺寸上限，请分段处理视频")
            }
            let file = String(format: "key-%03d.png", keys.count + 1)
            try Stitcher.png(frame.image, to: directory.appendingPathComponent(file))
            keys.append(VideoKey(file: file, seconds: frame.seconds, position: keyPosition, sharpness: frame.sharpness))
            anchor = frame; anchorTrack = trackPosition
            pending = nil
        }
        var nextSample = output.copyNextSampleBuffer()
        while let sample = nextSample {
            nextSample = output.copyNextSampleBuffer()
            try cancel.check()
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            // Every encoded frame can bridge a quick manual scroll. Dropping intermediate
            // frames here can turn a fully covered recording into an apparent content gap.
            let frame: VideoFrame? = autoreleasepool {
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return nil }
                var ci = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
                ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
                guard let full = context.createCGImage(ci, from: ci.extent) else { return nil }
                let rect = crop ?? CGRect(x: 0, y: 0, width: full.width, height: full.height)
                guard let image = full.cropping(to: rect), image.width >= 160, image.height >= 140, image.width * image.height <= 8_000_000 else { return nil }
                return VideoFrame(image, seconds: seconds)
            }
            guard let frame else { throw CaptureError.message("视频选区无效或超过 800 万像素，请重新裁剪") }
            frameCount += 1
            if frameCount % 8 == 0 { progress(min(0.72, seconds / duration * 0.72), "分析视频 \(Int(seconds)) / \(Int(duration)) 秒 · 已选 \(keys.count) 个关键帧") }
            if let previous = last {
                // Automatic input runs at 300 logical points/sec. A conservative
                // bound rejects a separator beyond the controller's possible motion.
                let limit = maximumPixelsPerSecond.map { max(8, Int(ceil(max(0, seconds - previous.seconds) * $0)) + 8) }
                switch VideoVision.alignment(previous, frame, upward: upward, maximumShift: limit) {
                case .unchanged:
                    unresolvedSince = nil
                    last = frame
                    // A still, sharper ending frame is useful without accumulating false motion.
                    if let candidate = finalCandidate, candidate.position == position, frame.sharpness > candidate.frame.sharpness {
                        finalCandidate = (frame, position)
                    }
                    lastGoodTime = seconds
                case .shifted(let shift):
                    unresolvedSince = nil
                    // Keep a bridge before a large step; choosing only the sharpest older
                    // candidate can otherwise leave the next keyframe without overlap.
                    if position > anchorTrack && position + shift - anchorTrack > frame.image.height * 65 / 100 {
                        do { try commit(previous, trackPosition: position) }
                        catch { warning = error.localizedDescription; stoppedForGap = true; break }
                    }
                    position += shift; last = frame; lastGoodTime = seconds
                    finalCandidate = (frame, position)
                    let distance = position - anchorTrack
                    if distance >= frame.image.height / 4 {
                        if pending == nil || frame.sharpness > pending!.frame.sharpness * 1.02 { pending = (frame, position) }
                    }
                    if distance >= frame.image.height * 42 / 100, let candidate = pending {
                        do { try commit(candidate.frame, trackPosition: candidate.position) }
                        catch { warning = error.localizedDescription; stoppedForGap = true }
                    }
                case .uncertain:
                    if unresolvedSince == nil { unresolvedSince = seconds }
                    // Decode later frames to recover a transient overlay or a blurred intermediate frame.
                    if seconds - lastGoodTime > 1.6 {
                        warning = "在约 \(String(format: "%.1f", lastGoodTime)) 秒后失去可靠重叠。当前长图只包含此前可确认内容，原视频仍可保存。"
                        stoppedForGap = true
                    }
                }
            } else {
                try commit(frame, trackPosition: 0); last = frame; lastGoodTime = seconds; finalCandidate = (frame, 0)
            }
            if stoppedForGap { break }
        }
        if warning == nil, unresolvedSince != nil {
            warning = "视频末尾有未能对齐的画面，长图只包含此前可确认内容。原视频仍可保存。"
        }
        if reader.status == .failed { throw reader.error ?? CaptureError.message("视频解码中断") }
        if let candidate = finalCandidate, candidate.position > anchorTrack {
            do { try commit(candidate.frame, trackPosition: candidate.position) }
            catch { warning = error.localizedDescription }
        }
        guard !keys.isEmpty else { throw CaptureError.message("视频中没有可用画面") }
        let ordered = upward ? Array(keys.reversed()) : keys
        let lastPosition = keys.last!.position
        var dimensions: [(Int, Int)] = [], samples: [SampleFrame] = [], boxes: [[CGRect]] = [], positions: [Int] = []
        for (i, key) in ordered.enumerated() {
            try cancel.check()
            progress(0.74 + Double(i) / Double(ordered.count) * 0.18, "Vision 识别文字与接缝 \(i + 1) / \(ordered.count)")
            guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(key.file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let sampled = SampleFrame(image) else {
                throw CaptureError.message("关键帧文件读取失败")
            }
            dimensions.append((image.width, image.height)); samples.append(sampled)
            do { boxes.append(try VideoVision.textBoxes(image)) }
            catch { throw CaptureError.message("本机 Vision 文字识别失败：\(error.localizedDescription)。原视频仍可保存。") }
            positions.append(upward ? lastPosition - key.position : key.position)
        }
        var seams: [Int] = []
        if dimensions.count > 1 {
            for i in 1..<dimensions.count {
                try cancel.check()
                let seam = try VideoVision.chooseSeam(previous: samples[i - 1], current: samples[i], previousStart: positions[i - 1], currentStart: positions[i],
                    textPrevious: boxes[i - 1], textCurrent: boxes[i], minimum: (seams.last ?? 0) + 1)
                seams.append(seam)
            }
        }
        progress(0.95, "用原视频像素生成长图…")
        var pieces: [CGImage] = []
        for i in 0..<dimensions.count {
            try cancel.check()
            let start = i == 0 ? 0 : seams[i - 1] - positions[i]
            let end = i == dimensions.count - 1 ? dimensions[i].1 : seams[i] - positions[i]
            guard start >= 0, end > start, end <= dimensions[i].1 else {
                throw CaptureError.message("接缝覆盖检查失败，请保存视频并重新处理")
            }
            let owned: CGImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(ordered[i].file) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let piece = image.cropping(to: CGRect(x: 0, y: start, width: image.width, height: end - start)),
                      let ctx = CGContext(data: nil, width: piece.width, height: piece.height, bitsPerComponent: 8, bytesPerRow: piece.width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.draw(piece, in: CGRect(x: 0, y: 0, width: piece.width, height: piece.height))
                return ctx.makeImage()
            }
            guard let owned else { throw CaptureError.message("无法读取或裁剪关键帧") }
            pieces.append(owned)
        }
        try cancel.check()
        var result = try Stitcher.assemble(pieces, maximumPixels: 40_000_000)
        if includeFixed, let cover = fixedCover, let crop {
            guard crop.minX == 0, Int(crop.width) == cover.width, result.width == cover.width else {
                throw CaptureError.message("固定区域与正文宽度不一致，请重新标记滚动区域")
            }
            var framed: [CGImage] = []
            if crop.minY > 0, let header = cover.cropping(to: CGRect(x: 0, y: 0, width: cover.width, height: Int(crop.minY))) { framed.append(header) }
            framed.append(result)
            if Int(crop.maxY) < cover.height, let footer = cover.cropping(to: CGRect(x: 0, y: Int(crop.maxY), width: cover.width, height: cover.height - Int(crop.maxY))) { framed.append(footer) }
            result = try Stitcher.assemble(framed, maximumPixels: 40_000_000)
            seams = seams.map { $0 + Int(crop.minY) }
        }
        var report = VideoReport(direction: upward ? "up" : "down", sourceDuration: duration, analyzedFrames: frameCount, keyFrames: keys, seamRows: seams,
                                 recognizedTextRegions: boxes.reduce(0) { $0 + $1.count }, width: result.width, height: result.height, warning: warning)
        report.scrollingCrop = crop
        report.verifiedThrough = lastGoodTime
        report.cropAdjustment = cropAdjustment
        report.maximumPixelsPerSecond = maximumPixelsPerSecond
        if includeFixed, let cover = fixedCover, let crop {
            report.fixedTopHeight = Int(crop.minY)
            report.fixedBottomHeight = cover.height - Int(crop.maxY)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("分析报告.json"))
        progress(1, warning == nil ? "视频已合成为长图。" : "已生成可确认部分，请查看提示。")
        return VideoResult(image: result, report: report, directory: directory)
    }
}
