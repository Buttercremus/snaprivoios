import SwiftUI
import SnagForgeDomain

struct CaptureSetupView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var explainsPermission = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(workspace.screenshot.needsPermission ? String(localized: "Bildschirmzugriff") : String(localized: "Aufnahmeoptionen")).font(.title2.bold())

            Label(workspace.screenshot.hasPermission ? String(localized: "Bildschirmzugriff bereit") : String(localized: "Bildschirmzugriff erforderlich"),
                  systemImage: workspace.screenshot.hasPermission ? "checkmark.circle" : "lock")
                .font(.callout).accessibilityIdentifier("capture.permission.status")
            Text(workspace.isScrollCapture ? String(localized: "Wähle nur den scrollenden Inhalt ohne feste Kopfzeile. Danach manuell nach unten scrollen und Abschnitte hinzufügen.") : sourceDescription)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .topLeading)

            Form {
                Picker(configuration.media == .video ? String(localized: "Vorlauf vor Video") : String(localized: "Vorlauf vor Auswahl"), selection: Binding(get: { workspace.captureConfiguration.delaySeconds }, set: {
                    workspace.captureConfiguration.delaySeconds = $0; workspace.preferences.captureDelay = $0
                })) {
                    Text(String(localized: "Keine")).tag(0)
                    Text(String(localized: "3 Sekunden")).tag(3)
                    Text(String(localized: "5 Sekunden")).tag(5)
                }
                Toggle(String(localized: "Mauszeiger aufnehmen"), isOn: Binding(get: { workspace.captureConfiguration.includesCursor }, set: {
                    workspace.captureConfiguration.includesCursor = $0; workspace.preferences.includesCursor = $0
                }))
                if configuration.media == .image {
                    Toggle(String(localized: "Screenshot automatisch kopieren"), isOn: Binding(
                        get: { workspace.preferences.copyAfterCapture }, set: { workspace.preferences.copyAfterCapture = $0 }
                    )).accessibilityIdentifier("capture.copyAfterCapture")
                }
            }
            .disabled(workspace.screenshot.isBusy)

            Divider()
            if let error = workspace.screenshot.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if workspace.screenshot.needsPermission {
                    HStack {
                        Button(String(localized: "Systemeinstellungen öffnen")) { workspace.screenshot.openPrivacySettings() }
                        if workspace.screenshot.permissionWasRequested || workspace.screenshot.needsRestart {
                            Button(String(localized: "App beenden")) { NSApp.terminate(nil) }
                                .help(String(localized: "Danach Snaprivo erneut öffnen, damit macOS die Freigabe übernimmt."))
                        }
                    }
                }
            }
            if workspace.screenshot.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(workspace.screenshot.status)
                    Spacer()
                    Button(String(localized: "Abbrechen")) { workspace.screenshot.cancel() }
                }
            } else {
                Text(configuration.media == .video ? String(localized: "Auswahl bestätigen. Danach optional Systemton und Mikrofon wählen, Video starten, mit Stop beenden und als MP4 speichern. Mikrofonzugriff wird nur beim Start mit gewähltem Mikrofon angefragt.") : String(localized: "1. Fenster anklicken oder einen freien Bereich aufziehen.\n2. Rahmen korrigieren und mit „Aufnehmen“ oder Enter bestätigen.\n3. Im Editor beschriften und als PNG speichern oder kopieren.\n\nDein Projekt wird automatisch gesichert. Esc bricht die Auswahl ab."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(workspace.screenshot.needsPermission ? String(localized: "Erneut prüfen") : String(localized: "Auswahl starten"), systemImage: "viewfinder") {
                        requestCapture()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(workspace.isLoading)
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            workspace.screenshot.refreshPermission()
            consumePendingCapture()
        }
        .onChange(of: workspace.pendingCapture) { _, _ in consumePendingCapture() }
        .onDisappear {
            workspace.pendingCapture = nil
            workspace.screenshot.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { workspace.screenshot.refreshPermission() }
        }
        .alert(String(localized: "Bildschirmaufnahme erlauben"), isPresented: $explainsPermission) {
            Button(String(localized: "Zugriff anfragen")) { beginCapture(requestPermission: true) }
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        } message: {
            Text(String(localized: "Snaprivo benötigt die macOS-Freigabe, um Fenster zu erkennen und deinen gewählten Bereich aufzunehmen. Die Aufnahme bleibt lokal. Im nächsten Schritt fragt macOS nach deiner Erlaubnis."))
        }
    }

    private var configuration: CaptureConfiguration { workspace.captureConfiguration }

    private func consumePendingCapture() {
        guard workspace.pendingCapture != nil else { return }
        workspace.pendingCapture = nil
        requestCapture()
    }

    private func requestCapture() {
        guard !workspace.screenshot.isBusy, !workspace.isLoading else { return }
        if workspace.screenshot.hasPermission || workspace.screenshot.needsPermission {
            beginCapture(requestPermission: false)
        } else {
            explainsPermission = true
        }
    }

    private func beginCapture(requestPermission: Bool = false) {
        CaptureLauncher.begin(workspace: workspace, using: openWindow, dismissWindow: dismissWindow,
                              requestPermission: requestPermission)
    }

    private var sourceDescription: String {
        return switch configuration.source {
        case .automatic: String(localized: "Fenster und freie Bereiche in einer Auswahl: Klicken markiert das erkannte Fenster, Ziehen markiert einen freien Bereich.")
        case .region: String(localized: "Ziehe mit der Maus einen Rahmen um den gewünschten Bereich.")
        case .window: String(localized: "Bewege die Maus über ein Fenster und klicke auf die hervorgehobene Fläche.")
        case .display: String(localized: "Wähle den Bildschirm aus, den du aufnehmen möchtest.")
        }
    }
}
