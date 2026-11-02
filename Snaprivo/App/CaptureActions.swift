import SnagForgeDomain
import SwiftUI

@MainActor
enum CaptureLauncher {
    static func showSetup(workspace: WorkspaceModel, using openWindow: OpenWindowAction) {
        guard workspace.editor?.isShowingImageSize != true, !workspace.isDirectOCRBusy, !workspace.screenshot.isBusy, !workspace.isLoading else { return }
        workspace.pendingCapture = nil
        workspace.pendingGuideCapture = nil
        workspace.isScrollCapture = false
        AppWindows.show("capture", using: openWindow)
    }

    /// Captures a region and appends it as the final step of the open guide.
    static func captureGuideStep(workspace: WorkspaceModel, using openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        guard workspace.requirePro(.guides), let guide = workspace.guides.document, guide.steps.count < 100,
              !workspace.guides.isBusy, !workspace.guides.isSuspended, !workspace.guides.showsTrash else { return }
        capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, guide: guide.id)
    }

    static func capture(_ action: CaptureAction, workspace: WorkspaceModel, using openWindow: OpenWindowAction,
                        dismissWindow: DismissWindowAction, scrolling: Bool = false, video: Bool = false, guide: UUID? = nil) {
        if action == .repeatLast { workspace.repeatLastCapture(using: openWindow, dismissWindow: dismissWindow); return }
        if action == .text || action == .code { workspace.captureText(using: openWindow, dismissWindow: dismissWindow, codesOnly: action == .code); return }
        // Leave native menu tracking before an existing setup view starts selection.
        Task { @MainActor in
            guard workspace.editor?.isShowingImageSize != true, !workspace.isDirectOCRBusy, !workspace.screenshot.isBusy, !workspace.isLoading, workspace.pendingCapture == nil else { return }
            guard workspace.authorizeCapture(scrolling: scrolling, video: video) else {
                if workspace.showPaywallWindow == nil { AppWindows.show("workspace", using: openWindow) }
                return
            }
            workspace.isScrollCapture = scrolling
            // Every started capture overwrites the target, so a cancelled guide capture never leaks into the next one.
            workspace.pendingGuideCapture = video ? nil : guide
            workspace.captureConfiguration = action.configuration(using: workspace.preferences.captureConfiguration)
            if video {
                workspace.captureConfiguration.media = .video
                workspace.captureConfiguration.source = action == .display ? .display : action == .window ? .window : .region
            }
            if !video, let error = workspace.storage.libraryError {
                workspace.importError = error
                AppWindows.show("workspace", using: openWindow)
                return
            }
            if workspace.screenshot.hasPermission {
                // A direct capture must never open/activate the setup scene first.
                begin(workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            } else {
                workspace.pendingCapture = UUID()
                AppWindows.show("capture", using: openWindow)
            }
        }
    }
    static func begin(workspace: WorkspaceModel, using openWindow: OpenWindowAction,
                      dismissWindow: DismissWindowAction, requestPermission: Bool = false) {
        let guide = workspace.captureConfiguration.media == .image ? workspace.pendingGuideCapture : nil
        workspace.pendingGuideCapture = nil
        guard workspace.authorizeCapture(scrolling: workspace.isScrollCapture, video: workspace.captureConfiguration.media == .video) else { return }
        if workspace.captureConfiguration.media == .image, let error = workspace.storage.libraryError {
            workspace.importError = error
            AppWindows.show("workspace", using: openWindow)
            return
        }
        workspace.editor?.finishTextEditing()
        workspace.screenshot.start(configuration: workspace.captureConfiguration, requestPermission: requestPermission, scrolling: workspace.isScrollCapture, videoMouseClicks: workspace.preferences.videoMouseClicks, videoAudio: .init(systemAudio: workspace.preferences.videoSystemAudio, microphone: workspace.preferences.videoMicrophone), activatesOnImageCapture: guide != nil || !workspace.preferences.quickPreviewAfterCapture, onFailure: {
            AppWindows.show("capture", using: openWindow)
        }, authorizeRecognition: { workspace.requirePro(.textRecognition) }, onRecognitionCapture: { image, codesOnly in
            workspace.recognizeCapturedText(image, codesOnly: codesOnly, onFinished: { dismissWindow(id: "capture") })
        }, onVideoCapture: { url in
            await workspace.videos.showPreview(recording: url, directlyEdit: workspace.preferences.opensVideoEditorAfterCapture)
            AppWindows.show("workspace", using: openWindow)
            dismissWindow(id: "capture")
        }) { image in
            if let guide {
                workspace.addCaptureToGuide(image, guide: guide)
                AppWindows.show("workspace", using: openWindow)
            } else {
                workspace.openScreenshot(image)
                if !workspace.preferences.quickPreviewAfterCapture { AppWindows.show("workspace", using: openWindow) }
            }
            dismissWindow(id: "capture")
        }
    }
}

