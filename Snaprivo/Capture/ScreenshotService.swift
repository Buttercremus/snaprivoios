import AppKit
import ScreenCaptureKit
import SnagForgeDomain

struct CapturableWindow {
    let id: CGWindowID
    let processID: pid_t?
    let applicationName: String?
    let frame: CGRect // Quartz global coordinates, top-left origin.
}

struct CaptureWindowRegion: Equatable {
    let id: CGWindowID
    let frame: CGRect
}

struct ScreenshotSelection {
    let displayID: CGDirectDisplayID
    let rect: CGRect
    let screenFrame: CGRect
    let windowID: CGWindowID?
    let media: CaptureMedia

    init(displayID: CGDirectDisplayID, rect: CGRect, screenFrame: CGRect, windowID: CGWindowID? = nil, media: CaptureMedia = .image) {
        self.displayID = displayID; self.rect = rect; self.screenFrame = screenFrame; self.windowID = windowID; self.media = media
    }
    init(displayID: CGDirectDisplayID, draft: CaptureSelectionDraft, screenFrame: CGRect, media: CaptureMedia) {
        self.init(displayID: displayID, rect: draft.rect, screenFrame: screenFrame,
                  windowID: media == .video ? draft.windowID : nil, media: media)
    }
    var videoSource: CaptureSource { windowID != nil ? .window : rect == screenFrame ? .display : .region }
}

/// Immutable pixels from before the selector is presented. Selection and final
/// output use this same image, never another capture of a changing live window.
struct FrozenDisplay {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let image: CGImage

    var scale: CGFloat { CGFloat(image.width) / screenFrame.width }

    func crop(_ rect: CGRect) throws -> CGImage {
        guard let source = CaptureGeometry.sourceRect(selection: rect, screen: screenFrame, scale: scale),
              let cropped = image.cropping(to: CGRect(x: (source.minX * scale).rounded(),
                                                     y: (source.minY * scale).rounded(),
                                                     width: (source.width * scale).rounded(),
                                                     height: (source.height * scale).rounded())) else {
            throw ScreenshotError.invalidRegion
        }
        return cropped
    }
}

struct FrozenDesktop {
    let displays: [FrozenDisplay]

    func crop(_ selection: ScreenshotSelection) throws -> CGImage {
        guard let display = displays.first(where: { $0.displayID == selection.displayID }),
              display.screenFrame == selection.screenFrame else { throw ScreenshotError.invalidRegion }
        return try display.crop(selection.rect)
    }
}

enum ScreenshotError: LocalizedError {
    case permission, noDisplays, invalidRegion

    var errorDescription: String? {
        switch self {
        case .permission: String(localized: "Erlaube Snaprivo unter Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme. Kehre anschließend hierher zurück und prüfe den Zugriff erneut. Wenn macOS einen Neustart verlangt oder der Zugriff weiter fehlt, beende Snaprivo und öffne die App erneut.")
        case .noDisplays: String(localized: "Es wurde kein aufnehmbarer Bildschirm gefunden.")
        case .invalidRegion: String(localized: "Der Bereich ist zu klein oder der Bildschirm wurde geändert. Bitte wähle erneut.")
        }
    }
}

@MainActor
struct ScreenshotService {
    func content() async throws -> SCShareableContent {
        // Enumerate capturable background windows too. The window-server list
        // below determines what actually belongs to the current desktop.
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    }

    /// CGWindowList provides front-to-back ordering. Only windows also exposed by
    /// ScreenCaptureKit are eligible; no Accessibility or input-monitoring access.
    func windows(in content: SCShareableContent) -> [CapturableWindow] {
        let eligible = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Self.windowRegions(in: entries, eligibleIDs: Set(eligible.keys), excludingPID: ProcessInfo.processInfo.processIdentifier).compactMap { region in
            eligible[region.id].map { CapturableWindow(id: $0.windowID, processID: $0.owningApplication?.processID,
                                                      applicationName: $0.owningApplication?.applicationName, frame: region.frame) }
        }
    }

    /// Use current Window Server bounds/order, not potentially older SCK bounds.
    /// Input comes from optionOnScreenOnly, so minimized windows and other Spaces
    /// cannot become targets even though SCK enumeration includes them.
    static func windowRegions(in entries: [[String: Any]], eligibleIDs: Set<CGWindowID>, excludingPID: pid_t) -> [CaptureWindowRegion] {
        entries.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  eligibleIDs.contains(id),
                  let owner = entry[kCGWindowOwnerPID as String] as? Int32, owner != excludingPID,
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = entry[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !frame.isInfinite, !frame.isNull, frame.width > 1, frame.height > 1 else { return nil }
            return CaptureWindowRegion(id: id, frame: frame)
        }
    }

    func freeze(_ content: SCShareableContent, cursor: Bool) async throws -> FrozenDesktop {
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return (id, screen.frame)
        }
        var snapshots: [FrozenDisplay] = []
        for (id, frame) in screens {
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw ScreenshotError.noDisplays }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.showsCursor = cursor
            config.captureResolution = .best
            config.ignoreShadowsDisplay = true
            config.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
            config.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            snapshots.append(FrozenDisplay(displayID: id, screenFrame: frame, image: image))
        }
        guard !snapshots.isEmpty else { throw ScreenshotError.noDisplays }
        return FrozenDesktop(displays: snapshots)
    }
}

extension ScreenshotService {
    func scrollFrame(_ selection: ScreenshotSelection) async throws -> CGImage {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == selection.displayID }),
              screen.frame == selection.screenFrame else { throw ScreenshotError.invalidRegion }
        let content = try await content()
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else { throw ScreenshotError.noDisplays }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        // Use the same display-sized rendering and crop as the frozen first frame.
        // A separately scaled SCK sourceRect can resample text at fractional pixels,
        // preventing an unchanged page from matching its initial display snapshot.
        let config = SCStreamConfiguration()
        config.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        config.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        config.showsCursor = false; config.captureResolution = .best; config.ignoreShadowsDisplay = true
        let displayImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try FrozenDisplay(displayID: selection.displayID, screenFrame: selection.screenFrame, image: displayImage).crop(selection.rect)
    }
}
