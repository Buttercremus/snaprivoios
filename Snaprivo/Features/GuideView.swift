import SwiftUI
import PDFKit
import SnagForgeDomain

struct GuideView: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var model: GuideModel
    @State private var choosingImages = false
    @State private var replacing: UUID?
    @State private var removing: UUID?
    var body: some View {
        HSplitView {
            if !model.documents.isEmpty || model.document != nil { guideList }
            if let document = model.document {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !workspace.purchases.hasPro {
                            Button(String(localized: "Anleitung bearbeiten · Pro"), systemImage: "lock") { workspace.showPro(.guides) }
                            Text(String(localized: "Öffnen und Exportieren bleibt kostenlos."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        TextField(String(localized: "Anleitungstitel"), text: field(\.title, limit: 256))
                            .font(.title2).textFieldStyle(.roundedBorder).accessibilityIdentifier("guide.title")
                            .disabled(!workspace.purchases.hasPro)
                        TextField(String(localized: "Einleitung (optional)"), text: field(\.introduction, limit: 8_000), axis: .vertical)
                            .lineLimit(2...8).textFieldStyle(.roundedBorder)
                            .disabled(!workspace.purchases.hasPro)
                        HStack {
                            Picker(String(localized: "PDF-Stil"), selection: Binding(get: { document.style }, set: { style in model.edit { $0.style = style } })) {
                                Text(String(localized: "Standard")).tag(GuideStyle.standard)
                                Text(String(localized: "Kompakt")).tag(GuideStyle.compact)
                            }.frame(maxWidth: 240).disabled(!workspace.purchases.hasPro)
                            Spacer()
                            Text(model.isSaving ? String(localized: "Wird gesichert …") : model.isDirty ? String(localized: "Ungesicherte Änderungen") : String(localized: "Gesichert"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = model.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).foregroundStyle(.red)
                                HStack {
                                    Button(String(localized: "Erneut sichern")) { Task { await model.flush() } }
                                    Button(String(localized: "Als neue Anleitung sichern")) { model.saveAsCopy() }
                                }
                            }
                        }
                        if let notice = model.notice { Text(notice).font(.callout).textSelection(.enabled) }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                addScreenshots.fixedSize()
                                Spacer(minLength: 8)
                                outputMenu(document).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                addScreenshots
                                outputMenu(document)
                            }
                        }
                        Text(String(localized: "Bilder übernehmen sichtbare Markierungen, Zuschnitt und Schwärzungen mit bis zu 2560 Pixeln Kantenlänge. Spätere Projektänderungen über „Bild aktualisieren“ übernehmen."))
                            .font(.caption).foregroundStyle(.secondary)
                        if document.steps.isEmpty {
                            ContentUnavailableView(String(localized: "Noch keine Schritte"), systemImage: "list.number", description: Text(String(localized: "Füge bearbeitete Screenshots aus deiner Bibliothek hinzu.")))
                        } else {
                            ForEach(Array(document.steps.enumerated()), id: \.element.id) { index, step in
                                stepView(step, index: index, count: document.steps.count)
                            }
                        }
                    }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label(model.documents.isEmpty ? String(localized: "Screenshots als Anleitung") : String(localized: "Anleitung auswählen"), systemImage: "list.number")
                } description: {
                    Text(model.documents.isEmpty ? String(localized: "Schritte sortieren, beschreiben und als PDF oder Markdown weitergeben.") : String(localized: "Wähle links eine Anleitung oder erstelle eine neue."))
                } actions: {
                    Button(String(localized: "Neue Anleitung")) { model.create() }
                        .buttonStyle(.glassProminent).accessibilityIdentifier("guide.empty.create")
                    if model.documents.isEmpty {
                        Button(String(localized: "Anleitung importieren …")) { model.chooseImport() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("guide.empty")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView(String(localized: "Anleitung verarbeiten …")).padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .safeAreaInset(edge: .bottom) {
            if !model.issues.isEmpty { Text(model.issues.joined(separator: "\n")).font(.caption).foregroundStyle(.red).padding() }
            if model.document == nil, let error = model.error { Text(error).foregroundStyle(.red).padding() }
        }
        .task { await model.refresh() }
        .sheet(isPresented: $choosingImages) {
            GuideProjectPicker(items: workspace.items, single: replacing != nil) { ids in
                workspace.addGuideProjects(ids, replacing: replacing)
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
                if let removing { model.edit { $0.steps.removeAll { $0.id == removing } } }
                removing = nil
            }
        } message: { Text(String(localized: "Das Bildprojekt bleibt in der Bibliothek erhalten.")) }
    }
    private var addScreenshots: some View {
        Button(String(localized: "Screenshots hinzufügen"), systemImage: "photo.badge.plus") {
            guard workspace.requirePro(.guides) else { return }
            replacing = nil; choosingImages = true
        }
            .accessibilityIdentifier("guide.addImages")
    }
    private func outputMenu(_ document: GuideDocument) -> some View {
        Menu(String(localized: "Ausgeben"), systemImage: "square.and.arrow.up") {
            Button(String(localized: "PDF-Vorschau")) { model.showPreview() }.disabled(document.steps.isEmpty)
            Button(String(localized: "PDF exportieren …")) { model.chooseExport(.pdf) }.disabled(document.steps.isEmpty)
            Button(String(localized: "Markdown exportieren …")) { model.chooseExport(.markdown) }.disabled(document.steps.isEmpty)
            Divider()
            Button(String(localized: "Bearbeitbare Anleitung exportieren …")) { model.chooseExport(.workingCopy) }
        }
    }
    private var guideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Anleitungen")).font(.headline)
                Spacer()
                Button(String(localized: "Neue Anleitung"), systemImage: "plus") { model.create() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(width: 28, height: 28).help(String(localized: "Neue Anleitung"))
                    .accessibilityIdentifier("guide.create")
            }.padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            List(selection: Binding(get: { model.document?.id }, set: { if let id = $0 { model.open(id) } })) {
                ForEach(model.documents) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title).lineLimit(2)
                        Text(String(localized: "\(document.stepCount) Schritte")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(document.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 0, maxHeight: .infinity)
            .accessibilityIdentifier("guide.list")
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button { model.chooseImport() } label: {
                    Label(String(localized: "Importieren …"), systemImage: "square.and.arrow.down")
                        .lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                }
                .help(String(localized: "Anleitung importieren …"))
                .accessibilityLabel(String(localized: "Anleitung importieren …"))
                .accessibilityIdentifier("guide.import")
                Text(String(localized: "In „Alles sichern“ enthalten"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(String(localized: "„Alles sichern“ enthält auch deine Anleitungen. Einzelne bearbeitbare Kopien kannst du zusätzlich exportieren."))
                    .accessibilityHint(String(localized: "„Alles sichern“ enthält auch deine Anleitungen. Einzelne bearbeitbare Kopien kannst du zusätzlich exportieren."))
            }.padding(16)
        }
        .frame(minWidth: 180, idealWidth: 208, maxWidth: 240, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }
    private func field(_ path: WritableKeyPath<GuideDocument, String>, limit: Int) -> Binding<String> {
        Binding(get: { model.document?[keyPath: path] ?? "" }, set: { text in model.edit { $0[keyPath: path] = String(text.prefix(limit)) } })
    }
    private func stepView(_ step: GuideStep, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Schritt \(index + 1)")).font(.headline)
                Spacer()
                Button(String(localized: "Schritt nach oben"), systemImage: "arrow.up") { model.edit { $0.moveStep(step.id, by: -1) } }
                    .disabled(index == 0 || !workspace.purchases.hasPro).labelStyle(.iconOnly)
                Button(String(localized: "Schritt nach unten"), systemImage: "arrow.down") { model.edit { $0.moveStep(step.id, by: 1) } }
                    .disabled(index == count - 1 || !workspace.purchases.hasPro).labelStyle(.iconOnly)
                Menu {
                    if let source = step.sourceProjectID, step.sourceLibrary == GuideModel.libraryKey(workspace.store), workspace.items.contains(where: { $0.id == source }) {
                        Button(String(localized: "Bild aktualisieren")) { workspace.addGuideProjects([source], replacing: step.id) }
                    }
                    Button(String(localized: "Bild ersetzen …")) { replacing = step.id; choosingImages = true }
                    Button(String(localized: "Schritt entfernen …"), role: .destructive) { removing = step.id }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "Schrittaktionen")) }
                .disabled(!workspace.purchases.hasPro)
            }
            TextField(String(localized: "Schritttitel"), text: Binding(get: { step.title }, set: { text in model.editStep(step.id) { $0.title = String(text.prefix(256)) } }))
                .textFieldStyle(.roundedBorder)
                .disabled(!workspace.purchases.hasPro)
            if let image = NSImage(data: step.png) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 280).frame(maxWidth: .infinity)
                    .accessibilityLabel(step.title)
            }
            TextField(String(localized: "Bildunterschrift / Beschreibung"), text: Binding(get: { step.caption }, set: { text in model.editStep(step.id) { $0.caption = String(text.prefix(8_000)) } }), axis: .vertical)
                .lineLimit(2...12).textFieldStyle(.roundedBorder)
                .disabled(!workspace.purchases.hasPro)
        }.padding(16).background(.background, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1) }
    }
}

