import SwiftUI
import SnagForgeDomain

#if !WORKFLOW_CHECKS
@main
#endif
struct SnagForgeApp: App {
    @NSApplicationDelegateAdaptor(SnagForgeDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel()
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.guideEditor) private var focusedGuideEditor

    private var guideEditingIsActive: Bool {
        guard workspace.section == .guides, focusedGuideEditor === workspace.guides,
              let window = NSApp.keyWindow, !(window is NSPanel), window.sheetParent == nil else { return false }
        return true
    }

    var body: some Scene {
        Window(String(localized: "Snaprivo"), id: "workspace") {
            WorkspaceView(workspace: workspace)
                .onAppear {
                    appDelegate.showWorkspace = { AppWindows.show("workspace", using: openWindow) }
                    workspace.showPaywallWindow = { AppWindows.show("pro", using: openWindow) }
                    appDelegate.workspace = workspace; workspace.preferences.applyAppearance()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "Über Snaprivo")) {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? String(localized: "Entwicklungsversion"),
                        .version: ""
                    ])
                }
            }
            CommandGroup(after: .newItem) {
                Button(String(localized: "Bild öffnen …")) { workspace.isImporting = true }
                    .keyboardShortcut("o")
                Button(String(localized: "Projekt importieren …")) { workspace.chooseTransfer(.importProject) }.disabled(workspace.isLoading)
                Divider()
                Button(String(localized: "Alles sichern …")) { workspace.chooseTransfer(.completeBackup) }.disabled(!workspace.canChangeStorage)
                Button(String(localized: "Alles wiederherstellen …")) { workspace.chooseTransfer(.restoreComplete) }.disabled(!workspace.canChangeStorage)
                Divider()
                Button(String(localized: "Bildbibliothek sichern …")) { workspace.chooseTransfer(.backup) }.disabled(workspace.isLoading)
                Button(String(localized: "Sicherung wiederherstellen …")) { workspace.chooseTransfer(.restoreBackup) }.disabled(workspace.isLoading)
                Button(String(localized: "Videos sichern …")) { workspace.videos.chooseBackup(restoring: false) }.disabled(workspace.videos.isBusy)
                Button(String(localized: "Videosicherung wiederherstellen …")) { workspace.videos.chooseBackup(restoring: true) }.disabled(workspace.videos.isBusy)
                Divider()
                Button(String(localized: "Neue Anleitung")) { workspace.section = .guides; workspace.guides.create() }
                    .disabled(workspace.guides.isBusy || workspace.videos.preview != nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button(workspace.section == .guides ? String(localized: "Anleitung sichern") : String(localized: "Projekt sichern")) {
                    Task {
                        if workspace.section == .guides { await workspace.guides.flush() }
                        else if let video = workspace.videos.preview { await video.apply() }
                        else { await workspace.editor?.flush() }
                    }
                }
                .keyboardShortcut("s")
                .disabled(workspace.section == .guides ? workspace.guides.document == nil || workspace.guides.isBusy || workspace.guides.isSuspended
                          : workspace.videos.preview != nil ? workspace.videos.preview?.canApply != true
                          : workspace.editor == nil || workspace.isLoading)
                Button(String(localized: "Bearbeitbares Projekt exportieren …")) {
                    if let id = workspace.editor?.document.id { workspace.chooseTransfer(.exportProject(id)) }
                }.disabled(workspace.section != .editor || workspace.editor == nil || workspace.isLoading)
                Button(workspace.section == .guides ? String(localized: "PDF exportieren …") : String(localized: "PNG exportieren …")) {
                    if workspace.section == .guides { workspace.guides.chooseExport(.pdf) }
                    else { workspace.editor?.exportPNG() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(workspace.section == .guides ? workspace.guides.document?.steps.isEmpty != false || workspace.guides.isBusy || workspace.guides.showsTrash || workspace.guides.selectedDocumentIDs.count > 1
                          : workspace.section != .editor || workspace.editor?.hasExportableImage != true || workspace.editor?.isExportingPNG == true)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(String(localized: "Rückgängig")) {
                    if guideEditingIsActive { workspace.guides.undo() }
                    else if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
                    else if let video = workspace.videos.preview, !video.hasUnappliedChanges { Task { await video.undo() } }
                    else if workspace.section == .editor { workspace.editor?.undo() }
                }.keyboardShortcut("z").disabled(guideEditingIsActive ? !workspace.guides.canUndo || !workspace.purchases.hasPro : (NSApp.keyWindow?.firstResponder as? NSTextView).map { $0.undoManager?.canUndo != true } ?? (workspace.videos.preview.map { !$0.canUndo } ?? (workspace.editor == nil)))
                Button(String(localized: "Wiederholen")) {
                    if guideEditingIsActive { workspace.guides.redo() }
                    else if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
                    else if let video = workspace.videos.preview, !video.hasUnappliedChanges { Task { await video.redo() } }
                    else if workspace.section == .editor { workspace.editor?.redo() }
                }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(guideEditingIsActive ? !workspace.guides.canRedo || !workspace.purchases.hasPro : (NSApp.keyWindow?.firstResponder as? NSTextView).map { $0.undoManager?.canRedo != true } ?? (workspace.videos.preview.map { !$0.canRedo } ?? (workspace.editor == nil)))
            }
            CaptureCommands(workspace: workspace)
            CommandGroup(replacing: .help) {
                Button(String(localized: "Einführung anzeigen …")) { openWindow(id: "workspace"); workspace.showsOnboarding = true }
                    .disabled(workspace.screenshot.isBusy || workspace.isLoading || workspace.isImporting || workspace.videos.preview != nil)
                Button(String(localized: "Editorhinweise erneut anzeigen")) { workspace.preferences.dismissedEditorHints = [] }
                Divider()
                SupportFeedbackButton()
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(String(localized: "90° nach rechts drehen")) { if let editor = workspace.editor { editor.transformImage(editor.history.transform.rotated()) } }
                    .disabled(workspace.section != .editor || workspace.editor?.canTransformImage != true)
                Button(String(localized: "90° nach links drehen")) { if let editor = workspace.editor { editor.transformImage(editor.history.transform.rotated(clockwise: false)) } }
                    .disabled(workspace.section != .editor || workspace.editor?.canTransformImage != true)
                Button(String(localized: "Horizontal spiegeln")) { if let editor = workspace.editor { editor.transformImage(editor.history.transform.flippedHorizontally()) } }
                    .disabled(workspace.section != .editor || workspace.editor?.canTransformImage != true)
                Button(String(localized: "Vertikal spiegeln")) { if let editor = workspace.editor { editor.transformImage(editor.history.transform.flippedVertically()) } }
                    .disabled(workspace.section != .editor || workspace.editor?.canTransformImage != true)
                Divider()
                Button(String(localized: "Objekt duplizieren")) { workspace.editor?.duplicateSelection() }
                    .keyboardShortcut("d")
                    .disabled(workspace.section != .editor || workspace.editor?.canDuplicateSelection != true)
                ForEach(EditorLayerMove.allCases, id: \.self) { direction in
                    Button(direction.title) { workspace.editor?.moveSelection(direction) }
                        .disabled(workspace.section != .editor || workspace.editor?.canMoveSelection(direction) != true)
                }
                Divider()
                Button(String(localized: "Text erkennen")) { workspace.editor?.beginInlineTextRecognition() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(workspace.section != .editor || workspace.editor?.hasExportableImage != true || workspace.editor?.isExporting == true)
                Button(String(localized: "Bildauflösung ändern …")) { workspace.editor?.beginImageResize() }
                    .disabled(workspace.editor == nil || workspace.editor?.cropDraft != nil || workspace.editor?.isCanvasGestureActive == true)
                Button(String(localized: "Zuschneiden")) { workspace.editor?.beginCrop() }
                    .keyboardShortcut("k").disabled(workspace.editor == nil || workspace.editor?.isCanvasGestureActive == true)
                Button(String(localized: "Zuschnitt aufheben")) { workspace.editor?.restoreOriginal() }
                    .disabled(workspace.editor?.document.crop == nil || workspace.editor?.cropDraft != nil)
            }
            CommandGroup(before: .toolbar) {
                Button(String(localized: "Letzte Schnellvorschau anzeigen")) { QuickCapturePanelController.shared.restore() }
                    .disabled(workspace.quickCapture == nil && !workspace.showsDirectCaptureResult)
                Button(String(localized: "Alle Anheftungen entsperren")) { PinnedImageController.shared.unlockAll() }
                Button(String(localized: "Alle Anheftungen schließen")) { PinnedImageController.shared.closeAll() }
                Divider()
                Button(String(localized: "Vergrößern")) { workspace.editor?.zoomBy(1.25) }
                    .keyboardShortcut("+").disabled(workspace.editor == nil)
                Button(String(localized: "Verkleinern")) { workspace.editor?.zoomBy(1 / 1.25) }
                    .keyboardShortcut("-").disabled(workspace.editor == nil)
                Button(String(localized: "Originalgröße (100 %)")) { workspace.editor?.setZoom(1) }
                    .keyboardShortcut("1").disabled(workspace.editor == nil)
                Button(String(localized: "An Fenster anpassen")) { workspace.editor?.fitImage() }
                    .keyboardShortcut("0").disabled(workspace.editor == nil)
                Divider()
            }
        }

        Window(String(localized: "Aufnahmeoptionen"), id: "capture") {
            CaptureSetupView(workspace: workspace)
        }
        .windowResizability(.contentSize)

        Window("Snaprivo Pro", id: "pro") {
            ProPaywallView(model: workspace.purchases, feature: workspace.requestedProFeature)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(workspace: workspace)
        }

        MenuBarExtra(String(localized: "Snaprivo"), systemImage: "viewfinder") {
            MenuBarContent(workspace: workspace)
        }
    }
}

private struct CaptureCommands: Commands {
    let workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu(String(localized: "Aufnahme")) {
            CaptureMenuItems(workspace: workspace)
        }
    }
}

