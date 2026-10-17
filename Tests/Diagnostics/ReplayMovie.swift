import AppKit

// Local-only reproduction of an existing session, with its original crop.
// This tool reads saved files and never captures or posts input events.
@main
struct ReplayMovie {
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 4 || (args.count == 5 && args[4] == "--automatic") else { throw CaptureError.message("Usage: replay-video original-report.json video.mov output-directory [--automatic]") }
            let report = try JSONDecoder().decode(VideoReport.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            let video = URL(fileURLWithPath: args[2]), directory = URL(fileURLWithPath: args[3], isDirectory: true)
            let cover = try await VideoEngine.firstImage(video)
            let result = try await VideoEngine.process(url: video, crop: report.scrollingCrop, upward: report.direction == "up",
                directory: directory, cancel: CancelFlag(), progress: { value, message in
                    if Int(value * 100) % 10 == 0 { print(message) }
                }, fixedCover: cover, includeFixed: report.fixedTopHeight + report.fixedBottomHeight > 0,
                maximumPixelsPerSecond: args.count == 5 ? 2400 : report.maximumPixelsPerSecond)
            try Stitcher.png(result.image, to: directory.appendingPathComponent("result.png"))
            print("RESULT \(result.image.width)x\(result.image.height); keys=\(result.report.keyFrames.count); warning=\(result.report.warning ?? "none")")
        } catch { fputs("REPLAY FAILED: \(error)\n", stderr); exit(1) }
    }
}