struct CaptureMenuItems: View {
    let workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button(String(localized: "Neue Aufnahme"), systemImage: "viewfinder") {
            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
        }
        .keyboardShortcut(workspace.captureShortcuts.bindings[.region]?.keyboardShortcut)
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "Letzten Bereich erneut aufnehmen"), systemImage: "arrow.clockwise") {
            CaptureLauncher.capture(.repeatLast, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
        }.keyboardShortcut(workspace.captureShortcuts.bindings[.repeatLast]?.keyboardShortcut)
            .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading || !workspace.screenshot.hasLastSelection)
        Button(String(localized: "Text direkt erfassen"), systemImage: "text.viewfinder") {
            CaptureLauncher.capture(.text, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
        }.keyboardShortcut(workspace.captureShortcuts.bindings[.text]?.keyboardShortcut)
            .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "QR-Code scannen"), systemImage: "qrcode.viewfinder") {
            CaptureLauncher.capture(.code, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
        }.keyboardShortcut(workspace.captureShortcuts.bindings[.code]?.keyboardShortcut)
            .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        if workspace.isDirectOCRBusy {
            Button(String(localized: "Texterfassung abbrechen"), systemImage: "xmark.circle") {
                workspace.cancelDirectTextCapture()
            }
        }
        Divider()
        Button(String(localized: "Letzten Bereich als Preset sichern …"), systemImage: "bookmark") {
            workspace.saveLastCapturePreset()
        }.disabled(workspace.screenshot.lastSelection == nil)
        if !workspace.preferences.capturePresets.isEmpty {
            Menu(String(localized: "Bereich-Presets"), systemImage: "bookmark.fill") {
                ForEach(workspace.preferences.capturePresets) { preset in
                    Button(preset.name, systemImage: preset.isValidOnCurrentDisplay ? "rectangle.dashed" : "exclamationmark.triangle") {
                        workspace.applyCapturePreset(preset, using: openWindow, dismissWindow: dismissWindow)
                    }.disabled(!preset.isValidOnCurrentDisplay || workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
                    Button(String(localized: "„\(preset.name)“ umbenennen …"), systemImage: "pencil") {
                        workspace.renameCapturePreset(preset)
                    }
                    Button(String(localized: "„\(preset.name)“ löschen"), systemImage: "trash") {
                        workspace.removeCapturePreset(preset)
                    }
                }
            }
        }
        Divider()
        ForEach([CaptureAction.display, .delayedRegion], id: \.rawValue) { action in
            Button(action.title, systemImage: action.symbol) {
                CaptureLauncher.capture(action, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            }
            .keyboardShortcut(workspace.captureShortcuts.bindings[action]?.keyboardShortcut)
            .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        }
        Button(String(localized: "Scroll-Aufnahme …"), systemImage: "arrow.down.square") {
            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, scrolling: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "Video: Bereich aufnehmen …"), systemImage: "video") {
            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "Video: Bildschirm aufnehmen …"), systemImage: "display") {
            CaptureLauncher.capture(.display, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "Video: Fenster aufnehmen …"), systemImage: "macwindow") {
            CaptureLauncher.capture(.window, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        Button(String(localized: "Lokale Videoaufnahmen …"), systemImage: "folder") {
            Task {
                let root = workspace.videos.files.root
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                NSWorkspace.shared.open(root)
            }
        }
        Button(String(localized: "Aufnahmeoptionen …"), systemImage: "slider.horizontal.3") {
            workspace.captureConfiguration = workspace.preferences.captureConfiguration
            CaptureLauncher.showSetup(workspace: workspace, using: openWindow)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        if workspace.screenshot.isBusy {
            Divider()
            Text(workspace.screenshot.status)
            if workspace.screenshot.hasVideoSession {
                Button(String(localized: "Video-Steuerung anzeigen"), systemImage: "video") { workspace.screenshot.showVideoControls() }
                if workspace.screenshot.isRecordingVideo {
                    Button(String(localized: "Video stoppen"), systemImage: "stop.circle") { workspace.screenshot.stopVideo() }
                }
            } else {
                Button(String(localized: "Aufnahme abbrechen"), systemImage: "xmark.circle") { workspace.screenshot.cancel() }
            }
        }
    }
}


// Presentation of capture presets and direct text capture belongs to the UI adapter.
extension WorkspaceModel {
    func repeatLastCapture(using openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        guard !isLoading, !isDirectOCRBusy, !screenshot.isBusy,
              editor?.isShowingImageSize != true, screenshot.hasLastSelection else { return }
        screenshot.repeatLast(configuration: preferences.captureConfiguration, onFailure: {
            AppWindows.show("workspace", using: openWindow)
        }) { [weak self] image in
            guard let self else { return }; openScreenshot(image); if !preferences.quickPreviewAfterCapture { AppWindows.show("workspace", using: openWindow) }; dismissWindow(id: "capture")
        }
    }
    func applyCapturePreset(_ preset: CaptureRegionPreset, using openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        guard !isLoading, !isDirectOCRBusy, !screenshot.isBusy,
              editor?.isShowingImageSize != true, preset.isValidOnCurrentDisplay else { return }
        let selection = ScreenshotSelection(displayID: preset.displayID, rect: preset.rect, screenFrame: preset.screenFrame)
        screenshot.repeatSelection(selection, expectedScale: preset.scale, configuration: preferences.captureConfiguration, onFailure: {
            AppWindows.show("workspace", using: openWindow)
        }) { [weak self] image in
            guard let self else { return }; openScreenshot(image); if !preferences.quickPreviewAfterCapture { AppWindows.show("workspace", using: openWindow) }; dismissWindow(id: "capture")
        }
    }
    func saveLastCapturePreset() {
        guard let selection = screenshot.lastSelection,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == selection.displayID }) else { return }
        let alert = NSAlert(); alert.messageText = String(localized: "Bereich als Preset sichern")
        let field = NSTextField(string: String(localized: "Mein Bereich")); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Sichern")); alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        preferences.saveCapturePreset(name: field.stringValue, displayID: selection.displayID, screenFrame: selection.screenFrame, rect: selection.rect, scale: screen.backingScaleFactor)
    }
    func removeCapturePreset(_ preset: CaptureRegionPreset) { preferences.removeCapturePreset(preset.id) }
    func renameCapturePreset(_ preset: CaptureRegionPreset) {
        let alert = NSAlert(); alert.messageText = String(localized: "Preset umbenennen")
        let field = NSTextField(string: preset.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Umbenennen")); alert.addButton(withTitle: String(localized: "Abbrechen"))
        if alert.runModal() == .alertFirstButtonReturn { preferences.renameCapturePreset(preset.id, to: field.stringValue) }
    }

    func captureText(using openWindow: OpenWindowAction, dismissWindow: DismissWindowAction, codesOnly: Bool = false) {
        guard !isLoading, editor?.isShowingImageSize != true, !screenshot.isBusy, requirePro(.textRecognition) else { return }
        guard directOCRTask == nil else { return }
        directCaptureNotice = nil
        directCaptureReadsCodes = codesOnly
        screenshot.start(configuration: CaptureConfiguration(media: .image, source: .region, includesCursor: false), requestPermission: true,
            imageOnly: true, destination: codesOnly ? .code : .text, activatesOnImageCapture: false,
            onFailure: { AppWindows.show("workspace", using: openWindow) },
            authorizeRecognition: { self.requirePro(.textRecognition) },
            onRecognitionCapture: { [weak self] image, codes in
                self?.recognizeCapturedText(image, codesOnly: codes, onFinished: { dismissWindow(id: "capture") })
            }) { [weak self] image in
                guard let self else { return }
                openScreenshot(image)
                if !preferences.quickPreviewAfterCapture { AppWindows.show("workspace", using: openWindow) }
                dismissWindow(id: "capture")
            }
    }

    /// The result stays available until dismissed, including after a failed clipboard write.
    func recognizeCapturedText(_ image: CGImage, codesOnly: Bool,
        recognize: @escaping @Sendable (CGImage, Bool) async throws -> TextRecognitionService.DirectResult = { image, codesOnly in
            if codesOnly { return .init(text: "", codes: try await TextRecognitionService.shared.recognizeCodes(image)) }
            return try await TextRecognitionService.shared.recognizeDirect(image, includeCodes: false)
        }, copy: @escaping @MainActor (String) -> Bool = { text in
            NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string)
        }, clipboardRevision: @escaping @MainActor () -> Int = { NSPasteboard.general.changeCount },
        onFinished: @escaping @MainActor () -> Void = {}) {
        guard directOCRTask == nil else { return }
        directCaptureNotice = nil; directCaptureError = nil; directCaptureText = ""; directCaptureCodes = []
        directCaptureReadsCodes = codesOnly; directCaptureImage = image; showsDirectCaptureResult = true
        let clipboardAtStart = clipboardRevision()
        let requestID = UUID(); directCaptureRequestID = requestID
        directOCRTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.directCaptureRequestID == requestID { self.directOCRTask = nil; onFinished() } }
            do {
                let result = try await recognize(image, codesOnly)
                guard !Task.isCancelled, self.directCaptureRequestID == requestID, self.purchases.hasPro else { return }
                self.directCaptureText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.directCaptureCodes = Array(Set(result.codes)).sorted()
                if codesOnly {
                    self.directCaptureNotice = self.directCaptureCodes.isEmpty ? String(localized: "Kein QR- oder Barcode erkannt") : String(localized: "QR- oder Barcode erkannt")
                } else if self.directCaptureText.isEmpty {
                    self.directCaptureNotice = String(localized: "Kein Text erkannt. Wähle einen engeren Bereich mit gut lesbarem Text.")
                } else if clipboardRevision() != clipboardAtStart {
                    self.directCaptureNotice = String(localized: "Text erkannt. Zwischenablage inzwischen geändert – zum Kopieren klicken.")
                } else {
                    _ = self.copyDirectCaptureText(using: copy)
                }
            } catch {
                if !Task.isCancelled, self.directCaptureRequestID == requestID {
                    let message = String(localized: "Die lokale Texterkennung ist fehlgeschlagen: \(error.localizedDescription)")
                    self.directCaptureError = message
                }
            }
        }
        QuickCapturePanelController.shared.present(workspace: self)
    }
    @discardableResult func copyDirectCaptureText(using copy: @MainActor (String) -> Bool = { value in
        NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(value, forType: .string)
    }) -> Bool {
        guard purchases.hasPro, !directCaptureText.isEmpty else { return false }
        let copied = copy(directCaptureText)
        directCaptureError = copied ? nil : String(localized: "Der erkannte Text konnte nicht in die Zwischenablage kopiert werden.")
        directCaptureNotice = copied ? String(localized: "Text kopiert. Mit ⌘V einfügen.") : nil
        return copied
    }
    func retryDirectTextCapture() {
        guard !isDirectOCRBusy, purchases.hasPro, let image = directCaptureImage else { return }
        recognizeCapturedText(image, codesOnly: directCaptureReadsCodes)
    }

}
