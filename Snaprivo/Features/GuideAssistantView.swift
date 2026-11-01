import SwiftUI
import SnagForgeDomain

struct GuideAssistantView: View {
    @Bindable var model: GuideAssistantModel
    /// Called when the dialog ends its request: applied, cancelled or closed. Not when it continues in the background.
    var onEnd: () -> Void = {}
    @State private var continuesInBackground = false
    @Environment(\.dismiss) private var dismiss
    private func end() { model.cancel(); onEnd(); dismiss() }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "Anleitungstexte mit Apple Intelligence"), systemImage: "apple.intelligence").font(.headline)
                Spacer()
                Button(String(localized: "Schließen"), systemImage: "xmark") { end() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .accessibilityIdentifier("guide.assistant.close")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.availability.message).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("guide.assistant.availability")
                    if !model.availability.isAvailable {
                        Button(String(localized: "Erneut prüfen")) { Task { await model.refreshAvailability() } }
                            .disabled(model.availability == .checking)
                    }
                    configuration
                    if model.request.source.steps.isEmpty {
                        Text(String(localized: "Hier entstehen Titel und Einleitung. Für Schrittbeschreibungen füge zuerst Screenshots zur Anleitung hinzu."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if model.isGenerating {
                        VStack(alignment: .leading, spacing: 8) {
                            GuideAssistantActivityView(model: model)
                            if let progress = model.progress, progress.total > 1, progress.completed > 0 {
                                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                                Text(String(localized: "\(progress.completed) von \(progress.total) Textvorschlägen erstellt"))
                                    .font(.caption).monospacedDigit()
                            }
                        }.accessibilityIdentifier("guide.assistant.progress")
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("guide.assistant.error")
                    }
                    if let draft = model.visibleDraft { review(draft) }
                    else if !model.isGenerating {
                        Text(String(localized: "Die Vorschläge erscheinen hier zur Prüfung. Erst „Übernehmen“ ändert deine Anleitung; anschließend ist alles gemeinsam rückgängig zu machen."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(String(localized: "Abbrechen")) { end() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isGenerating {
                    Button(String(localized: "Generierung stoppen")) { model.cancel() }
                    Button(String(localized: "Im Hintergrund weiter"), systemImage: "rectangle.portrait.and.arrow.forward") {
                        continuesInBackground = true; dismiss()
                    }
                    .help(String(localized: "Fenster schließen und weiterarbeiten. Der Fortschritt steht oben in der Anleitung."))
                    .accessibilityIdentifier("guide.assistant.background")
                } else {
                    Button(model.draft == nil ? String(localized: "Vorschläge erstellen") : String(localized: "Neu erstellen")) { model.generate() }
                        .disabled(!model.canGenerate)
                        .accessibilityIdentifier("guide.assistant.generate")
                }
                Button(String(localized: "Übernehmen")) { if model.apply() { onEnd(); dismiss() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.glassProminent).disabled(!model.canApply)
                    .accessibilityIdentifier("guide.assistant.apply")
            }.padding(20)
        }
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 900, minHeight: 520, idealHeight: 660, maxHeight: 900)
        .task(id: model.language) { await model.prepare() }
        .onDisappear { if !continuesInBackground { model.cancel(); onEnd() } }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker(String(localized: "Aufgabe"), selection: $model.mode) {
                    ForEach(GuideAssistantMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(String(localized: "Sprache"), selection: $model.language) {
                    ForEach(GuideAssistantLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }.frame(maxWidth: 200)
            }
            TextField(String(localized: "Ziel oder ergänzende Hinweise"), text: Binding(get: { model.goal }, set: { model.goal = String($0.prefix(2_000)) }), axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("guide.assistant.goal")
            Text(String(localized: "Beschreibe kurz, was die Anleitung erklären soll. Bei Bedarf ergänze Hinweise wie „Schritt 2: Ton ausschalten“."))
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(model.isGenerating)
    }
    private func review(_ draft: GuideTextDraft) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Divider()
            Text(model.isGenerating ? String(localized: "Vorschläge entstehen …") : String(localized: "Vorschläge prüfen und anpassen")).font(.headline)
            Text(String(localized: "Prüfe besonders Bedienelemente und Handlungen. Apple Intelligence kann sich irren."))
                .font(.callout).foregroundStyle(.secondary)
            if draft.scope == .document, draft.title != nil {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(String(localized: "Anleitungstitel"), text: Binding(get: { model.visibleDraft?.title ?? "" }, set: { text in model.editDraft { $0.title = String(text.prefix(256)) } }))
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("guide.assistant.title")
                    TextField(String(localized: "Einleitung (optional)"), text: Binding(get: { model.visibleDraft?.introduction ?? "" }, set: { text in model.editDraft { $0.introduction = String(text.prefix(8_000)) } }), axis: .vertical)
                        .lineLimit(2...8).textFieldStyle(.roundedBorder)
                }
            }
            ForEach(Array(draft.steps.enumerated()), id: \.element.id) { _, step in
                VStack(alignment: .leading, spacing: 8) {
                    if let index = model.request.source.steps.firstIndex(where: { $0.id == step.id }) {
                        Text(String(localized: "Schritt \(index + 1)")).font(.subheadline)
                        ProjectThumbnail(data: model.request.source.steps[index].png, maximumDimension: 1280)
                            .frame(height: 160).frame(maxWidth: .infinity)
                        if !model.request.source.steps[index].caption.isEmpty {
                            DisclosureGroup(String(localized: "Bisheriger Text")) {
                                Text(model.request.source.steps[index].caption).font(.callout).textSelection(.enabled)
                            }
                        }
                    }
                    TextField(String(localized: "Schritttitel"), text: stepField(step.id, path: \.title, limit: 256))
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "Bildunterschrift / Beschreibung"), text: stepField(step.id, path: \.caption, limit: 8_000), axis: .vertical)
                        .lineLimit(2...10).textFieldStyle(.roundedBorder)
                }.padding(16).background(.quaternary, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("guide.assistant.step.\(step.id)")
            }
        }
        // Streamed text keeps its fields in place; only a finished draft is editable.
        .disabled(model.isGenerating)
    }
    private func stepField(_ id: UUID, path: WritableKeyPath<GuideTextDraft.Step, String>, limit: Int) -> Binding<String> {
        Binding(get: { model.visibleDraft?.steps.first(where: { $0.id == id })?[keyPath: path] ?? "" }, set: { text in
            model.editDraft { draft in
                if let index = draft.steps.firstIndex(where: { $0.id == id }) { draft.steps[index][keyPath: path] = String(text.prefix(limit)) }
            }
        })
    }
}

/// A suggestion right below a step's description: written live, applied or discarded in place.
struct GuideInlineSuggestionView: View {
    let model: GuideAssistantModel
    let apply: () -> Void
    let regenerate: () -> Void
    let discard: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).accessibilityHidden(true)
                if model.isGenerating { GuideAssistantActivityView(model: model, compact: true) }
                else { Text(String(localized: "Vorschlag von Apple Intelligence")).font(.subheadline.weight(.semibold)) }
                Spacer()
                Button(String(localized: "Verwerfen"), systemImage: "xmark", action: discard)
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help(String(localized: "Verwerfen"))
            }
            if let step = model.visibleDraft?.steps.first {
                if !step.title.isEmpty { Text(step.title).font(.headline).textSelection(.enabled) }
                if !step.caption.isEmpty { Text(step.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else if model.availability != .checking, !model.availability.isAvailable {
                Text(model.availability.message).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(String(localized: "Übernehmen"), action: apply)
                    .buttonStyle(.glassProminent).disabled(!model.canApply)
                Button(String(localized: "Neu erstellen"), systemImage: "arrow.clockwise", action: regenerate)
                    .disabled(model.isGenerating)
                Spacer()
                Text(String(localized: "Ersetzt Titel und Beschreibung dieses Schritts. Rückgängig mit ⌘Z."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.accentColor.opacity(0.06)), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Vorschlag von Apple Intelligence"))
    }
}

/// Spinner, current phase and elapsed time; before the first text a note explains a cold model start.
struct GuideAssistantActivityView: View {
    let model: GuideAssistantModel
    var compact = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(model.activityStartedAt)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.activityText).font(compact ? .subheadline : .callout)
                    if elapsed >= 3 {
                        Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                            .font(compact ? .subheadline : .callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if !compact, model.visibleDraft == nil, elapsed >= 8 {
                    Text(String(localized: "Beim ersten Mal nach einer Pause lädt macOS das lokale Sprachmodell. Das kann bis zu einer Minute dauern."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.assistant.activity")
    }
}
