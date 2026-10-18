import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var captureAfterIntroduction = false

    var body: some View {
        NavigationSplitView {
            List(selection: $workspace.section) {
                Section(String(localized: "Arbeitsbereich")) {
                    Label(String(localized: "Bibliothek"), systemImage: "photo.on.rectangle")
                        .tag(WorkspaceSection.library)
                    Label(String(localized: "Editor"), systemImage: "pencil.and.outline")
                        .tag(WorkspaceSection.editor)
                    Label(String(localized: "Anleitungen"), systemImage: "list.number")
                        .tag(WorkspaceSection.guides)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                Button("Snaprivo Pro") { workspace.showsPaywall = true }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        } detail: {
            Group {
                if workspace.section == .editor {
                    EditorView(workspace: workspace)
                } else if workspace.section == .guides {
                    GuideView(workspace: workspace, model: workspace.guides)
                } else {
                    VStack(spacing: 0) {
                        Picker(String(localized: "Bibliotheksinhalt"), selection: $workspace.libraryShowsVideos) {
                            Text(String(localized: "Bilder")).tag(false)
                            Text(String(localized: "Videos")).tag(true)
                        }.pickerStyle(.segmented).frame(maxWidth: 320).padding(.top, 12).padding(.horizontal)
                            .accessibilityIdentifier("library.media")
                        if workspace.libraryShowsVideos {
                            VideoLibraryView(model: workspace.videos, allBackup: { workspace.chooseTransfer(.completeBackup) }, allRestore: { workspace.chooseTransfer(.restoreComplete) })
                        } else {
                        if !workspace.preferences.completedFirstCapture {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "viewfinder").font(.largeTitle).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(localized: "Deine erste Aufnahme")).font(.headline)
                                    Text(String(localized: "Fenster anklicken oder Bereich aufziehen → Aufnahme bestätigen → direkt im Bild bearbeiten."))
                                    Text(String(localized: "Die Bildschirmfreigabe fragt macOS erst beim Start an. Deine Projekte bleiben lokal.")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "Neue Aufnahme")) { CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow) }
                                    .buttonStyle(.glassProminent)
                            }.padding().accessibilityIdentifier("capture.firstRun")
                            Divider()
                        }
                        LibraryView(workspace: workspace)
                        }
                    }
                }
            }
            .disabled(workspace.isTransferring || workspace.isChangingLibrary)
            .navigationTitle(workspace.section == .editor ? String(localized: "Editor") : workspace.section == .guides ? String(localized: "Anleitungen") : String(localized: "Bibliothek"))
            .toolbar {
                ToolbarItem {
                    Button(String(localized: "Bild öffnen"), systemImage: "folder") { workspace.isImporting = true }
                        .help(String(localized: "Ein Bild als bearbeitbares Projekt importieren"))
                        .disabled(workspace.isLoading && workspace.editor?.isSwitchingImage != true)
                        .allowsHitTesting(!workspace.isLoading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Video aufnehmen"), systemImage: "video") {
                        CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, video: true)
                    }
                    .help(String(localized: "Video: Bereich aufnehmen …"))
                    .accessibilityIdentifier("workspace.capture.video")
                    .disabled(workspace.screenshot.isBusy || (workspace.isLoading && workspace.editor?.isSwitchingImage != true))
                    .allowsHitTesting(!workspace.isLoading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Neue Aufnahme"), systemImage: "viewfinder") {
                        CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                    }
                    .disabled(workspace.screenshot.isBusy || (workspace.isLoading && workspace.editor?.isSwitchingImage != true))
                    .allowsHitTesting(!workspace.isLoading)
                }
            }
        }
        .task { await workspace.purchases.start() }
        .task {
            await workspace.refreshLibrary()
            if !workspace.hasOpenedExternalFile && !workspace.preferences.completedOnboarding && !workspace.preferences.completedFirstCapture
                && workspace.items.isEmpty && workspace.videos.items.isEmpty && workspace.videos.preview == nil
                && workspace.editor == nil && !workspace.screenshot.isBusy {
                workspace.showsOnboarding = true
            }
        }
        .sheet(isPresented: $workspace.showsPaywall) { ProPaywallView(model: workspace.purchases) }
        .sheet(isPresented: Binding(get: { workspace.quickCapture != nil }, set: { if !$0 { workspace.quickCapture = nil } })) {
            if let capture = workspace.quickCapture { QuickCaptureView(workspace: workspace, model: capture) }
        }
        .sheet(isPresented: $workspace.showsOnboarding, onDismiss: {
            if captureAfterIntroduction {
                captureAfterIntroduction = false
                CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            }
        }) {
            OnboardingView(shortcuts: workspace.captureShortcuts) { startCapture in
                workspace.preferences.completedOnboarding = true
                captureAfterIntroduction = startCapture
                workspace.showsOnboarding = false
            }
        }
        .onAppear { [weak workspace, openWindow, dismissWindow] in
            guard let workspace else { return }
            // Keep the scene-opening action available to global hotkeys even when
            // the workspace window is closed. The workspace lives with the app.
            workspace.captureShortcuts.start { [weak workspace] action in
                guard let workspace else { return }
                CaptureLauncher.capture(action, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            }
        }
        .overlay { if workspace.isLoading && (workspace.section != .editor || workspace.editor == nil || workspace.isChangingLibrary || workspace.isTransferring) { ProgressView(workspace.isChangingLibrary ? String(localized: "Bibliothek übernehmen …") : workspace.isTransferring ? String(localized: "Projekte verarbeiten …") : String(localized: "Projekt öffnen …")).padding(24).background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .alert(String(localized: "Dateiaktion abgeschlossen"), isPresented: Binding(get: { workspace.transferNotice != nil }, set: { if !$0 { workspace.transferNotice = nil } })) {
            Button("OK", role: .cancel) { workspace.transferNotice = nil }
        } message: { Text(workspace.transferNotice ?? "") }
        .frame(minWidth: 800, minHeight: 540)
        .disabled(workspace.guides.isSuspended)
        .fileImporter(isPresented: $workspace.isImporting, allowedContentTypes: [.png, .jpeg, .tiff, .heic]) { result in
            switch result {
            case .success(let url): workspace.openImage(at: url)
            case .failure(let error): workspace.importError = error.localizedDescription
            }
        }
        .alert(String(localized: "Aktion konnte nicht abgeschlossen werden"), isPresented: Binding(
            get: { workspace.importError != nil },
            set: { if !$0 { workspace.importError = nil } }
        )) {
            Button("OK", role: .cancel) { workspace.importError = nil }
        } message: {
            Text(workspace.importError ?? "")
        }
    }

}
