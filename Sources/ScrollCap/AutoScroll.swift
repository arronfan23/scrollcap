import AppKit
import ApplicationServices

enum AutoScrollPace: String, CaseIterable {
    case careful = "慢速 · 推荐", standard = "标准"
    var fraction: CGFloat { self == .careful ? 0.20 : 0.25 }
    var pause: Double { self == .careful ? 0.9 : 0.65 }
    func points(bodyHeight: CGFloat, scale: CGFloat) -> Int {
        max(1, min(180, Int((bodyHeight / max(1, scale) * fraction).rounded())))
    }
}

enum AutoScrollObservation: Equatable { case moved, unchanged, unstable, finished }

struct AutoScrollProgress {
    private(set) var unchanged = 0
    private(set) var hasMoved = false
    mutating func observe(_ before: CGImage, _ after: CGImage, upward: Bool, maximumShift: Int? = nil) -> AutoScrollObservation {
        guard let a = VideoFrame(before, seconds: 0), let b = VideoFrame(after, seconds: 1) else { unchanged = 0; return .unstable }
        let match = VideoVision.alignment(a, b, upward: upward, maximumShift: maximumShift)
        switch match {
        case .shifted: unchanged = 0; hasMoved = true; return .moved
        case .unchanged: break
        case .uncertain:
            // A blinking caret or spinner must not prevent end detection. Most rows
            // still need to agree; a new page or a real scroll cannot count as idle.
            guard Self.stillDifference(a.fine, b.fine) < 0.65 else { unchanged = 0; return .unstable }
        }
        unchanged += 1
        return unchanged >= 3 ? .finished : .unchanged
    }
    static func stillDifference(_ a: SampleFrame, _ b: SampleFrame) -> Double {
        guard a.height == b.height else { return .infinity }
        var rows: [Double] = []
        for y in stride(from: 0, to: a.height, by: max(1, a.height / 160)) {
            var error = 0.0
            for x in stride(from: 6, to: 88, by: 2) { error += Double(abs(Int(a.pixels[y * 96 + x]) - Int(b.pixels[y * 96 + x]))) }
            rows.append(error / 41)
        }
        rows.sort()
        let count = max(1, rows.count * 9 / 10)
        return rows.prefix(count).reduce(0, +) / Double(count)
    }
}

struct CapturePermissions: Codable {
    var screen: Bool
    var automation: Bool
    static func current() -> CapturePermissions {
        CapturePermissions(screen: CGPreflightScreenCaptureAccess(), automation: CGPreflightPostEventAccess())
    }
    func missingRequirement(automatic: Bool) -> CapturePermissionIssue? {
        if !screen { return .screen }
        if automatic && !automation { return .automation }
        return nil
    }
}

enum CapturePermissionIssue {
    case screen, automation
    var title: String { self == .screen ? "需要屏幕录制权限" : "自动滚动需要辅助功能权限" }
    var settingsPane: String { self == .screen ? "Privacy_ScreenCapture" : "Privacy_Accessibility" }
    var message: String {
        let guidance = self == .screen
            ? "请在系统设置的「录屏与系统录音」中开启 ScrollCap，完成后返回并重新开始。"
            : "请在系统设置的「辅助功能」中开启 ScrollCap，完成后返回重试。也可以先切换到手动滚动。"
        return guidance + "\n\n若开关已开启但仍无法使用，请移除旧条目，重新添加「应用程序」中的 ScrollCap，并重新打开软件。"
    }
}

struct ScrollStep: Codable {
    var pid: Int32
    var center: CGPoint
    var points: Int
    var upward: Bool
    var first: Bool
    var windowID: UInt32?
    var windowBounds: CGRect?
}

