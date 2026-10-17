import AppKit
import ImageIO

@MainActor
func runHistoryTests() throws {
    var count = 0
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(description: message) }
        count += 1; print("PASS \(message)")
    }
    let files = FileManager.default
    let sandbox = files.temporaryDirectory.appendingPathComponent("ScrollCapHistoryTests-\(UUID())", isDirectory: true)
    let root = sandbox.appendingPathComponent("History", isDirectory: true)
    try files.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: sandbox) }
    var trashed: [URL] = []
    let trash: (URL) throws -> Void = { url in
        guard url.deletingLastPathComponent() == root else { throw TestFailure(description: "history attempted to delete outside its root") }
        trashed.append(url); try files.removeItem(at: url)
    }
    let context = ScreenshotRenderer.context(width: 480, height: 240)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 480, height: 240))
    for x in stride(from: 0, to: 480, by: 2) {
        context.setFillColor((x % 4 == 0 ? NSColor.black : NSColor.white).cgColor)
        context.fill(CGRect(x: x, y: 70, width: 2, height: 60))
    }
    let original = context.makeImage()!
    func pixels(_ image: CGImage) -> Data {
        let context = ScreenshotRenderer.context(width: image.width, height: image.height)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()!.dataProvider!.data! as Data
    }
    let document = ScreenshotDocument(original)
    let tools: [ScreenshotTool] = [.pen, .arrow, .rectangle, .ellipse, .mosaic, .text]
    let marks = tools.enumerated().map { offset, tool in
        ScreenshotMark(tool: tool, points: tool == .text ? [CGPoint(x: 20, y: 180)] : [CGPoint(x: 20 + offset * 7, y: 100), CGPoint(x: 420, y: 110)],
            color: NSColor(srgbRed: 0.1, green: 0.55, blue: 0.85, alpha: 0.9), width: tool == .mosaic ? 32 : 5,
            text: tool == .text ? "SMO 中文标注测试 🐱" : "", fontSize: 28)
    }
    document.commit(marks)
    let store = ScreenshotHistoryStore(rootURL: root, trash: trash)
    try require(store.entries.isEmpty && store.errorMessage == nil, "new isolated history starts empty")
    let firstID = try store.save(document: document, kind: .single)
    let first = store.entries[0]
    try require(first.id == firstID && first.kind == .single && first.width == 480 && first.height == 240 && !first.title.isEmpty, "saved history records stable identity, dimensions, kind and title")
    let reopened = ScreenshotHistoryStore(rootURL: root, trash: trash)
    try require(reopened.entries == store.entries, "history survives creation of a fresh store")
    let loaded = try reopened.load(firstID)
    try require(pixels(loaded.original) == pixels(original), "editable history retains exact original image pixels")
    let restored = loaded.marks
    let complete = zip(marks, restored).allSatisfy { left, right in
        guard let a = left.color.usingColorSpace(.sRGB), let b = right.color.usingColorSpace(.sRGB) else { return false }
        return left.id == right.id && left.tool == right.tool && left.points == right.points && left.width == right.width
            && left.text == right.text && left.fontSize == right.fontSize
            && abs(a.redComponent - b.redComponent) < 0.00001 && abs(a.greenComponent - b.greenComponent) < 0.00001
            && abs(a.blueComponent - b.blueComponent) < 0.00001 && abs(a.alphaComponent - b.alphaComponent) < 0.00001
    }
    try require(restored.count == marks.count && complete, "all annotation types, geometry, sRGB color, alpha and Chinese text round-trip")
    try require(!loaded.canUndo && !loaded.canRedo, "reopened history starts at its saved annotations without undoing them all")
    try require(pixels(loaded.rendered()!) != pixels(original) && loaded.marks.contains { $0.tool == .mosaic }, "reopened history renders annotations and preserves the editable mosaic brush")
    let secondID = try reopened.save(document: ScreenshotDocument(original), kind: .scrolling)
    try require(reopened.entries.map(\.id) == [secondID, firstID], "history is ordered by most recently updated screenshot")
    loaded.append(ScreenshotMark(tool: .text, points: [CGPoint(x: 30, y: 20)], text: "再次编辑", fontSize: 24))
    let upsertID = try reopened.save(document: loaded, kind: .single, id: firstID)
    try require(upsertID == firstID && reopened.entries.count == 2 && reopened.entries[0].id == firstID
        && reopened.entries[0].createdAt == first.createdAt && reopened.entries[0].updatedAt > first.updatedAt, "editing history updates the same item, preserves creation date and moves it to the top")
    let thirdStore = ScreenshotHistoryStore(rootURL: root, trash: trash)
    let reedited = try thirdStore.load(firstID)
    try require(reedited.marks.count == marks.count + 1 && reedited.marks.last?.text == "再次编辑", "edited history persists across another store restart")
    let thumbnail = thirdStore.thumbnail(thirdStore.entries[0])
    try require(thumbnail != nil && thumbnail!.size.width <= 320 && thumbnail!.size.height <= 320 && thumbnail!.size.width > 0, "history supplies a bounded flattened thumbnail")
    // Resolve only a test-owned history pointer to inspect the persisted asset contract.
    let item = root.appendingPathComponent(firstID.uuidString)
    let pointerData = try Data(contentsOf: item.appendingPathComponent("current.json"))
    let pointer = try JSONSerialization.jsonObject(with: pointerData) as! [String: Any]
    let revision = item.appendingPathComponent("revisions").appendingPathComponent(pointer["revision"] as! String)
    let persistedPreview = CGImageSourceCreateWithURL(revision.appendingPathComponent("preview.png") as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    try require(persistedPreview != nil && pixels(persistedPreview!) == pixels(reedited.rendered()!), "stored flattened preview includes the saved annotations")
    let invalid = ScreenshotDocument(original)
    invalid.append(ScreenshotMark(tool: .pen, points: [CGPoint(x: 10, y: 10)], width: .nan))
    var rejected = false
    do { try thirdStore.save(document: invalid, kind: .single, id: firstID) } catch { rejected = !error.localizedDescription.isEmpty }
    let preserved = try thirdStore.load(firstID)
    try require(rejected && (try Data(contentsOf: item.appendingPathComponent("current.json"))) == pointerData && preserved.marks.count == reedited.marks.count, "failed history update leaves the previous committed pointer and editable document intact")
    let brokenID = UUID(), broken = root.appendingPathComponent(brokenID.uuidString)
    try files.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("broken JSON".utf8).write(to: broken.appendingPathComponent("current.json"))
    let damagedStore = ScreenshotHistoryStore(rootURL: root, trash: trash)
    try require(damagedStore.entries.count == 3 && damagedStore.entryErrors[brokenID] != nil
        && damagedStore.entries.contains { $0.id == firstID && $0.width == 480 }, "one corrupt item remains visible with an error while healthy history stays available")
    var loadRejected = false
    do { _ = try damagedStore.load(brokenID) } catch { loadRejected = !error.localizedDescription.isEmpty }
    try require(loadRejected && damagedStore.errorMessage != nil, "loading damaged history reports a displayable error")
    let deniedStore = ScreenshotHistoryStore(rootURL: root, trash: { _ in throw TestFailure(description: "simulated trash failure") })
    var deleteRejected = false
    do { try deniedStore.delete(firstID) } catch { deleteRejected = true }
    try require(deleteRejected && deniedStore.entries.contains { $0.id == firstID } && files.fileExists(atPath: item.path), "failed trash operation preserves both history item and its files")
    let export = sandbox.appendingPathComponent("user-export.png")
    try Stitcher.png(reedited.rendered()!, to: export)
    let exportBefore = try Data(contentsOf: export)
    try damagedStore.delete(firstID)
    try require(!damagedStore.entries.contains { $0.id == firstID } && trashed.contains(item)
        && (try Data(contentsOf: export)) == exportBefore, "deleting history invokes its trash operation and leaves exported PNG untouched")
    try damagedStore.deleteAll()
    try require(damagedStore.entries.isEmpty && ScreenshotHistoryStore(rootURL: root, trash: trash).entries.isEmpty
        && (try Data(contentsOf: export)) == exportBefore && trashed.count == 3, "clearing healthy and corrupt history trashes only history items and preserves exports")
    print("\(count) editable screenshot history checks passed")
}
