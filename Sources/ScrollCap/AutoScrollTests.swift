import AppKit

func runAutoScrollTests() throws {
    var count = 0
    func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw TestFailure(description: name) }
        count += 1; print("PASS \(name)")
    }
    try require(AutoScrollPace.careful.points(bodyHeight: 1080, scale: 2) == 108, "automatic step uses logical points on Retina")
    try require(AutoScrollPace.standard.points(bodyHeight: 1080, scale: 2) == 135, "standard step keeps 75 percent overlap")
    try require(AutoScrollPace.careful.points(bodyHeight: 8000, scale: 1) == 180, "large viewport step stays bounded")
    try require(AutoScrollPace.careful.points(bodyHeight: 1, scale: 0) == 1, "small viewport step remains positive")
    let doc = fixture(width: 640, height: 2400)
    let a = doc.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 800))!
    let b = doc.cropping(to: CGRect(x: 0, y: 160, width: 640, height: 800))!
    var tracker = AutoScrollProgress()
    try require(!tracker.hasMoved, "a stationary target is not reported as a completed long capture")
    try require(tracker.observe(a, b, upward: false) == .moved, "automatic downward movement is recognized")
    try require(tracker.hasMoved, "a confirmed scroll is remembered for end reporting")
    try require(tracker.observe(b, a, upward: true) == .moved, "automatic upward movement is recognized")
    try require(tracker.observe(a, a, upward: false) == .unchanged, "one idle observation does not end capture")
    try require(tracker.observe(a, a, upward: false) == .unchanged, "two idle observations do not end capture")
    try require(tracker.observe(a, a, upward: false) == .finished, "three idle observations confirm the end")
    _ = tracker.observe(a, b, upward: false)
    try require(tracker.unchanged == 0, "movement resets end confirmation")
    let changed = fixture(width: 640, height: 800, seed: 990)
    try require(tracker.observe(a, changed, upward: false) == .unstable, "a changed page cannot be mistaken for the end")
    try require(tracker.unchanged == 0, "unstable frames reset idle confirmation")
    let ctx = CGContext(data: nil, width: 640, height: 800, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(a, in: CGRect(x: 0, y: 0, width: 640, height: 800))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 200, y: 200, width: 60, height: 8))
    let cursor = ctx.makeImage()!
    try require(AutoScrollProgress.stillDifference(SampleFrame(a)!, SampleFrame(cursor)!) < 0.65, "a blinking caret does not prevent end detection")
    let bad = ScrollStep(pid: -1, center: .zero, points: 100, upward: false, first: true)
    try require(ScrollHelper.validate(bad) == .invalid, "invalid scroll requests cannot send input")
    let oversized = ScrollStep(pid: 1, center: .zero, points: 999, upward: false, first: true)
    try require(ScrollHelper.validate(oversized) == .invalid, "oversized scroll requests cannot send input")
    let permissionData = try JSONEncoder().encode(CapturePermissions(screen: false, automation: false))
    let permissions = try JSONDecoder().decode(CapturePermissions.self, from: permissionData)
    try require(!permissions.screen && !permissions.automation, "missing permissions are retained as denied")
    let up = ScrollHelper.event(points: 6, center: CGPoint(x: 100, y: 200))!
    let down = ScrollHelper.event(points: -6, center: CGPoint(x: 100, y: 200))!
    try require(up.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) > 0 && down.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) < 0, "wheel events preserve upward and downward pixel directions")
    try require(up.flags.isEmpty && down.flags.isEmpty, "automatic wheel events do not inherit keyboard modifiers")
    print("\(count) automatic-scroll checks passed")
}
