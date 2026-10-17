import AppKit

if CommandLine.arguments.contains("--capture-permissions") {
    if let data = try? JSONEncoder().encode(CapturePermissions.current()) { FileHandle.standardOutput.write(data) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--scroll-step") {
    guard CommandLine.arguments.indices.contains(index + 1), let data = Data(base64Encoded: CommandLine.arguments[index + 1]),
          let step = try? JSONDecoder().decode(ScrollStep.self, from: data) else { print("invalid"); exit(1) }
    print(ScrollHelper.perform(step)); exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--auto-test") {
    do { try runAutoScrollTests(); exit(0) }
    catch { fputs("FAIL AUTO: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--crop-test") {
    do { try MainActor.assumeIsolated { try runCropTests() }; exit(0) }
    catch { fputs("FAIL CROP: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--permission-test") {
    do { try MainActor.assumeIsolated { try runPermissionTests() }; exit(0) }
    catch { fputs("FAIL PERMISSIONS: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--shortcut-test") {
    do { try MainActor.assumeIsolated { try runShortcutTests() }; exit(0) }
    catch { fputs("FAIL SHORTCUTS: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--annotation-test") {
    do { try MainActor.assumeIsolated { try runAnnotationTests() }; exit(0) }
    catch { fputs("FAIL ANNOTATION: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--history-test") {
    do { try MainActor.assumeIsolated { try runHistoryTests() }; exit(0) }
    catch { fputs("FAIL HISTORY: \(error)\n", stderr); exit(1) }
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
