import AppKit
import Combine
import ImageIO

struct ScreenshotHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let width: Int
    let height: Int
    let kind: CaptureKind
    let title: String
}

private struct HistoryPointer: Codable {
    let version: Int
    let revision: UUID
}

private struct HistoryMetadata: Codable {
    let version: Int
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let width: Int
    let height: Int
    let kind: String
    let title: String
    var entry: ScreenshotHistoryEntry? {
        guard version == 1, let kind = CaptureKind(rawValue: kind), width > 0, height > 0 else { return nil }
        return ScreenshotHistoryEntry(id: id, createdAt: createdAt, updatedAt: updatedAt, width: width, height: height, kind: kind, title: title)
    }
}

private struct HistoryPoint: Codable {
    let x: Double
    let y: Double
}

private struct HistoryMark: Codable {
    let id: UUID
    let tool: String
    let points: [HistoryPoint]
    let rgba: [Double]
    let width: Double
    let text: String
    let fontSize: Double
    init(_ mark: ScreenshotMark) throws {
        guard let color = mark.color.usingColorSpace(.sRGB) else { throw HistoryFailure("标注颜色无法保存。") }
        id = mark.id; tool = mark.tool.rawValue
        points = mark.points.map { HistoryPoint(x: Double($0.x), y: Double($0.y)) }
        rgba = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent), Double(color.alphaComponent)]
        width = Double(mark.width); text = mark.text; fontSize = Double(mark.fontSize)
        _ = try restored()
    }
    func restored() throws -> ScreenshotMark {
        guard let tool = ScreenshotTool(rawValue: tool), rgba.count == 4,
              rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }), width.isFinite, width > 0,
              fontSize.isFinite, fontSize > 0, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw HistoryFailure("截图标注数据已损坏或版本不受支持。")
        }
        return ScreenshotMark(id: id, tool: tool, points: points.map { CGPoint(x: $0.x, y: $0.y) },
            color: NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]),
            width: CGFloat(width), text: text, fontSize: CGFloat(fontSize))
    }
}

