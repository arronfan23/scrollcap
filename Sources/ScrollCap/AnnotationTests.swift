import AppKit
import ImageIO

@MainActor
func runAnnotationTests() throws {
    var count = 0
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(description: message) }
        count += 1; print("PASS \(message)")
    }
    let context = ScreenshotRenderer.context(width: 240, height: 160)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
    for x in stride(from: 0, to: 240, by: 2) {
        context.setFillColor((x % 4 == 0 ? NSColor.black : NSColor.white).cgColor)
        context.fill(CGRect(x: x, y: 60, width: 2, height: 40))
    }
    let source = context.makeImage()!
    func bytes(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }
    func changedPixels(_ a: CGImage, _ b: CGImage) -> Int {
        let aa = [UInt8](bytes(a)), bb = [UInt8](bytes(b)); return zip(aa, bb).filter { $0 != $1 }.count
    }
    let sourceBytes = bytes(source)
    let doc = ScreenshotDocument(source)
    try require(bytes(doc.rendered()!) == sourceBytes && !doc.canUndo && !doc.canRedo, "fresh editor preserves original pixels without history")
    let pen = ScreenshotMark(tool: .pen, points: [CGPoint(x: 15, y: 25), CGPoint(x: 220, y: 25)], color: .red, width: 8)
    doc.append(pen)
    let drawn = doc.rendered()!
    try require(drawn.width == source.width && drawn.height == source.height && changedPixels(source, drawn) > 1000, "pen renders onto original-size pixels")
    try require(bytes(source) == sourceBytes, "annotation never mutates source image")
    doc.undo(); try require(bytes(doc.rendered()!) == sourceBytes && doc.canRedo, "undo returns exact original pixels")
    doc.redo(); try require(bytes(doc.rendered()!) == bytes(drawn), "redo restores exact annotated pixels")
    doc.undo(); doc.append(ScreenshotMark(tool: .ellipse, points: [CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 55)], color: .blue, width: 6))
    try require(!doc.canRedo && doc.marks.count == 1, "new drawing after undo discards obsolete redo branch")
    let arrow = ScreenshotMark(tool: .arrow, points: [CGPoint(x: 10, y: 20), CGPoint(x: 120, y: 130)], color: .green, width: 5)
    let translated = arrow.translated(CGPoint(x: 10, y: -10))
    try require(translated.points == [CGPoint(x: 20, y: 10), CGPoint(x: 130, y: 120)] && translated.id == arrow.id, "dragging an arrow moves both endpoints while preserving identity")
    try require(arrow.hit(CGPoint(x: 65, y: 75), tolerance: 3) && !arrow.hit(CGPoint(x: 210, y: 20), tolerance: 3), "arrow hit testing selects line without claiming distant image content")
    let shapes = [ScreenshotMark(tool: .rectangle, points: [CGPoint(x: 50, y: 10), CGPoint(x: 180, y: 145)], color: .blue, width: 4), arrow]
    try require(changedPixels(source, ScreenshotRenderer.render(source, marks: shapes)!) > 500, "rectangle and directional arrow are flattened into output")
    let text = ScreenshotMark(tool: .text, points: [CGPoint(x: 20, y: 110)], color: .red, text: "ScrollCap 中文", fontSize: 22)
    try require(text.bounds.width > 80 && text.bounds.height > 10 && changedPixels(source, ScreenshotRenderer.render(source, marks: [text])!) > 100, "Unicode text has selectable geometry and is rendered into PNG pixels")
    let mosaic = ScreenshotMark(tool: .mosaic, points: [CGPoint(x: 40, y: 80), CGPoint(x: 200, y: 80)], width: 32)
    let blurred = ScreenshotRenderer.render(source, marks: [mosaic])!
    try require(changedPixels(source, blurred) > 1000, "mosaic brush replaces detailed source pixels")
    let raw = [UInt8](bytes(blurred)), originalRaw = [UInt8](sourceBytes)
    try require((0..<30).allSatisfy { y in (0..<blurred.bytesPerRow).allSatisfy { raw[y * blurred.bytesPerRow + $0] == originalRaw[y * source.bytesPerRow + $0] } }, "mosaic does not alter untouched image rows")
    try require(stride(from: 3, to: raw.count, by: 4).allSatisfy { raw[$0] == 255 }, "mosaic output is opaque and does not reveal source through alpha")
    let singleDot = ScreenshotRenderer.render(source, marks: [ScreenshotMark(tool: .mosaic, points: [CGPoint(x: 120, y: 80)], width: 32)])!
    try require(changedPixels(source, singleDot) > 100, "click-only mosaic brush produces a visible mask")
    let point = ScreenshotGeometry.endpoint(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 60, y: 80), square: true)
    try require(point == CGPoint(x: 60, y: 60), "Shift constrains shapes in negative drag directions")
    let frame = CGRect(x: 100, y: 200, width: 640, height: 480), anchor = CGPoint(x: 300, y: 400)
    let enlarged = ScreenshotGeometry.zoomed(frame, factor: 1.5, anchor: anchor)
    try require(enlarged.width / enlarged.height == frame.width / frame.height && (anchor.x - enlarged.minX) / enlarged.width == (anchor.x - frame.minX) / frame.width, "wheel zoom preserves aspect ratio and cursor anchor")
    try require(ScreenshotGeometry.maximumZoom(imageWidth: 2000, initialWidth: 35) * 35 >= 2000, "very long fitted screenshots can zoom to readable native pixel size")
    let location = ScreenshotGeometry.cocoaRect(quartz: CGRect(x: -1200, y: -200, width: 400, height: 300), displayBounds: CGRect(x: -1440, y: -400, width: 1440, height: 900), screenFrame: CGRect(x: -1440, y: 456, width: 1440, height: 900))
    try require(location == CGRect(x: -1200, y: 856, width: 400, height: 300), "capture origin converts correctly on offset secondary displays")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("scrollcap-annotation-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Stitcher.png(blurred, to: url)
    let encoded = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(encoded, 0, nil)!
    try require(CGImageSourceGetCount(encoded) == 1 && decoded.width == 240 && decoded.height == 160, "saved annotated PNG contains one flattened full-resolution image")
    try require(changedPixels(source, decoded) > 1000, "PNG export retains the mosaic instead of restoring original content")
    print("\(count) annotation and floating-editor checks passed")
}
