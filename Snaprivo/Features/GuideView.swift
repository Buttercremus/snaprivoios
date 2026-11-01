import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import SnagForgeDomain

struct GuideView: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var model: GuideModel
    @State private var removing: UUID?
    @State private var deleting: UUID?
    @State private var navigationRequest = 0
    @State private var assistantRequest: GuideAssistantRequest?
    @FocusState private var focusedStep: UUID?
    @FocusState private var focusedTitle: Bool
    @AccessibilityFocusState private var accessibleStep: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HSplitView {
            if !model.documents.isEmpty || !model.trash.isEmpty || model.document != nil { guideList }
            // A stable split column survives selection changes and document replacement.
            ZStack {
                if model.showsTrash { trashView }
                else if model.selectedDocumentIDs.count > 1 { multipleSelectionView }
                else if let document = model.document { editor(document) }
                else { emptyView }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.guideEditor, model)
        .disabled(model.isBusyForControls || model.isSuspended)
        // Keep the native split/list hierarchy interactive; a separate shield catches busy clicks.
        .overlay { GuideActivityShield(model: model) }
        .transaction(value: model.document?.id) { transaction in
            transaction.animation = nil; transaction.disablesAnimations = true
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.issues.isEmpty { Text(model.issues.joined(separator: "\n")).font(.caption).foregroundStyle(.red) }
                if model.error != nil { GuideFailureView(model: model) }
                if let notice = model.notice { Text(notice).font(.callout).textSelection(.enabled) }
            }.padding(model.error != nil || model.notice != nil || !model.issues.isEmpty ? 12 : 0)
        }
        .task { await model.refresh() }
        .sheet(item: $assistantRequest) { request in GuideAssistantView(request: request, guide: model) }
        .sheet(item: $model.imageRequest) { request in
            GuideProjectPicker(items: workspace.items, maximum: request.replacing != nil ? 1 : max(0, 100 - (model.document?.steps.count ?? 0))) { ids in
                guard model.document?.id == request.documentID else { return }
                workspace.addGuideProjects(ids, replacing: request.replacing, at: request.position)
            }
        }
        .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.preview = nil } })) {
            VStack(spacing: 0) {
                HStack {
                    Text(String(localized: "PDF-Vorschau")).font(.headline)
                    Spacer()
                    Button(String(localized: "Schließen")) { model.preview = nil }.keyboardShortcut(.cancelAction)
                }.padding()
                GuidePDFPreview(data: model.preview ?? Data())
            }.frame(minWidth: 620, minHeight: 600)
        }
        .confirmationDialog(String(localized: "Schritt entfernen?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(String(localized: "Schritt entfernen"), role: .destructive) {
                if let removing { model.removeStep(removing) }; removing = nil
            }
        } message: { Text(String(localized: "Das Bildprojekt bleibt in der Bibliothek erhalten. Du kannst den Schritt mit Rückgängig wiederherstellen.")) }
        .confirmationDialog(String(localized: "Anleitung endgültig löschen?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "Endgültig löschen"), role: .destructive) {
                if let deleting { model.permanentlyDelete(deleting) }; deleting = nil
            }
        } message: { Text(String(localized: "Die Anleitung und ihre gespeicherten Bildstände werden gelöscht. Die Bildprojekte bleiben erhalten.")) }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(model.documents.isEmpty ? String(localized: "Screenshots als Anleitung") : String(localized: "Anleitung auswählen"), systemImage: "list.number")
        } description: {
            Text(model.documents.isEmpty ? String(localized: "Schritte sortieren, beschreiben und als PDF oder Markdown weitergeben.") : String(localized: "Wähle links eine Anleitung oder erstelle eine neue."))
        } actions: {
            Button(String(localized: "Neue Anleitung")) { model.create() }
                .buttonStyle(.glassProminent).accessibilityIdentifier("guide.empty.create")
            Button(String(localized: "Anleitung importieren …")) { model.chooseImport() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("guide.empty")
    }
    private var multipleSelectionView: some View {
        ContentUnavailableView {
            Label(String(localized: "\(model.selectedDocumentIDs.count) ausgewählt"), systemImage: "doc.on.doc")
        } description: {
            Text(String(localized: "Wähle eine einzelne Anleitung zum Bearbeiten oder verschiebe die Auswahl in den Papierkorb."))
        } actions: {
            Button(String(localized: "In den Papierkorb"), systemImage: "trash") { model.trashSelection() }
                .accessibilityIdentifier("guide.selection.trash")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("guide.multipleSelection")
    }

    private func editor(_ document: GuideDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(String(localized: "Rückgängig"), systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndoForControls || !workspace.purchases.hasPro).labelStyle(.iconOnly).help(String(localized: "Rückgängig (⌘Z)"))
                    .accessibilityIdentifier("guide.undo")
                Button(String(localized: "Wiederholen"), systemImage: "arrow.uturn.forward") { model.redo() }
                    .disabled(!model.canRedoForControls || !workspace.purchases.hasPro).labelStyle(.iconOnly)
                    .accessibilityIdentifier("guide.redo")
                Button(String(localized: "Apple Intelligence …"), systemImage: "sparkles") { openAssistant(.document) }
                    .buttonStyle(.borderless).help(String(localized: "Anleitungstexte vorschlagen, überarbeiten oder kürzen"))
                    .accessibilityIdentifier("guide.assistant.open")
                Spacer()
                Text(model.isSaving ? String(localized: "Wird gesichert …") : model.isDirty ? String(localized: "Ungesicherte Änderungen") : String(localized: "Automatisch gesichert"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            if !document.steps.isEmpty { stepOverview(document) }
            Divider()
            // Keep the overview outside this reader: its ForEach uses the same step IDs.
            // Otherwise scrollTo can resolve a horizontal thumbnail instead of the step card.
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !workspace.purchases.hasPro {
                            Button(String(localized: "Anleitung bearbeiten · Pro"), systemImage: "lock") { workspace.showPro(.guides) }
                            Text(String(localized: "Öffnen und Exportieren bleibt kostenlos.")).font(.caption).foregroundStyle(.secondary)
                        }
                        TextField(String(localized: "Anleitungstitel"), text: field(\.title, name: "title", limit: 256))
                            .font(.title2).textFieldStyle(.roundedBorder).accessibilityIdentifier("guide.title").id(document.id).disabled(!workspace.purchases.hasPro)
                            .focused($focusedTitle)
                            // Focus only after creation finishes, once actions are available again.
                            .task(id: model.focusesTitle && !model.isBusy) {
                                guard model.focusesTitle, !model.isBusy else { return }
                                await Task.yield()
                                focusedTitle = true; model.focusesTitle = false
                            }
                        TextField(String(localized: "Einleitung (optional)"), text: field(\.introduction, name: "introduction", limit: 8_000), axis: .vertical)
                            .lineLimit(2...8).textFieldStyle(.roundedBorder).disabled(!workspace.purchases.hasPro)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { stylePicker(document); coverToggle(document) }
                            VStack(alignment: .leading, spacing: 12) { stylePicker(document); coverToggle(document) }
                        }
                        if document.steps.isEmpty {
                            ContentUnavailableView {
                                Label(String(localized: "Noch keine Schritte"), systemImage: "list.number")
                            } description: {
                                Text(String(localized: "Nimm jeden Schritt direkt auf oder übernimm vorhandene Screenshots aus deiner Bibliothek."))
                            } actions: {
                                captureStepButton(document).buttonStyle(.glassProminent)
                                libraryStepButton(document)
                            }.frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityIdentifier("guide.steps.empty")
                        } else {
                            Text(String(localized: "Jeder Schritt behält seine eigene Bildkopie. Spätere Änderungen im Editor übernimmst du mit „Bild aktualisieren“."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(document.steps.enumerated()), id: \.element.id) { index, step in
                            stepView(step, index: index, count: document.steps.count).id(step.id)
                        }
                        if !document.steps.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { captureStepButton(document); libraryStepButton(document) }
                                VStack(spacing: 8) { captureStepButton(document); libraryStepButton(document) }
                            }.frame(maxWidth: .infinity).padding(.vertical, 8).accessibilityIdentifier("guide.steps.add")
                        }
                    }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
                }
                .task(id: document.id) {
                    guard let id = model.stepToReveal else { return }
                    await Task.yield()
                    guard !Task.isCancelled, !model.isBusy else { return }
                    reader.scrollTo(id, anchor: .top); focusStep(id, in: document); model.stepToReveal = nil
                }
                .onChange(of: model.stepToReveal) { _, id in
                    guard let id, !model.isBusy else { return }
                    reader.scrollTo(id, anchor: .top); focusStep(id, in: document); model.stepToReveal = nil
                }
                .onChange(of: model.isBusy) { _, busy in
                    guard !busy, let id = model.stepToReveal else { return }
                    reader.scrollTo(id, anchor: .top); focusStep(id, in: document); model.stepToReveal = nil
                }
                .onChange(of: (model.selectedStep?.uuidString ?? "") + String(navigationRequest)) { _, _ in
                    guard let id = model.selectedStep else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { reader.scrollTo(id, anchor: .top) }
                }
            }
        }
    }
    private func focusStep(_ id: UUID, in document: GuideDocument) {
        guard document.steps.contains(where: { $0.id == id }) else { return }
        focusedStep = id; accessibleStep = id
    }
    private func stylePicker(_ document: GuideDocument) -> some View {
        Picker(String(localized: "PDF-Stil"), selection: Binding(get: { document.style }, set: { style in model.edit { $0.style = style } })) {
            Text(String(localized: "Standard")).tag(GuideStyle.standard)
            Text(String(localized: "Kompakt")).tag(GuideStyle.compact)
        }.frame(maxWidth: 240).disabled(!workspace.purchases.hasPro)
            .help(String(localized: "Standard: ein Schritt pro Seite. Kompakt: mehrere kurze Schritte auf einer Seite."))
    }
    private func coverToggle(_ document: GuideDocument) -> some View {
        Toggle(String(localized: "Eigene Titelseite"), isOn: Binding(get: { document.includesCover }, set: { cover in model.edit { $0.includesCover = cover } }))
            .toggleStyle(.checkbox).disabled(!workspace.purchases.hasPro).accessibilityIdentifier("guide.cover")
    }
    private func stepOverview(_ document: GuideDocument) -> some View {
        ScrollViewReader { overview in
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(document.steps.enumerated()), id: \.element.id) { index, step in
                    Button { revealStep(step.id) } label: {
                        HStack(spacing: 8) {
                            GuideImage(data: step.png, maximumDimension: 112,
                                prepared: model.imagePreviews.image(for: step, overview: true)).equatable().frame(width: 48, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Schritt \(index + 1)")).font(.caption).foregroundStyle(.secondary)
                                Text(step.title).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                            }
                        }.padding(8).padding(.leading, workspace.purchases.hasPro ? 20 : 0)
                    }
                    .buttonStyle(.plain)
                    .background(model.selectedStep == step.id ? Color.accentColor.opacity(contrast == .increased ? 0.25 : 0.12) : Color.clear, in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(model.selectedStep == step.id ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 2 : 1) }
                    .overlay(alignment: .leading) {
                        if workspace.purchases.hasPro {
                            GuideStepDragHandle(payload: "\(document.id):\(step.id)")
                                .frame(width: 20, height: 36).padding(.leading, 4)
                                .help(String(localized: "Am Griff ziehen, um den Schritt zu verschieben"))
                                .accessibilityHidden(true)
                        }
                    }
                    .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in acceptDrop(providers, in: document, before: step.id) }
                    .contextMenu {
                        stepEditingActions(step.id, count: document.steps.count)
                        Divider()
                        Button(String(localized: "Schritt nach oben"), systemImage: "arrow.up") { moveStep(step.id, by: -1) }.disabled(index == 0 || !workspace.purchases.hasPro)
                        Button(String(localized: "Schritt nach unten"), systemImage: "arrow.down") { moveStep(step.id, by: 1) }.disabled(index == document.steps.count - 1 || !workspace.purchases.hasPro)
                    }
                    .accessibilityLabel(String(localized: "Schritt \(index + 1): \(step.title)"))
                    .accessibilityAddTraits(model.selectedStep == step.id ? [.isSelected] : [])
                    .accessibilityIdentifier("guide.overview.\(step.id)")
                }
                if workspace.purchases.hasPro && document.steps.count > 1 {
                    Label(String(localized: "Ans Ende"), systemImage: "arrow.right.to.line")
                        .font(.caption).padding(12).contentShape(.rect)
                        .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in acceptDrop(providers, in: document, before: nil) }
                }
            }.padding(.horizontal, 12).padding(.bottom, 12)
        }.accessibilityLabel(String(localized: "Schrittübersicht"))
            .onChange(of: model.selectedStep) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { overview.scrollTo(id, anchor: .center) }
            }
        }
    }
    private func acceptDrop(_ providers: [NSItemProvider], in document: GuideDocument, before target: UUID?) -> Bool {
        guard workspace.purchases.hasPro, let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, error in
            guard error == nil, let payload = object as? String, payload.count == 73 else { return }
            Task { @MainActor in _ = reorder(payload, in: document, before: target) }
        }
        return true
    }
    private func reorder(_ payload: String?, in document: GuideDocument, before target: UUID?) -> Bool {
        guard let payload, let id = model.moveStep(payload: payload, documentID: document.id, before: target) else { return false }
        revealStep(id); return true
    }
    private var guideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Anleitungen")).font(.headline)
                Spacer()
                GuideOpeningIndicator(model: model).frame(width: 16, height: 16)
                Button(String(localized: "In den Papierkorb"), systemImage: "trash") { model.trashSelection() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(!model.canTrashSelectionForControls)
                    .help(String(localized: "Ausgewählte Anleitungen in den Papierkorb verschieben"))
                    .accessibilityIdentifier("guide.list.trashSelection")
                Button(String(localized: "Neue Anleitung"), systemImage: "plus") { model.create() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help(String(localized: "Neue Anleitung")).accessibilityIdentifier("guide.create")
            }.padding(16)
            TextField(String(localized: "Anleitungen suchen"), text: $model.searchQuery)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.bottom, 12)
                .accessibilityIdentifier("guide.search")
                .help(String(localized: "Titel, Einleitung und Schritttexte durchsuchen"))
                .onSubmit { if !model.isSearching, let match = model.searchResults.first { openSearchMatch(match) } }
            if model.isSearching { ProgressView(String(localized: "Anleitungen durchsuchen …")).controlSize(.small).padding(.horizontal, 12) }
            if let error = model.searchError { Text(error).font(.caption).foregroundStyle(.red).padding(12) }
            Divider()
            List(selection: Binding(get: { model.showsTrash ? Set<UUID>() : model.selectedDocumentIDs }, set: { model.selectDocuments($0) })) {
                if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(model.searchResults) { match in
                        Button { openSearchMatch(match) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.documentTitle).font(.headline).lineLimit(2)
                                if let number = match.stepNumber, let title = match.stepTitle {
                                    Text(String(localized: "Schritt \(number): \(title)")).font(.caption).lineLimit(2)
                                }
                                Text(match.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }.buttonStyle(.plain).accessibilityIdentifier("guide.search.result.\(match.id)")
                    }
                    if model.searchResults.isEmpty && !model.isSearching && model.searchError == nil {
                        Text(String(localized: "Keine passenden Anleitungen oder Schritte")).foregroundStyle(.secondary)
                    }
                } else {
                ForEach(model.documents) { document in
                    // A single title line keeps the row height independent of the width List measures with.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title).lineLimit(1)
                        Text(String(localized: "\(document.stepCount) Schritte")).font(.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4).help(document.title).tag(document.id)
                        .contextMenu {
                            Button(String(localized: "Anleitung duplizieren"), systemImage: "doc.on.doc") { model.duplicate(document.id) }.disabled(!workspace.purchases.hasPro)
                            Button(String(localized: "In den Papierkorb"), systemImage: "trash", role: .destructive) {
                                model.moveToTrash(model.selectedDocumentIDs.contains(document.id) ? model.selectedDocumentIDs : [document.id])
                            }
                        }
                }
                }
            }.listStyle(.inset).scrollContentBackground(.hidden).frame(minHeight: 0, maxHeight: .infinity).accessibilityIdentifier("guide.list")
                .onDeleteCommand { model.trashSelection() }
                .help(String(localized: "⌘-Klick wählt mehrere Anleitungen, Umschalt-Klick einen Bereich. Entf oder Rücktaste verschiebt die Auswahl in den Papierkorb."))
                // Rows inserted into the visible list keep a stale default height and clip their step count.
                // Rebuilding on membership changes measures every row like the initial layout; reordering keeps the list.
                .id(Set(model.documents.map(\.id)))
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Button(String(localized: "Importieren …"), systemImage: "square.and.arrow.down") { model.chooseImport() }.accessibilityIdentifier("guide.import")
                Button { if !model.isBusy { model.showsTrash.toggle() } } label: {
                    Label(String(localized: "Papierkorb") + " (\(model.trash.count))", systemImage: "trash")
                }.accessibilityIdentifier("guide.trash")
                Text(String(localized: "In „Alles sichern“ enthalten")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16)
        }.frame(minWidth: 180, idealWidth: 208, maxWidth: 240, maxHeight: .infinity, alignment: .top).background(.background)
    }
    private func openSearchMatch(_ match: GuideSearchMatch) {
        model.open(match.documentID, revealing: match.stepID, fromSearch: true)
    }
    private func captureStepButton(_ document: GuideDocument) -> some View {
        Button(String(localized: "Schritt aufnehmen"), systemImage: "viewfinder") {
            CaptureLauncher.captureGuideStep(workspace: workspace, using: openWindow, dismissWindow: dismissWindow)
        }
        .disabled(document.steps.count >= 100 || workspace.screenshot.isBusy || workspace.isDirectOCRBusy || workspace.isLoading)
        .help(String(localized: "Bereich aufnehmen und als nächsten Schritt anhängen"))
        .accessibilityIdentifier("guide.captureStep")
    }
    private func libraryStepButton(_ document: GuideDocument) -> some View {
        Button(String(localized: "Aus Bibliothek hinzufügen …"), systemImage: "photo.on.rectangle") { model.chooseImages() }
            .disabled(document.steps.count >= 100)
            .accessibilityIdentifier("guide.addFromLibrary")
    }
    @ViewBuilder private func stepEditingActions(_ id: UUID, count: Int) -> some View {
        Button(String(localized: "Text mit Apple Intelligence …"), systemImage: "sparkles") { openAssistant(.step(id)) }
            .disabled(!workspace.purchases.hasPro)
        Button(String(localized: "Schritt duplizieren"), systemImage: "doc.on.doc") { model.duplicateStep(id) }
            .disabled(count >= 100 || !workspace.purchases.hasPro)
        Button(String(localized: "Schritt davor hinzufügen …"), systemImage: "plus") { model.chooseImages(at: .before(id)) }
            .disabled(count >= 100 || !workspace.purchases.hasPro)
        Button(String(localized: "Schritt danach hinzufügen …"), systemImage: "plus") { model.chooseImages(at: .after(id)) }
            .disabled(count >= 100 || !workspace.purchases.hasPro)
    }
    private var trashView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "Anleitungs-Papierkorb")).font(.title2)
                Spacer()
                Button(String(localized: "Zurück")) { model.showsTrash = false }
            }
            Text(String(localized: "Gelöschte Anleitungen bleiben wiederherstellbar und werden mit „Alles sichern“ gesichert.")).foregroundStyle(.secondary)
            if model.trash.isEmpty { ContentUnavailableView(String(localized: "Der Papierkorb ist leer"), systemImage: "trash").frame(maxHeight: .infinity) }
            else {
                List(model.trash) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline)
                        HStack {
                            Button(String(localized: "Wiederherstellen")) { model.restore(item.id) }
                            Button(String(localized: "Endgültig löschen …"), role: .destructive) { deleting = item.id }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8).accessibilityElement(children: .contain)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func field(_ path: WritableKeyPath<GuideDocument, String>, name: String, limit: Int) -> Binding<String> {
        Binding(get: { model.document?[keyPath: path] ?? "" }, set: { text in model.edit(textGroup: name) { $0[keyPath: path] = String(text.prefix(limit)) } })
    }
    private func stepView(_ step: GuideStep, index: Int, count: Int) -> some View {
        let source = workspace.guideSource(for: step)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Schritt \(index + 1)")).font(.headline)
                Spacer()
                Button(String(localized: "Schritt nach oben"), systemImage: "arrow.up") { moveStep(step.id, by: -1) }
                    .disabled(index == 0 || !workspace.purchases.hasPro).labelStyle(.iconOnly)
                Button(String(localized: "Schritt nach unten"), systemImage: "arrow.down") { moveStep(step.id, by: 1) }
                    .disabled(index == count - 1 || !workspace.purchases.hasPro).labelStyle(.iconOnly)
                Menu {
                    stepEditingActions(step.id, count: count)
                    Divider()
                    if let source {
                        Button(String(localized: "Bild im Editor bearbeiten")) { Task { await workspace.editGuideImage(step.id) } }
                        Button(String(localized: "Bild aktualisieren")) { workspace.addGuideProjects([source.id], replacing: step.id) }
                    }
                    Button(String(localized: "Bild ersetzen …")) { model.chooseImages(replacing: step.id) }
                    Button(String(localized: "Schritt entfernen …"), role: .destructive) { removing = step.id }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "Aktionen für Schritt \(index + 1)")) }.disabled(!workspace.purchases.hasPro)
            }
            TextField(String(localized: "Schritttitel"), text: Binding(get: { step.title }, set: { text in model.editStep(step.id, textGroup: "title-\(step.id)") { $0.title = String(text.prefix(256)) } }))
                .textFieldStyle(.roundedBorder).disabled(!workspace.purchases.hasPro)
                 .accessibilityIdentifier("guide.step.title.\(step.id)")
                .accessibilityLabel(String(localized: "Titel von Schritt \(index + 1)"))
                .focused($focusedStep, equals: step.id)
                .accessibilityFocused($accessibleStep, equals: step.id)
            GuideImage(data: step.png, maximumDimension: 1280,
                prepared: model.imagePreviews.image(for: step, overview: false)).equatable()
                .frame(height: 240).frame(maxWidth: .infinity).accessibilityLabel(step.title)
            if let source {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sourceActions(step, source: source) }
                    VStack(alignment: .leading, spacing: 8) { sourceActions(step, source: source) }
                }
            } else {
                Text(String(localized: "Eigenständiger Bildstand. Über „Bild ersetzen“ kannst du ein Bildprojekt zuordnen.")).font(.caption).foregroundStyle(.secondary)
            }
            TextField(String(localized: "Bildunterschrift / Beschreibung"), text: Binding(get: { step.caption }, set: { text in model.editStep(step.id, textGroup: "caption-\(step.id)") { $0.caption = String(text.prefix(8_000)) } }), axis: .vertical)
                .lineLimit(2...12).textFieldStyle(.roundedBorder).disabled(!workspace.purchases.hasPro)
                .accessibilityIdentifier("guide.step.caption.\(step.id)")
                .accessibilityLabel(String(localized: "Beschreibung von Schritt \(index + 1)"))
        }.padding(16).background(.background, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(model.selectedStep == step.id ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 2 : 1) }
    }
    @ViewBuilder private func sourceActions(_ step: GuideStep, source: ProjectLibraryItem) -> some View {
        Button(String(localized: "Bild bearbeiten"), systemImage: "pencil") { Task { await workspace.editGuideImage(step.id) } }.disabled(!workspace.purchases.hasPro)
        if step.sourceRevision == nil {
            Button(String(localized: "Bild aktualisieren"), systemImage: "arrow.triangle.2.circlepath") { workspace.addGuideProjects([source.id], replacing: step.id) }
                .disabled(!workspace.purchases.hasPro)
        } else if step.sourceRevision != source.document.revision {
            Button(String(localized: "Quellprojekt geändert · Aktualisieren"), systemImage: "arrow.triangle.2.circlepath") { workspace.addGuideProjects([source.id], replacing: step.id) }
                .disabled(!workspace.purchases.hasPro).accessibilityIdentifier("guide.sourceChanged.\(step.id)")
        }
    }
    private func revealStep(_ id: UUID) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        model.selectedStep = id; navigationRequest += 1
    }
    private func openAssistant(_ scope: GuideTextScope) {
        guard !model.isBusy, !model.isSuspended, !model.showsTrash, model.selectedDocumentIDs.count <= 1,
              let document = model.document, model.requestFeature(.guides) else { return }
        assistantRequest = GuideAssistantRequest(source: document, scope: scope)
    }
    private func moveStep(_ id: UUID, by offset: Int) {
        model.edit { $0.moveStep(id, by: offset) }; revealStep(id)
    }
}