private struct HistoryFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Local editable originals are kept separately from flattened exports and clipboard data.
@MainActor
final class ScreenshotHistoryStore: ObservableObject {
    static let shared = ScreenshotHistoryStore()
    @Published private(set) var entries: [ScreenshotHistoryEntry] = []
    @Published private(set) var entryErrors: [UUID: String] = [:]
    @Published private(set) var errorMessage: String?
    private let rootURL: URL
    private let trash: (URL) throws -> Void
    private let files = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }()
    private let decoder = JSONDecoder()

    init(rootURL: URL? = nil, trash: ((URL) throws -> Void)? = nil) {
        if let rootURL { self.rootURL = rootURL.standardizedFileURL }
        else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
#if DESIGN_PREVIEW
            let folder = "ScrollCap Design Preview"
#else
            let folder = Bundle.main.bundleIdentifier == "io.github.arronfan23.scrollcap.designpreview" ? "ScrollCap Design Preview" : "ScrollCap"
#endif
            self.rootURL = support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("History", isDirectory: true)
        }
        self.trash = trash ?? { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        reload()
    }

    /// Scans each item independently so one damaged item never hides healthy history.
    func reload() {
        do {
            try files.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let directories = try files.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            var found: [ScreenshotHistoryEntry] = [], failures: [UUID: String] = [:]
            for directory in directories {
                guard let id = UUID(uuidString: directory.lastPathComponent), (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                do {
                    let (_, metadata) = try current(id)
                    guard let entry = metadata.entry else { throw HistoryFailure("历史截图格式不受支持。") }
                    found.append(entry)
                } catch {
                    let date = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    found.append(ScreenshotHistoryEntry(id: id, createdAt: date, updatedAt: date, width: 0, height: 0, kind: .single, title: "无法读取的截图"))
                    failures[id] = message(error, prefix: "这张历史截图无法读取")
                }
            }
            entries = sorted(found); entryErrors = failures
            errorMessage = failures.isEmpty ? nil : "有 \(failures.count) 张历史截图无法读取，其余截图仍可正常使用。"
        } catch { errorMessage = message(error, prefix: "无法读取截图历史") }
    }

    @discardableResult
    func save(document: ScreenshotDocument, kind: CaptureKind, id: UUID? = nil) throws -> UUID {
        let id = id ?? UUID(), directory = itemURL(id), revision = UUID()
        let revisionURL = directory.appendingPathComponent("revisions", isDirectory: true).appendingPathComponent(revision.uuidString, isDirectory: true)
        let existed = files.fileExists(atPath: directory.path)
        do {
            // Validate everything before writing or replacing an existing current pointer.
            let marks = try document.marks.map(HistoryMark.init)
            let marksData = try encoder.encode(marks)
            let previous = existed ? try current(id).1 : nil
            let now = Date()
            let updated = max(now, (previous?.updatedAt ?? .distantPast).addingTimeInterval(0.000001))
            let title: String
            if let previous { title = previous.title }
            else {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                title = "\(kind.title) · \(formatter.string(from: now))"
            }
            let metadata = HistoryMetadata(version: 1, id: id, createdAt: previous?.createdAt ?? now, updatedAt: updated,
                width: document.original.width, height: document.original.height, kind: kind.rawValue, title: title)
            guard let rendered = document.rendered(), let thumbnail = makeThumbnail(rendered) else { throw HistoryFailure("生成历史截图预览失败。") }
            try files.createDirectory(at: revisionURL, withIntermediateDirectories: true)
            try Stitcher.png(document.original, to: revisionURL.appendingPathComponent("original.png"))
            try Stitcher.png(rendered, to: revisionURL.appendingPathComponent("preview.png"))
            try Stitcher.png(thumbnail, to: revisionURL.appendingPathComponent("thumbnail.png"))
            try marksData.write(to: revisionURL.appendingPathComponent("annotations.json"), options: .atomic)
            try encoder.encode(metadata).write(to: revisionURL.appendingPathComponent("metadata.json"), options: .atomic)
            // The immutable revision becomes visible only after all of its assets are complete.
            try encoder.encode(HistoryPointer(version: 1, revision: revision)).write(to: directory.appendingPathComponent("current.json"), options: .atomic)
            entries.removeAll { $0.id == id }; entries.append(metadata.entry!); entries = sorted(entries)
            entryErrors[id] = nil; errorMessage = nil
            // A successful commit no longer needs prior internal revisions. Exports are elsewhere.
            let revisions = revisionURL.deletingLastPathComponent()
            if let previousRevisions = try? files.contentsOfDirectory(at: revisions, includingPropertiesForKeys: nil) {
                for old in previousRevisions where old.lastPathComponent != revision.uuidString && UUID(uuidString: old.lastPathComponent) != nil { try? files.removeItem(at: old) }
            }
            return id
        } catch {
            try? files.removeItem(at: revisionURL)
            if !existed { try? files.removeItem(at: directory) }
            let failure = HistoryFailure(message(error, prefix: "保存截图历史失败")); errorMessage = failure.localizedDescription; throw failure
        }
    }

    func load(_ id: UUID) throws -> ScreenshotDocument {
        do {
            let (revision, metadata) = try current(id)
            guard let source = CGImageSourceCreateWithURL(revision.appendingPathComponent("original.png") as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  image.width == metadata.width, image.height == metadata.height else { throw HistoryFailure("原始截图文件已损坏或缺失。") }
            let marks = try decoder.decode([HistoryMark].self, from: Data(contentsOf: revision.appendingPathComponent("annotations.json"))).map { try $0.restored() }
            let document = ScreenshotDocument(image, marks: marks)
            entryErrors[id] = nil
            return document
        } catch {
            let failure = HistoryFailure(message(error, prefix: "打开历史截图失败"))
            entryErrors[id] = failure.localizedDescription; errorMessage = failure.localizedDescription; throw failure
        }
    }

    func thumbnail(_ entry: ScreenshotHistoryEntry) -> NSImage? {
        guard let (revision, _) = try? current(entry.id) else { return nil }
        return NSImage(contentsOf: revision.appendingPathComponent("thumbnail.png"))
    }

    func delete(_ id: UUID) throws {
        do {
            let directory = itemURL(id)
            if files.fileExists(atPath: directory.path) { try trash(directory) }
            entries.removeAll { $0.id == id }; entryErrors[id] = nil; errorMessage = nil
        } catch {
            let failure = HistoryFailure(message(error, prefix: "无法将历史截图移到废纸篓")); errorMessage = failure.localizedDescription; throw failure
        }
    }

    func deleteAll() throws {
        var failures = 0
        for id in entries.map(\.id) {
            do { try delete(id) } catch { failures += 1 }
        }
        if failures > 0 {
            let failure = HistoryFailure("有 \(failures) 张历史截图未能移到废纸篓，已保留在历史中。")
            errorMessage = failure.localizedDescription; throw failure
        }
    }

    private func itemURL(_ id: UUID) -> URL { rootURL.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func current(_ id: UUID) throws -> (URL, HistoryMetadata) {
        let directory = itemURL(id)
        let pointer = try decoder.decode(HistoryPointer.self, from: Data(contentsOf: directory.appendingPathComponent("current.json")))
        guard pointer.version == 1 else { throw HistoryFailure("历史截图版本不受支持。") }
        let revision = directory.appendingPathComponent("revisions", isDirectory: true).appendingPathComponent(pointer.revision.uuidString, isDirectory: true)
        let metadata = try decoder.decode(HistoryMetadata.self, from: Data(contentsOf: revision.appendingPathComponent("metadata.json")))
        guard metadata.id == id, metadata.entry != nil else { throw HistoryFailure("历史截图索引已损坏。") }
        for asset in ["original.png", "preview.png", "thumbnail.png", "annotations.json"] {
            guard files.fileExists(atPath: revision.appendingPathComponent(asset).path) else { throw HistoryFailure("历史截图文件不完整（\(asset)）。") }
        }
        return (revision, metadata)
    }
    private func sorted(_ values: [ScreenshotHistoryEntry]) -> [ScreenshotHistoryEntry] {
        values.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    private func makeThumbnail(_ image: CGImage) -> CGImage? {
        let preview = image.height > image.width
            ? (image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: max(1, Int(Double(image.width) * 0.76)))) ?? image) : image
        let scale = min(1, 320 / CGFloat(max(preview.width, preview.height)))
        let width = max(1, Int(CGFloat(preview.width) * scale)), height = max(1, Int(CGFloat(preview.height) * scale))
        guard let context = ScreenshotRenderer.context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high; context.draw(preview, in: CGRect(x: 0, y: 0, width: width, height: height)); return context.makeImage()
    }
    private func message(_ error: Error, prefix: String) -> String { "\(prefix)：\(error.localizedDescription)" }
}