enum AutoScrollStop: String, Error, LocalizedError {
    case permission, focusChanged, windowMoved, pointerMoved, cancelled, invalid
    var errorDescription: String? {
        switch self {
        case .permission: return "自动滚动尚未获准。请在主窗口开启辅助功能权限，再重试。"
        case .focusChanged: return "切换了应用，自动采集已停止。"
        case .windowMoved: return "目标窗口移动、缩放或关闭，自动采集已停止。"
        case .pointerMoved: return "鼠标移出了滚动位置，自动采集已停止。"
        case .cancelled: return "已结束自动采集。"
        case .invalid: return "自动滚动参数无效，已停止采集。"
        }
    }
}

enum ScrollHelper {
    static func event(points: Int32, center: CGPoint) -> CGEvent? {
        // Keep held shortcuts and the last hardware event out of generated input.
        let source = CGEventSource(stateID: .privateState)
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                            wheel1: points, wheel2: 0, wheel3: 0)
        event?.flags = []
        event?.location = center
        return event
    }
    static func validate(_ step: ScrollStep) -> AutoScrollStop? {
        guard step.pid > 0, step.points > 0, step.points <= 180,
              step.center.x.isFinite, step.center.y.isFinite else { return .invalid }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == step.pid else { return .focusChanged }
        if let id = step.windowID, let expected = step.windowBounds {
            guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                  let target = info.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
                  (target[kCGWindowOwnerPID as String] as? Int32) == step.pid,
                  let data = target[kCGWindowBounds as String] as? [String: CGFloat],
                  let actual = CGRect(dictionaryRepresentation: data as CFDictionary),
                  abs(actual.minX - expected.minX) <= 2, abs(actual.minY - expected.minY) <= 2,
                  abs(actual.width - expected.width) <= 2, abs(actual.height - expected.height) <= 2 else { return .windowMoved }
        }
        return nil
    }
    static func perform(_ step: ScrollStep) -> String {
        guard CGPreflightPostEventAccess() else { return AutoScrollStop.permission.rawValue }
        if let failure = validate(step) { return failure.rawValue }
        if step.first { CGWarpMouseCursorPosition(step.center) }
        var remaining = step.points
        while remaining > 0 {
            if let failure = validate(step) { return failure.rawValue }
            if let pointer = CGEvent(source: nil)?.location,
               hypot(pointer.x - step.center.x, pointer.y - step.center.y) > 24 { return AutoScrollStop.pointerMoved.rawValue }
            let pulse = min(6, remaining)
            guard let event = event(points: Int32(step.upward ? pulse : -pulse), center: step.center) else { return AutoScrollStop.invalid.rawValue }
            event.post(tap: .cghidEventTap)
            remaining -= pulse
            Thread.sleep(forTimeInterval: 0.02)
        }
        return "ok"
    }
}

@MainActor
final class AutoScrollClient {
    private var activeScroll: Process?
    // The signed app runs its own short-lived helper. This refreshes macOS's
    // per-process permission cache without reusing another app's authorization.
    func permissions() async throws -> CapturePermissions {
        let data = try await execute(["--capture-permissions"], scrolling: false)
        return try JSONDecoder().decode(CapturePermissions.self, from: data)
    }
    func scroll(_ step: ScrollStep) async throws {
        let data = try JSONEncoder().encode(step)
        let result = try await execute(["--scroll-step", data.base64EncodedString()], scrolling: true)
        let status = String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if status != "ok" { throw AutoScrollStop(rawValue: status) ?? .invalid }
    }
    func cancel() { if let activeScroll, activeScroll.isRunning { activeScroll.terminate() } }
    private func execute(_ arguments: [String], scrolling: Bool) async throws -> Data {
        guard let executable = Bundle.main.executableURL else { throw AutoScrollStop.invalid }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process(), output = Pipe()
            process.executableURL = executable; process.arguments = arguments; process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] child in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                Task { @MainActor in
                    if self?.activeScroll === child { self?.activeScroll = nil }
                    if child.terminationStatus == 0 { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: AutoScrollStop.cancelled) }
                }
            }
            do { try process.run(); if scrolling { activeScroll = process } }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
    }
}
