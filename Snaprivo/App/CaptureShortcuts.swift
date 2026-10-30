import AppKit
import Carbon
import Observation
import SnagForgeDomain
import SwiftUI

/// Both capture variants intentionally launch the same automatic window/region selector.
enum CaptureAction: UInt32, CaseIterable, Codable, Sendable {
    case display = 1, region, window, delayedRegion, repeatLast, text, code
    var title: String {
        switch self {
        case .display: String(localized: "Bildschirm aufnehmen")
        case .region: String(localized: "Neue Aufnahme")
        case .window: String(localized: "Neue Aufnahme (alternativ)")
        case .delayedRegion: String(localized: "Aufnahme mit 3 Sekunden Vorlauf")
        case .repeatLast: String(localized: "Letzten Bereich erneut aufnehmen")
        case .text: String(localized: "Text direkt erfassen")
        case .code: String(localized: "QR-Code scannen")
        }
    }
    var symbol: String {
        switch self { case .display: "display"; case .region: "viewfinder"; case .window: "viewfinder"; case .delayedRegion: "timer"; case .repeatLast: "arrow.clockwise"; case .text: "text.viewfinder"; case .code: "qrcode.viewfinder" }
    }
    var defaultShortcut: CaptureShortcut {
        let key = switch self { case .display: kVK_ANSI_1; case .region: kVK_ANSI_2; case .window: kVK_ANSI_3; case .delayedRegion: kVK_ANSI_5; case .repeatLast: kVK_ANSI_6; case .text: kVK_ANSI_7; case .code: kVK_ANSI_8 }
        return CaptureShortcut(keyCode: UInt32(key), modifiers: UInt32(controlKey | shiftKey))
    }
    func configuration(using previous: CaptureConfiguration) -> CaptureConfiguration {
        CaptureConfiguration(media: .image, source: self == .display ? .display : .automatic,
                             includesCursor: previous.includesCursor,
                             delaySeconds: self == .delayedRegion ? 3 : previous.delaySeconds)
    }
}

/// Hardware key codes preserve the actual chosen key. Labels follow the current keyboard layout.
struct CaptureShortcut: Codable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    var isValid: Bool {
        Self.supportedKeys.contains(keyCode) && modifiers & ~Self.allowedModifiers == 0 &&
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }
    static let supportedKeys: Set<UInt32> = Set((0...50).map(UInt32.init)).union([
        65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92,
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126
    ])
    @MainActor var label: String { modifierLabel + keyName }
    var modifierLabel: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "")
    }
    @MainActor var keyName: String {
        if let special = Self.specialKeys[keyCode] { return special.label }
        return translatedKey()?.uppercased() ?? String(localized: "Taste \(keyCode)")
    }
    @MainActor var keyboardShortcut: KeyboardShortcut? {
        let character = Self.specialKeys[keyCode]?.key ?? translatedKey()?.lowercased().first
        guard let character else { return nil }
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags, localization: .withoutMirroring)
    }
    @MainActor private func translatedKey() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0, count = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, characters.count, &count, &characters)
        guard status == noErr, count > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: count)
    }
    private static let specialKeys: [UInt32: (label: String, key: Character)] = {
        var values: [UInt32: (String, Character)] = [36: ("↩", "\r"), 48: ("⇥", "\t"), 49: (String(localized: "Leertaste"), " "),
            76: ("⌤", "\u{03}"), 115: ("↖", "\u{F729}"), 116: ("⇞", "\u{F72C}"), 117: ("⌦", "\u{F728}"),
            119: ("↘", "\u{F72B}"), 121: ("⇟", "\u{F72D}"), 123: ("←", "\u{F702}"), 124: ("→", "\u{F703}"),
            125: ("↓", "\u{F701}"), 126: ("↑", "\u{F700}")]
        for (index, code) in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106].enumerated() {
            values[UInt32(code)] = ("F\(index + 1)", Character(UnicodeScalar(0xF704 + index)!))
        }
        return values
    }()
    /// Keep document/editor commands and common macOS navigation available.
    @MainActor var isReserved: Bool {
        let key = translatedKey()?.lowercased()
        if modifiers == UInt32(cmdKey) {
            if [kVK_Tab, kVK_Space].contains(Int(keyCode)) { return true }
            if let key { return ["a", "c", "d", "x", "v", "z", "q", "w", "h", "m", "o", "s", "k", ",", "0", "1", "-", "=", "+"].contains(key) }
            return [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_X, kVK_ANSI_V, kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_W,
                    kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_O, kVK_ANSI_S, kVK_ANSI_K, kVK_ANSI_Comma,
                    kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_Tab, kVK_Space].contains(Int(keyCode))
        }
        if modifiers == UInt32(cmdKey | shiftKey) {
            if [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(Int(keyCode)) { return true }
            if let key { return ["z", "e", "q"].contains(key) }
            return [kVK_ANSI_Z, kVK_ANSI_E, kVK_ANSI_Q].contains(Int(keyCode))
        }
        return (keyCode == UInt32(kVK_Space) && modifiers == UInt32(cmdKey | optionKey)) ||
               ((key == "q" || (key == nil && keyCode == UInt32(kVK_ANSI_Q))) && modifiers == UInt32(cmdKey | controlKey))
    }
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0) |
        (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
}

