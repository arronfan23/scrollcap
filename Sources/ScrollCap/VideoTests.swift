import AppKit
import AVFoundation
import CoreImage
import CoreText

// Large repeated separators and sparse headings used to match only a few
// agreeing rows, turning a 24-pixel scroll into a false 600-pixel jump.
func posterDocument(width: Int = 1380, height: Int = 3600) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for i in 0..<6 {
        let top = CGFloat(i * 602 + 200)
        ctx.setFillColor(CGColor(gray: 0.75, alpha: 1)); ctx.fill(CGRect(x: 57, y: CGFloat(height) - top - 3, width: CGFloat(width - 114), height: 3))
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.beginPath(); ctx.move(to: CGPoint(x: width / 2, y: Int(CGFloat(height) - top + 24)))
        ctx.addLine(to: CGPoint(x: width / 2 + 24, y: Int(CGFloat(height) - top)))
        ctx.addLine(to: CGPoint(x: width / 2, y: Int(CGFloat(height) - top - 24)))
        ctx.addLine(to: CGPoint(x: width / 2 - 24, y: Int(CGFloat(height) - top)))
        ctx.closePath(); ctx.fillPath()
        let title = ["交付内容包含", "高频场景实测", "本机验证结果", "完整教程说明", "不同标题内容", "滚动截图末尾"][i]
        for (text, size, y) in [(title, 72.0, top + 140), ("第 \(i + 1) 节 · 本地处理与截图校验", 38.0, top + 210)] {
            let font = CTFontCreateWithName("PingFangSC-Medium" as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key:font,kCTForegroundColorAttributeName as NSAttributedString.Key:NSColor.black.cgColor]))
            ctx.textPosition = CGPoint(x: (CGFloat(width) - CGFloat(CTLineGetTypographicBounds(line,nil,nil,nil))) / 2, y: CGFloat(height) - y)
            CTLineDraw(line,ctx)
        }
        ctx.setFillColor(NSColor.systemPurple.cgColor)
        for j in 0..<3 { ctx.fill(CGRect(x: 80 + j * 430, y: Int(CGFloat(height) - top - 430), width: 360, height: 132)) }
    }
    return ctx.makeImage()!
}

func textDocument(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for i in 0..<(height / 70) {
        let y = height - i * 70 - 12
        ctx.setFillColor(NSColor(calibratedHue: CGFloat((i * 37) % 100) / 100, saturation: 0.5, brightness: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 22, y: y - 11, width: 100 + (i * 43) % (width - 140), height: 11))
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 17, nil)
        let text = "第 \(i + 1) 条消息 · 测试编号 \(i * 17 + 5) · " + String(repeating: "内容 ", count: 2 + i % 5)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.darkGray.cgColor]))
        ctx.textPosition = CGPoint(x: 22, y: y - 38); CTLineDraw(line, ctx)
    }
    return ctx.makeImage()!
}
func windowFrame(document: CGImage, offset: Int, bodyHeight: Int = 540, header: Int = 80, footer: Int = 100) -> CGImage {
    let width = document.width, height = bodyHeight + header + footer
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.94, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: height - header, width: width, height: header))
    ctx.setFillColor(NSColor(calibratedWhite: 0.94, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: footer))
    let font = CTFontCreateWithName("PingFangSC-Medium" as CFString, 22, nil)
    for (text, y) in [("固定对话框标题 · 只出现一次", height - 48), ("固定输入框 · 请输入消息", 43)] {
        ctx.textPosition = CGPoint(x: 26, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.darkGray.cgColor])), ctx)
    }
    let body = document.cropping(to: CGRect(x: 0, y: offset, width: width, height: bodyHeight))!
    ctx.draw(body, in: CGRect(x: 0, y: footer, width: width, height: bodyHeight))
    return ctx.makeImage()!
}

func writeFixtureMovie(_ url: URL, upward: Bool, gap: Bool = false, offsets: [Int]? = nil,
                       document suppliedDocument: CGImage? = nil, bodyHeight: Int = 540, fixedChrome: Bool = true) async throws -> CGImage {
    let document = suppliedDocument ?? textDocument(width: 640, height: 3000)
    let width = document.width, height = bodyHeight + (fixedChrome ? 180 : 0)
    func frame(_ offset: Int) -> CGImage {
        fixedChrome ? windowFrame(document: document, offset: offset, bodyHeight: bodyHeight)
            : document.cropping(to: CGRect(x: 0, y: offset, width: width, height: height))!
    }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: width, AVVideoHeightKey: height])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CaptureError.message("Fixture writer start failed") }
    writer.startSession(atSourceTime: .zero)
    let count = offsets?.count ?? (gap ? 48 : 67)
    for i in 0..<count {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        let delta = min(1080, max(0, i - 6) * 18)
        let offset = offsets?[i] ?? (gap ? (i < 20 ? min(200, i * 10) : 1800) : (upward ? 1080 - delta : delta))
        let image = frame(offset)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixel = buffer!; CVPixelBufferLockBaseAddress(pixel, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 20)) else { throw writer.error ?? CaptureError.message("Fixture append failed") }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CaptureError.message("Fixture finish failed") }
    return frame(offsets?.first ?? (upward ? 1080 : 0))
}

