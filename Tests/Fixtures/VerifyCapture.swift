import AppKit
import Vision

do {
    let args = CommandLine.arguments
    guard args.count == 5, let expectedWidth = Int(args[2]), let expectedHeight = Int(args[3]),
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey:"Usage: verify-capture image.png width height receipt.json"]) }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US", "zh-Hans"]; request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let text = lines.joined(separator: "\n").uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "–", with: "-")
    let expression = try NSRegularExpression(pattern: "SCAP-([0-9]{2})")
    // Vision downsamples very tall images. Check each known 80-point fixture row
    // at original resolution, rather than treating a missed OCR line as a lost row.
    var ids: [Int] = [], rowLines: [[String]] = []
    let scale = CGFloat(expectedWidth) / 640
    for row in 0..<24 {
        let rect = CGRect(x: 0, y: (60 + CGFloat(row) * 80) * scale, width: 200 * scale, height: 80 * scale)
        guard let strip = image.cropping(to: rect) else { rowLines.append([]); continue }
        let rowRequest = VNRecognizeTextRequest()
        rowRequest.recognitionLevel = .accurate; rowRequest.recognitionLanguages = ["en-US"]; rowRequest.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: strip, options: [:]).perform([rowRequest])
        let strings = (rowRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        rowLines.append(strings)
        let rowText = strings.joined(separator: "\n").uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "–", with: "-")
        ids += expression.matches(in: rowText, range: NSRange(rowText.startIndex..., in: rowText)).compactMap { match -> Int? in
            guard let range = Range(match.range(at: 1), in: rowText) else { return nil }; return Int(rowText[range])
        }
    }
    let header = text.components(separatedBy: "HEADER-ONCE").count - 1
    let footer = text.components(separatedBy: "FOOTER-ONCE").count - 1
    let checks: [String: Bool] = ["dimensions": image.width == expectedWidth && abs(image.height - expectedHeight) <= 2,
                                "allMessagesInOrder": ids == Array(1...24), "headerOnce": header == 1, "footerOnce": footer == 1]
    let receipt: [String: Any] = ["width":image.width,"height":image.height,"messageIDs":ids,"headerCount":header,"footerCount":footer,"checks":checks,"recognizedLines":lines,"originalResolutionRows":rowLines]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath:args[4]))
    for key in checks.keys.sorted() { print("\(checks[key]! ? "PASS" : "FAIL") \(key)") }
    print("IMAGE \(image.width)x\(image.height); messages=\(ids); header=\(header); footer=\(footer)")
    exit(checks.values.allSatisfy { $0 } ? 0 : 1)
} catch { fputs("\(error)\n",stderr); exit(1) }
