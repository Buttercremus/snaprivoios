import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pendingOnboardingAction: OnboardingAction?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { workspace.section }, set: { section in
                var transaction = Transaction(animation: navigationAnimation)
                transaction[SidebarTransition.self] = true
                withTransaction(transaction) { workspace.section = section }
            })) {
                Section(String(localized: "Arbeitsbereich")) {
                    Label(String(localized: "Bibliothek"), systemImage: "photo.on.rectangle")
                        .tag(WorkspaceSection.library)
                    Label(String(localized: "Editor"), systemImage: "pencil.and.outline")
                        .tag(WorkspaceSection.editor)
                    Label(String(localized: "Anleitungen"), systemImage: "list.number")
                        .tag(WorkspaceSection.guides)
                }
                Section(String(localized: "Schnellaktionen")) {
                    Button(String(localized: "Neue Aufnahme"), systemImage: "viewfinder") { capture(.region) }
                        .accessibilityIdentifier("sidebar.capture")
                    Button(String(localized: "Nur Text kopieren"), systemImage: "text.viewfinder") { capture(.text) }
                        .accessibilityIdentifier("sidebar.copyText")
                        .help(String(localized: "Bildschirmbereich auswählen und erkannten Text direkt kopieren"))
                    Button(String(localized: "QR-Code scannen"), systemImage: "qrcode.viewfinder") { capture(.code) }
                        .accessibilityIdentifier("sidebar.scanCode")
                    Menu {
                        Button(String(localized: "Letzten Bereich erneut aufnehmen")) { capture(.repeatLast) }
                            .disabled(!workspace.screenshot.hasLastSelection)
                        ForEach(workspace.preferences.capturePresets) { preset in
                            Button(preset.name) { workspace.applyCapturePreset(preset, using: openWindow, dismissWindow: dismissWindow) }
                        }
                        Divider()
                        Button(String(localized: "Bereich als Preset sichern")) { workspace.saveLastCapturePreset() }
                            .disabled(!workspace.screenshot.hasLastSelection || workspace.isLoading)
                    } label: { Label(String(localized: "Aufnahmevorlagen"), systemImage: "rectangle.stack") }
                        .menuStyle(.borderlessButton)
                }.buttonStyle(.plain)
                    .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || (workspace.isLoading && workspace.editor?.isSwitchingImage != true))
                    .allowsHitTesting(!workspace.isLoading)
                if workspace.isDirectOCRBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(workspace.directCaptureReadsCodes ? String(localized: "Code wird gelesen …") : String(localized: "Text wird erkannt …"))
                            .font(.caption)
                        Spacer(minLength: 0)
                        Button(String(localized: "Abbrechen"), systemImage: "xmark.circle.fill") { workspace.cancelDirectTextCapture() }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }.accessibilityIdentifier("sidebar.recognitionProgress")
                } else if let notice = workspace.directCaptureNotice {
                    Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("sidebar.recognitionResult")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                Button("Snaprivo Pro") { workspace.showPro() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        } detail: {
            ZStack {
                if workspace.section == .editor {
                    ZStack {
                        EditorView(workspace: workspace)
                            .safeAreaInset(edge: .top) {
                                if let target = workspace.guideImageReturn, target.guide == workspace.guides.document?.id, target.project == workspace.editor?.document.id {
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 12) { guideReturnActions }
                                        VStack(alignment: .leading, spacing: 8) { guideReturnActions }
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                                }
                            }
                            .transaction { if $0[SidebarTransition.self] { $0.animation = nil } }
                    }.transition(.opacity)
                } else if workspace.section == .guides {
                    ZStack {
                        GuideView(workspace: workspace, model: workspace.guides)
                            .transaction { if $0[SidebarTransition.self] { $0.animation = nil } }
                    }.transition(.opacity)
                } else {
                    ZStack {
                        VStack(spacing: 0) {
                            Picker(String(localized: "Bibliotheksinhalt"), selection: Binding(get: { workspace.libraryShowsVideos }, set: { videos in
                                var transaction = Transaction(animation: navigationAnimation)
                                transaction[MediaTransition.self] = true
                                withTransaction(transaction) { workspace.libraryShowsVideos = videos }
                            })) {
                                Text(String(localized: "Bilder")).tag(false)
                                Text(String(localized: "Videos")).tag(true)
                            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320).padding(.top, 12).padding(.horizontal)
                                .accessibilityIdentifier("library.media")
                            ZStack {
                                if workspace.libraryShowsVideos {
                                    ZStack {
                                        VideoLibraryView(model: workspace.videos, allBackup: { workspace.chooseTransfer(.completeBackup) }, allRestore: { workspace.chooseTransfer(.restoreComplete) })
                                            .transaction { if $0[MediaTransition.self] { $0.animation = nil } }
                                    }.transition(.opacity)
                                } else {
                                    ZStack {
                                    VStack(spacing: 0) {
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
                                    .transaction { if $0[MediaTransition.self] { $0.animation = nil } }
                                    }.transition(.opacity)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .transaction { transaction in
                            // Keep descendant layout and image pixels out of sidebar transitions.
                            if transaction[SidebarTransition.self] { transaction.animation = nil }
                        }
                    }.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(workspace.isTransferring || workspace.isChangingLibrary)
            .navigationTitle(workspace.section == .editor ? String(localized: "Editor") : workspace.section == .guides ? String(localized: "Anleitungen") : String(localized: "Bibliothek"))
            .toolbar {
                if workspace.section == .guides {
                    // „Neue Anleitung“ lives in the guide list header; the toolbar acts on the open guide.
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(String(localized: "Schritt aufnehmen"), systemImage: "viewfinder") {
                                CaptureLauncher.captureGuideStep(workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                            }
                                .disabled(workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
                            Button(String(localized: "Aus Bibliothek hinzufügen …"), systemImage: "photo.on.rectangle") { workspace.guides.chooseImages() }
                        } label: {
                            Label(String(localized: "Schritt hinzufügen"), systemImage: "photo.badge.plus")
                        }
                        .labelStyle(.titleAndIcon)
                        .disabled(workspace.guides.document == nil || workspace.guides.isBusyForControls || workspace.guides.isSuspended || workspace.guides.showsTrash || workspace.guides.selectedDocumentIDs.count > 1 || (workspace.guides.document?.steps.count ?? 0) >= 100)
                        .accessibilityIdentifier("guide.addImages")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "Apple Intelligence"), systemImage: "apple.intelligence") { workspace.guides.assistantOpenRequest += 1 }
                            .labelStyle(.titleAndIcon)
                            .help(String(localized: "Titel, Einleitung und Schritttexte vorschlagen, überarbeiten oder kürzen"))
                            .disabled(workspace.guides.document == nil || workspace.guides.isBusyForControls || workspace.guides.isSuspended || workspace.guides.showsTrash || workspace.guides.selectedDocumentIDs.count > 1)
                            .accessibilityIdentifier("guide.toolbar.assistant")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "PDF-Vorschau"), systemImage: "doc.richtext") { workspace.guides.showPreview() }
                            .disabled(workspace.guides.document?.steps.isEmpty != false || workspace.guides.isBusyForControls || workspace.guides.isSuspended || workspace.guides.showsTrash || workspace.guides.selectedDocumentIDs.count > 1)
                    }
                    ToolbarItem(placement: .primaryAction) { GuideOutputMenu(model: workspace.guides) }
                } else {
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
                    HStack(spacing: 0) {
                        Button(String(localized: "Neue Aufnahme"), systemImage: "viewfinder") {
                            CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                        }
                        Menu {
                            Button(String(localized: "Foto aufnehmen"), systemImage: "camera") {
                                CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                            }
                            Button(String(localized: "Textaufnahme – nur Text kopieren"), systemImage: "text.viewfinder") {
                                CaptureLauncher.capture(.text, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                            }
                            Button(String(localized: "QR-Code scannen"), systemImage: "qrcode.viewfinder") {
                                CaptureLauncher.capture(.code, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
                            }
                            Button(String(localized: "Scroll-Aufnahme"), systemImage: "arrow.down.square") {
                                CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow, scrolling: true)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel(String(localized: "Aufnahmeart wählen"))
                        .accessibilityIdentifier("workspace.capture.photoChoices")
                        .help(String(localized: "Foto, Textaufnahme oder QR-Code"))
                    }
                    .disabled(workspace.screenshot.isBusy || (workspace.isLoading && workspace.editor?.isSwitchingImage != true))
                    .allowsHitTesting(!workspace.isLoading)
                }
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
        .sheet(isPresented: $workspace.showsPaywall) { ProPaywallView(model: workspace.purchases, feature: workspace.requestedProFeature) }
        .onChange(of: workspace.quickCaptures.map { $0.document.id }) { previous, current in
            if current.contains(where: { !previous.contains($0) }), let capture = workspace.quickCapture {
                QuickCapturePanelController.shared.present(workspace: workspace, model: capture)
            } else { QuickCapturePanelController.shared.refreshLayout(animated: true) }
        }
        .sheet(isPresented: $workspace.showsOnboarding, onDismiss: {
            let action = pendingOnboardingAction
            pendingOnboardingAction = nil
            switch action {
            case .capture:
                CaptureLauncher.capture(.region, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            case .example:
                workspace.openOnboardingExample()
            case .skip, nil:
                break
            }
        }) {
            OnboardingView(shortcuts: workspace.captureShortcuts) { action in
                workspace.preferences.completedOnboarding = true
                pendingOnboardingAction = action
                workspace.showsOnboarding = false
            }
        }
        .onAppear { [weak workspace, openWindow, dismissWindow] in
            workspace?.showWorkspaceWindow = { AppWindows.show("workspace", using: openWindow) }
            workspace?.onQuickCaptureReady = { [weak workspace] model in
                guard let workspace else { return }
                QuickCapturePanelController.shared.present(workspace: workspace, model: model)
            }
            guard let workspace else { return }
            // Keep the scene-opening action available to global hotkeys even when
            // the workspace window is closed. The workspace lives with the app.
            workspace.captureShortcuts.start { [weak workspace] action in
                guard let workspace else { return }
                CaptureLauncher.capture(action, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
            }
        }
        .overlay { if workspace.isLoading && workspace.openingProjectID == nil && (workspace.section != .editor || workspace.editor == nil || workspace.isChangingLibrary || workspace.isTransferring) { ProgressView(workspace.isChangingLibrary ? String(localized: "Bibliothek übernehmen …") : workspace.isTransferring ? String(localized: "Projekte verarbeiten …") : String(localized: "Projekt öffnen …")).padding(24).background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
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
            set: { if !$0 { workspace.acknowledgeImportError() } }
        )) {
            Button("OK", role: .cancel) { workspace.acknowledgeImportError() }
        } message: {
            Text(workspace.importError ?? "")
        }
    }

    private func capture(_ action: CaptureAction) {
        CaptureLauncher.capture(action, workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
    }

    @ViewBuilder private var guideReturnActions: some View {
        Text(String(localized: "Bild für deine Anleitung bearbeiten")).font(.callout)
        Button(String(localized: "Zurück zur Anleitung")) { Task { await workspace.returnToGuide(applyingChanges: false) } }
        Button(String(localized: "Änderungen übernehmen")) { Task { await workspace.returnToGuide(applyingChanges: true) } }
            .buttonStyle(.glassProminent).disabled(!workspace.purchases.hasPro || workspace.isLoading || workspace.guides.isBusy)
            .accessibilityIdentifier("guide.applyImageChanges")
    }

    private var navigationAnimation: Animation? {
        // Keyboard/VoiceOver navigation and programmatic capture routing stay immediate.
        guard let type = NSApp.currentEvent?.type, type == .leftMouseDown || type == .leftMouseUp else { return nil }
        return reduceMotion ? .linear(duration: 0.08) : .smooth(duration: 0.18, extraBounce: 0)
    }

}

// Only navigation transactions suppress descendant animation. Internal actions,
// such as moving guide steps, keep their own motion and never animate the canvas.
private struct SidebarTransition: TransactionKey {
    static let defaultValue = false
}

private struct MediaTransition: TransactionKey {
    static let defaultValue = false
}
