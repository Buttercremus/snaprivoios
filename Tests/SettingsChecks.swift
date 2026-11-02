import AppKit
import Carbon
import SwiftUI
import SnagForgeDomain

@MainActor final class TestHotKeys: CaptureHotKeyRegistering {
    var active: [CaptureAction: CaptureShortcut] = [:]
    var blocked: Set<CaptureShortcut> = []
    var onAction: (@MainActor (CaptureAction) -> Void)?
    func start(handler: @escaping @MainActor (CaptureAction) -> Void) -> Bool { onAction = handler; return true }
    func register(_ shortcut: CaptureShortcut, for action: CaptureAction) -> OSStatus {
        guard !blocked.contains(shortcut), !active.values.contains(shortcut) else { return OSStatus(-9878) }
        active[action] = shortcut; return noErr
    }
    func unregisterAll() { active = [:] }
    func stop() { unregisterAll(); onAction = nil }
}

@main struct SettingsChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let suite = "SnagForge-Settings-Test-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        checkLanguage(defaults: defaults, suite: suite)
        let preferences = AppPreferences(defaults: defaults)
        precondition(Array(preferences.imageToolbarActions.prefix(4)) == [.copy, .savePNG, .share, .pin])
        precondition(preferences.extraToolbarTools == [.recognizeText, .resize, .colorPicker, .insertImage, .presentation, .transform, .scanCode])
        defaults.set(["resize", "copy", "savePNG", "recognizeText", "share", "openWith", "pin", "colorPicker", "insertImage", "output"], forKey: "editor.toolbarActions.v1")
        precondition(Array(AppPreferences(defaults: defaults).imageToolbarActions.prefix(4)) == [.copy, .savePNG, .share, .openWith])
        defaults.removeObject(forKey: "editor.toolbarActions.v1")


        precondition(!preferences.completedOnboarding && preferences.dismissedEditorHints.isEmpty)
        preferences.completedOnboarding = true
        preferences.dismissedEditorHints.insert("selection")
        let restoredIntroduction = AppPreferences(defaults: defaults)
        precondition(restoredIntroduction.completedOnboarding && restoredIntroduction.dismissedEditorHints == ["selection"])
        restoredIntroduction.dismissedEditorHints.formUnion(["firstAnnotation", "crop", "redaction", "filmstripMultiCopy"])
        let restoredHints = AppPreferences(defaults: defaults)
        precondition(restoredHints.completedOnboarding && restoredHints.dismissedEditorHints == ["selection", "firstAnnotation", "crop", "redaction", "filmstripMultiCopy"])
        restoredIntroduction.dismissedEditorHints = []
        precondition(AppPreferences(defaults: defaults).dismissedEditorHints.isEmpty)
        precondition(preferences.toolbarSize == .standard && preferences.captureDelay == 0 && !preferences.copyAfterCapture
                     && !preferences.capturesImmediately, "Immediate capture must start off; the confirmation bar stays the default")
        precondition(preferences.automaticallyFitsImage, "Existing installations must keep fit as their default")
        preferences.automaticallyFitsImage = false
        precondition(!preferences.videoSystemAudio && !preferences.videoMicrophone && !preferences.videoMouseClicks)
        precondition(!preferences.opensVideoEditorAfterCapture)
        preferences.opensVideoEditorAfterCapture = true
        preferences.videoSystemAudio = true; preferences.videoMicrophone = true; preferences.videoMouseClicks = true
        preferences.toolbarSize = .large; preferences.captureDelay = 5; preferences.includesCursor = true; preferences.copyAfterCapture = true
        preferences.capturesImmediately = true
        let restored = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(restored.videoSystemAudio && restored.videoMicrophone && restored.videoMouseClicks)
        precondition(restored.opensVideoEditorAfterCapture)
        precondition(restored.toolbarSize == .large && restored.captureDelay == 5 && restored.includesCursor && restored.copyAfterCapture
                     && restored.capturesImmediately, "Immediate capture was not restored")
        precondition(!restored.automaticallyFitsImage, "Actual-pixel opening preference did not survive restart")
        checkToolbarOrder(defaults: defaults, suite: suite)
        checkToolbarVisibility(defaults: defaults, suite: suite)
        checkGroupedShapesMigration()
        for action in CaptureAction.allCases {
            let config = action.configuration(using: restored.captureConfiguration)
            let videos: Set<CaptureAction> = [.videoRegion, .videoDisplay, .videoWindow]
            let source: CaptureSource = switch action {
            case .display, .videoDisplay: .display
            case .videoWindow: .window
            case .videoRegion, .scrolling: .region
            default: .automatic
            }
            precondition(action.isVideo == videos.contains(action))
            precondition(config.includesCursor && config.media == (videos.contains(action) ? .video : .image)
                         && config.delaySeconds == (action == .delayedRegion ? 3 : 5) && config.source == source)
        }
        let defaultCount = 8
        let registrar = TestHotKeys(), shortcuts = GlobalCaptureShortcuts(defaults: defaults, registrar: registrar)
        var actions: [CaptureAction] = []
        shortcuts.start { actions.append($0) }
        precondition(registrar.active.count == defaultCount)
        let original = shortcuts.bindings[.region]!
        let custom = CaptureShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey | shiftKey))
        shortcuts.beginRecording(.region)
        precondition(registrar.active.isEmpty)
        registrar.onAction?(.region); precondition(actions.isEmpty, "Recording triggered a capture")
        precondition(!shortcuts.setShortcut(.init(keyCode: 0, modifiers: UInt32(shiftKey)), for: .region))
        // Editor commands follow the keyboard layout: German Z is on the ANSI Y key.
        let logicalZ = CaptureShortcut.supportedKeys.first { CaptureShortcut(keyCode: $0, modifiers: UInt32(cmdKey)).keyName == "Z" }!
        precondition(!shortcuts.setShortcut(.init(keyCode: logicalZ, modifiers: UInt32(cmdKey)), for: .region))
        precondition(CaptureShortcut(keyCode: logicalZ, modifiers: UInt32(cmdKey | shiftKey)).isReserved)
        precondition(!shortcuts.setShortcut(.init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey)), for: .region))
        precondition(!shortcuts.setShortcut(shortcuts.bindings[.display], for: .region))
        registrar.blocked = [custom]
        precondition(!shortcuts.setShortcut(custom, for: .region) && shortcuts.bindings[.region] == original)
        precondition(defaults.data(forKey: "capture.shortcuts.v1") == nil, "Rejected shortcut was persisted")
        shortcuts.cancelRecording(); precondition(registrar.active[.region] == original)
        registrar.blocked = []
        shortcuts.beginRecording(.region); precondition(shortcuts.setShortcut(custom, for: .region))
        precondition(registrar.active[.region] == custom && !custom.label.isEmpty && custom.keyboardShortcut != nil)
        registrar.onAction?(.region); precondition(actions == [.region])
        precondition(shortcuts.setShortcut(nil, for: .window))
        let loaded = GlobalCaptureShortcuts(defaults: UserDefaults(suiteName: suite)!, registrar: TestHotKeys())
        precondition(loaded.bindings[.region] == custom && loaded.bindings[.window] == nil)
        shortcuts.setEnabled(false); precondition(registrar.active.isEmpty)
        shortcuts.setEnabled(true); precondition(registrar.active.count == defaultCount - 1)
        registrar.blocked = [custom]; shortcuts.retryRegistration()
        precondition(shortcuts.unavailable == [.region])
        registrar.blocked = []; shortcuts.retryRegistration(); precondition(shortcuts.unavailable.isEmpty)
        shortcuts.restoreDefaults(); precondition(shortcuts.bindings.count == defaultCount && shortcuts.bindings[.region] == original)
        // Native recorder: consume protected commands, Escape/Tab cancel, Delete clears.
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 80), styleMask: .titled, backing: .buffered, defer: false)
        let recorder = ShortcutRecorderButton(action: .region, shortcuts: shortcuts)
        window.contentView = recorder
        func key(_ code: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                             context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: UInt16(code))!
        }
        recorder.beginRecording()
        precondition(recorder.handleRecordingEvent(key(kVK_ANSI_Q, .command)) && shortcuts.recordingAction == .region)
        precondition(shortcuts.bindings[.region] == original && shortcuts.recordingError != nil)
        recorder.handleRecordingEvent(key(kVK_Escape)); precondition(shortcuts.recordingAction == nil && registrar.active.count == defaultCount)
        recorder.beginRecording(); precondition(!recorder.handleRecordingEvent(key(kVK_Tab)))
        precondition(shortcuts.recordingAction == nil)
        recorder.beginRecording(); recorder.handleRecordingEvent(key(kVK_Delete))
        precondition(shortcuts.bindings[.region] == nil && registrar.active.count == defaultCount - 1)
        recorder.beginRecording(); window.contentView = NSView()
        precondition(shortcuts.recordingAction == nil && registrar.active.count == defaultCount - 1)
        shortcuts.restoreDefaults(); shortcuts.stop()
        // Real public API: the second owner must fail, and succeed after release.
        let first = CarbonCaptureHotKeys(), second = CarbonCaptureHotKeys()
        let rare = CaptureShortcut(keyCode: UInt32(kVK_F16), modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        defer { first.stop(); second.stop() }
        precondition(first.start { _ in } && second.start { _ in })
        precondition(first.register(rare, for: .region) == noErr)
        precondition(second.register(rare, for: .region) != noErr, "Exclusive registration conflict was missed")
        first.unregisterAll(); precondition(second.register(rare, for: .region) == noErr)
        second.stop()
        // Version 1 preserves deliberately cleared bindings and existing key ownership.
        let legacySuite = "Snaprivo-LegacyShortcuts-\(UUID())", legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        let legacyEntries: [[String: Any]] = [
            ["action": CaptureAction.display.rawValue, "shortcut": ["keyCode": CaptureAction.display.requiredDefault.keyCode, "modifiers": CaptureAction.display.requiredDefault.modifiers]],
            ["action": CaptureAction.region.rawValue, "shortcut": ["keyCode": CaptureAction.repeatLast.requiredDefault.keyCode, "modifiers": CaptureAction.repeatLast.requiredDefault.modifiers]],
            ["action": CaptureAction.window.rawValue, "shortcut": NSNull()],
            ["action": CaptureAction.delayedRegion.rawValue, "shortcut": NSNull()]
        ]
        legacyDefaults.set(try JSONSerialization.data(withJSONObject: ["version": 1, "entries": legacyEntries]), forKey: "capture.shortcuts.v1")
        let migrated = GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys())
        precondition(migrated.preferencesError == nil && migrated.bindings[.window] == nil && migrated.bindings[.delayedRegion] == nil)
        precondition(migrated.bindings[.region] == CaptureAction.repeatLast.requiredDefault && migrated.bindings[.repeatLast] == nil && migrated.bindings[.text] == CaptureAction.text.requiredDefault)
        // Invalid stored data is reported and never silently rewritten during load.
        let version2Entries: [[String: Any]] = [CaptureAction.display, .region, .window, .delayedRegion, .repeatLast, .text].map { action in
            ["action": action.rawValue, "shortcut": action == .text ? NSNull() : ["keyCode": (action == .region ? CaptureAction.code.requiredDefault : action.requiredDefault).keyCode,
                "modifiers": action.requiredDefault.modifiers]]
        }
        legacyDefaults.set(try JSONSerialization.data(withJSONObject: ["version": 2, "entries": version2Entries]), forKey: "capture.shortcuts.v1")
        let migrated2 = GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys())
        precondition(migrated2.preferencesError == nil && migrated2.bindings[.text] == nil && migrated2.bindings[.code] == nil)
        precondition(migrated2.bindings[.region] == CaptureAction.code.requiredDefault)
        // Version 3 gains the instant shortcut only where its default key is still free; saving writes version 5.
        func version3(region: CaptureShortcut) throws -> GlobalCaptureShortcuts {
            let entries: [[String: Any]] = [CaptureAction.display, .region, .window, .delayedRegion, .repeatLast, .text, .code].map { action in
                let shortcut = action == .region ? region : action.requiredDefault
                return ["action": action.rawValue, "shortcut": ["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers]]
            }
            legacyDefaults.set(try JSONSerialization.data(withJSONObject: ["version": 3, "entries": entries]), forKey: "capture.shortcuts.v1")
            return GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys())
        }
        let instant = CaptureAction.instantRegion.requiredDefault
        precondition(!instant.isReserved && instant != CaptureAction.region.requiredDefault)
        let gained = try version3(region: CaptureAction.region.requiredDefault)
        precondition(gained.preferencesError == nil && gained.bindings[.instantRegion] == instant)
        let occupied = try version3(region: instant)
        precondition(occupied.preferencesError == nil && occupied.bindings[.region] == instant && occupied.bindings[.instantRegion] == nil)
        occupied.restoreDefaults()
        let saved = try JSONSerialization.jsonObject(with: legacyDefaults.data(forKey: "capture.shortcuts.v1")!) as! [String: Any]
        precondition(saved["version"] as? Int == 5 && (saved["entries"] as? [Any])?.count == CaptureAction.allCases.count)
        precondition(GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys()).bindings[.instantRegion] == instant)
        // Version 4 keeps custom and deliberately removed keys; the new starts stay unassigned.
        let added: [CaptureAction] = [.scrolling, .videoRegion, .videoDisplay, .videoWindow]
        precondition(added.allSatisfy { $0.defaultShortcut == nil })
        precondition(Set(CaptureAction.menuActions + [.window]) == Set(CaptureAction.allCases)
                     && Set(CaptureAction.menuActions).count == CaptureAction.menuActions.count,
                     "Menu/settings starts drifted or have duplicate entries")
        let version4Entries: [[String: Any]] = CaptureAction.allCases.filter { $0.rawValue <= 8 }.map { action in
            let shortcut = action == .region ? custom : action.requiredDefault
            return ["action": action.rawValue, "shortcut": action == .window ? NSNull() : ["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers]]
        }
        let version4 = try JSONSerialization.data(withJSONObject: ["version": 4, "entries": version4Entries])
        legacyDefaults.set(version4, forKey: "capture.shortcuts.v1")
        let newRegistrar = TestHotKeys(), upgraded = GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: newRegistrar)
        precondition(upgraded.preferencesError == nil && upgraded.bindings[.region] == custom && upgraded.bindings[.window] == nil)
        precondition(added.allSatisfy { upgraded.bindings[$0] == nil } && legacyDefaults.data(forKey: "capture.shortcuts.v1") == version4)
        var newlyTriggered: [CaptureAction] = []
        upgraded.start { newlyTriggered.append($0) }
        newRegistrar.onAction?(.videoRegion); precondition(newlyTriggered.isEmpty, "An unassigned new action ran")
        for (action, keyCode) in zip(added, [kVK_ANSI_S, kVK_ANSI_V, kVK_ANSI_D, kVK_ANSI_W]) {
            let shortcut = CaptureShortcut(keyCode: UInt32(keyCode), modifiers: UInt32(controlKey | optionKey | shiftKey))
            upgraded.beginRecording(action)
            precondition(upgraded.setShortcut(shortcut, for: action) && newRegistrar.active[action] == shortcut)
            newRegistrar.onAction?(action)
        }
        precondition(newlyTriggered == added, "New video/scroll hotkeys did not dispatch their own source action")
        let videoDisplayKey = upgraded.bindings[.videoDisplay]
        precondition(!upgraded.setShortcut(custom, for: .videoDisplay) && upgraded.bindings[.videoDisplay] == videoDisplayKey,
                     "A new video shortcut stole an existing key")
        let reopened = GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys())
        precondition(reopened.preferencesError == nil && reopened.bindings == upgraded.bindings)
        precondition(upgraded.setShortcut(nil, for: .videoWindow))
        let removedVideo = GlobalCaptureShortcuts(defaults: legacyDefaults, registrar: TestHotKeys())
        precondition(removedVideo.bindings[.videoWindow] == nil && removedVideo.bindings[.videoRegion] == upgraded.bindings[.videoRegion])
        let format5 = try JSONSerialization.jsonObject(with: legacyDefaults.data(forKey: "capture.shortcuts.v1")!) as! [String: Any]
        precondition(format5["version"] as? Int == 5 && (format5["entries"] as? [Any])?.count == CaptureAction.allCases.count)
        upgraded.stop()
        let broken = Data("broken".utf8); defaults.set(broken, forKey: "capture.shortcuts.v1")
        let corrupt = GlobalCaptureShortcuts(defaults: defaults, registrar: TestHotKeys())
        precondition(corrupt.preferencesError != nil && corrupt.bindings.count == defaultCount && defaults.data(forKey: "capture.shortcuts.v1") == broken)
        try await checkCaptureCopy(defaults: defaults)
        try await StorageLocationChecks.run()
        print("Settings checks passed: preference restart, toolbar order/visibility, source configurations, shared menu starts, version 1–4 migration, unassigned video/scroll defaults, new hotkey dispatch/restart/removal, duplicate protection, transactional registration failure, recorder cancellation, real exclusive Carbon registration and screenshot-only automatic PNG copy.")
    }
    @MainActor static func checkToolbarOrder(defaults: UserDefaults, suite: String) {
        let preferences = AppPreferences(defaults: defaults)
        let tools = EditorToolItem.all.map(\.tool)
        let actions = EditorToolbarAction.allCases
        precondition(preferences.toolbarTools == tools && preferences.toolbarActions == actions)
        // Exercise native List moves in both directions and at either boundary.
        preferences.toolbarTools.move(fromOffsets: IndexSet(integer: tools.count - 1), toOffset: 0)
        preferences.toolbarActions.move(fromOffsets: IndexSet(integer: 1), toOffset: actions.count)
        let restored = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(restored.toolbarTools == preferences.toolbarTools && restored.toolbarActions == preferences.toolbarActions)
        precondition(restored.toolbarTools.first == .crop && restored.toolbarActions.last == actions[1])
        preferences.toolbarTools.move(fromOffsets: IndexSet(integer: 0), toOffset: tools.count)
        preferences.toolbarActions.move(fromOffsets: IndexSet(integer: actions.count - 1), toOffset: 1)
        precondition(preferences.toolbarTools == tools && preferences.toolbarActions == actions)
        // Missing/future items and duplicates must not lose or duplicate visible commands.
        defaults.set(["share", "future-action", "share", "copy"], forKey: "editor.toolbarActions.v1")
        defaults.set(["crop", "future-tool", "crop", "arrow"], forKey: "editor.toolbarTools.v1")
        let repaired = AppPreferences(defaults: defaults)
        precondition(repaired.toolbarActions == [.share, .copy] + actions.filter { $0 != .share && $0 != .copy })
        precondition(repaired.toolbarTools == [.crop, .arrow] + tools.filter { $0 != .crop && $0 != .arrow })
        precondition(Set(repaired.toolbarTools).count == tools.count && Set(repaired.toolbarActions).count == actions.count)
        repaired.toolbarTools = [.text, .text]
        repaired.toolbarActions = [.copy, .copy]
        precondition(repaired.toolbarTools == [.text] + tools.filter { $0 != .text })
        precondition(repaired.toolbarActions == [.copy] + actions.filter { $0 != .copy })
        repaired.resetToolbarOrder()
        let reset = AppPreferences(defaults: defaults)
        precondition(reset.toolbarTools == tools && reset.toolbarActions == actions && reset.copyAfterCapture)
    }
    @MainActor static func checkLanguage(defaults: UserDefaults, suite: String) {
        let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let preferences = AppPreferences(defaults: defaults, languageDomain: suite)
        precondition(preferences.language == .system && !preferences.requiresLanguageRestart)
        precondition(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        defaults.set("preserved", forKey: "language-test.other-setting")

        preferences.language = .english
        precondition(preferences.requiresLanguageRestart)
        precondition(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["en"])
        let restored = AppPreferences(defaults: UserDefaults(suiteName: suite)!, languageDomain: suite)
        precondition(restored.language == .english && !restored.requiresLanguageRestart)
        restored.language = .german
        precondition(restored.requiresLanguageRestart)
        precondition(AppPreferences(defaults: defaults, languageDomain: suite).language == .german)
        restored.language = .english
        precondition(!restored.requiresLanguageRestart, "Returning to the launch language must clear the restart notice")

        // Adopt an existing native macOS per-app override, including region tags.
        defaults.set(["de-DE"], forKey: "AppleLanguages")
        precondition(AppPreferences(defaults: defaults, languageDomain: suite).language == .german)
        defaults.set(["fr-FR", "en-GB"], forKey: "AppleLanguages")
        precondition(AppPreferences(defaults: defaults, languageDomain: suite).language == .english)
        restored.language = .system
        precondition(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        precondition(AppPreferences(defaults: defaults, languageDomain: suite).language == .system)
        precondition(defaults.string(forKey: "language-test.other-setting") == "preserved")
        precondition(UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] == globalLanguages)
        defaults.removeObject(forKey: "language-test.other-setting")
    }
    @MainActor static func checkToolbarVisibility(defaults: UserDefaults, suite: String) {
        let preferences = AppPreferences(defaults: defaults)
        let tools = EditorToolItem.all.map(\.tool), actions = EditorToolbarAction.allCases
        precondition(preferences.visibleToolbarTools == tools && preferences.visibleToolbarActions == actions)
        preferences.hiddenToolbarTools = [.arrow, .crop]
        preferences.hiddenToolbarActions = [.copy, .share]
        precondition(preferences.visibleToolbarTools == tools.filter { $0 != .arrow && $0 != .crop })
        precondition(preferences.visibleToolbarActions == actions.filter { $0 != .copy && $0 != .share })
        // Hidden icons stay in the settings/order, so showing them restores their chosen position.
        preferences.toolbarTools.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        preferences.toolbarActions.move(fromOffsets: IndexSet(integer: actions.firstIndex(of: .share)!), toOffset: 0)
        let restored = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(restored.hiddenToolbarTools == [.arrow, .crop] && restored.hiddenToolbarActions == [.copy, .share])
        precondition(restored.toolbarTools.first == .arrow && restored.toolbarActions.first == .share)
        precondition(restored.visibleToolbarTools.first == .selection && restored.visibleToolbarActions.first == .savePNG)
        restored.hiddenToolbarTools.remove(.arrow); restored.hiddenToolbarActions.remove(.share)
        precondition(restored.visibleToolbarTools.first == .arrow && restored.visibleToolbarActions.first == .share)
        // Allow an empty toolbar without losing any choices; restoring order keeps visibility separate.
        restored.hiddenToolbarTools = Set(tools); restored.hiddenToolbarActions = Set(actions)
        restored.resetToolbarOrder()
        let empty = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(empty.visibleToolbarTools.isEmpty && empty.visibleToolbarActions.isEmpty)
        precondition(empty.toolbarTools == tools && empty.toolbarActions == actions)
        empty.showAllToolbarItems()
        let shown = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(shown.visibleToolbarTools == tools && shown.visibleToolbarActions == actions && shown.copyAfterCapture)
        // Old settings default to all visible; future/duplicate values cannot hide other icons.
        defaults.set(["arrow", "future-tool", "arrow"], forKey: "editor.hiddenToolbarTools.v1")
        defaults.set(["share", "future-action", "share"], forKey: "editor.hiddenToolbarActions.v1")
        let repaired = AppPreferences(defaults: defaults)
        precondition(repaired.hiddenToolbarTools == [.arrow] && repaired.hiddenToolbarActions == [.share])
        repaired.showAllToolbarItems()
    }
    @MainActor static func checkGroupedShapesMigration() {
        let tools = EditorToolItem.all.map(\.tool)
        precondition(tools.filter { $0 == .rectangle }.count == 1 && !tools.contains(.ellipse))
        precondition(AnnotationTool.ellipse.toolbarTool == .rectangle)
        for oldHidden: [AnnotationTool] in [[], [.rectangle], [.ellipse], [.rectangle, .ellipse]] {
            let suite = "Snaprivo-GroupedShapes-\(UUID())", defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(["crop", "ellipse", "arrow", "rectangle", "text"], forKey: "editor.toolbarTools.v1")
            defaults.set(oldHidden.map(\.rawValue), forKey: "editor.hiddenToolbarTools.v1")
            let migrated = AppPreferences(defaults: defaults)
            precondition(Array(migrated.toolbarTools.prefix(4)) == [.crop, .rectangle, .arrow, .text],
                "Merging the shape entries lost the custom toolbar position")
            precondition(migrated.hiddenToolbarTools.contains(.rectangle) == (oldHidden.contains(.rectangle) && oldHidden.contains(.ellipse)),
                "Merging the shape entries lost an available shape tool")
            precondition(!migrated.toolbarTools.contains(.ellipse) && !migrated.hiddenToolbarTools.contains(.ellipse))
            // A later deliberate hide must survive restarts after the one-time migration.
            migrated.hiddenToolbarTools.insert(.rectangle)
            let reloaded = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
            precondition(reloaded.hiddenToolbarTools.contains(.rectangle) && reloaded.toolbarTools == migrated.toolbarTools)
            reloaded.toolbarTools = [.ellipse, .rectangle, .arrow]
            precondition(Array(reloaded.toolbarTools.prefix(2)) == [.rectangle, .arrow] && Set(reloaded.toolbarTools).count == tools.count)
        }
    }
    @MainActor static func checkCaptureCopy(defaults: UserDefaults) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Settings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard(name: NSPasteboard.Name("SnagForge-Settings-\(UUID())"))
        defer { board.releaseGlobally() }
        let context = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.orange.cgColor); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let image = context.makeImage()!, png = try EditorRenderer.png(image: image, objects: [])
        var copyCount = 0
        let workspace = WorkspaceModel(root: root, defaults: defaults, copyCapture: { editor in copyCount += 1; editor.copyPNG(to: board) })
        workspace.preferences.copyAfterCapture = true
        workspace.openScreenshot(image)
        for _ in 0..<1000 where workspace.isLoading || workspace.editor?.isExporting == true { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!workspace.isLoading && copyCount == 1 && board.data(forType: .png) == png)
        precondition(workspace.editor?.viewport.zoom == 1, "Workspace ignored the saved actual-pixel preference")
        workspace.preferences.automaticallyFitsImage = true
        let imported = root.appendingPathComponent("synthetic.png"); try png.write(to: imported)
        workspace.openImage(at: imported)
        for _ in 0..<1000 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(copyCount == 1 && !workspace.isLoading && workspace.importError == nil)
        precondition(workspace.editor?.viewport.zoom == nil, "New editor ignored the saved fit preference")
        workspace.preferences.copyAfterCapture = false; workspace.openScreenshot(image)
        for _ in 0..<1000 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(copyCount == 1 && workspace.items.count == 3 && !workspace.isLoading)
        // A previous project's write failure must not suppress the new screenshot's copy.
        let previous = workspace.editor!
        let blocked = root.appendingPathComponent("\(previous.document.id.uuidString).snagforge/Revisions/\(previous.document.revision + 1).json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        previous.commit([EditorObject(kind: .arrow, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 60, y: 40))])
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let nextImage = context.makeImage()!, nextPNG = try EditorRenderer.png(image: nextImage, objects: [])
        workspace.preferences.copyAfterCapture = true
        workspace.openScreenshot(nextImage)
        for _ in 0..<1000 where workspace.isLoading || board.data(forType: .png) != nextPNG { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!workspace.isLoading && copyCount == 2 && board.data(forType: .png) == nextPNG)
        precondition(workspace.editor === previous && previous.isDirty && previous.saveError != nil && workspace.items.count == 4)
        try FileManager.default.removeItem(at: blocked)
        let saved = await workspace.flushBeforeQuitting(); precondition(saved)
    }
}

private extension CaptureAction {
    var requiredDefault: CaptureShortcut { defaultShortcut! }
}
