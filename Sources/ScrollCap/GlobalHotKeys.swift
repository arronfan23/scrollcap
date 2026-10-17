import AppKit
import Carbon

@MainActor
protocol HotKeyRegistering: AnyObject {
    /// A failed replacement must leave the existing registration intact.
    func set(_ shortcut: KeyShortcut?, for action: ShortcutAction) -> OSStatus
    func clear()
}

@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var installationStatus: OSStatus = noErr
    var onAction: ((ShortcutAction) -> Void)?
    private let signature: OSType = 0x534D4F43 // SMOC
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        installationStatus = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == owner.signature, let action = ShortcutAction.event(identifier.id) else { return OSStatus(eventNotHandledErr) }
                owner.onAction?(action); return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func set(_ shortcut: KeyShortcut?, for action: ShortcutAction) -> OSStatus {
        guard let shortcut else {
            if let previous = references.removeValue(forKey: action) { UnregisterEventHotKey(previous) }
            return noErr
        }
        guard installationStatus == noErr else { return installationStatus }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: signature, id: action.eventID),
                                        GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard result == noErr, let replacement else { return result == noErr ? OSStatus(paramErr) : result }
        if let previous = references[action] { UnregisterEventHotKey(previous) }
        references[action] = replacement
        return noErr
    }
    func clear() { references.values.forEach { UnregisterEventHotKey($0) }; references.removeAll() }
    deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    @Published private(set) var errors: [ShortcutAction: String] = [:]
    private let preferences: AppPreferences
    private let registrar: HotKeyRegistering
    private var registered: Set<ShortcutAction> = []
    private var suspended = false
    var onAction: ((ShortcutAction) -> Void)?
    init(preferences: AppPreferences, registrar: HotKeyRegistering? = nil) {
        self.preferences = preferences; self.registrar = registrar ?? CarbonHotKeyRegistrar()
        if let carbon = self.registrar as? CarbonHotKeyRegistrar {
            carbon.onAction = { [weak self] action in guard let self, !self.suspended else { return }; self.onAction?(action) }
        }
        registerCurrent()
    }
    @discardableResult
    func update(_ action: ShortcutAction, to value: KeyShortcut?) -> String? {
        if let value {
            if let message = value.validationMessage { return message }
            if let other = ShortcutAction.allCases.first(where: { $0 != action && preferences.shortcut(for: $0) == value }) {
                return "这个快捷键已用于「\(other.title)」，请换一组。"
            }
        }
        if preferences.shortcut(for: action) == value && (registered.contains(action) || value == nil) { return nil }
        let result = suspended ? noErr : registrar.set(value, for: action)
        guard result == noErr else { return Self.message(result) }
        preferences.setShortcut(action, to: value); errors[action] = nil
        if value == nil { registered.remove(action) } else if !suspended { registered.insert(action) }
        return nil
    }
    func restoreDefaults() -> String? {
        let previous = preferences.shortcuts
        registrar.clear(); registered.removeAll()
        var failed: String?
        for action in ShortcutAction.allCases {
            if let value = KeyShortcut.defaults[action], !suspended {
                let result = registrar.set(value, for: action)
                if result != noErr { failed = "「\(action.title)」的默认组合不可用：\(Self.message(result))"; break }
            }
        }
        if let failed { registrar.clear(); preferences.replaceShortcuts(previous); registerCurrent(); return failed }
        preferences.replaceShortcuts(KeyShortcut.defaults); errors.removeAll()
        registered = suspended ? [] : Set(ShortcutAction.allCases)
        return nil
    }
    func suspendRecording(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value { registrar.clear(); registered.removeAll() } else { registerCurrent() }
    }
    func shutdown() { registrar.clear(); registered.removeAll() }
    private func registerCurrent() {
        guard !suspended else { return }
        errors.removeAll()
        for action in ShortcutAction.allCases {
            guard let shortcut = preferences.shortcut(for: action) else { continue }
            let result = registrar.set(shortcut, for: action)
            if result == noErr { registered.insert(action) } else { errors[action] = Self.message(result) }
        }
    }
    private static func message(_ result: OSStatus) -> String {
        result == eventHotKeyExistsErr ? "这个组合已被系统或其他应用占用，请换一组。" : "快捷键注册失败（\(result)），请换一组再试。"
    }
}
