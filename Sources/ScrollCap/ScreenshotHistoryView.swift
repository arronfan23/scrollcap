import AppKit
import SwiftUI

struct ScreenshotHistoryView: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var history: ScreenshotHistoryStore
    @ObservedObject var preferences: AppPreferences
    @State private var search = ""
    @State private var deleting: ScreenshotHistoryEntry?
    @State private var deletingAll = false
    @State private var confirmingDelete = false

    private var visibleEntries: [ScreenshotHistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { ($0.title + " " + $0.kind.title + " " + $0.updatedAt.formatted(date: .abbreviated, time: .shortened)).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("历史截图").font(.title3.weight(.semibold))
                Text("\(history.entries.count) 张").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button {
                    deleting = nil; deletingAll = true; confirmingDelete = true
                } label: { Label("全部删除", systemImage: "trash") }
                    .disabled(history.entries.isEmpty || model.busy)
                    .help("将全部历史截图移到系统废纸篓，已导出文件不受影响")
            }
            HStack {
                Text(preferences.historyRetention == .exported
                     ? "保存或复制后的截图会保留在这里。打开即可继续编辑。"
                     : "截图自动保留在这里。打开即可继续编辑。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("搜索类型或日期", text: $search).textFieldStyle(.plain)
                        .accessibilityLabel("搜索历史截图")
                }.padding(7).frame(width: 200)
                    .background(ScrollCapStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ScrollCapStyle.separator, lineWidth: 1))
            }
            if let error = history.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("还没有历史截图", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(preferences.historyRetention == .exported ? "截图后点击保存或复制，即可在这里找到。" : "完成一次截图后，就会出现在这里。")
                } actions: {
                    Button("去截图") { model.showingHistory = false }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleEntries) { entry in
                    HistoryScreenshotRow(entry: entry, history: history,
                        edit: { model.openHistory(entry) }, copy: { model.copyHistory(entry) },
                        export: { model.exportHistory(entry) }, delete: {
                            deleting = entry; deletingAll = false; confirmingDelete = true
                        })
                    .listRowSeparator(.visible)
                }.listStyle(.inset).scrollContentBackground(.hidden)
                    .background(ScrollCapStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScrollCapStyle.separator.opacity(0.7), lineWidth: 1))
            }
            HStack {
                Label("仅保存在此 Mac · 包含可编辑原图和标注", systemImage: "internaldrive")
                Spacer()
                if model.status == "历史截图已复制。" { Text(model.status) }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(24)
            .confirmationDialog(deletingAll ? "删除全部 \(history.entries.count) 张历史截图？" : "删除这张历史截图？",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(deletingAll ? "全部移到废纸篓" : "移到废纸篓", role: .destructive) {
                    if deletingAll { model.deleteAllHistory() }
                    else if let deleting { model.deleteHistory(deleting) }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: {
                Text("只删除应用内历史，已另存的图片不受影响。对应编辑窗口会关闭，可从系统废纸篓找回历史文件夹。")
            }
    }
}

private struct HistoryScreenshotRow: View {
    let entry: ScreenshotHistoryEntry
    @ObservedObject var history: ScreenshotHistoryStore
    let edit: () -> Void
    let copy: () -> Void
    let export: () -> Void
    let delete: () -> Void
    @State private var thumbnail: NSImage?
    private var unreadable: Bool { history.entryErrors[entry.id] != nil }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: edit) {
                ZStack {
                    ScrollCapStyle.canvas
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().padding(4)
                    } else { Image(systemName: "photo").foregroundStyle(.secondary) }
                }.frame(width: 100, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ScrollCapStyle.separator.opacity(0.6), lineWidth: 1))
            }.buttonStyle(.plain).disabled(unreadable).accessibilityLabel("编辑\(entry.title)")
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                if let error = history.entryErrors[entry.id] {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else {
                    Text("\(entry.kind.title) · \(entry.width) × \(entry.height) px").font(.caption).foregroundStyle(.secondary)
                    Text("更新于 \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: edit) { Label("编辑", systemImage: "pencil") }.disabled(unreadable)
            Button(action: copy) { Image(systemName: "doc.on.doc") }.disabled(unreadable)
                .help("复制包含标注的截图").accessibilityLabel("复制\(entry.title)")
            Button(action: delete) { Image(systemName: "trash") }
                .help("删除这张历史截图").accessibilityLabel("删除\(entry.title)")
        }.padding(.vertical, 8).buttonStyle(.borderless).tint(ScrollCapStyle.emphasis)
            .contextMenu {
                Button("重新编辑", action: edit).disabled(unreadable)
                Button("复制", action: copy).disabled(unreadable)
                Button("另存为 PNG…", action: export).disabled(unreadable)
                Divider()
                Button("删除", role: .destructive, action: delete)
            }
            .task(id: entry.updatedAt) { thumbnail = history.thumbnail(entry) }
    }
}
