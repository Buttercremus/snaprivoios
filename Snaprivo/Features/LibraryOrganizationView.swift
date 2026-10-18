import SwiftUI
import SnagForgeDomain

struct LibraryIndexControls: View {
    let workspace: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(String(localized: "Bildinhalt lokal durchsuchen (OCR)"), isOn: Binding(
                get: { workspace.preferences.ocrIndexingEnabled }, set: { workspace.preferences.ocrIndexingEnabled = $0 }))
                .accessibilityIdentifier("library.index.enabled")
            Text(String(localized: "Titel, Tags und Sammlungen sind immer durchsuchbar. OCR speichert erkannten sichtbaren Bildtext lokal im löschbaren Suchcache; Ausschalten entfernt diesen Cache."))
                .font(.caption).foregroundStyle(.secondary)
            if workspace.preferences.ocrIndexingEnabled {
                HStack {
                    if workspace.search.isIndexing { ProgressView().controlSize(.small) }
                    Text(String(localized: "Suchindex: \(workspace.search.completed) von \(workspace.search.total) Projekten verarbeitet"))
                        .font(.caption).monospacedDigit()
                    Spacer(minLength: 8)
                    if workspace.search.isIndexing {
                        Button(String(localized: "Abbrechen")) { workspace.search.cancel() }.accessibilityIdentifier("library.index.cancel")
                    } else {
                        Menu(String(localized: "Suchindex")) {
                            Button(String(localized: "Indexierung fortsetzen")) { workspace.synchronizeSearch(retry: true) }
                            Button(String(localized: "Suchindex neu aufbauen")) { workspace.synchronizeSearch(rebuild: true) }
                        }.accessibilityIdentifier("library.index.actions")
                    }
                }
                if workspace.search.failures > 0 {
                    Text(String(localized: "\(workspace.search.failures) Projekte konnten nicht erkannt werden. Setze die Indexierung erneut fort."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if let error = workspace.search.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if !workspace.preferences.ocrIndexingEnabled && workspace.search.error != nil {
                Button(String(localized: "Suchcache entfernen")) { workspace.synchronizeSearch(retry: true) }
            }
            if let notice = workspace.search.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProjectOrganizationSheet: View {
    let document: ProjectDocument
    let existingCollections: [String]
    let save: ([String], [String]) async -> Bool
    @State private var tags: String
    @State private var collections: String
    @State private var saving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    init(document: ProjectDocument, existingCollections: [String], save: @escaping ([String], [String]) async -> Bool) {
        self.document = document; self.existingCollections = existingCollections; self.save = save
        _tags = State(initialValue: document.tags.joined(separator: "\n"))
        _collections = State(initialValue: document.collections.joined(separator: "\n"))
    }
    private var normalizedTags: [String]? { normalize(tags, limit: ProjectOrganization.maximumTags) }
    private var normalizedCollections: [String]? { normalize(collections, limit: ProjectOrganization.maximumCollections) }
    private func normalize(_ text: String, limit: Int) -> [String]? {
        guard text.utf8.count <= 16_000 else { return nil }
        return try? ProjectOrganization.normalized(text.components(separatedBy: .newlines), limit: limit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Tags und Sammlungen")).font(.title2.bold())
            Text(document.title).lineLimit(2).foregroundStyle(.secondary)
            Text(String(localized: "Je Zeile ein Eintrag. Bis zu 32 Tags und 16 Sammlungen mit jeweils 80 Zeichen. Leere Zeilen werden entfernt, doppelte Namen zusammengefasst."))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text(String(localized: "Tags")).font(.headline)
                    TextEditor(text: $tags).font(.body).padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                        .accessibilityLabel(String(localized: "Tags, je Zeile ein Eintrag"))
                        .accessibilityIdentifier("project.organization.tags")
                }
                VStack(alignment: .leading) {
                    Text(String(localized: "Sammlungen")).font(.headline)
                    TextEditor(text: $collections).font(.body).padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                        .accessibilityLabel(String(localized: "Sammlungen, je Zeile ein Eintrag"))
                        .accessibilityIdentifier("project.organization.collections")
                    Menu(String(localized: "Vorhandene Sammlung hinzufügen")) {
                        ForEach(existingCollections, id: \.self) { name in
                            Button(name) { collections += (collections.isEmpty ? "" : "\n") + name }
                        }
                    }.disabled(existingCollections.isEmpty)
                }
            }.frame(height: 180).disabled(saving)
            Text(String(localized: "Eine neue Sammlung entsteht durch Zuordnen eines Projekts. Gleiche Namen gruppieren Projekte; Entfernen einer Zuordnung löscht kein Projekt. Tags und Zuordnungen bleiben in Projekt und Backup erhalten."))
                .font(.caption).foregroundStyle(.secondary)
            if normalizedTags == nil || normalizedCollections == nil {
                Text(String(localized: "Prüfe die Anzahl und Länge der Einträge. Steuerzeichen sind nicht erlaubt."))
                    .font(.caption).foregroundStyle(.orange)
            }
            if failed { Text(String(localized: "Die Zuordnungen konnten nicht gesichert werden. Versuche es erneut.")).foregroundStyle(.orange) }
            HStack {
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Spacer()
                Button(String(localized: "Sichern")) {
                    guard let tags = normalizedTags, let collections = normalizedCollections else { return }
                    saving = true
                    Task { if await save(tags, collections) { dismiss() } else { failed = true }; saving = false }
                }.keyboardShortcut(.defaultAction).disabled(saving || normalizedTags == nil || normalizedCollections == nil)
                    .accessibilityIdentifier("project.organization.save")
            }
        }.padding(24).frame(width: 560).interactiveDismissDisabled(saving)
    }
}
