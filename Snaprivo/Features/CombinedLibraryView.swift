import SwiftUI
import SnagForgeDomain

/// Images and videos in one grid. Trash, selection, favorites, tags and file actions stay in the
/// single-media tabs; here a card opens its item, and rename/trash sit in the context menu.
struct CombinedLibraryView: View {
    let workspace: WorkspaceModel
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var byName = false
    @State private var imageMatches: Set<UUID>?
    @State private var renamingImage: ProjectDocument?
    @State private var renamingVideo: VideoDocument?
    private struct SearchKey: Equatable {
        let query: String
        let revisions: [String]
        let indexVersion: Int
        let includesOCR: Bool
        let hasPro: Bool
    }
    private var activeVideos: [VideoRecordingFiles.Item] { workspace.videos.items.filter { $0.document.trashedAt == nil } }
    /// The open editor holds the newest title and revision of its image.
    private var documents: [ProjectDocument] {
        workspace.items.map { item in workspace.editor.map { $0.document.id == item.id ? $0.document : item.document } ?? item.document }
    }
    private var searchKey: SearchKey {
        SearchKey(query: query, revisions: documents.map { "\($0.id):\($0.revision)" }, indexVersion: workspace.search.changeVersion,
                  includesOCR: workspace.purchases.hasPro && workspace.preferences.ocrIndexingEnabled, hasPro: workspace.purchases.hasPro)
    }
    private var entries: [LibraryEntry] {
        LibraryEntry.combined(images: workspace.items, videos: workspace.videos.items, query: query, imageMatches: imageMatches,
                              includesOrganization: workspace.purchases.hasPro, byName: byName)
    }
    var body: some View {
        @Bindable var videos = workspace.videos
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Reuses the singular/plural forms of both tabs („1 Bild · 2 Videos“).
                Text(verbatim: String(localized: "\(workspace.items.count) Bilder") + " · " + String(localized: "\(activeVideos.count) Videos"))
                    .font(.headline).fixedSize()
                Spacer()
                Menu {
                    Picker(String(localized: "Sortieren"), selection: $byName) {
                        Text(String(localized: "Neueste zuerst")).tag(false)
                        Text(String(localized: "Name")).tag(true)
                    }.pickerStyle(.inline).labelsHidden()
                } label: { Label(byName ? String(localized: "Name") : String(localized: "Neueste zuerst"), systemImage: "arrow.up.arrow.down") }
                    .fixedSize().accessibilityLabel(String(localized: "Sortieren")).accessibilityIdentifier("library.all.sort")
            }.padding(16)
            if let error = workspace.storage.libraryError {
                ContentUnavailableView {
                    Label(String(localized: "Bibliothek nicht erreichbar"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button(String(localized: "Speicherort in Einstellungen prüfen …")) { openSettings() }
                }
            } else if !workspace.didLoadLibrary || !videos.didLoad {
                ProgressView(String(localized: "Bibliothek laden …")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if workspace.items.isEmpty && activeVideos.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Deine Aufnahmen, an einem Ort"), systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text(String(localized: "Bilder und Videos erscheinen hier gemeinsam, die neuesten zuerst."))
                } actions: {
                    Button(String(localized: "Bild öffnen …")) { workspace.isImporting = true }.buttonStyle(.glassProminent)
                }
            } else if entries.isEmpty {
                ContentUnavailableView(String(localized: "Keine passenden Aufnahmen"), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Video cards carry an extra line; top alignment keeps each row's images and titles level.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 20, alignment: .top)], spacing: 20) {
                        ForEach(entries) { entry in card(entry) }
                    }.padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .searchable(text: $query, prompt: String(localized: "Bilder und Videos durchsuchen"))
        .sheet(item: $renamingImage) { document in
            ProjectRenameSheet(title: document.title) { await workspace.updateProjectMetadata(document.id, title: $0) }
        }
        .sheet(item: $renamingVideo) { document in
            ProjectRenameSheet(title: document.title, heading: String(localized: "Video umbenennen"), prompt: String(localized: "Videoname")) {
                await workspace.videos.rename(document.id, title: $0)
            }
        }
        .sheet(item: $videos.preview) { preview in VideoReviewView(model: preview) }
        .alert(String(localized: "Videoaktion fehlgeschlagen"), isPresented: Binding(get: { videos.error != nil }, set: { if !$0 { videos.error = nil } })) {
            Button("OK") { videos.error = nil }
        } message: { Text(videos.error ?? "") }
        .task { await workspace.videos.refresh() }
        // Content search runs like in the image tab; until it finishes, titles, tags and collections match directly.
        .task(id: searchKey) {
            imageMatches = nil
            let key = searchKey
            guard !LibrarySearch.terms(key.query).isEmpty else { return }
            let documents = documents.map { document in
                var value = document
                if !key.hasPro { value.tags = []; value.collections = [] }
                return value
            }
            guard let result = try? await workspace.search.matches(query: key.query, documents: documents, includeOCR: key.includesOCR),
                  !Task.isCancelled else { return }
            imageMatches = result
        }
    }

    @ViewBuilder private func card(_ entry: LibraryEntry) -> some View {
        switch entry {
        case .image(let item):
            Button { workspace.openProject(item.id) } label: { LibraryCard(item: item) }
                .buttonStyle(.plain)
                .help(String(localized: "Bild öffnen und weiter bearbeiten"))
                .accessibilityIdentifier("library.all.image.\(item.id)")
                .disabled(workspace.isUpdatingMetadata)
                .allowsHitTesting(!workspace.isLoading)
                .contextMenu {
                    Button(String(localized: "Umbenennen …")) { renamingImage = item.document }
                    Button(String(localized: "In den Papierkorb"), systemImage: "trash") { Task { _ = await workspace.changeTrash(item.id, action: .trash) } }
                }
        case .video(let item):
            Group {
                if item.document.state == .finished {
                    Button { Task { await workspace.videos.showPreview(item.id) } } label: { VideoLibraryCard(item: item) }
                        .buttonStyle(.plain).help(String(localized: "Video ansehen"))
                } else {
                    VideoLibraryCard(item: item)
                }
            }
            .accessibilityIdentifier("library.all.video.\(item.id)")
            .disabled(workspace.videos.isBusy)
            .contextMenu {
                Button(String(localized: "Umbenennen …")) { renamingVideo = item.document }
                Button(String(localized: "In den Papierkorb"), systemImage: "trash") { Task { _ = await workspace.videos.changeTrash(item.id, action: .trash) } }
            }
        }
    }
}
