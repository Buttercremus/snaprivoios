import SwiftUI

struct SettingsView: View {
    let workspace: WorkspaceModel
    var body: some View {
        TabView {
            GeneralSettings(preferences: workspace.preferences, workspace: workspace)
                .tabItem { Label(String(localized: "Allgemein"), systemImage: "gearshape") }
            EditorToolbarSettings(preferences: workspace.preferences)
                .tabItem { Label(String(localized: "Symbolleiste"), systemImage: "slider.horizontal.3") }
            StorageSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Speicherorte"), systemImage: "folder") }
            CaptureSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Aufnahme"), systemImage: "viewfinder") }
            ShortcutSettings(shortcuts: workspace.captureShortcuts)
                .tabItem { Label(String(localized: "Tastenkürzel"), systemImage: "keyboard") }
            PrivacySettings(screenshot: workspace.screenshot)
                .tabItem { Label(String(localized: "Datenschutz"), systemImage: "hand.raised") }
        }
        .padding(.top, 8)
        .frame(width: 680, height: 580)
        .onDisappear { workspace.captureShortcuts.cancelRecording() }
        .onAppear { workspace.preferences.applyAppearance() }
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: AppPreferences
    let workspace: WorkspaceModel
    var body: some View {
        Form {
            Section(String(localized: "Sprache")) {
                Picker(String(localized: "Sprache"), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.language")
                Text(String(localized: "Die Sprache wird beim nächsten Start von Snaprivo übernommen. Die Systemsprache deines Macs bleibt unverändert."))
                    .font(.callout).foregroundStyle(.secondary)
                if preferences.requiresLanguageRestart {
                    Button(String(localized: "Snaprivo beenden")) { NSApplication.shared.terminate(nil) }
                        .accessibilityIdentifier("settings.language.quit")
                    Text(String(localized: "Öffne Snaprivo anschließend erneut, um die neue Sprache zu verwenden."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "Erscheinungsbild")) {
                Picker(String(localized: "Darstellung"), selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance")
                Text(String(localized: "System übernimmt die Einstellung von macOS. Die Auswahl gilt sofort für Snaprivo und bleibt gespeichert."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            CaptureClipboardSettings(preferences: preferences)
            Section(String(localized: "Projekte")) {
                LabeledContent(String(localized: "Speicherung"), value: String(localized: "Lokal · Automatisch"))
                Text(String(localized: "Aufnahmen und importierte Bilder bleiben mit ihren Markierungen und Zuschnitten in der Bibliothek bearbeitbar. ⌘S sichert sofort."))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(String(localized: "Bildinhalt lokal durchsuchen (OCR)"), isOn: Binding(
                    get: { workspace.purchases.hasPro && preferences.ocrIndexingEnabled }, set: { workspace.setOCRIndexing($0) }))
                    .accessibilityIdentifier("settings.library.ocr")
                Text(String(localized: "Texterkennung und OCR-Inhaltssuche gehören zu Pro. Die Indexierung ist zunächst aus und bleibt lokal. Ausschalten entfernt den Suchcache."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(String(localized: "Snaprivo")) {
                LabeledContent(String(localized: "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Entwicklungsversion"))
                LabeledContent(String(localized: "Unterstützt"), value: String(localized: "macOS 26 oder neuer"))
                SupportFeedbackButton()
            }
        }.formStyle(.grouped)
    }
}

struct CaptureClipboardSettings: View {
    @Bindable var preferences: AppPreferences
    var body: some View {
        Section(String(localized: "Nach dem Screenshot")) {
            Toggle(String(localized: "Schnellvorschau nach der Aufnahme"), isOn: $preferences.quickPreviewAfterCapture)
            Text(String(localized: "Bis zu fünf Aufnahmen bleiben unten links griffbereit. Schließen entfernt nur die Vorschau; die Bilder bleiben in der Bibliothek."))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(String(localized: "Screenshot automatisch in die Zwischenablage kopieren"), isOn: $preferences.copyAfterCapture)
                .accessibilityIdentifier("settings.capture.copy")
            Text(String(localized: "Nach dem Bestätigen der Aufnahme steht das PNG automatisch zum Einfügen bereit. Der Screenshot bleibt zusätzlich als bearbeitbares Projekt im Editor. Gilt auch für Scroll-Aufnahmen; Bildimporte werden nicht kopiert."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct EditorToolbarSettings: View {
    @Bindable var preferences: AppPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Symbolgröße"), selection: $preferences.toolbarSize) {
                ForEach(EditorToolbarSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).accessibilityIdentifier("settings.toolbarSize")
            Text(String(localized: "Mit dem Auge Symbole ein- oder ausblenden. Zeilen ziehen oder mit den Pfeilen verschieben; oben entspricht links in der Leiste. Änderungen bleiben gespeichert."))
                .font(.callout).foregroundStyle(.secondary)
            Text(String(localized: "Die ersten vier sichtbaren Bildaktionen stehen direkt in der Leiste, weitere unter Mehr. Bei wenig Platz wandern zusätzliche Aktionen ins Menü."))
                .font(.caption).foregroundStyle(.secondary)
            List {
                Section(String(localized: "Bildaktionen · rechts")) {
                    ForEach(preferences.imageToolbarActions) { action in
                        ToolbarOrderRow(title: action.title, symbol: action.symbol, id: "action.\(action.id)",
                                        item: action, order: $preferences.imageToolbarActions, hidden: $preferences.hiddenToolbarActions)
                    }
                    .onMove { preferences.imageToolbarActions.move(fromOffsets: $0, toOffset: $1) }
                }
                Section(String(localized: "Werkzeuge · links")) {
                    ForEach(preferences.toolbarTools, id: \.rawValue) { tool in
                        if let item = EditorToolItem.all.first(where: { $0.tool == tool }) {
                            ToolbarOrderRow(title: item.title, symbol: item.symbol, id: "tool.\(item.id)",
                                            item: tool, order: $preferences.toolbarTools, hidden: $preferences.hiddenToolbarTools)
                        }
                    }
                    .onMove { preferences.toolbarTools.move(fromOffsets: $0, toOffset: $1) }
                    ForEach(preferences.extraToolbarTools) { action in
                        ToolbarOrderRow(title: action.title, symbol: action.symbol, id: "action.\(action.id)",
                                        item: action, order: $preferences.extraToolbarTools, hidden: $preferences.hiddenToolbarActions)
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("settings.toolbar.order")
            HStack {
                Button(String(localized: "Alle einblenden")) { preferences.showAllToolbarItems() }
                    .disabled(preferences.hiddenToolbarTools.isEmpty && preferences.hiddenToolbarActions.isEmpty)
                    .accessibilityIdentifier("settings.toolbar.showAll")
                Spacer()
                Button(String(localized: "Standardreihenfolge wiederherstellen")) { preferences.resetToolbarOrder() }
                    .disabled(preferences.toolbarTools == EditorToolItem.all.map(\.tool)
                              && preferences.toolbarActions == EditorToolbarAction.allCases)
                    .accessibilityIdentifier("settings.toolbar.reset")
            }
        }
        .padding(20)
    }
}

private struct ToolbarOrderRow<Item: Hashable>: View {
    let title: String
    let symbol: String
    let id: String
    let item: Item
    @Binding var order: [Item]
    @Binding var hidden: Set<Item>
    private var index: Int { order.firstIndex(of: item) ?? 0 }
    private var isVisible: Bool { !hidden.contains(item) }
    private var visibilityAction: String {
        isVisible ? String(localized: "\(title) ausblenden") : String(localized: "\(title) einblenden")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if isVisible { hidden.insert(item) } else { hidden.remove(item) }
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash").frame(width: 24, height: 24)
            }
            .foregroundStyle(isVisible ? Color.primary : Color.secondary)
            .help(visibilityAction)
            .accessibilityLabel(visibilityAction)
            .accessibilityValue(isVisible ? String(localized: "Eingeblendet") : String(localized: "Ausgeblendet"))
            .accessibilityIdentifier("settings.toolbar.\(id).visibility")
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            Image(systemName: symbol).resizable().scaledToFit()
                .frame(width: 18, height: 18).frame(width: 24).accessibilityHidden(true)
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)
            Text(title).foregroundStyle(isVisible ? Color.primary : Color.secondary)
            Spacer()
            Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help(String(localized: "\(title) nach links verschieben"))
                .accessibilityLabel(String(localized: "\(title) nach links verschieben"))
                .accessibilityIdentifier("settings.toolbar.\(id).earlier")
            Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == order.count - 1)
                .help(String(localized: "\(title) nach rechts verschieben"))
                .accessibilityLabel(String(localized: "\(title) nach rechts verschieben"))
                .accessibilityIdentifier("settings.toolbar.\(id).later")
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityValue(String(localized: "Position \(index + 1) von \(order.count)"))
    }
    private func move(by offset: Int) {
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? destination + 1 : destination)
    }
}

private struct StorageSettings: View {
    let workspace: WorkspaceModel
    @State private var usage: CompleteBackup.Usage?
    @State private var usageError: String?
    var body: some View {
        Form {
            Section(String(localized: "Alle Inhalte")) {
                if let usage {
                    LabeledContent(String(localized: "Bilder einschließlich Papierkorb"), value: ByteCountFormatter.string(fromByteCount: usage.images, countStyle: .file))
                    LabeledContent(String(localized: "Videos einschließlich Papierkorb"), value: ByteCountFormatter.string(fromByteCount: usage.videos, countStyle: .file))
                    LabeledContent(String(localized: "Anleitungen"), value: ByteCountFormatter.string(fromByteCount: usage.guides, countStyle: .file))
                    if let available = usage.available { LabeledContent(String(localized: "Frei am Bildspeicherort"), value: ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) }
                }
                if let usageError { Text(usageError).foregroundStyle(.secondary) }
                Button(String(localized: "Speicherbelegung aktualisieren")) { Task { await refreshUsage() } }

                Button(String(localized: "Alles sichern …")) { workspace.chooseTransfer(.completeBackup) }
                Button(String(localized: "Alles wiederherstellen …")) { workspace.chooseTransfer(.restoreComplete) }
                Button(String(localized: "Bisherige Snaprivo-Daten übernehmen …")) { workspace.chooseTransfer(.importLegacy) }
                Text(String(localized: "Bilder, Videos, Papierkörbe und Anleitungen in einer Sicherung. Zum Freigeben von Speicherplatz Videos in der Bibliothek entfernen und ihren Papierkorb prüfen."))
                    .font(.callout).foregroundStyle(.secondary)
            }.disabled(!workspace.canChangeStorage)
            Section(String(localized: "PNG-Standardordner")) {
                LabeledContent(String(localized: "Ordner")) {
                    Text(workspace.storage.path(for: .png) ?? String(localized: "Beim Speichern wählen"))
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Button(String(localized: "Ordner wählen …")) { workspace.chooseStorageFolder(.png) }
                        .accessibilityIdentifier("settings.storage.png.choose")
                    Button(String(localized: "Zurücksetzen")) { workspace.storage.clearPNGFolder(); workspace.storageNotice = nil }
                        .disabled(workspace.storage.path(for: .png) == nil)
                        .accessibilityIdentifier("settings.storage.png.reset")
                }.disabled(!workspace.canChangeStorage)
                Text(String(localized: "„PNG speichern …“ beginnt in diesem Ordner. Du kannst den Zielort beim Speichern weiter ändern."))
                    .font(.callout).foregroundStyle(.secondary)
                if let error = workspace.storage.errors[.png] { Text(error).font(.callout).foregroundStyle(.orange) }
            }
            Section(String(localized: "Projektbibliothek")) {
                LabeledContent(String(localized: "Ordner")) {
                    Text((workspace.storage.libraryURL ?? workspace.storage.storedLibraryURL ?? workspace.store.root).path)
                        .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                }
                Button(workspace.storage.libraryError == nil ? String(localized: "Ordner ändern …") : String(localized: "Ordner erneut freigeben …")) {
                    workspace.chooseStorageFolder(.library)
                }.disabled(!workspace.canChangeStorage).accessibilityIdentifier("settings.storage.library.choose")
                Text(String(localized: "Enthält Originale, bearbeitbare Projekte und Papierkorb. Snaprivo legt im gewählten Ordner „Snaprivo-Bibliothek“ an und übernimmt die vorhandenen Projekte. Der bisherige Ordner bleibt erhalten."))
                    .font(.callout).foregroundStyle(.secondary)
                if let error = workspace.storage.libraryError { Text(error).font(.callout).foregroundStyle(.orange) }
                if workspace.isChangingLibrary { ProgressView(String(localized: "Projekte und Papierkorb übernehmen …")) }
            }
            if let notice = workspace.storageNotice { Text(notice).font(.callout).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .task { await refreshUsage() }
        .alert(String(localized: "Speicherort konnte nicht geändert werden"), isPresented: Binding(
            get: { workspace.storageError != nil }, set: { if !$0 { workspace.storageError = nil } })) {
                Button("OK") { workspace.storageError = nil }
            } message: { Text(workspace.storageError ?? "") }
    }
    private func refreshUsage() async {
        do {
            usage = try await CompleteBackup(images: workspace.store, videos: workspace.videos.files, guides: workspace.guides.store).usage()
            usageError = nil
        } catch { usageError = error.localizedDescription }
    }

}

private struct CaptureSettings: View {
    let workspace: WorkspaceModel
    var body: some View {
        Form {
            Section(String(localized: "Aufnahmevorgaben")) {
                Picker(String(localized: "Vorlauf"), selection: Binding(get: { workspace.preferences.captureDelay }, set: {
                    workspace.preferences.captureDelay = $0
                    if !workspace.screenshot.isBusy { workspace.captureConfiguration.delaySeconds = $0 }
                })) {
                    Text(String(localized: "Keine")).tag(0); Text(String(localized: "3 Sekunden")).tag(3); Text(String(localized: "5 Sekunden")).tag(5)
                }.accessibilityIdentifier("settings.capture.delay")
                Text(String(localized: "Bei Screenshots vor der Auswahl, bei Video direkt nach dem Klick auf „Video“. Während des Vorlaufs kannst du abbrechen."))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(String(localized: "Mauszeiger aufnehmen"), isOn: Binding(get: { workspace.preferences.includesCursor }, set: {
                    workspace.preferences.includesCursor = $0
                    if !workspace.screenshot.isBusy { workspace.captureConfiguration.includesCursor = $0 }
                })).accessibilityIdentifier("settings.capture.cursor")
                Text(String(localized: "Neue Aufnahme erkennt Fenster automatisch. Ziehen wählt einen freien Bereich; vor dem Bestätigen lässt sich der Rahmen korrigieren."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(String(localized: "Videoton")) {
                Toggle(String(localized: "Mausklicks im Video hervorheben"), isOn: Binding(
                        get: { workspace.preferences.videoMouseClicks },
                        set: { workspace.preferences.videoMouseClicks = $0 }))
                    .accessibilityIdentifier("settings.capture.mouseClicks")
                Toggle(String(localized: "Systemton aufnehmen"), isOn: Binding(
                    get: { workspace.preferences.videoSystemAudio },
                    set: { workspace.preferences.videoSystemAudio = $0 }))
                    .accessibilityIdentifier("settings.capture.systemAudio")
                Text(String(localized: "Nimmt auch Ton von Apps außerhalb des Bildausschnitts auf."))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(String(localized: "Mikrofon aufnehmen"), isOn: Binding(
                    get: { workspace.preferences.videoMicrophone },
                    set: { workspace.preferences.videoMicrophone = $0 }))
                    .accessibilityIdentifier("settings.capture.microphone")
                Text(String(localized: "Die Tonoptionen gelten für neue Videos. Mikrofonzugriff fragt macOS erst beim Aufnahmestart an."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            CaptureClipboardSettings(preferences: workspace.preferences)
            Section(String(localized: "Ausgabe")) {
                LabeledContent(String(localized: "Bildformat"), value: String(localized: "PNG · sRGB · mit Transparenz"))
                Text(String(localized: "„PNG speichern …“ exportiert den bearbeiteten Ausschnitt an einen gewählten Ort. Das Original bleibt im Projekt erhalten."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    let shortcuts: GlobalCaptureShortcuts
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Auch in anderen Apps verfügbar"), isOn: Binding(get: { shortcuts.isEnabled }, set: { shortcuts.setEnabled($0) }))
                    .accessibilityIdentifier("settings.shortcuts.enabled")
                Text(String(localized: "Snaprivo muss dafür laufen. Die Menüs in Snaprivo bleiben mit den gewählten Kürzeln bedienbar."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(String(localized: "Aufnahme-Tastenkürzel")) }
            Section {
                ForEach([CaptureAction.region, .display, .delayedRegion, .window], id: \.rawValue) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(action.title, systemImage: action.symbol)
                            Spacer(minLength: 8)
                            ShortcutRecorder(action: action, shortcuts: shortcuts).frame(width: 170, height: 30)
                            Button { shortcuts.setShortcut(nil, for: action) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help(String(localized: "Kürzel für \(action.title) entfernen"))
                                .accessibilityLabel(String(localized: "Kürzel für \(action.title) entfernen"))
                                .disabled(shortcuts.bindings[action] == nil)
                        }
                        if shortcuts.recordingAction == action {
                            Text(shortcuts.recordingError ?? String(localized: "Jetzt ⌘, ⌥ oder ⌃ zusammen mit einer Taste drücken. Esc: abbrechen · ⌫: entfernen"))
                                .font(.callout).foregroundStyle(shortcuts.recordingError == nil ? Color.secondary : Color.orange)
                        } else if shortcuts.unavailable.contains(action) {
                            Text(String(localized: "Nicht verfügbar. Möglicherweise von macOS oder einer anderen App belegt; wähle ein anderes Kürzel."))
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                }
                HStack {
                    Button(String(localized: "Standardkürzel wiederherstellen")) { shortcuts.restoreDefaults() }
                    Spacer()
                    if !shortcuts.unavailable.isEmpty {
                        Button(String(localized: "Erneut prüfen")) { shortcuts.retryRegistration() }
                    }
                }
            } footer: {
                Text(String(localized: "Klicke auf ein Kürzel und drücke deine Kombination. Doppelte Belegungen und reservierte Editorbefehle werden abgelehnt. Die alternative Aufnahme startet dieselbe Fenster-/Bereichsauswahl."))
            }
            if let error = shortcuts.preferencesError { Text(error).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .onDisappear { shortcuts.cancelRecording() }
    }
}

private struct PrivacySettings: View {
    let screenshot: ScreenshotCoordinator
    @State private var hasPermission = false
    var body: some View {
        Form {
            Section(String(localized: "Bildschirmzugriff")) {
                Label(hasPermission ? String(localized: "Bildschirmzugriff ist freigegeben") : String(localized: "Bildschirmzugriff ist noch nicht freigegeben"),
                      systemImage: hasPermission ? "checkmark.circle.fill" : "lock")
                    .foregroundStyle(hasPermission ? Color.green : Color.secondary)
                HStack {
                    Button(String(localized: "Systemeinstellungen öffnen")) { screenshot.openPrivacySettings() }
                    Button(String(localized: "Status prüfen")) { refresh() }
                }
                Text(String(localized: "macOS fragt beim ersten Aufnahmeauftrag nach deiner Freigabe. Die Tastenkürzel benötigen keine Bedienungshilfen- oder Eingabeüberwachungsfreigabe."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(String(localized: "Deine Inhalte")) {
                Text(String(localized: "Bilder und bearbeitbare Projekte bleiben lokal auf deinem Mac. Snaprivo überträgt keine Bildinhalte und enthält derzeit keine Analyse- oder Cloud-Dienste."))
                Text(String(localized: "Das Projekt behält sein vollständiges Original. Zuschnitt und Unschärfe entfernen keine Quelldaten aus dem bearbeitbaren Projekt."))
                    .font(.callout).foregroundStyle(.secondary)
                Link(String(localized: "Datenschutzerklärung"), destination: SnaprivoPrivacyPolicy.url(for: Bundle.main.preferredLocalizations))
                    .accessibilityIdentifier("settings.privacy.policy")
            }
        }.formStyle(.grouped)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() { screenshot.refreshPermission(); hasPermission = screenshot.hasPermission }
}

enum SnaprivoPrivacyPolicy {
    static func url(for preferredLanguages: [String]) -> URL {
        let language = Bundle.preferredLocalizations(from: ["en", "de"], forPreferences: preferredLanguages).first
        return URL(string: language == "de"
            ? "https://snaprivo.com/de/privacy/"
            : "https://snaprivo.com/en/privacy/")!
    }
}