func runVideoTests(at base: URL) async throws {
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    var checks = 0
    func require(_ condition: Bool, _ text: String) throws { guard condition else { throw TestFailure(description: text) }; print("PASS \(text)"); checks += 1 }
    let crop = CGRect(x: 0, y: 80, width: 640, height: 540)
    for up in [false, true] {
        let name = up ? "up" : "down"
        let url = base.appendingPathComponent("\(name).mov")
        try? FileManager.default.removeItem(at: url)
        let cover = try await writeFixtureMovie(url, upward: up)
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let result = try await VideoEngine.process(url: url, crop: crop, upward: up, directory: dir, cancel: CancelFlag(), progress: { _, _ in }, fixedCover: cover, includeFixed: true)
        print("RESULT \(name): \(result.image.width)x\(result.image.height), \(result.report.keyFrames.count) keys, warning=\(result.report.warning ?? "none")")
        try require(result.report.warning == nil, "\(name): complete video coverage")
        try require(abs(result.image.height - 1800) <= 2, "\(name): no duplicated or missing scroll rows")
        try require(result.image.width == 640, "\(name): full window width retained")
        try require(result.report.recognizedTextRegions > 0, "\(name): Vision OCR ran and found text")
        try require(result.report.keyFrames.count >= 4, "\(name): multiple sharp keyframes")
        let top = result.image.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 80))!
        let topExpected = cover.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 80))!
        try require(SampleFrame(top)!.pixels == SampleFrame(topExpected)!.pixels, "\(name): fixed title retained exactly once")
        let bottom = result.image.cropping(to: CGRect(x: 0, y: result.image.height - 100, width: 640, height: 100))!
        let bottomExpected = cover.cropping(to: CGRect(x: 0, y: 620, width: 640, height: 100))!
        try require(SampleFrame(bottom)!.pixels == SampleFrame(bottomExpected)!.pixels, "\(name): fixed input box retained exactly once")
        try require(zip(result.report.seamRows, result.report.seamRows.dropFirst()).allSatisfy { $0 < $1 }, "\(name): seams are ordered")
        try Stitcher.png(result.image, to: base.appendingPathComponent("\(name)-result.png"))
        let expectedDoc = textDocument(width: 640, height: 3000).cropping(to: CGRect(x: 0, y: 0, width: 640, height: 1620))!
        let actualBody = result.image.cropping(to: CGRect(x: 0, y: 80, width: 640, height: 1620))!
        try require(VideoVision.difference(SampleFrame(expectedDoc)!, SampleFrame(actualBody)!) < 3.5, "\(name): original text and reading order preserved")
    }
    // Each original frame overlaps, while sampling every 0.115 s loses the bridge.
    let fastOffsets = [0, 0, 0, 0, 120, 130, 380, 660, 790, 1030, 1260, 1510, 1800, 1800, 1800, 1800]
    for up in [false, true] {
        let name = up ? "fast-up" : "fast-down"
        let url = base.appendingPathComponent("\(name).mov")
        let cover = try await writeFixtureMovie(url, upward: up, offsets: up ? fastOffsets.map { 1800 - $0 } : fastOffsets)
        let result = try await VideoEngine.process(url: url, crop: crop, upward: up, directory: base.appendingPathComponent(name),
                                                   cancel: CancelFlag(), progress: { _, _ in }, fixedCover: cover, includeFixed: true)
        try require(result.report.warning == nil, "\(name): accelerated scrolling retains complete coverage")
        try require(abs(result.image.height - 2520) <= 2, "\(name): intermediate frames prevent missing content")
        let expected = textDocument(width: 640, height: 3000).cropping(to: CGRect(x: 0, y: 0, width: 640, height: 2340))!
        let body = result.image.cropping(to: CGRect(x: 0, y: 80, width: 640, height: 2340))!
        try require(VideoVision.difference(SampleFrame(expected)!, SampleFrame(body)!) < 3.5, "\(name): accelerated scroll preserves text pixels and order")
        try require((result.report.verifiedThrough ?? 0) >= 0.7, "\(name): verifies the end of the recording")
    }
    let poster = posterDocument()
    let posterA = VideoFrame(poster.cropping(to: CGRect(x: 0, y: 30, width: 1380, height: 868))!, seconds: 0)!
    let posterB = VideoFrame(poster.cropping(to: CGRect(x: 0, y: 54, width: 1380, height: 868))!, seconds: 1)!
    try require(VideoVision.alignment(posterA, posterB, upward: false) == .shifted(24), "sparse poster separators cannot turn 24 pixels into a 660-pixel jump")
    try require(VideoVision.alignment(posterB, posterA, upward: true) == .shifted(24), "sparse poster separators align in the upward direction")
    let posterOffsets = [0, 0] + (0...90).map { $0 * 24 } + [2160, 2160]
    for up in [false, true] {
        let name = up ? "poster-up" : "poster-down", url = base.appendingPathComponent(up ? "poster-up.mov" : "poster-down.mov")
        let cover = try await writeFixtureMovie(url, upward: up, offsets: up ? posterOffsets.map { 2160 - $0 } : posterOffsets,
                                               document: poster, bodyHeight: 868)
        let result = try await VideoEngine.process(url: url, crop: CGRect(x: 0, y: 80, width: 1380, height: 868), upward: up,
            directory: base.appendingPathComponent(name), cancel: CancelFlag(), progress: { _, _ in }, fixedCover: cover, includeFixed: true, maximumPixelsPerSecond: 2400)
        print("RESULT \(name): \(result.image.height), warning=\(result.report.warning ?? "none")")
        try require(result.report.warning == nil, "\(name): repeated separators retain full video coverage")
        try require(result.image.height == 3208, "\(name): no false cumulative scrolling distance")
        let expected = poster.cropping(to: CGRect(x: 0, y: 0, width: 1380, height: 3028))!
        let actual = result.image.cropping(to: CGRect(x: 0, y: 80, width: 1380, height: 3028))!
        try require(VideoVision.difference(SampleFrame(expected)!, SampleFrame(actual)!) < 3.5, "\(name): later poster sections preserve original pixels and order")
        try Stitcher.png(result.image, to: base.appendingPathComponent("\(name)-result.png"))
    }
    let movingBandsURL = base.appendingPathComponent("moving-bands.mov")
    let movingCover = try await writeFixtureMovie(movingBandsURL, upward: false, offsets: posterOffsets,
                                                  document: poster, bodyHeight: 1048, fixedChrome: false)
    let movingBands = try await VideoEngine.process(url: movingBandsURL, crop: CGRect(x: 0, y: 80, width: 1380, height: 868),
        upward: false, directory: base.appendingPathComponent("moving-bands"), cancel: CancelFlag(), progress: { _, _ in }, fixedCover: movingCover, includeFixed: true, maximumPixelsPerSecond: 2400)
    try require(movingBands.report.cropAdjustment != nil, "moving fixed-region markings produce a visible correction notice")
    // The first 80 pixels of this fixture are blank. A blank band can be fixed
    // without changing any output pixels; the moving footer must be expanded.
    try require(movingBands.report.fixedBottomHeight == 0 && Int(movingBands.report.scrollingCrop?.maxY ?? 0) == movingCover.height, "scrolling footer content is included in the moving page")
    try require(movingBands.report.warning == nil && movingBands.image.height == 3208, "corrected whole-page capture retains the full recording")
    let expectedPage = poster.cropping(to: CGRect(x: 0, y: 0, width: 1380, height: 3208))!
    try require(VideoVision.difference(SampleFrame(expectedPage)!, SampleFrame(movingBands.image)!) < 3.5, "corrected page preserves the actual first and last content without repeated footer")
    let source = base.appendingPathComponent("gap.mov")
    try? FileManager.default.removeItem(at: source)
    _ = try await writeFixtureMovie(source, upward: false, gap: true)
    let gap = try await VideoEngine.process(url: source, crop: crop, upward: false, directory: base.appendingPathComponent("gap"), cancel: CancelFlag(), progress: { _, _ in })
    try require(gap.report.warning != nil, "missing overlap produces an explicit partial-result warning")
    try require(gap.image.height < 1000, "missing content is not fabricated")
    let cancel = CancelFlag(); cancel.cancel()
    do {
        _ = try await VideoEngine.process(url: source, crop: crop, upward: false, directory: base.appendingPathComponent("cancel"), cancel: cancel, progress: { _, _ in })
        throw TestFailure(description: "cancellation not honored")
    } catch is CancellationError { checks += 1; print("PASS processing cancellation") }
    print("\(checks) video checks passed")
}
