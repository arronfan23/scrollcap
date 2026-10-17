import AppKit
import Carbon

enum CaptureKind: String, CaseIterable, Identifiable, Codable {
    case scrolling, single
    var id: String { rawValue }
    var title: String { self == .scrolling ? "长截图" : "普通截图" }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case exported, all
    var id: String { rawValue }
    var title: String { self == .exported ? "保存或复制后保留" : "所有截图自动保留" }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case single, scrolling, stop
    var id: String { rawValue }
    var title: String {
        switch self { case .single: return "普通截图"; case .scrolling: return "长截图"; case .stop: return "结束采集" }
    }
    var detail: String {
        switch self {
        case .single: return "拖动框选，松开后立即生成截图。"
        case .scrolling: return "框选窗口并标记正文，按当前设置采集。"
        case .stop: return "结束正在进行的长截图，或取消处理。"
        }
    }
    var eventID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)!) + 1 }
    static func event(_ id: UInt32) -> Self? { allCases.first { $0.eventID == id } }
}

struct KeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        modifiers = (flags.contains(.command) ? UInt32(cmdKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
    var display: String {
        let symbols = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
        return symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + Self.keyName(keyCode)
    }
    static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"⎋",65:".",67:"*",69:"+",75:"/",76:"⌤",78:"−",81:"=",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",117:"⌦",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        return names[code] ?? "Key \(code)"
    }
    var validationMessage: String? {
        guard keyCode <= 126, ![54,55,56,57,58,59,60,61,62,63].contains(keyCode), modifiers & ~Self.modifierMask == 0 else { return "请选择一个有效按键。" }
        guard modifiers & UInt32(cmdKey | controlKey) != 0 else { return "快捷键需要包含 ⌘ Command 或 ⌃ Control，避免影响正常输入。" }
        let commandShift = UInt32(cmdKey | shiftKey)
        if (modifiers & commandShift) == commandShift && [20,21,23,22].contains(keyCode) {
            return "请避开 macOS 已使用的系统截图快捷键。"
        }
        if keyCode == 49 && [UInt32(cmdKey),UInt32(cmdKey | optionKey),UInt32(controlKey),UInt32(controlKey | optionKey)].contains(modifiers) {
            return "这个组合通常用于系统搜索或输入法，请换一组快捷键。"
        }
        if keyCode == 53 && modifiers == UInt32(cmdKey | optionKey) { return "这个组合用于系统强制退出，请换一组。" }
        if modifiers == UInt32(cmdKey), [12,13,4,46,1,8,9,7,6,43].contains(keyCode) {
            return "请给常用的 ⌘ 组合再加一个修饰键，避免影响其他应用。"
        }
        return nil
    }
    static let defaults: [ShortcutAction: KeyShortcut] = [
        .single: KeyShortcut(keyCode: 18, modifiers: UInt32(controlKey | shiftKey)),
        .scrolling: KeyShortcut(keyCode: 19, modifiers: UInt32(controlKey | shiftKey)),
        .stop: KeyShortcut(keyCode: 47, modifiers: UInt32(controlKey | shiftKey))
    ]
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults: UserDefaults
    @Published var autoPinSingle: Bool { didSet { defaults.set(autoPinSingle, forKey: "autoPinSingle") } }
    @Published var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: "historyRetention") } }
    @Published private(set) var shortcuts: [ShortcutAction: KeyShortcut]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoPinSingle = defaults.bool(forKey: "autoPinSingle")
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "historyRetention") ?? "") ?? .exported
        if let data = defaults.data(forKey: "captureShortcuts.v1"), let decoded = try? JSONDecoder().decode([String: KeyShortcut].self, from: data) {
            shortcuts = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let action = ShortcutAction(rawValue: key), value.validationMessage == nil else { return nil }
                return (action, value)
            })
        } else { shortcuts = KeyShortcut.defaults }
    }
    func shortcut(for action: ShortcutAction) -> KeyShortcut? { shortcuts[action] }
    func setShortcut(_ action: ShortcutAction, to value: KeyShortcut?) {
        shortcuts[action] = value; persist()
    }
    func replaceShortcuts(_ values: [ShortcutAction: KeyShortcut]) { shortcuts = values; persist() }
    private func persist() {
        let values = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "captureShortcuts.v1") }
    }
}
