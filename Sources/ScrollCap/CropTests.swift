import AppKit
import ImageIO

@MainActor
func runCropTests() throws {
    var passes = 0
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(description: message) }
        passes += 1; print("PASS \(message)")
    }
    let size = CGSize(width: 640, height: 2400)
    let full = CGRect(origin: .zero, size: size)
    let original = CGRect(x: 80, y: 200, width: 400, height: 1600)
    let expected: [(CropHandle, CGRect)] = [
        (.left, CGRect(x: 100, y: 200, width: 380, height: 1600)),
        (.right, CGRect(x: 80, y: 200, width: 420, height: 1600)),
        (.top, CGRect(x: 80, y: 230, width: 400, height: 1570)),
        (.bottom, CGRect(x: 80, y: 200, width: 400, height: 1630)),
        (.topLeft, CGRect(x: 100, y: 230, width: 380, height: 1570)),
        (.topRight, CGRect(x: 80, y: 230, width: 420, height: 1570)),
        (.bottomLeft, CGRect(x: 100, y: 200, width: 380, height: 1630)),
        (.bottomRight, CGRect(x: 80, y: 200, width: 420, height: 1630))
    ]
    for (handle, rect) in expected {
        try require(CropGeometry.dragged(original, handle: handle, delta: CGSize(width: 20, height: 30), in: size) == rect, "drag \(handle) preserves the opposite edges")
    }
    for handle in CropHandle.allCases {
        let rect = CropGeometry.dragged(original, handle: handle, delta: CGSize(width: 10000, height: -10000), in: size)
        try require(full.contains(rect) && rect.width >= 16 && rect.height >= 16, "\(handle) cannot invert or leave the image")
    }
    try require(CropGeometry.dragged(original, handle: .move, delta: CGSize(width: 10000, height: -10000), in: size) == CGRect(x: 240, y: 0, width: 400, height: 1600), "move clamps location and retains size")
    try require(CropGeometry.bounded(CGRect(x: 10.4, y: 20.8, width: 100.3, height: 200.5), in: size) == CGRect(x: 10, y: 21, width: 101, height: 200), "selection uses whole source pixels")
    try require(CropGeometry.bounded(.null, in: size) == full, "invalid selection restores full bounds")
    try require(CropGeometry.bounded(CGRect(x: 9999, y: 9999, width: 0, height: 0), in: size) == CGRect(x: 639, y: 2399, width: 1, height: 1), "out of range selection still yields a valid pixel")

    let width = 64, height = 96
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        bytes[i] = UInt8(x * 3); bytes[i + 1] = UInt8(y * 2); bytes[i + 2] = UInt8((x + y) % 256)
    } }
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    func pixels(_ image: CGImage) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return rgba
    }
    let rect = CGRect(x: 7, y: 13, width: 29, height: 41)
    let cropped = CropGeometry.cropped(image, to: rect)!
    var expectedPixels = [UInt8]()
    let allPixels = pixels(image)
    for y in 13..<54 {
        expectedPixels.append(contentsOf: allPixels[(y * width + 7) * 4..<(y * width + 36) * 4])
    }
    try require(cropped.width == 29 && cropped.height == 41, "crop exports exact source dimensions")
    try require(pixels(cropped) == expectedPixels, "crop retains original pixels with top-left coordinates")
    try require(CropGeometry.cropped(image, to: CGRect(x: 0, y: 0, width: width, height: height)) === image, "full selection retains original image")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollCap-crop-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Stitcher.png(cropped, to: url)
    let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    try require(pixels(decoded) == expectedPixels && decoded.width == 29 && decoded.height == 41, "saved PNG contains only the crop, without scaling")

    let model = CaptureModel()
    model.setResultImage(image); model.updateCrop(rect)
    try require(model.isCropped && model.outputSize == "29 × 41 px" && pixels(model.croppedImage!) == expectedPixels, "model exports the current selection")
    try require(model.previewImage === image, "editing keeps the original image available")
    model.cropEditing = false
    try require(model.previewImage === model.croppedImage && model.previewSelection == CGRect(x: 0, y: 0, width: 29, height: 41), "finish shows only cropped content")
    model.cropEditing = true
    try require(model.previewImage === image && model.cropRect == rect, "reopening crop preserves the selection")
    model.resetCrop()
    try require(!model.isCropped && model.croppedImage === image && model.cropEditing, "reset restores all original pixels")
    model.updateCrop(rect); model.setResultImage(fixture(width: 128, height: 256))
    try require(!model.isCropped && model.outputSize == "128 × 256 px", "next capture clears the previous crop")
    print("\(passes) crop checks passed")
}
