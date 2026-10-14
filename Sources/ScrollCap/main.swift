import AppKit
import ApplicationServices

if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--video-test") {
    Task {
        do { try await runVideoTests(at: URL(fileURLWithPath: CommandLine.arguments.last!)); exit(0) }
        catch { fputs("FAIL VIDEO: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}
if CommandLine.arguments.contains("--diagnostics") {
    print("Screen Recording: \(CGPreflightScreenCaptureAccess())")
    print("Post Event: \(CGPreflightPostEventAccess()); AX trusted: \(AXIsProcessTrusted())")
    print("Application: \(Bundle.main.bundleURL.path)")
    exit(0)
}
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