private struct MenuBarContent: View {
    let workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CaptureMenuItems(workspace: workspace)
        Divider()
        Button(String(localized: "Letzte Schnellvorschau anzeigen")) { QuickCapturePanelController.shared.restore() }
            .disabled(workspace.quickCapture == nil && !workspace.showsDirectCaptureResult)
        Button(String(localized: "Alle Anheftungen entsperren")) { PinnedImageController.shared.unlockAll() }
        Button(String(localized: "Alle Anheftungen schließen")) { PinnedImageController.shared.closeAll() }
        Divider()
        Button(String(localized: "Bibliothek öffnen"), systemImage: "photo.on.rectangle") {
            workspace.section = .library
            AppWindows.show("workspace", using: openWindow)
        }
        Divider()
        if !workspace.captureShortcuts.unavailable.isEmpty {
            Text(String(localized: "Ein Tastenkürzel ist nicht verfügbar"))
        }
        SettingsLink()
        SupportFeedbackButton()
        Button(String(localized: "Snaprivo beenden"), role: .destructive) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// MenuBarExtra actions may run while another app is active. Opening a scene alone
/// does not reliably activate its existing window. Finish menu tracking, then focus it.
@MainActor
enum AppWindows {
    static func show(_ id: String, using openWindow: OpenWindowAction) {
        Task { @MainActor in
            openWindow(id: id)
            NSApp.activate(ignoringOtherApps: true)
            await Task.yield()
            NSApp.windows.first { $0.identifier?.rawValue == id }?.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class SnagForgeDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel? { didSet { drainOpenFiles() } }
    var showWorkspace: (() -> Void)?
    private var pendingFiles: [URL] = []
    private var openingFiles = false
    func application(_ application: NSApplication, open urls: [URL]) { Task { await openFiles(urls) } }
    func openFiles(_ urls: [URL]) async {
        pendingFiles.append(contentsOf: urls)
        drainOpenFiles()
    }
    private func drainOpenFiles() {
        guard !openingFiles, let workspace, !pendingFiles.isEmpty else { return }
        openingFiles = true
        showWorkspace?()
        workspace.showsOnboarding = false
        Task {
            defer { openingFiles = false }
            while !pendingFiles.isEmpty { await workspace.openExternalFile(pendingFiles.removeFirst()) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    private var awaitingSave = false
    func applicationWillTerminate(_ notification: Notification) {
        workspace?.captureShortcuts.stop()
        workspace?.storage.endAccess()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        workspace?.preferences.applyAppearance()
        // Use the bundled icon even if Launch Services cached an older iconless build.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        if awaitingSave { return .terminateLater }
        awaitingSave = true
        Task {
            let saved = await workspace.flushBeforeQuitting()
            awaitingSave = false
            if !saved {
                if workspace.videos.preview == nil {
                    workspace.section = workspace.guides.isDirty ? .guides : .editor
                }
                sender.activate(ignoringOtherApps: true)
            }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