@MainActor protocol CaptureHotKeyRegistering: AnyObject {
    func start(handler: @escaping @MainActor (CaptureAction) -> Void) -> Bool
    func register(_ shortcut: CaptureShortcut, for action: CaptureAction) -> OSStatus
    func unregisterAll()
    func stop()
}

/// Discrete public HIToolbox hotkeys; no global keyboard monitor or extra TCC permission.
@MainActor final class CarbonCaptureHotKeys: CaptureHotKeyRegistering {
    private var references: [CaptureAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var onAction: (@MainActor (CaptureAction) -> Void)?
    private static let signature: OSType = 0x534E4147 // SNAG
    func start(handler: @escaping @MainActor (CaptureAction) -> Void) -> Bool {
        onAction = handler
        if eventHandler != nil { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            return MainActor.assumeIsolated {
                guard id.signature == CarbonCaptureHotKeys.signature, let action = CaptureAction(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
                Unmanaged<CarbonCaptureHotKeys>.fromOpaque(context).takeUnretainedValue().onAction?(action)
                return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        return status == noErr
    }
    func register(_ shortcut: CaptureShortcut, for action: CaptureAction) -> OSStatus {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                        EventHotKeyID(signature: Self.signature, id: action.rawValue),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        if status == noErr, let reference { references[action] = reference }
        return status
    }
    func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }; references.removeAll()
    }
    func stop() {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }; eventHandler = nil; onAction = nil
    }
}

@MainActor @Observable
final class GlobalCaptureShortcuts {
    private(set) var isEnabled: Bool
    private(set) var bindings: [CaptureAction: CaptureShortcut]
    private(set) var unavailable: [CaptureAction] = []
    private(set) var recordingAction: CaptureAction?
    private(set) var recordingError: String?
    private(set) var preferencesError: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registrar: any CaptureHotKeyRegistering
    @ObservationIgnored private var onAction: (@MainActor (CaptureAction) -> Void)?
    private static let storageKey = "capture.shortcuts.v1"
    private struct Stored: Codable {
        let version: Int
        let entries: [Entry]
        struct Entry: Codable { let action: CaptureAction; let shortcut: CaptureShortcut? }
    }
    init(defaults: UserDefaults = .standard, registrar: (any CaptureHotKeyRegistering)? = nil) {
        self.defaults = defaults; self.registrar = registrar ?? CarbonCaptureHotKeys()
        isEnabled = defaults.object(forKey: "capture.globalShortcutsEnabled") as? Bool ?? true
        bindings = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.defaultShortcut) })
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                let stored = try JSONDecoder().decode(Stored.self, from: data)
                let expected: Set<CaptureAction> = stored.version == 1 ? [.display, .region, .window, .delayedRegion] : stored.version == 2 ? [.display, .region, .window, .delayedRegion, .repeatLast, .text] : Set(CaptureAction.allCases)
                guard (1...3).contains(stored.version),
                      Set(stored.entries.map(\.action)) == expected,
                      stored.entries.count == expected.count else { throw CocoaError(.coderReadCorrupt) }
                var decoded: [CaptureAction: CaptureShortcut] = [:]
                for entry in stored.entries {
                    if let value = entry.shortcut {
                        guard value.isValid, !value.isReserved, !decoded.values.contains(value) else { throw CocoaError(.coderReadCorrupt) }
                        decoded[entry.action] = value
                    }
                }
                bindings = decoded
                // Preserve deliberate removals and user keys while adding new actions.
                for action in CaptureAction.allCases where !expected.contains(action) && !bindings.values.contains(action.defaultShortcut) {
                    bindings[action] = action.defaultShortcut
                }
            } catch { preferencesError = String(localized: "Gespeicherte Tastenkürzel konnten nicht gelesen werden. Es gelten die Standardkürzel, bis du sie neu festlegst.") }
        }
    }
    func start(onAction: @escaping @MainActor (CaptureAction) -> Void) {
        self.onAction = onAction; rebuildRegistrations()
    }
    /// Existing user capture bindings take precedence over the editor's optional navigation keys.
    func editorNavigationShortcut(_ direction: Int) -> KeyboardShortcut? {
        guard direction == -1 || direction == 1 else { return nil }
        let candidate = CaptureShortcut(keyCode: direction == -1 ? 123 : 124, modifiers: UInt32(cmdKey | optionKey))
        return bindings.values.contains(candidate) ? nil : candidate.keyboardShortcut
    }
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled; defaults.set(enabled, forKey: "capture.globalShortcutsEnabled")
        recordingAction = nil; recordingError = nil; rebuildRegistrations()
    }
    func beginRecording(_ action: CaptureAction) {
        recordingAction = action; recordingError = nil; registrar.unregisterAll()
    }
    func cancelRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil; recordingError = nil; rebuildRegistrations()
    }
    /// Probe registration before replacing the old binding. Failed attempts never persist.
    @discardableResult func setShortcut(_ candidate: CaptureShortcut?, for action: CaptureAction) -> Bool {
        if let candidate {
            if !candidate.isValid { recordingError = String(localized: "Verwende ⌘, ⌥ oder ⌃ zusammen mit einer Taste."); return false }
            if candidate.isReserved { recordingError = String(localized: "Dieses Kürzel ist für macOS oder einen Editorbefehl reserviert."); return false }
            if let duplicate = bindings.first(where: { $0.key != action && $0.value == candidate }) {
                recordingError = String(localized: "Dieses Kürzel wird bereits für „\(duplicate.key.title)“ verwendet."); return false
            }
        }
        registrar.unregisterAll()
        defer { rebuildRegistrations() }
        if let candidate, isEnabled, onAction != nil {
            guard prepareHandler(), registrar.register(candidate, for: action) == noErr else {
                recordingError = String(localized: "Dieses Kürzel ist nicht verfügbar. Wähle eine andere Kombination; das bisherige Kürzel bleibt erhalten.")
                return false
            }
            registrar.unregisterAll()
        }
        bindings[action] = candidate
        recordingAction = nil; recordingError = nil
        persist()
        return true
    }
    func restoreDefaults() {
        recordingAction = nil; recordingError = nil
        bindings = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.defaultShortcut) })
        persist(); rebuildRegistrations()
    }
    func retryRegistration() { rebuildRegistrations() }
    func stop() { recordingAction = nil; registrar.stop(); unavailable = [] }
    private func persist() {
        let stored = Stored(version: 3, entries: CaptureAction.allCases.map { .init(action: $0, shortcut: bindings[$0]) })
        do { defaults.set(try JSONEncoder().encode(stored), forKey: Self.storageKey); preferencesError = nil }
        catch { preferencesError = String(localized: "Die Tastenkürzel konnten nicht gespeichert werden.") }
    }
    private func prepareHandler() -> Bool {
        registrar.start { [weak self] action in
            guard let self, self.isEnabled, self.recordingAction == nil, self.bindings[action] != nil else { return }
            self.onAction?(action)
        }
    }
    private func rebuildRegistrations() {
        registrar.unregisterAll(); unavailable = []
        guard isEnabled, recordingAction == nil, onAction != nil else { return }
        guard prepareHandler() else { unavailable = CaptureAction.allCases.filter { bindings[$0] != nil }; return }
        for action in CaptureAction.allCases {
            if let value = bindings[action], registrar.register(value, for: action) != noErr { unavailable.append(action) }
        }
    }
}
