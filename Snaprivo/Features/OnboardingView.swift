import SwiftUI
import SnagForgeDomain

struct OnboardingView: View {
    let shortcuts: GlobalCaptureShortcuts
    let finish: (Bool) -> Void
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        switch step {
        case 0: String(localized: "Ein Bild. Alles erklärt.")
        case 1: String(localized: "Zeig, worauf es ankommt.")
        case 2: String(localized: "Bereit zum Weitergeben.")
        default: String(localized: "Dein Kürzel. Dein Start.")
        }
    }
    private var explanation: String {
        switch step {
        case 0: String(localized: "Klicke am Auswahlrahmen auf „Foto“ für ein Bild oder auf „Video“ für eine Videoaufnahme. Bilder öffnen sich im Editor. Video startet direkt mit deinen Tonoptionen aus den Einstellungen. Mit „Stop“ beendest du die Aufnahme. Deine Aufnahmen bleiben lokal.")
        case 1: String(localized: "Zeichne Pfeile, kreise Details ein und decke vertraulichen Text ab. Jede Markierung bleibt bearbeitbar. Mit ⌘Z machst du Änderungen rückgängig.")
        case 2: String(localized: "Dein Projekt wird automatisch gesichert. Mit ⌘S speicherst du ein PNG. Unter Bildausgabe findest du JPEG, PDF und die Gestaltung mit Hintergrund und Schatten. Videos findest du in der Bibliothek unter Videos und kannst sie als MP4 speichern.")
        default: String(localized: "Übernimm dein Screenshot-Kürzel oder klicke darauf und drücke deine Wunschkombination. Du kannst es später in Einstellungen → Tastenkürzel ändern.")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Snaprivo", systemImage: "viewfinder").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "Schritt \(step + 1) von 4")).font(.callout).foregroundStyle(.secondary)
            }
            OnboardingIllustration(step: step, shortcutLabel: shortcuts.bindings[.region]?.label ?? "—").frame(height: step == 3 ? 110 : 160).id(step).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(explanation).font(.body).fixedSize(horizontal: false, vertical: true).frame(minHeight: 65, alignment: .topLeading)
            if step == 0 {
                Label(String(localized: "macOS fragt bei der ersten Aufnahme nach Bildschirmzugriff. Mikrofonzugriff wird erst beim Videostart mit eingeschaltetem Mikrofon angefragt."), systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if step == 3 {
                HStack {
                    Label(String(localized: "Neue Aufnahme"), systemImage: "camera")
                    Spacer()
                    ShortcutRecorder(action: .region, shortcuts: shortcuts).frame(width: 170, height: 30)
                }
                Toggle(String(localized: "Auch in anderen Apps verfügbar"), isOn: Binding(
                    get: { shortcuts.isEnabled }, set: { shortcuts.setEnabled($0) }))
                Text(String(localized: "Snaprivo muss dafür laufen. Die Menüs in Snaprivo bleiben mit den gewählten Kürzeln bedienbar."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error = shortcuts.recordingError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                } else if shortcuts.unavailable.contains(.region) {
                    Text(String(localized: "Nicht verfügbar. Möglicherweise von macOS oder einer anderen App belegt; wähle ein anderes Kürzel."))
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button(String(localized: "Überspringen")) { finish(false) }.keyboardShortcut(.cancelAction)
                Spacer()
                if step > 0 { Button(String(localized: "Zurück")) { changeStep(-1) } }
                Button(step == 3 ? String(localized: "Erste Aufnahme starten") : String(localized: "Weiter")) {
                    if step == 3 { shortcuts.cancelRecording(); finish(true) } else { changeStep(1) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 620, height: 620)
        .interactiveDismissDisabled()
        .onDisappear { shortcuts.cancelRecording() }
    }
    private func changeStep(_ delta: Int) {
        shortcuts.cancelRecording()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step += delta }
    }
}

private struct OnboardingIllustration: View {
    let step: Int
    let shortcutLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.08))
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in Circle().fill(.secondary.opacity(0.3)).frame(width: 7, height: 7) }
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.16)).frame(width: 150, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.1)).frame(height: 38)
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.1)).frame(width: 200, height: 12)
            }.padding(20).frame(width: 300).background(.background, in: .rect(cornerRadius: 12))
            if step == 0 {
                RoundedRectangle(cornerRadius: 10).trim(from: 0, to: revealed || reduceMotion ? 1 : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [7, 4])).frame(width: 318, height: 160)
                Image(systemName: "cursorarrow").font(.title).foregroundStyle(.tint).offset(x: 152, y: 72)
            } else if step == 1 {
                Path { p in
                    p.move(to: CGPoint(x: 110, y: 45)); p.addQuadCurve(to: CGPoint(x: 245, y: 95), control: CGPoint(x: 205, y: 30))
                    p.move(to: CGPoint(x: 224, y: 91)); p.addLine(to: CGPoint(x: 245, y: 95)); p.addLine(to: CGPoint(x: 240, y: 74))
                }.trim(from: 0, to: revealed || reduceMotion ? 1 : 0).stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Ellipse().trim(from: 0.02, to: revealed || reduceMotion ? 0.97 : 0.02)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 130, height: 48).offset(x: 48, y: 4)
                Capsule().fill(.primary).frame(width: 110, height: 14).offset(x: -55, y: 45).opacity(revealed || reduceMotion ? 1 : 0)
            } else if step == 3 {
                Label(shortcutLabel, systemImage: "keyboard").font(.title.bold()).padding(18)
                    .background(.background, in: .rect(cornerRadius: 14))
            } else {
                Label("⌘S", systemImage: "square.and.arrow.down").font(.title.bold()).padding(18)
                    .background(.background, in: .rect(cornerRadius: 14)).shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.9).opacity(revealed || reduceMotion ? 1 : 0)
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { revealed = true } }
    }
}

struct EditorLearningHint: View {
    let tool: AnnotationTool
    let preferences: AppPreferences
    private var key: String { tool == .arrow || tool == .ellipse ? "drawing" : tool == .selection ? "selection" : "output" }
    private var message: String {
        switch key {
        case "drawing": String(localized: "Wie von Hand: Wähle rechts Zeichenstil → Handgezeichnet für Pfeile und Kreise.")
        case "selection": String(localized: "Gemeinsam bearbeiten: Umschalt-Klick wählt mehrere Objekte. ⌘G gruppiert sie.")
        default: String(localized: "Fertig zum Teilen? ⌘S speichert ein PNG. Bildausgabe bietet JPEG, PDF und Hintergründe.")
        }
    }
    var body: some View {
        if !preferences.dismissedEditorHints.contains(key) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(.tint)
                Text(message).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(String(localized: "Verstanden")) { preferences.dismissedEditorHints.insert(key) }
            }.font(.callout).padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}
