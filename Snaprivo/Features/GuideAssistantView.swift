import SwiftUI
import SnagForgeDomain

struct GuideAssistantView: View {
    @State private var model: GuideAssistantModel
    @Environment(\.dismiss) private var dismiss
    init(request: GuideAssistantRequest, guide: GuideModel, service: any GuideTextGenerating = AppleGuideTextService.shared) {
        _model = State(initialValue: GuideAssistantModel(request: request, guide: guide, service: service))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "Anleitungstexte mit Apple Intelligence"), systemImage: "sparkles").font(.headline)
                Spacer()
                Button(String(localized: "Schließen"), systemImage: "xmark") { model.cancel(); dismiss() }
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
                            if let progress = model.progress {
                                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                                Text(String(localized: "\(progress.completed) von \(progress.total) Textvorschlägen erstellt"))
                                    .font(.caption).monospacedDigit()
                            } else { ProgressView(String(localized: "Textvorschläge werden erstellt …")) }
                        }.accessibilityIdentifier("guide.assistant.progress")
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("guide.assistant.error")
                    }
                    if let draft = model.draft { review(draft) }
                    else if !model.isGenerating {
                        Text(String(localized: "Die Vorschläge erscheinen hier zur Prüfung. Erst „Übernehmen“ ändert deine Anleitung; anschließend ist alles gemeinsam rückgängig zu machen."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(String(localized: "Abbrechen")) { model.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isGenerating {
                    Button(String(localized: "Generierung stoppen")) { model.cancel() }
                } else {
                    Button(model.draft == nil ? String(localized: "Vorschläge erstellen") : String(localized: "Neu erstellen")) { model.generate() }
                        .disabled(!model.canGenerate)
                        .accessibilityIdentifier("guide.assistant.generate")
                }
                Button(String(localized: "Übernehmen")) { if model.apply() { dismiss() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.glassProminent).disabled(!model.canApply)
                    .accessibilityIdentifier("guide.assistant.apply")
            }.padding(20)
        }
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 900, minHeight: 520, idealHeight: 660, maxHeight: 900)
        .task(id: model.language) { await model.refreshAvailability() }
        .onDisappear { model.cancel() }
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
            Text(String(localized: "Vorschläge prüfen und anpassen")).font(.headline)
            Text(String(localized: "Prüfe besonders Bedienelemente und Handlungen. Apple Intelligence kann sich irren."))
                .font(.callout).foregroundStyle(.secondary)
            if draft.scope == .document {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(String(localized: "Anleitungstitel"), text: Binding(get: { model.draft?.title ?? "" }, set: { text in model.editDraft { $0.title = String(text.prefix(256)) } }))
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("guide.assistant.title")
                    TextField(String(localized: "Einleitung (optional)"), text: Binding(get: { model.draft?.introduction ?? "" }, set: { text in model.editDraft { $0.introduction = String(text.prefix(8_000)) } }), axis: .vertical)
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
    }
    private func stepField(_ id: UUID, path: WritableKeyPath<GuideTextDraft.Step, String>, limit: Int) -> Binding<String> {
        Binding(get: { model.draft?.steps.first(where: { $0.id == id })?[keyPath: path] ?? "" }, set: { text in
            model.editDraft { draft in
                if let index = draft.steps.firstIndex(where: { $0.id == id }) { draft.steps[index][keyPath: path] = String(text.prefix(limit)) }
            }
        })
    }
}