struct GuideOutputMenu: View {
    @Bindable var model: GuideModel
    var body: some View {
        Menu(String(localized: "Exportieren"), systemImage: "square.and.arrow.up") {
            Button(String(localized: "PDF exportieren …")) { model.chooseExport(.pdf) }.disabled(model.document?.steps.isEmpty != false)
            Button(String(localized: "Markdown exportieren …")) { model.chooseExport(.markdown) }.disabled(model.document?.steps.isEmpty != false)
            Divider()
            Button(String(localized: "Bearbeitbare Anleitung exportieren …")) { model.chooseExport(.workingCopy) }
        }.disabled(model.document == nil || model.isBusyForControls || model.isSuspended || model.showsTrash || model.selectedDocumentIDs.count > 1)
    }
}

/// Busy presentation observes its state independently of the split columns.
private struct GuideActivityShield: View {
    @Bindable var model: GuideModel
    var body: some View {
        Color.clear.contentShape(.rect)
            .onTapGesture { }
            .overlay {
                if model.isBusy && !model.isOpeningDocument {
                    ProgressView(String(localized: "Anleitung verarbeiten …"))
                        .padding().background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .allowsHitTesting(model.isBusy || model.isSuspended)
            .accessibilityHidden(!model.isBusy)
    }
}

/// Long opens get a small reserved indicator, never a popup over the entire editor.
private struct GuideOpeningIndicator: View {
    @Bindable var model: GuideModel
    @State private var progressDocumentID: UUID?
    var body: some View {
        ProgressView(String(localized: "Anleitung verarbeiten …")).labelsHidden().controlSize(.small)
            .opacity(model.isOpeningDocument && progressDocumentID == model.openingDocumentID ? 1 : 0)
            .accessibilityHidden(!model.isOpeningDocument || progressDocumentID != model.openingDocumentID)
            .allowsHitTesting(false)
            .task(id: model.openingDocumentID) {
                progressDocumentID = nil
                guard let id = model.openingDocumentID else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard !Task.isCancelled, model.openingDocumentID == id else { return }
                progressDocumentID = id
            }
    }
}
private struct GuideFailureView: View {
    @Bindable var model: GuideModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.error ?? "").foregroundStyle(.red).textSelection(.enabled)
            HStack {
                switch model.failureContext {
                case .save:
                    Button(String(localized: "Erneut sichern")) { Task { await model.flush() } }
                    Button(String(localized: "Als neue Anleitung sichern")) { model.saveAsCopy() }
                case .output(let output):
                    Button(String(localized: "Export erneut versuchen …")) { model.chooseExport(output) }
                case .preview:
                    Button(String(localized: "Vorschau erneut erstellen")) { model.showPreview() }
                case .operation: EmptyView()
                }
                Button(String(localized: "Schließen")) { model.error = nil }
            }
        }.accessibilityIdentifier("guide.failure")
    }
}

