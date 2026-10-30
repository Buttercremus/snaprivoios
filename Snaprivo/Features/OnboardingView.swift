import SwiftUI
import SnagForgeDomain

enum OnboardingAction: Equatable {
    case skip
    case capture
    case example
}

struct OnboardingView: View {
    let shortcuts: GlobalCaptureShortcuts
    let finish: (OnboardingAction) -> Void

    enum Stage: Int, CaseIterable, Identifiable {
        case capture, annotate, copy
        var id: Self { self }
        var title: String {
            switch self {
            case .capture: String(localized: "Aufnehmen")
            case .annotate: String(localized: "Markieren")
            case .copy: String(localized: "Kopieren")
            }
        }
        var symbol: String {
            switch self {
            case .capture: "camera.viewfinder"
            case .annotate: "pencil.and.outline"
            case .copy: "doc.on.clipboard"
            }
        }
        var explanation: String {
            switch self {
            case .capture: String(localized: "Wähle einen Bereich aus – Snaprivo hält ihn als Bild fest und zeigt je nach Einstellung zuerst die Schnellvorschau.")
            case .annotate: String(localized: "Zeichne Pfeile, Kreise oder Abdeckungen. Markierungen lassen sich jederzeit verschieben und ändern.")
            case .copy: String(localized: "Kopiere das fertige Bild mit ⌘C oder exportiere es als PNG, JPEG oder PDF.")
            }
        }
    }

    @State private var stage: Stage = .capture
    @State private var showsShortcutOptions = false
    @State private var demoProgress = 0.0
    @State private var replay = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Snaprivo", systemImage: "viewfinder")
                    .font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "Schnellstart"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker(String(localized: "Schnellstart"), selection: $stage) {
                ForEach(Stage.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("onboarding.stage")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingIllustration(stage: stage, progress: demoProgress)
                        .frame(height: 160).accessibilityHidden(true)
                    HStack {
                        Spacer()
                        Button(String(localized: "Erneut zeigen"), systemImage: "arrow.clockwise") { replay += 1 }
                            .buttonStyle(.borderless)
                            .disabled(reduceMotion)
                            .help(String(localized: "Animation erneut abspielen"))
                            .accessibilityIdentifier("onboarding.replay")
                    }
                    Text(stage.title)
                        .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(stage.explanation)
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    if stage == .capture {
                        Label(String(localized: "Bei der ersten Aufnahme bittet macOS um Bildschirmzugriff. Snaprivo verarbeitet Aufnahmen lokal."), systemImage: "lock.shield")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if stage == .copy {
                        Label(String(localized: "Dein Original bleibt im Projekt erhalten; Kopieren und Export erzeugen eine fertige Ausgabe."), systemImage: "checkmark.shield")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup(String(localized: "Aufnahmekürzel anpassen"), isExpanded: $showsShortcutOptions) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(String(localized: "Neue Aufnahme"), systemImage: "camera")
                                Spacer()
                                ShortcutRecorder(action: .region, shortcuts: shortcuts).frame(width: 170, height: 30)
                            }
                            Toggle(String(localized: "Auch in anderen Apps verfügbar"), isOn: Binding(
                                get: { shortcuts.isEnabled }, set: { shortcuts.setEnabled($0) }))
                            if let error = shortcuts.recordingError {
                                Text(error).font(.callout).foregroundStyle(.orange)
                            } else if shortcuts.unavailable.contains(.region) {
                                Text(String(localized: "Nicht verfügbar. Möglicherweise von macOS oder einer anderen App belegt."))
                                    .font(.callout).foregroundStyle(.orange)
                            }
                        }.padding(.top, 6)
                    }
                    .accessibilityIdentifier("onboarding.shortcut.options")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button(String(localized: "Überspringen")) { complete(.skip) }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("onboarding.skip")
                Spacer()
                Button(String(localized: "Mit Beispiel üben")) { complete(.example) }
                    .accessibilityIdentifier("onboarding.example")
                Button(String(localized: "Erste Aufnahme starten")) { complete(.capture) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.capture")
            }
        }
        .padding(24).frame(width: 620, height: 600)
        .interactiveDismissDisabled()
        .task(id: "\(stage.rawValue)-\(replay)-\(reduceMotion)") {
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { demoProgress = reduceMotion ? 1 : 0 }
            guard !reduceMotion else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 3)) { demoProgress = 1 }
        }
        .onDisappear { shortcuts.cancelRecording() }
    }

    private func complete(_ action: OnboardingAction) {
        shortcuts.cancelRecording()
        finish(action)
    }
}