private struct GuideProjectPicker: View {
    let items: [ProjectLibraryItem]
    let single: Bool
    let completion: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var query = ""
    private var filteredItems: [ProjectLibraryItem] {
        items.filter { query.isEmpty || $0.document.title.localizedStandardContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(single ? String(localized: "Bild ersetzen") : String(localized: "Screenshots hinzufügen")).font(.headline)
            TextField(String(localized: "Projekte suchen"), text: $query).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("guide.picker.search")
            List {
                ForEach(filteredItems) { item in
                    Toggle(isOn: Binding(get: { selection.contains(item.id) }, set: { chosen in
                        if single { selection = chosen ? [item.id] : [] }
                        else if chosen { selection.insert(item.id) } else { selection.remove(item.id) }
                    })) {
                        HStack(spacing: 12) {
                            ProjectThumbnail(data: item.thumbnail, maximumDimension: 168)
                                .frame(width: 80, height: 56)
                                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 4))
                                .clipShape(.rect(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.document.title).lineLimit(2)
                                Text(String(localized: "\(item.document.outputPixelSize.width) × \(item.document.outputPixelSize.height) Pixel"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .toggleStyle(.checkbox).padding(.vertical, 4)
                    .help(item.document.title)
                    .accessibilityIdentifier("guide.picker.project.\(item.id)")
                }
            }
            .listStyle(.inset)
            .overlay {
                if filteredItems.isEmpty {
                    if items.isEmpty {
                        ContentUnavailableView(String(localized: "Noch keine Screenshots"), systemImage: "photo.on.rectangle", description: Text(String(localized: "Füge bearbeitete Screenshots aus deiner Bibliothek hinzu.")))
                    } else { ContentUnavailableView.search(text: query) }
                }
            }
            HStack {
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Übernehmen")) { completion(items.filter { selection.contains($0.id) }.map(\.id)); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(selection.isEmpty)
                    .accessibilityIdentifier("guide.picker.confirm")
            }
        }.padding(20).frame(width: 560, height: 480)
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
