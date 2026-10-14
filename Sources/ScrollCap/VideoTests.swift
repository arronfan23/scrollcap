import AppKit
import AVFoundation
import CoreImage
import CoreText

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

func writeFixtureMovie(_ url: URL, upward: Bool, gap: Bool = false) async throws -> CGImage {
    let document = textDocument(width: 640, height: 3000)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: 640, AVVideoHeightKey: 720])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 720, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CaptureError.message("Fixture writer start failed") }
    writer.startSession(atSourceTime: .zero)
    let count = gap ? 48 : 67
    for i in 0..<count {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        let delta = min(1080, max(0, i - 6) * 18)
        let offset = gap ? (i < 20 ? min(200, i * 10) : 1800) : (upward ? 1080 - delta : delta)
        let image = windowFrame(document: document, offset: offset)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixel = buffer!; CVPixelBufferLockBaseAddress(pixel, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 640, height: 720, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 720))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 20)) else { throw writer.error ?? CaptureError.message("Fixture append failed") }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CaptureError.message("Fixture finish failed") }
    return windowFrame(document: document, offset: upward ? 1080 : 0)
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
