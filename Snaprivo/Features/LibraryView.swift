import SwiftUI
import SnagForgeDomain

struct LibraryView: View {
    let workspace: WorkspaceModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedProjects = Set<UUID>()
    @State private var selecting = false
    @State private var showsTrash = false
    @State private var deleting: ProjectDocument?
    private var displayedItems: [ProjectLibraryItem] { showsTrash ? workspace.trashItems : workspace.items }
    private var issues: [String] { showsTrash ? workspace.trashIssues : workspace.libraryIssues }
    @State private var query = ""
    @State private var renaming: ProjectDocument?
    @State private var organizing: ProjectDocument?
    @State private var tagFilter = ""
    @State private var collectionFilter = ""
    @State private var matches = Set<UUID>()
    @State private var resultKey: SearchInputs?
    @State private var searchError: String?
    @State private var showsSearchProgress = false
    @State private var showsOpeningProgress = false
    private struct SearchInputs: Equatable {
        let query: String
        let revisions: [String]
        let indexVersion: Int
        let includesOCR: Bool
        let trash: Bool
        let hasPro: Bool
    }
    private var documents: [ProjectDocument] {
        displayedItems.map { item in
            if !showsTrash, let editor = workspace.editor, editor.document.id == item.id { return editor.document }
            return item.document
        }
    }
    private var searchInputs: SearchInputs {
        SearchInputs(query: query, revisions: documents.map { "\($0.id):\($0.revision)" },
                     indexVersion: workspace.search.changeVersion, includesOCR: workspace.purchases.hasPro && workspace.preferences.ocrIndexingEnabled && !showsTrash, trash: showsTrash, hasPro: workspace.purchases.hasPro)
    }
    private var isSearching: Bool { !LibrarySearch.terms(query).isEmpty && resultKey != searchInputs }
    private func names(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(LibrarySearch.fold($0)).inserted }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var tags: [String] { names(documents.flatMap(\.tags)) }
    private var collections: [String] { names(documents.flatMap(\.collections)) }
    private var filtered: [ProjectLibraryItem] {
        let byID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        let input = searchInputs
        let hasQuery = !LibrarySearch.terms(query).isEmpty
        // Retain the last completed result while a new query runs. Never retain
        // OCR matches across edits, library scopes or a privacy/entitlement change.
        let canRetain = resultKey.map {
            $0.revisions == input.revisions && $0.includesOCR == input.includesOCR
                && $0.trash == input.trash && $0.hasPro == input.hasPro
        } ?? false
        let retainAll = canRetain && LibrarySearch.terms(resultKey?.query ?? "").isEmpty
        return workspace.preferences.librarySort.ordered(displayedItems.filter { item in
            let document = byID[item.id] ?? item.document
            var metadata = document
            if !input.hasPro { metadata.tags = []; metadata.collections = [] }
            let matchesQuery = !hasQuery || (canRetain ? retainAll || matches.contains(item.id)
                : LibrarySearch.matches(metadata, query: query))
            return matchesQuery
                && (!workspace.purchases.hasPro || tagFilter.isEmpty || document.tags.contains { LibrarySearch.fold($0) == tagFilter })
                && (!workspace.purchases.hasPro || collectionFilter.isEmpty || document.collections.contains { LibrarySearch.fold($0) == collectionFilter })
                && (showsTrash || !workspace.preferences.favoritesOnly || document.isFavorite)
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            libraryControls
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if !issues.isEmpty && workspace.storage.libraryError == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "\(issues.count) Bilder konnten nicht geladen werden"), systemImage: "exclamationmark.triangle")
                    DisclosureGroup(String(localized: "Details")) {
                        ForEach(issues, id: \.self) { Text($0).textSelection(.enabled).font(.caption) }
                    }
                    Button(String(localized: "Erneut laden")) { Task { await workspace.refreshLibrary() } }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
            if let error = workspace.storage.libraryError {
                ContentUnavailableView {
                    Label(String(localized: "Bibliothek nicht erreichbar"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button(String(localized: "Speicherort in Einstellungen prüfen …")) { openSettings() }
                }
            } else if !workspace.didLoadLibrary {
                ProgressView(String(localized: "Bibliothek laden …")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showsTrash && displayedItems.isEmpty {
                ContentUnavailableView(String(localized: "Papierkorb ist leer"), systemImage: "trash", description: Text(String(localized: "Hier bleiben entfernte Bilder erhalten, bis du sie endgültig löschst.")))
            } else if displayedItems.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Deine Aufnahmen, an einem Ort"), systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text(String(localized: "Erstelle eine Aufnahme oder importiere ein Bild. Original und Markierungen werden automatisch in deiner lokalen Bibliothek gesichert."))
                } actions: {
                    Button(String(localized: "Bild öffnen …")) { workspace.isImporting = true }.buttonStyle(.glassProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 20)], spacing: 20) {
                        ForEach(filtered) { item in
                            VStack(spacing: 0) {
                                Button {
                                    if selecting {
                                        if selectedProjects.contains(item.id) { selectedProjects.remove(item.id) } else { selectedProjects.insert(item.id) }
                                    } else if !showsTrash { workspace.openProject(item.id) }
                                } label: {
                                    LibraryCard(item: item).overlay(alignment: .topTrailing) {
                                        if selecting { Image(systemName: selectedProjects.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.tint).padding(12) }
                                    }.overlay(alignment: .bottomTrailing) {
                                        if showsOpeningProgress && workspace.openingProjectID == item.id {
                                            ProgressView().controlSize(.small).padding(8)
                                                .background(.regularMaterial, in: .capsule).padding(10)
                                                .accessibilityLabel(String(localized: "Projekt öffnen …"))
                                                .accessibilityIdentifier("library.openingProgress")
                                        }
                                    }
                                }
                                .accessibilityValue(selecting && selectedProjects.contains(item.id) ? String(localized: "Ausgewählt") : "")
                                    .buttonStyle(.plain)
                                    .disabled(showsTrash)
                                    .help(showsTrash ? String(localized: "Zum Bearbeiten zuerst wiederherstellen") : String(localized: "Bild öffnen und weiter bearbeiten"))
                                HStack {
                                    if showsTrash {
                                        Button(String(localized: "Wiederherstellen"), systemImage: "arrow.uturn.backward") { Task { _ = await workspace.changeTrash(item.id, action: .restore) } }
                                        Spacer()
                                        Button(String(localized: "Löschen …"), systemImage: "trash", role: .destructive) { deleting = item.document }
                                    } else {
                                    Button { Task { _ = await workspace.updateProjectMetadata(item.id, favorite: !item.document.isFavorite) } } label: {
                                        Image(systemName: item.document.isFavorite ? "star.fill" : "star")
                                    }.accessibilityLabel(item.document.isFavorite ? String(localized: "Aus Favoriten entfernen") : String(localized: "Zu Favoriten hinzufügen"))
                                        .help(item.document.isFavorite ? String(localized: "Aus Favoriten entfernen") : String(localized: "Zu Favoriten hinzufügen"))
                                    Spacer()
                                    Button(String(localized: "Umbenennen …"), systemImage: "pencil") { renaming = item.document }
                                        .labelStyle(.iconOnly).help(String(localized: "Umbenennen …"))
                                    Button {
                                        guard workspace.requirePro(.organization) else { return }
                                        organizing = workspace.editor?.document.id == item.id ? workspace.editor?.document : item.document
                                    } label: { Image(systemName: "tag") }
                                        .help(String(localized: "Tags und Sammlungen bearbeiten"))
                                        .accessibilityLabel(String(localized: "Tags und Sammlungen bearbeiten"))
                                        .accessibilityIdentifier("library.organize.\(item.id)")
                                    Button { Task { _ = await workspace.changeTrash(item.id, action: .trash) } } label: { Image(systemName: "trash") }
                                        .help(String(localized: "In den Papierkorb")).accessibilityLabel(String(localized: "In den Papierkorb"))
                                    }
                                }.buttonStyle(.borderless).padding(10)
                            }.disabled(workspace.isUpdatingMetadata)
                                .allowsHitTesting(!workspace.isLoading)
                                .contextMenu {
                                    if !showsTrash {
                                    Button(String(localized: "Bearbeitbares Projekt exportieren …")) { workspace.chooseTransfer(.exportProject(item.id)) }
                                    Button(String(localized: "Umbenennen …")) { renaming = item.document }
                                    Button(String(localized: "Tags und Sammlungen …")) { organizing = item.document }
                                    Button(item.document.isFavorite ? String(localized: "Aus Favoriten entfernen") : String(localized: "Zu Favoriten hinzufügen")) {
                                        Task { _ = await workspace.updateProjectMetadata(item.id, favorite: !item.document.isFavorite) }
                                    }
                                    Button(String(localized: "In den Papierkorb"), systemImage: "trash") { Task { _ = await workspace.changeTrash(item.id, action: .trash) } }
                                    }
                                }
                        }
                    }.padding()
                }
                .overlay {
                    if filtered.isEmpty && !isSearching {
                        ContentUnavailableView(String(localized: "Keine passenden Bilder"), systemImage: workspace.preferences.favoritesOnly ? "star" : "magnifyingglass",
                                               description: Text(String(localized: "Ändere die Suche, Tags, Sammlung oder den Favoritenfilter.")))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsSearchProgress && isSearching {
                        ProgressView(String(localized: "Bilder durchsuchen …"))
                            .controlSize(.small).padding(10)
                            .background(.regularMaterial, in: .rect(cornerRadius: 10))
                            .padding(12).allowsHitTesting(false)
                            .accessibilityIdentifier("library.search.progress")
                    }
                }
            }
        }
        .alert(String(localized: "Bild endgültig löschen?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { document in
            Button(String(localized: "Endgültig löschen"), role: .destructive) { Task { _ = await workspace.changeTrash(document.id, action: .delete) } }
            Button(String(localized: "Abbrechen"), role: .cancel) { }
        } message: { document in
            Text(String(localized: "„\(document.title)“ wird mit Original und allen Bearbeitungen dauerhaft gelöscht. Das lässt sich nicht rückgängig machen."))
        }
        .searchable(text: $query, prompt: String(localized: "Bilder durchsuchen"))
        .sheet(item: $renaming) { document in
            ProjectRenameSheet(title: document.title) { title in
                await workspace.updateProjectMetadata(document.id, title: title)
            }
        }
        .sheet(item: $organizing) { document in
            ProjectOrganizationSheet(document: document, existingCollections: collections) { tags, collections in
                await workspace.updateProjectMetadata(document.id, tags: tags, collections: collections)
            }
        }
        .task(id: searchInputs) {
            let input = searchInputs
            let documents = documents.map { document in
                var value = document
                if !input.hasPro { value.tags = []; value.collections = [] }
                return value
            }
            do {
                let result = try await workspace.search.matches(query: input.query, documents: documents, includeOCR: input.includesOCR)
                try Task.checkCancellation()
                matches = result; resultKey = input; searchError = nil
            } catch is CancellationError { }
            catch {
                let fallback = await Task.detached { Set(documents.filter { LibrarySearch.matches($0, query: input.query) }.map(\.id)) }.value
                guard !Task.isCancelled else { return }
                matches = fallback; resultKey = input
                searchError = String(localized: "Die Inhaltssuche ist gerade nicht verfügbar. Titel, Tags und Sammlungen werden weiter durchsucht.")
            }
        }
        .task(id: workspace.openingProjectID) {
            showsOpeningProgress = false
            guard workspace.openingProjectID != nil else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, workspace.openingProjectID != nil else { return }
            showsOpeningProgress = true
        }
        .task(id: isSearching) {
            showsSearchProgress = false
            guard isSearching else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled, isSearching else { return }
            showsSearchProgress = true
        }
        .onChange(of: showsTrash) { tagFilter = ""; collectionFilter = ""; selectedProjects = []; selecting = false }
        .onChange(of: selecting) { if !selecting { selectedProjects = [] } }
    }

    /// Two aligned rows of equally sized buttons and menus: what you see and what you can do with it,
    /// then how it is filtered and sorted. Selection actions replace the count, so nothing is reserved or shifted.
    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { countOrSelection; Spacer(minLength: 16); modeControls }
                VStack(alignment: .leading, spacing: 8) { countOrSelection; modeControls }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { filterControls; Spacer(minLength: 16); indexControls; sortMenu }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { filterControls }
                    HStack(spacing: 8) { indexControls; sortMenu }
                }
            }
        }.padding(16)
    }

    @ViewBuilder private var countOrSelection: some View {
        if selecting && !showsTrash {
            HStack(spacing: 8) {
                Text(String(localized: "\(selectedProjects.count) ausgewählt")).font(.headline).monospacedDigit()
                Button(String(localized: "Anleitung erstellen"), systemImage: "list.number") {
                    workspace.createGuide(from: filtered.filter { selectedProjects.contains($0.id) }.map(\.id))
                    selectedProjects = []; selecting = false
                }.disabled(selectedProjects.isEmpty || selectedProjects.count > 100 || workspace.guides.isBusy || workspace.isLoading)
            }.fixedSize()
        } else {
            imageCount
        }
    }

    private var modeControls: some View {
        HStack(spacing: 8) {
            Toggle(String(localized: "Auswählen"), systemImage: "checkmark.circle", isOn: $selecting)
                .toggleStyle(.button)
                .disabled(showsTrash || workspace.isLoading)
            Toggle(String(localized: "Papierkorb"), systemImage: "trash", isOn: $showsTrash)
                .toggleStyle(.button).accessibilityIdentifier("library.trash")
            fileMenu
        }.fixedSize()
    }

    private var filterControls: some View {
        HStack(spacing: 8) {
            organizationFilters
            Toggle(String(localized: "Favoriten"), systemImage: "star.fill", isOn: Binding(get: { workspace.preferences.favoritesOnly }, set: { workspace.preferences.favoritesOnly = $0 }))
                .toggleStyle(.button).disabled(showsTrash).accessibilityIdentifier("library.favoritesOnly")
        }.fixedSize()
    }

    private var indexControls: some View {
        LibraryIndexControls(workspace: workspace).disabled(showsTrash)
    }

    @ViewBuilder private var organizationFilters: some View {
        if workspace.purchases.hasPro {
            tagMenu; collectionMenu
        } else {
            Button(String(localized: "Tags und Sammlungen · Pro"), systemImage: "lock") { workspace.showPro(.organization) }
        }
    }
    private var tagMenu: some View {
        let title = tags.first { LibrarySearch.fold($0) == tagFilter } ?? (tagFilter.isEmpty ? String(localized: "Alle Tags") : tagFilter)
        return Menu {
            Picker(String(localized: "Tag"), selection: $tagFilter) {
                Text(String(localized: "Alle Tags")).tag("")
                ForEach(tags, id: \.self) { Text($0).tag(LibrarySearch.fold($0)) }
                if !tagFilter.isEmpty && !tags.contains(where: { LibrarySearch.fold($0) == tagFilter }) { Text(tagFilter).tag(tagFilter) }
            }.pickerStyle(.inline).labelsHidden()
        } label: { Label(Self.menuTitle(title), systemImage: "tag") }
            .help(title).accessibilityLabel(String(localized: "Tag")).accessibilityValue(title)
            .accessibilityIdentifier("library.filter.tag")
    }
    private var collectionMenu: some View {
        let title = collections.first { LibrarySearch.fold($0) == collectionFilter } ?? (collectionFilter.isEmpty ? String(localized: "Alle Sammlungen") : collectionFilter)
        return Menu {
            Picker(String(localized: "Sammlung"), selection: $collectionFilter) {
                Text(String(localized: "Alle Sammlungen")).tag("")
                ForEach(collections, id: \.self) { Text($0).tag(LibrarySearch.fold($0)) }
                if !collectionFilter.isEmpty && !collections.contains(where: { LibrarySearch.fold($0) == collectionFilter }) { Text(collectionFilter).tag(collectionFilter) }
            }.pickerStyle(.inline).labelsHidden()
        } label: { Label(Self.menuTitle(title), systemImage: "rectangle.stack") }
            .help(title).accessibilityLabel(String(localized: "Sammlung")).accessibilityValue(title)
            .accessibilityIdentifier("library.filter.collection")
    }
    /// Long user-defined names stay readable in the help tag instead of stretching the filter row.
    private static func menuTitle(_ title: String) -> String {
        title.count > 24 ? String(title.prefix(23)) + "…" : title
    }

    private var imageCount: some View {
        Text(showsTrash ? String(localized: "Papierkorb (\(displayedItems.count))") : String(localized: "\(displayedItems.count) Bilder"))
            .font(.headline).fixedSize()
    }

    private var fileMenu: some View {
        Menu(String(localized: "Dateien"), systemImage: "folder") {
            Button(String(localized: "Alles sichern …")) { workspace.chooseTransfer(.completeBackup) }
            Button(String(localized: "Alles wiederherstellen …")) { workspace.chooseTransfer(.restoreComplete) }
            Divider()
            Button(String(localized: "Projekt importieren …")) { workspace.chooseTransfer(.importProject) }
            Button(String(localized: "Bildbibliothek sichern …")) { workspace.chooseTransfer(.backup) }
            Button(String(localized: "Sicherung wiederherstellen …")) { workspace.chooseTransfer(.restoreBackup) }
        }.disabled(workspace.isLoading || workspace.isUpdatingMetadata)
    }

    private var sortMenu: some View {
        Menu {
            Picker(String(localized: "Sortieren"), selection: Binding(get: { workspace.preferences.librarySort }, set: { workspace.preferences.librarySort = $0 })) {
                ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.inline).labelsHidden()
        } label: { Label(workspace.preferences.librarySort.title, systemImage: "arrow.up.arrow.down") }
            .fixedSize()
            .accessibilityLabel(String(localized: "Sortieren")).accessibilityValue(workspace.preferences.librarySort.title)
            .accessibilityIdentifier("library.sort")
    }
}