private struct GuideProjectPicker: View {
    let items: [ProjectLibraryItem]
    let maximum: Int
    let completion: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [UUID] = []
    @State private var query = ""
    private var filteredItems: [ProjectLibraryItem] { items.filter { query.isEmpty || $0.document.title.localizedStandardContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(maximum == 1 ? String(localized: "Screenshot wählen") : String(localized: "Screenshots hinzufügen")).font(.headline)
            TextField(String(localized: "Projekte suchen"), text: $query).textFieldStyle(.roundedBorder).accessibilityIdentifier("guide.picker.search")
            if !selection.isEmpty {
                Text(String(localized: "Reihenfolge der Schritte")).font(.subheadline)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(selection.enumerated()), id: \.element) { index, id in
                            VStack(spacing: 4) {
                                Text("\(index + 1). " + (items.first { $0.id == id }?.document.title ?? "")).lineLimit(1).frame(width: 150)
                                HStack {
                                    Button(String(localized: "Schritt nach oben"), systemImage: "arrow.left") { selection.swapAt(index, index - 1) }.disabled(index == 0)
                                    Button(String(localized: "Schritt nach unten"), systemImage: "arrow.right") { selection.swapAt(index, index + 1) }.disabled(index == selection.count - 1)
                                    Button(String(localized: "Auswahl entfernen"), systemImage: "xmark") { selection.removeAll { $0 == id } }
                                }.labelStyle(.iconOnly)
                            }.padding(8).background(.quaternary, in: .rect(cornerRadius: 8))
                        }
                    }
                }.frame(height: 76).accessibilityIdentifier("guide.picker.order")
            }
            List {
                ForEach(filteredItems) { item in
                    Toggle(isOn: Binding(get: { selection.contains(item.id) }, set: { chosen in
                        if chosen {
                            if maximum == 1 { selection = [item.id] }
                            else if selection.count < maximum && !selection.contains(item.id) { selection.append(item.id) }
                        } else { selection.removeAll { $0 == item.id } }
                    })) {
                        HStack(spacing: 12) {
                            GuideImage(data: item.thumbnail, maximumDimension: 168).equatable().frame(width: 80, height: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.document.title).lineLimit(2)
                                if let index = selection.firstIndex(of: item.id) { Text(String(localized: "Schritt \(index + 1)")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                    }.toggleStyle(.checkbox).padding(.vertical, 4)
                        .disabled(!selection.contains(item.id) && selection.count >= maximum && maximum != 1)
                        .accessibilityIdentifier("guide.picker.project.\(item.id)")
                }
            }.listStyle(.inset).overlay {
                if filteredItems.isEmpty {
                    if items.isEmpty { ContentUnavailableView(String(localized: "Noch keine Screenshots"), systemImage: "photo.on.rectangle") }
                    else { ContentUnavailableView.search(text: query) }
                }
            }
            HStack {
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Übernehmen")) { completion(selection); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(selection.isEmpty).accessibilityIdentifier("guide.picker.confirm")
            }
        }.padding(20).frame(width: 560, height: 540)
    }
}
private struct GuidePDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}

