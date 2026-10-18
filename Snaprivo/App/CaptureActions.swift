import SnagForgeDomain
import SwiftUI

@MainActor
enum CaptureLauncher {
    static func showSetup(workspace: WorkspaceModel, using openWindow: OpenWindowAction) {
        guard workspace.editor?.isShowingImageSize != true, !workspace.screenshot.isBusy, !workspace.isLoading else { return }
        workspace.pendingCapture = nil
        workspace.isScrollCapture = false
        AppWindows.show("capture", using: openWindow)
    }

    static func capture(_ action: CaptureAction, workspace: WorkspaceModel, using openWindow: OpenWindowAction,
                        dismissWindow: DismissWindowAction, scrolling: Bool = false, video: Bool = false) {
        // Leave native menu tracking before an existing setup view starts selection.
        Task { @MainActor in
            guard workspace.editor?.isShowingImageSize != true, !workspace.screenshot.isBusy, !workspace.isLoading, workspace.pendingCapture == nil else { return }
            workspace.isScrollCapture = scrolling
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
        if workspace.captureConfiguration.media == .image, let error = workspace.storage.libraryError {
            workspace.importError = error
            AppWindows.show("workspace", using: openWindow)
            return
        }
        workspace.editor?.finishTextEditing()
        workspace.screenshot.start(configuration: workspace.captureConfiguration, requestPermission: requestPermission, scrolling: workspace.isScrollCapture, videoAudio: .init(systemAudio: workspace.preferences.videoSystemAudio, microphone: workspace.preferences.videoMicrophone), onFailure: {
            AppWindows.show("capture", using: openWindow)
        }, onVideoCapture: { url in
            await workspace.videos.showPreview(recording: url)
            AppWindows.show("workspace", using: openWindow)
            dismissWindow(id: "capture")
        }) { image in
            workspace.openScreenshot(image)
            AppWindows.show("workspace", using: openWindow)
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
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
        Divider()
        ForEach([CaptureAction.display, .delayedRegion], id: \.rawValue) { action in
            Button(action.title, systemImage: action.symbol) {
                CaptureLauncher.capture(action, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            }
            .keyboardShortcut(workspace.captureShortcuts.bindings[action]?.keyboardShortcut)
            .disabled(workspace.screenshot.isBusy || workspace.isLoading)
        }
        Button(String(localized: "Scroll-Aufnahme (manuell) …"), systemImage: "arrow.down.square") {
            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, scrolling: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
        Button(String(localized: "Video: Bereich aufnehmen …"), systemImage: "video") {
            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
        Button(String(localized: "Video: Bildschirm aufnehmen …"), systemImage: "display") {
            CaptureLauncher.capture(.display, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
        Button(String(localized: "Video: Fenster aufnehmen …"), systemImage: "macwindow") {
            CaptureLauncher.capture(.window, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
        }
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
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
        .disabled(workspace.screenshot.isBusy || workspace.isLoading)
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