struct LibraryCard: View {
    let item: ProjectLibraryItem
    @State private var thumbnail: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().padding(8) }
                else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
            }.frame(height: 160).clipShape(.rect(cornerRadius: 12))
            Text(item.document.title).font(.headline).lineLimit(1)
            if !item.document.tags.isEmpty {
                Label(item.document.tags.joined(separator: " · "), systemImage: "tag").font(.caption).lineLimit(1)
            }
            if !item.document.collections.isEmpty {
                Label(item.document.collections.joined(separator: " · "), systemImage: "folder").font(.caption).lineLimit(1)
            }
            Text(item.document.modifiedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(String(localized: "\(item.document.objects.count) Markierungen"))
                Spacer()
                if item.recovered { Image(systemName: "clock.arrow.circlepath").help(String(localized: "Vorheriger Speicherstand wiederhergestellt")) }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.quaternary) }
        .contentShape(.rect)
        .task(id: item.document.revision) {
            thumbnail = item.thumbnail.flatMap(NSImage.init(data:))
        }
        .accessibilityElement(children: .combine)
    }
}


struct ProjectRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var saving = false
    @State private var failed = false
    let save: (String) async -> Bool
    let heading: String
    let prompt: String
    init(title: String, heading: String = String(localized: "Bild umbenennen"), prompt: String = String(localized: "Bildname"), save: @escaping (String) async -> Bool) {
        _title = State(initialValue: title); self.heading = heading; self.prompt = prompt; self.save = save
    }
    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(heading).font(.headline)
            TextField(prompt, text: $title).textFieldStyle(.roundedBorder).accessibilityIdentifier("project.rename.title")
            if trimmed.isEmpty || trimmed.count > 1024 { Text(String(localized: "Bitte 1 bis 1.024 Zeichen eingeben.")).font(.caption).foregroundStyle(.secondary) }
            if failed { Text(String(localized: "Der Name konnte nicht gesichert werden. Bitte erneut versuchen.")).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(String(localized: "Umbenennen")) {
                    saving = true
                    Task { if await save(trimmed) { dismiss() } else { failed = true }; saving = false }
                }.keyboardShortcut(.defaultAction).disabled(saving || trimmed.isEmpty || trimmed.count > 1024)
            }
        }.padding(24).frame(width: 400).interactiveDismissDisabled(saving)
    }
}
