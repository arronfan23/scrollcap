import AppKit
import Carbon

@MainActor
private final class TestHotKeyRegistrar: HotKeyRegistering {
    var values: [ShortcutAction: KeyShortcut] = [:]
    var blocked: [KeyShortcut] = []
    func set(_ shortcut: KeyShortcut?, for action: ShortcutAction) -> OSStatus {
        if let shortcut, blocked.contains(shortcut) { return OSStatus(eventHotKeyExistsErr) }
        values[action] = shortcut; return noErr
    }
    func clear() { values.removeAll() }
}

@MainActor
func runShortcutTests() throws {
    var count = 0
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw TestFailure(description: message) }
        count += 1; print("PASS \(message)")
    }
    let suite = "io.github.arronfan23.scrollcap.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    try require(preferences.historyRetention == .exported, "new installs retain history only after save or copy")
    preferences.historyRetention = .all
    try require(AppPreferences(defaults: defaults).historyRetention == .all, "history retention preference persists across launches")
    preferences.historyRetention = .exported
    let registrar = TestHotKeyRegistrar()
    let manager = GlobalHotKeyManager(preferences: preferences, registrar: registrar)
    try require(registrar.values.count == 3 && !preferences.autoPinSingle, "all three default shortcuts register and automatic pinning is opt-in")
    try require(preferences.shortcut(for: .single)?.display == "⌃⇧1" && preferences.shortcut(for: .scrolling)?.display == "⌃⇧2", "ordinary and scrolling defaults are distinct and legible")
    let typing = KeyShortcut(keyCode: 0, modifiers: UInt32(shiftKey))
    try require(manager.update(.single, to: typing) != nil && preferences.shortcut(for: .single) == KeyShortcut.defaults[.single], "typing-only shortcut is rejected without replacing the working default")
    let system = KeyShortcut(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey))
    try require(manager.update(.single, to: system) != nil, "system screenshot shortcut is reserved")
    try require(manager.update(.single, to: preferences.shortcut(for: .scrolling)) != nil && registrar.values[.single] == KeyShortcut.defaults[.single], "duplicate in-app shortcut preserves the old registration")
    let custom = KeyShortcut(keyCode: 8, modifiers: UInt32(controlKey | optionKey | shiftKey))
    try require(manager.update(.single, to: custom) == nil && registrar.values[.single] == custom, "custom shortcut replaces the selected action only")
    let occupied = KeyShortcut(keyCode: 9, modifiers: UInt32(controlKey | optionKey | shiftKey))
    registrar.blocked = [occupied]
    try require(manager.update(.single, to: occupied) != nil && preferences.shortcut(for: .single) == custom && registrar.values[.single] == custom, "external conflict preserves both preferences and the active old shortcut")
    preferences.autoPinSingle = true
    let reloaded = AppPreferences(defaults: defaults)
    try require(reloaded.autoPinSingle && reloaded.shortcut(for: .single) == custom, "custom shortcuts and auto-pin setting persist across launches")
    try require(manager.update(.single, to: nil) == nil && registrar.values[.single] == nil && AppPreferences(defaults: defaults).shortcut(for: .single) == nil, "clearing a shortcut stays cleared after reload")
    manager.suspendRecording(true)
    try require(registrar.values.isEmpty, "shortcut recording suspends all capture triggers")
    manager.suspendRecording(false)
    try require(registrar.values.count == 2 && registrar.values[.scrolling] != nil, "leaving shortcut recording restores all enabled triggers")
    try require(manager.restoreDefaults() == nil && registrar.values == KeyShortcut.defaults, "restore defaults re-registers all actions")
    _ = manager.update(.single, to: custom)
    registrar.blocked = [KeyShortcut.defaults[.single]!]
    try require(manager.restoreDefaults() != nil && preferences.shortcut(for: .single) == custom && registrar.values[.single] == custom, "failed default restore rolls back the previously working configuration")
    registrar.blocked = []; manager.shutdown()
    try require(registrar.values.isEmpty, "shutdown releases all global combinations")
    let model = CaptureModel(); model.captureKind = .single; model.automatic = true; model.preparing = true
    try require(model.applyStartPermissions(CapturePermissions(screen: true, automation: false)) && model.permissionIssue == nil, "ordinary screenshot never requires automation even when the last long mode was automatic")
    let frame = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 103, pixelsHigh: 77, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.cgImage!
    model.preparing = false; model.setResultImage(frame, kind: .single)
    try require(model.resultKind == .single && model.outputSize == "103 × 77 px", "ordinary results preserve odd pixel dimensions and carry the correct result type")
    model.updateCrop(CGRect(x: 3, y: 5, width: 93, height: 61))
    try require(model.croppedImage?.width == 93 && model.croppedImage?.height == 61, "ordinary screenshots share the exact crop export path")
    let firstResult = model.resultID!
    model.resultWarning = "old warning"; model.resultNotice = "old notice"; model.hasVideo = true; model.hasFrames = true
    model.dismissResult(firstResult)
    try require(model.resultID == nil && model.previewImage == nil && model.image == nil && model.croppedImage == nil && model.cropRect == .zero && model.imageSize.isEmpty && model.resultWarning == nil && model.resultNotice == nil && !model.hasVideo && !model.hasFrames, "closing a screenshot discards its preview, crop, warnings and capture resources")
    model.setResultImage(frame, kind: .single)
    let secondResult = model.resultID!
    model.dismissResult(firstResult)
    try require(model.resultID == secondResult && model.outputSize == "103 × 77 px", "closing an older floating image cannot discard the newer result")
    model.preparing = true; model.hasVideo = true
    model.dismissResult(secondResult)
    try require(model.resultID == secondResult && model.hasVideo && model.preparing, "closing a floating image never interrupts an active capture")
    model.preparing = false
    model.startSingle()
    let clearedBeforePermission = model.preparing && model.resultID == nil && model.previewImage == nil && !model.hasVideo
    model.stop(); model.dismissResult(secondResult)
    try require(clearedBeforePermission && !model.preparing && model.image == nil, "new screenshot shortcut clears the old result before permission checks, even when the request is cancelled")
    let saved = FileManager.default.temporaryDirectory.appendingPathComponent("scrollcap-close-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: saved) }
    try Stitcher.png(frame, to: saved)
    let savedBytes = try Data(contentsOf: saved)
    model.setResultImage(frame, kind: .single); model.dismissResult(model.resultID!)
    let preserved = try Data(contentsOf: saved)
    try require(model.previewImage == nil && preserved == savedBytes, "closing after export discards memory while preserving the saved PNG")
    print("\(count) shortcut and ordinary-capture checks passed")
}
