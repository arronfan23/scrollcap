import AppKit
import Foundation

struct SampleFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let texture: [Double]

    init?(_ image: CGImage) {
        let width = 96
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { data -> Bool in
            guard let context = CGContext(data: data.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var gray = [UInt8](repeating: 0, count: width * height)
        var detail = [Double](repeating: 0, count: height)
        for y in 0..<height {
            var minV = 255, maxV = 0
            for x in 0..<width {
                let p = (y * width + x) * 4
                let v = (Int(bytes[p]) * 77 + Int(bytes[p + 1]) * 150 + Int(bytes[p + 2]) * 29) >> 8
                gray[y * width + x] = UInt8(v)
                if x > 5 && x < width - 8 { minV = min(minV, v); maxV = max(maxV, v) }
            }
            detail[y] = Double(maxV - minV)
        }
        pixels = gray
        texture = detail
    }
}

enum MatchResult: Equatable {
    case unchanged
    case shifted(Int)
    case uncertain(String)
}

enum Stitcher {
    static func match(_ previous: SampleFrame, _ current: SampleFrame, upward: Bool, maximumShift: Int? = nil) -> MatchResult {
        guard previous.height == current.height else { return .uncertain("窗口尺寸发生变化") }
        let h = previous.height, w = previous.width
        guard h >= 100 else { return .uncertain("选区太矮，请框选更大的正文区域") }
        // Ignore the scrollbar and outermost margins. Sparse moving cursors do not dominate the score.
        var unchanged = 0.0, sameCount = 0
        for y in stride(from: 0, to: h, by: max(1, h / 150)) {
            for x in stride(from: 6, to: w - 8, by: 2) {
                unchanged += Double(abs(Int(previous.pixels[y * w + x]) - Int(current.pixels[y * w + x])))
                sameCount += 1
            }
        }
        if unchanged / Double(sameCount) < 0.85 { return .unchanged }
        let maxShift = min(h * 78 / 100, max(1, maximumShift ?? h))
        func score(_ shift: Int) -> Double {
            let overlap = h - shift
            var error = 0.0, rows = 0
            let step = max(1, overlap / 100)
            for y in stride(from: 3, to: overlap - 3, by: step) {
                let py = upward ? y : y + shift
                let cy = upward ? y + shift : y
                if previous.texture[py] < 22 && current.texture[cy] < 22 { continue }
                var rowError = 0.0
                for x in stride(from: 6, to: w - 8, by: 2) {
                    rowError += Double(abs(Int(previous.pixels[py * w + x]) - Int(current.pixels[cy * w + x])))
                }
                error += rowError / 41.0
                rows += 1
            }
            return rows >= 6 ? error / Double(rows) : .infinity
        }
        var candidates: [(Int, Double)] = []
        for shift in 1...maxShift { candidates.append((shift, score(shift))) }
        candidates.sort { $0.1 < $1.1 }
        guard let coarse = candidates.first, coarse.1.isFinite else {
            return .uncertain("重叠区域缺少可识别内容，请缩小滚动步幅或换一个选区")
        }
        var best = coarse
        for shift in max(1, coarse.0 - 2)...min(maxShift, coarse.0 + 2) {
            let s = score(shift)
            if s < best.1 { best = (shift, s) }
        }
        guard best.1 < 8.0 else { return .uncertain("画面无法对齐，可能滚动过快或正文仍在加载") }
        // Repeated paragraphs and repeated chat bubbles can produce multiple equally good seams.
        if let other = candidates.first(where: { abs($0.0 - best.0) > 8 }), other.1 < best.1 + 0.65 {
            return .uncertain("出现重复内容，无法可靠判断接缝")
        }
        return .shifted(best.0)
    }

    static func assemble(_ pieces: [CGImage], maximumPixels: Int = 100_000_000) throws -> CGImage {
        guard let first = pieces.first else { throw CaptureError.message("还没有截图") }
        let height = pieces.reduce(0) { $0 + $1.height }
        guard pieces.allSatisfy({ $0.width == first.width }), height > 0,
              height <= 60_000, first.width * height <= maximumPixels else {
            throw CaptureError.message("图片已达到尺寸上限，请分段保存")
        }
        guard let ctx = CGContext(data: nil, width: first.width, height: height,
            bitsPerComponent: 8, bytesPerRow: first.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.message("内存不足，无法生成长图")
        }
        var top = 0
        for piece in pieces {
            ctx.draw(piece, in: CGRect(x: 0, y: height - top - piece.height, width: piece.width, height: piece.height))
            top += piece.height
        }
        guard let result = ctx.makeImage() else { throw CaptureError.message("生成图片失败") }
        return result
    }

    static func png(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CaptureError.message("无法写入图片文件")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.message("保存失败，请检查磁盘空间和文件夹权限") }
    }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