private struct GuideImage: View, Equatable {
    let data: Data?
    var maximumDimension: Int
    var prepared: CGImage? = nil
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data && lhs.maximumDimension == rhs.maximumDimension && lhs.prepared === rhs.prepared
    }
    var body: some View {
        Group {
            if let prepared { Image(decorative: prepared, scale: 1).resizable().scaledToFit() }
            else { ProjectThumbnail(data: data, maximumDimension: maximumDimension) }
        }.accessibilityHidden(false)
    }
}

/// An explicit AppKit drag handle keeps the button's click and the system drag distinct.
private struct GuideStepDragHandle: NSViewRepresentable {
    let payload: String
    func makeNSView(context: Context) -> GuideStepDragSource { GuideStepDragSource() }
    func updateNSView(_ view: GuideStepDragSource, context: Context) { view.payload = payload }
}
private final class GuideStepDragSource: NSView, NSDraggingSource {
    var payload = ""
    private var start: NSPoint?
    private var isDragging = false
    private var symbol: NSImage? {
        NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        symbol?.draw(in: NSRect(x: 3, y: bounds.midY - 7, width: 14, height: 14))
    }
    override func mouseDown(with event: NSEvent) {
        traceDrag("mouseDown")
        start = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(nil)
    }
    override func mouseDragged(with event: NSEvent) {
        traceDrag("mouseDragged")
        guard !isDragging, let start, payload.count == 73 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - start.x, dy = point.y - start.y
        guard dx * dx + dy * dy >= 9 else { return }
        let writer = NSPasteboardItem(); writer.setString(payload, forType: .string)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: symbol)
        isDragging = true
        traceDrag("session started")
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) { traceDrag("mouseUp"); start = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.move, .copy] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        traceDrag("session ended: \(operation.rawValue)"); isDragging = false; start = nil
    }
    private func traceDrag(_ message: String) {
        #if GUIDE_WORKFLOW_QA
        // Only the disposable fixture records native event names; never image or text content.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snaprivo-guide-drag-qa.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data((message + "\n").utf8))
        }
        #endif
    }
}

private struct GuideEditorFocusKey: FocusedValueKey { typealias Value = GuideModel }
extension FocusedValues {
    var guideEditor: GuideModel? {
        get { self[GuideEditorFocusKey.self] }
        set { self[GuideEditorFocusKey.self] = newValue }
    }
}
