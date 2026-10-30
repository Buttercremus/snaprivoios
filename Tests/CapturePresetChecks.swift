import AppKit

/// Persistence and geometry checks for capture presets. The app target owns the
/// model; this check deliberately exercises only its deterministic validation.
@main
struct CapturePresetChecks {
    @MainActor static func main() {
        let suite = "CapturePresetChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let screen = NSScreen.screens.first
        if let screen {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 1
            let rect = screen.frame.insetBy(dx: 20, dy: 20)
            let preset = CaptureRegionPreset(id: UUID(), name: "Test", displayID: id, screenFrame: screen.frame, rect: rect, scale: screen.backingScaleFactor)
            precondition(preset.rect == rect)
            precondition(preset.isValidOnCurrentDisplay)
            let stale = CaptureRegionPreset(id: preset.id, name: preset.name, displayID: id, screenFrame: screen.frame, rect: rect, scale: screen.backingScaleFactor + 1)
            precondition(!stale.isValidOnCurrentDisplay, "Changed backing scale must invalidate preset")
            let preferences = AppPreferences(defaults: defaults)
            preferences.saveCapturePreset(name: " Demo ", displayID: id, screenFrame: screen.frame, rect: rect, scale: screen.backingScaleFactor)
            precondition(preferences.capturePresets.first?.name == "Demo")
            let savedID = preferences.capturePresets[0].id
            preferences.renameCapturePreset(savedID, to: "Renamed")
            precondition(preferences.capturePresets.first?.name == "Renamed")
            preferences.removeCapturePreset(savedID)
            precondition(preferences.capturePresets.isEmpty)
            defaults.removePersistentDomain(forName: suite)
        }
        let missing = CaptureRegionPreset(id: UUID(), name: "Missing", displayID: .max, screenFrame: .zero, rect: .zero, scale: 2)
        precondition(!missing.isValidOnCurrentDisplay, "Unknown display must invalidate preset")
    }
}
