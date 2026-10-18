import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let action: CaptureAction
    let shortcuts: GlobalCaptureShortcuts
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let view = ShortcutRecorderButton(action: action, shortcuts: shortcuts)
        view.refresh()
        return view
    }
    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        _ = shortcuts.bindings; _ = shortcuts.recordingAction; _ = shortcuts.isEnabled
        view.refresh()
    }
    static func dismantleNSView(_ view: ShortcutRecorderButton, coordinator: ()) { view.endRecording() }
}

@MainActor final class ShortcutRecorderButton: NSButton {
    let captureAction: CaptureAction
    let shortcuts: GlobalCaptureShortcuts
    private var monitor: Any?
    private weak var observedWindow: NSWindow?
    override var acceptsFirstResponder: Bool { true }
    init(action: CaptureAction, shortcuts: GlobalCaptureShortcuts) {
        captureAction = action; self.shortcuts = shortcuts
        super.init(frame: .zero)
        bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self; self.action = #selector(beginRecording)
        setAccessibilityIdentifier("settings.shortcut.\(action.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
        if window == nil { endRecording() }
        observedWindow = window
        if let window { NotificationCenter.default.addObserver(self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: window) }
    }
    @objc private func windowResigned() { endRecording() }
    @objc func beginRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        shortcuts.beginRecording(captureAction)
        if monitor == nil {
            // Only this app's events, during explicit recording; no global input monitoring.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, event.window === self.window, self.window?.isKeyWindow == true else { return false }
                    return self.handleRecordingEvent(event)
                }
                return consumed ? nil : event
            }
        }
        refresh()
    }
    func refresh() {
        let recording = shortcuts.recordingAction == captureAction
        if !recording { removeMonitor() }
        title = recording ? String(localized: "Kürzel eingeben …") : (shortcuts.bindings[captureAction]?.label ?? String(localized: "Kürzel festlegen …"))
        setAccessibilityLabel("\(captureAction.title): \(title)")
        setAccessibilityHelp(recording ? String(localized: "Tastenkombination drücken. Escape bricht ab, Rückschritt entfernt das Kürzel.") : String(localized: "Klicken, um ein eigenes Aufnahmekürzel festzulegen."))
    }
    /// Consume recorded keys before menus, document commands or the editor receive them.
    @discardableResult func handleRecordingEvent(_ event: NSEvent) -> Bool {
        guard shortcuts.recordingAction == captureAction else { return false }
        if event.type == .flagsChanged {
            let value = CaptureShortcut(keyCode: 0, modifiers: CaptureShortcut.modifiers(from: event.modifierFlags)).modifierLabel
            title = value.isEmpty ? String(localized: "Kürzel eingeben …") : value + " …"
            return true
        }
        guard event.type == .keyDown else { return false }
        if event.isARepeat { return true }
        if event.keyCode == UInt16(kVK_Escape) { endRecording(); return true }
        if event.keyCode == UInt16(kVK_Tab), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            endRecording(); return false
        }
        let clear = event.keyCode == UInt16(kVK_Delete) && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        let candidate = clear ? nil : CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: CaptureShortcut.modifiers(from: event.modifierFlags))
        if shortcuts.setShortcut(candidate, for: captureAction) { removeMonitor(); refresh() }
        return true
    }
    func endRecording() {
        if shortcuts.recordingAction == captureAction { shortcuts.cancelRecording() }
        removeMonitor(); refresh()
    }
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    }
    override func resignFirstResponder() -> Bool { endRecording(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        if !handleRecordingEvent(event) { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleRecordingEvent(event) || super.performKeyEquivalent(with: event)
    }
}
