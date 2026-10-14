import AppKit
import CoreText

struct TestFailure: Error, CustomStringConvertible { let description: String }

func fixture(width: Int = 640, height: Int = 2400, repeated: Bool = false, seed: Int = 1) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        let row = repeated ? y % 100 : y
        for x in 0..<width {
            let i = (y * width + x) * 4
            let value: UInt8
            if x < 35 || x > width - 35 || row % 32 < 9 { value = 248 }
            else {
                var hash = UInt64(row) &* 0x9E3779B185EBCA87 ^ UInt64(x / 9) &* 0xC2B2AE3D27D4EB4F ^ UInt64(seed) &* 0x165667B19E3779F9
                hash = (hash ^ (hash >> 30)) &* 0xBF58476D1CE4E5B9
                hash = (hash ^ (hash >> 27)) &* 0x94D049BB133111EB
                hash ^= hash >> 31
                value = hash % 7 < 3 ? UInt8(30 + hash % 80) : 248
            }
            bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func runSelfTests() throws {
    var passes = 0
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(description: message) }; passes += 1; print("PASS \(message)")
    }
    let doc = fixture()
    let a = doc.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 800))!
    let b = doc.cropping(to: CGRect(x: 0, y: 326, width: 640, height: 800))!
    let sa = SampleFrame(a)!, sb = SampleFrame(b)!
    try require(Stitcher.match(sa, sb, upward: false) == .shifted(326), "downward overlap 326 px")
    try require(Stitcher.match(sb, sa, upward: true) == .shifted(326), "upward overlap 326 px")
    try require(Stitcher.match(sa, sa, upward: false) == .unchanged, "unchanged viewport / end detection")
    for delta in [1, 87, 319, 520, 620] {
        let frame = doc.cropping(to: CGRect(x: 0, y: delta, width: 640, height: 800))!
        try require(Stitcher.match(sa, SampleFrame(frame)!, upward: false) == .shifted(delta), "manual variable scroll \(delta) px")
    }
    let strip = b.cropping(to: CGRect(x: 0, y: 800 - 326, width: 640, height: 326))!
    let joined = try Stitcher.assemble([a, strip])
    let expected = doc.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 1126))!
    try require(joined.width == 640 && joined.height == 1126, "export dimensions")
    try require(SampleFrame(joined)!.pixels == SampleFrame(expected)!.pixels, "downward stitch retains exact content and order")
    let top = a.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 326))!
    let upJoined = try Stitcher.assemble([top, b])
    try require(SampleFrame(upJoined)!.pixels == SampleFrame(expected)!.pixels, "upward stitch retains exact content and order")
    let unrelated = fixture(seed: 998).cropping(to: CGRect(x: 0, y: 0, width: 640, height: 800))!
    if case .uncertain = Stitcher.match(sa, SampleFrame(unrelated)!, upward: false) { passes += 1; print("PASS changed content rejected") }
    else { throw TestFailure(description: "unrelated viewport accepted") }
    let repeated = fixture(repeated: true)
    let ra = SampleFrame(repeated.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 800))!)!
    let rb = SampleFrame(repeated.cropping(to: CGRect(x: 0, y: 43, width: 640, height: 800))!)!
    if case .uncertain = Stitcher.match(ra, rb, upward: false) { passes += 1; print("PASS ambiguous repeated content rejected") }
    else { throw TestFailure(description: "repeated pattern accepted") }
    do { _ = try Stitcher.assemble([a], maximumPixels: 100); throw TestFailure(description: "pixel limit not enforced") }
    catch is CaptureError { passes += 1; print("PASS image allocation limit") }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollCap-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try Stitcher.png(joined, to: tmp)
    let source = CGImageSourceCreateWithURL(tmp as CFURL, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    try require(decoded.width == 640 && decoded.height == 1126, "PNG roundtrip")
    print("\(passes) checks passed")
}
