import AppKit

@MainActor
func runPermissionTests() throws {
    var count = 0
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw TestFailure(description: message) }
        count += 1; print("PASS \(message)")
    }
    let denied = CapturePermissions(screen: false, automation: false)
    let screenOnly = CapturePermissions(screen: true, automation: false)
    let allowed = CapturePermissions(screen: true, automation: true)
    try require(denied.missingRequirement(automatic: false) == .screen, "manual capture explains missing recording access")
    try require(screenOnly.missingRequirement(automatic: false) == nil, "manual capture does not require accessibility")
    try require(denied.missingRequirement(automatic: true) == .screen, "automatic capture requests recording before accessibility")
    try require(screenOnly.missingRequirement(automatic: true) == .automation, "automatic capture explains missing accessibility")
    try require(allowed.missingRequirement(automatic: true) == nil, "authorized capture can enter selection")
    let model = CaptureModel()
    model.preparing = true
    let refused = model.applyStartPermissions(denied)
    try require(!refused && !model.busy && model.permissionIssue == .screen && model.status == "需要屏幕录制权限", "a blocked start displays an actionable issue and releases busy state")
    model.automatic = true; model.preparing = true
    _ = model.applyStartPermissions(screenOnly)
    try require(!model.busy && model.permissionIssue == .automation && model.screenGranted && !model.accessGranted, "accessibility blocking retains the actual recording grant")
    model.preparing = true
    let ready = model.applyStartPermissions(allowed)
    try require(ready && model.preparing && model.permissionIssue == nil && model.screenGranted && model.accessGranted, "a fresh grant clears the old blocker and continues preparation")
    print("\(count) permission checks passed")
}