/// One finite, replayable demonstration. Animatable keeps cursor and drawing on the same timeline.
struct OnboardingIllustration: View, Animatable {
    let stage: OnboardingView.Stage
    nonisolated var progress: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let frame = OnboardingDemoFrame(stage: stage, progress: progress)
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 12).fill(.background)
                .frame(width: 360, height: 138)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(.secondary.opacity(0.28)).frame(width: 7, height: 7) }
                        Spacer()
                    }.padding(14)
                }
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer().frame(height: 25)
                        RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.22)).frame(width: 180, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.12)).frame(height: 28)
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.14)).frame(height: 9)
                            RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.10)).frame(width: 92, height: 9)
                        }
                    }
                    .padding(20)
                }
            Canvas { context, _ in
                if stage == .capture {
                    context.stroke(Path(roundedRect: frame.selection, cornerRadius: 6), with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                } else {
                    drawAnnotations(context, frame: frame)
                }
            }.frame(width: 360, height: 138)
            if stage == .copy {
                HStack(spacing: 12) {
                    Label { Text(verbatim: "PNG") } icon: { Image(systemName: "photo") }
                    Label { Text(verbatim: "PDF") } icon: { Image(systemName: "doc.richtext") }
                    if frame.copied {
                        Label(String(localized: "Kopiert"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label { Text(verbatim: "⌘C") } icon: { Image(systemName: "doc.on.clipboard") }
                    }
                }.font(.headline).padding(14)
                    .background(.background, in: .rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .opacity(frame.copyCard)
                    .scaleEffect(0.96 + 0.04 * frame.copyCard)
                    .offset(y: 6 * (1 - frame.copyCard))
            }
            Image(systemName: "cursorarrow")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .shadow(color: .white, radius: 1)
                .offset(x: frame.cursor.x - 180, y: frame.cursor.y - 69)
                .opacity(frame.cursorOpacity)
        }
    }

    private func drawAnnotations(_ context: GraphicsContext, frame: OnboardingDemoFrame) {
        var arrow = EditorObject(kind: .arrow, start: OnboardingDemoFrame.arrowStart, end: OnboardingDemoFrame.arrowEnd)
        arrow.lineWidth = 4.5
        // Use the editor's filled arrowhead, with the shaft ending underneath its base.
        let head = EditorArrow.head(for: arrow)
        let angle = atan2(arrow.end.y - arrow.start.y, arrow.end.x - arrow.start.x)
        let length = arrow.lineWidth * 4
        var shaft = Path()
        shaft.move(to: arrow.start)
        shaft.addLine(to: CGPoint(x: arrow.end.x - cos(angle) * length, y: arrow.end.y - sin(angle) * length))
        context.stroke(shaft.trimmedPath(from: 0, to: frame.arrow), with: .color(.orange),
                       style: StrokeStyle(lineWidth: arrow.lineWidth, lineCap: .round))
        var headContext = context
        headContext.opacity = OnboardingDemoFrame.portion(frame.arrow, from: 0.8, to: 1)
        headContext.fill(Path(head), with: .color(.orange))
        let circle = Path(ellipseIn: OnboardingDemoFrame.circleRect)
        context.stroke(circle.trimmedPath(from: 0, to: frame.circle), with: .color(.orange),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let redaction = CGRect(x: 78, y: 108, width: 104 * frame.redaction, height: 13)
        context.fill(Path(roundedRect: redaction, cornerRadius: min(6.5, redaction.width / 2)), with: .color(.primary))
    }
}

/// Drawing coordinates are local to the 360 × 138 mock window, never screen coordinates.
struct OnboardingDemoFrame {
    static let arrowStart = CGPoint(x: 60, y: 54)
    static let arrowEnd = CGPoint(x: 230, y: 82)
    static let circleRect = CGRect(x: 190, y: 44, width: 130, height: 54)
    let selection: CGRect
    let arrow: CGFloat
    let circle: CGFloat
    let redaction: CGFloat
    let copyCard: Double
    let copied: Bool
    let cursor: CGPoint
    let cursorOpacity: Double

    static func portion(_ value: Double, from start: Double, to end: Double) -> Double {
        min(1, max(0, (value - start) / (end - start)))
    }
    init(stage: OnboardingView.Stage, progress: Double) {
        let p = progress.isFinite ? min(1, max(0, progress)) : 1
        let capture = Self.portion(p, from: 0.1, to: 0.72)
        selection = CGRect(x: 55, y: 32, width: max(2, 250 * capture), height: max(2, 82 * capture))
        arrow = stage == .copy ? 1 : Self.portion(p, from: 0.08, to: 0.34)
        circle = stage == .copy ? 1 : Self.portion(p, from: 0.44, to: 0.7)
        redaction = stage == .copy ? 1 : Self.portion(p, from: 0.78, to: 0.96)
        copyCard = Self.portion(p, from: 0.12, to: 0.4)
        copied = p >= 0.7
        cursorOpacity = 1 - Self.portion(p, from: 0.92, to: 1)
        switch stage {
        case .capture:
            cursor = CGPoint(x: selection.maxX, y: selection.maxY)
        case .annotate:
            if p <= 0.34 {
                cursor = CGPoint(x: Self.arrowStart.x + (Self.arrowEnd.x - Self.arrowStart.x) * arrow,
                                 y: Self.arrowStart.y + (Self.arrowEnd.y - Self.arrowStart.y) * arrow)
            } else if p < 0.44 {
                cursor = Self.between(Self.arrowEnd, CGPoint(x: Self.circleRect.maxX, y: Self.circleRect.midY),
                                      progress: Self.portion(p, from: 0.34, to: 0.44))
            } else if p <= 0.7 {
                let angle = circle * 2 * .pi
                cursor = CGPoint(x: Self.circleRect.midX + cos(angle) * Self.circleRect.width / 2,
                                 y: Self.circleRect.midY + sin(angle) * Self.circleRect.height / 2)
            } else if p < 0.78 {
                cursor = Self.between(CGPoint(x: Self.circleRect.maxX, y: Self.circleRect.midY), CGPoint(x: 78, y: 114),
                                      progress: Self.portion(p, from: 0.7, to: 0.78))
            } else {
                cursor = CGPoint(x: 78 + 104 * redaction, y: 114)
            }
        case .copy:
            cursor = CGPoint(x: 268, y: 92)
        }
    }
    private static func between(_ start: CGPoint, _ end: CGPoint, progress: Double) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
    }
}

enum EditorLearningHintRoute: String, Equatable {
    case crop, redaction, drawing, firstAnnotation, selection, output

    static func route(tool: AnnotationTool, cropDraftExists: Bool, objectCount: Int, selectionCount: Int) -> Self {
        if cropDraftExists { return .crop }
        if tool == .redact { return .redaction }
        if [.arrow, .rectangle, .ellipse, .callout, .pen].contains(tool) { return .drawing }
        if tool == .selection, objectCount == 0 { return .firstAnnotation }
        if tool == .selection, selectionCount > 1 { return .selection }
        return .output
    }
}

struct EditorLearningHint: View {
    let model: EditorModel
    let preferences: AppPreferences
    private var route: EditorLearningHintRoute {
        EditorLearningHintRoute.route(tool: model.tool, cropDraftExists: model.cropDraft != nil,
                                      objectCount: model.history.objects.count, selectionCount: model.selectedIDs.count)
    }
    private var key: String { route.rawValue }
    private var message: String {
        switch key {
        case "crop": return String(localized: "Ausschnitt gewählt? Drücke Return/Enter zum Übernehmen oder Esc zum Verwerfen.")
        case "redaction": return String(localized: "Abdeckungen werden in der Ausgabe dauerhaft abgeflacht. Dein Projekt behält die bearbeitbare Originalaufnahme.")
        case "drawing": return String(localized: "Ziehe Pfeile und Formen direkt auf dem Bild auf. Die Zeichenstile findest du rechts.")
        default:
            if model.tool == .selection, model.selectedIDs.count > 1 {
                return String(localized: "Mehrere Objekte: Umschalt-Klick wählt weitere Markierungen. Mit ⌘G gruppierst du sie.")
            }
            if model.tool == .selection, model.history.objects.isEmpty {
                return String(localized: "Noch keine Markierung? Wähle oben einen Pfeil oder eine Abdeckung und kopiere danach dein Bild.")
            }
            return String(localized: "Fertig zum Teilen? ⌘C kopiert das Bild. ⇧⌘E exportiert PNG, JPEG oder PDF.")
        }
    }
    var body: some View {
        if !preferences.dismissedEditorHints.contains(key) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(.tint)
                Text(message).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(String(localized: "Verstanden")) { preferences.dismissedEditorHints.insert(key) }
            }.font(.callout).padding(10)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}
