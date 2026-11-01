import AppKit
import Observation
import UniformTypeIdentifiers
import SnagForgeDomain

@MainActor @Observable final class GuideModel {
    // Low-level models can also be used by isolated renderer/persistence checks.
    // Workspace installs the live entitlement policy before exposing them to UI.
    @ObservationIgnored var requestFeature: @MainActor (ProFeature) -> Bool = { _ in true }
    let store: GuideStore
    private(set) var documents: [GuideSummary] = []
    private(set) var document: GuideDocument? {
        didSet {
            if oldValue?.id != document?.id || oldValue?.steps.map(\.id) != document?.steps.map(\.id) {
                onStepMembershipChange?(document?.id, Set(document?.steps.map(\.id) ?? []))
            }
        }
    }
    /// Transient step work must end even when the guide view is not on screen.
    @ObservationIgnored var onStepMembershipChange: (@MainActor (UUID?, Set<UUID>) -> Void)?
    private(set) var imagePreviews = GuideImagePreviews()
    private(set) var trash: [GuideSummary] = []
    private(set) var selectedDocumentIDs: Set<UUID> = []
    private(set) var openingDocumentID: UUID?
    var isOpeningDocument: Bool { openingDocumentID != nil }
    /// Opening retains the current chrome; action guards still use `isBusy`.
    var isBusyForControls: Bool { isBusy && !isOpeningDocument }
    var showsTrash = false
    struct ImageRequest: Identifiable {
        let id = UUID()
        let documentID: UUID
        let replacing: UUID?
        let position: GuideInsertion
    }
    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                searchResults = []
                if selectedDocumentIDs.count > 1 { selectedDocumentIDs = [] }
            }
            scheduleSearch()
        }
    }
    private(set) var searchResults: [GuideSearchMatch] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchRequest = UUID()
    private func scheduleSearch() {
        searchTask?.cancel(); searchRequest = UUID()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchError = nil
        guard !query.isEmpty else { searchResults = []; isSearching = false; return }
        isSearching = true
        let request = searchRequest
        searchTask = Task { [weak self, store] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                var matches = try await store.search(query)
                guard let self, !Task.isCancelled, request == searchRequest else { return }
                // Unsaved text is searchable immediately; the current manifest may be older.
                if let current = document {
                    matches.removeAll { $0.documentID == current.id }
                    matches.insert(contentsOf: GuideSearchMatch.matches(in: current, query: query), at: 0)
                }
                searchResults = matches; isSearching = false
            } catch {
                guard let self, !Task.isCancelled, request == searchRequest else { return }
                searchError = error.localizedDescription; isSearching = false
            }
        }
    }
    var imageRequest: ImageRequest?
    enum FailureContext: Equatable { case save, output(Output), preview, operation }
    private(set) var failureContext: FailureContext = .operation
    private struct HistoryEntry { let document: GuideDocument; let selection: UUID? }
    private var past: [HistoryEntry] = []
    private var future: [HistoryEntry] = []
    @ObservationIgnored private var textGroup: String?
    @ObservationIgnored private var lastTextEdit = Date.distantPast
    var canUndo: Bool { !past.isEmpty && !isBusy && !isSuspended && selectedDocumentIDs.count <= 1 }
    var canRedo: Bool { !future.isEmpty && !isBusy && !isSuspended && selectedDocumentIDs.count <= 1 }
    var canUndoForControls: Bool { !past.isEmpty && !isBusyForControls && !isSuspended && selectedDocumentIDs.count <= 1 }
    var canRedoForControls: Bool { !future.isEmpty && !isBusyForControls && !isSuspended && selectedDocumentIDs.count <= 1 }
    var canTrashSelectionForControls: Bool {
        !selectedDocumentIDs.isEmpty && !showsTrash && !isBusyForControls && !isSuspended
            && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canTrashSelection: Bool { canTrashSelectionForControls && !isBusy }
    var selectedStep: UUID?
    var stepToReveal: UUID?
    /// Set by `create()`; the view focuses the title field once and resets it.
    var focusesTitle = false
    /// Incremented by the window toolbar; the guide editor opens the writing assistant.
    var assistantOpenRequest = 0
    /// The step a guide capture just appended, so the editor can suggest its text.
    var lastCapturedStep: UUID?
    private(set) var isBusy = false
    // Workspace holds this for the entire quit sequence, including other editors' saves.
    var isSuspended = false
    private(set) var isDirty = false
    private(set) var isSaving = false
    var error: String?
    var notice: String?
    var preview: Data?
    var issues: [String] = []
    @ObservationIgnored private var change = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var panel: NSSavePanel?
    init(root: URL) { store = GuideStore(root: root) }
    private static func message(_ error: Error) -> String {
        switch error as? ProjectError {
        case .invalidDocument: String(localized: "Die Anleitung enthält ungültige Texte oder Bilddaten. Prüfe Titel und Schritte.")
        case .staleRevision: String(localized: "Eine andere App-Instanz hat diese Anleitung geändert. Sichere deine Änderungen als neue Anleitung.")
        case .unsupportedVersion: String(localized: "Diese Anleitung benötigt eine andere Snaprivo-Version. Sie wird nicht überschrieben.")
        case .fileTooLarge, .documentTooLarge: String(localized: "Die Anleitung überschreitet die unterstützten Grenzen: 100 Schritte und 256 MB.")
        default: error.localizedDescription
        }
    }
    func refresh() async {
        do {
            let result = try await store.list(), removed = try await store.listTrash()
            documents = result.documents; trash = removed.documents; issues = result.issues + removed.issues
            selectedDocumentIDs.formIntersection(documents.map(\.id))
            scheduleSearch()
        }
        catch { issues = [error.localizedDescription] }
    }
    private func run(context: FailureContext = .operation, opening id: UUID? = nil, _ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !isSuspended, panel == nil else { return }
        openingDocumentID = id
        isBusy = true; error = nil; failureContext = context; notice = nil
        operation = Task {
            defer { isBusy = false; openingDocumentID = nil; operation = nil }
            do { try await action() }
            catch { self.failureContext = context; self.error = Self.message(error) }
        }
    }
    func create() {
        guard requestFeature(.guides), !isBusy, !isSuspended else { return }
        // Repeated clicks reuse the untouched new guide instead of listing empty copies.
        if let document, document.steps.isEmpty, document.introduction.isEmpty, document.title == String(localized: "Neue Anleitung") {
            selectedDocumentIDs = [document.id]; showsTrash = false; focusesTitle = true; return
        }
        run { [self] in
            guard await flush() else { return }
            let value = GuideDocument(title: String(localized: "Neue Anleitung"))
            try await store.create(value); install(value); focusesTitle = true
            await refresh()
        }
    }
    func open(_ id: UUID, revealing step: UUID? = nil, fromSearch: Bool = false) {
        guard !isBusy, !isSuspended, panel == nil else { return }
        let previousSelection = selectedDocumentIDs
        selectedDocumentIDs = [id]
        guard id != document?.id else {
            showsTrash = false
            if fromSearch {
                selectedStep = step.flatMap { target in document?.steps.contains(where: { $0.id == target }) == true ? target : nil }
                stepToReveal = selectedStep ?? id
            }
            return
        }
        run(opening: id) { [self] in
            defer {
                if document?.id != id { selectedDocumentIDs = previousSelection }
            }
            guard await flush() else { return }
            let loaded = try await store.load(id), value = loaded.document
            let images = try await Task.detached(priority: .userInitiated) {
                try GuideExporter.preparePreviews(value, revealing: fromSearch ? step : nil)
            }.value
            install(value, images: images)
            if fromSearch {
                selectedStep = step.flatMap { id in value.steps.contains { $0.id == id } ? id : nil }
                stepToReveal = selectedStep ?? value.id
            }
            if loaded.recovered { notice = String(localized: "Vorheriger Speicherstand wiederhergestellt") }
        }
    }
    func selectDocuments(_ ids: Set<UUID>) {
        guard !isBusy, !isSuspended, panel == nil else { return }
        let selection = ids.intersection(documents.map(\.id))
        if selection.count == 1, let id = selection.first { open(id) }
        else {
            selectedDocumentIDs = selection
            if !selection.isEmpty { showsTrash = false }
        }
    }
    func saveAsCopy() {
        run { [self] in
            timer?.cancel(); timer = nil
            if let saving { _ = await saving.value }
            guard var value = document else { return }
            value.id = UUID(); value.revision = 0; value.modifiedAt = .now
            try await store.create(value)
            install(value); error = nil
            await refresh()
        }
    }
    private func install(_ value: GuideDocument, images: GuideImagePreviews = GuideImagePreviews()) {
        imagePreviews = images
        document = value; selectedStep = value.steps.first?.id; preview = nil; isDirty = false
        selectedDocumentIDs = [value.id]
        past = []; future = []; textGroup = nil; stepToReveal = nil; showsTrash = false
    }
    private func remember() {
        guard let document else { return }
        past.append(HistoryEntry(document: document, selection: selectedStep)); future.removeAll(); textGroup = nil
        // Data shares unchanged PNG buffers. The conservative byte budget also bounds replaced images.
        while past.count > 1 && (past.count > 40 || past.reduce(0, { $0 + $1.document.steps.reduce(0, { $0 + $1.png.count }) }) > 128_000_000) { past.removeFirst() }
    }
    private func changed() {
        change += 1; isDirty = true; preview = nil
        scheduleSearch()
        timer?.cancel()
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            _ = await self?.flush()
        }
    }
    func chooseImages(replacing: UUID? = nil, at position: GuideInsertion = .end) {
        guard requestFeature(.guides), let document, !isBusy, !isSuspended else { return }
        if let replacing { guard document.steps.contains(where: { $0.id == replacing }) else { return } }
        else {
            guard document.steps.count < 100 else { return }
            switch position {
            case .end: break
            case .before(let id), .after(let id): guard document.steps.contains(where: { $0.id == id }) else { return }
            }
        }
        imageRequest = ImageRequest(documentID: document.id, replacing: replacing, position: position)
    }
    func duplicateStep(_ id: UUID) {
        guard requestFeature(.guides), !isBusy, !isSuspended, var value = document else { return }
        do {
            let copied = try value.duplicateStep(id)
            remember(); document = value; selectedStep = copied; stepToReveal = copied; changed()
        } catch { failureContext = .operation; self.error = Self.message(error) }
    }
    func edit(textGroup group: String? = nil, _ mutation: (inout GuideDocument) -> Void) {
        guard requestFeature(.guides), !isBusy, !isSuspended, var value = document else { return }
        mutation(&value)
        guard value != document else { return }
        if group == nil || group != textGroup || Date().timeIntervalSince(lastTextEdit) > 1.2 { remember() }
        textGroup = group; lastTextEdit = .now
        document = value; changed()
    }
    func editStep(_ id: UUID, textGroup: String? = nil, _ mutation: (inout GuideStep) -> Void) {
        edit(textGroup: textGroup) { value in
            if let i = value.steps.firstIndex(where: { $0.id == id }) { mutation(&value.steps[i]) }
        }
    }
    /// Review acceptance uses the ordinary history/autosave path as one edit.
    @discardableResult func applyTextDraft(_ draft: GuideTextDraft, basedOn source: GuideDocument) throws -> Bool {
        guard !isBusy, !isSuspended, selectedDocumentIDs.count <= 1, !showsTrash,
              requestFeature(.guides), let current = document else { return false }
        let value = try draft.applying(to: current, basedOn: source)
        edit { $0 = value }
        return true
    }
    private func restoreHistory(_ entry: HistoryEntry) {
        guard let current = document else { return }
        var value = entry.document
        value.revision = current.revision; value.modifiedAt = current.modifiedAt
        document = value; selectedStep = entry.selection.flatMap { id in value.steps.contains { $0.id == id } ? id : nil } ?? value.steps.first?.id
        textGroup = nil; changed()
    }
    func undo() {
        guard canUndo, requestFeature(.guides), let current = document, let entry = past.popLast() else { return }
        future.append(HistoryEntry(document: current, selection: selectedStep)); restoreHistory(entry)
    }
    func redo() {
        guard canRedo, requestFeature(.guides), let current = document, let entry = future.popLast() else { return }
        past.append(HistoryEntry(document: current, selection: selectedStep)); restoreHistory(entry)
    }
    /// A local step drag carries only two IDs, never image or text content.
    @discardableResult func moveStep(payload: String, documentID: UUID, before target: UUID?) -> UUID? {
        guard !isBusy, !isSuspended, let current = document, current.id == documentID, payload.count == 73 else { return nil }
        let parts = payload.split(separator: ":")
        guard parts.count == 2, UUID(uuidString: String(parts[0])) == documentID,
              let id = UUID(uuidString: String(parts[1])), current.steps.contains(where: { $0.id == id }),
              target == nil || current.steps.contains(where: { $0.id == target }), requestFeature(.guides) else { return nil }
        edit { $0.moveStep(id, before: target) }; selectedStep = id; return id
    }
    func removeStep(_ id: UUID) {
        edit { $0.steps.removeAll { $0.id == id } }
        if selectedStep == id { selectedStep = document?.steps.first?.id }
    }
    func duplicate(_ id: UUID? = nil) {
        guard requestFeature(.guides), id != nil || document != nil else { return }
        run { [self] in
            guard await flush() else { return }
            var value: GuideDocument
            if let id { value = try await store.load(id).document }
            else if let current = document { value = current }
            else { return }
            value.id = UUID(); value.revision = 0; value.modifiedAt = .now
            value.title = String(value.title.prefix(240)) + String(localized: " – Kopie")
            try await store.create(value); install(value); await refresh()
        }
    }
    func moveToTrash(_ id: UUID) {
        moveToTrash([id])
    }
    func trashSelection() {
        guard canTrashSelection else { return }
        moveToTrash(selectedDocumentIDs)
    }
    func moveToTrash(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        run { [self] in
            guard await flush() else { return }
            do {
                let expected = document.flatMap { ids.contains($0.id) ? [$0.id: $0.revision] : nil } ?? [:]
                try await store.moveToTrash(ids, expectedRevisions: expected)
                await finishTrashing(ids, completed: true)
            } catch { await finishTrashing(ids, completed: false); throw error }
        }
    }
    private func finishTrashing(_ ids: Set<UUID>, completed: Bool) async {
        await refresh()
        if completed { selectedDocumentIDs.subtract(ids) }
        if let id = document?.id, ids.contains(id), completed || trash.contains(where: { $0.id == id }) {
            document = nil; imagePreviews = GuideImagePreviews(); selectedStep = nil; past = []; future = []; preview = nil
        }
    }
    func restore(_ id: UUID) {
        run { [self] in try await store.restore(id); await refresh() }
    }
    func permanentlyDelete(_ id: UUID) {
        run { [self] in try await store.permanentlyDelete(id); await refresh() }
    }
    @discardableResult func flush() async -> Bool {
        timer?.cancel(); timer = nil
        if let saving, !(await saving.value) { return false }
        guard isDirty, let snapshot = document else { return true }
        guard !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failureContext = .save; error = String(localized: "Bitte gib einen Anleitungstitel ein."); return false
        }
        let stamp = change
        isSaving = true
        let task = Task { [self] in
            defer { isSaving = false; saving = nil }
            do {
                let saved = try await store.save(snapshot, expectedRevision: snapshot.revision)
                document?.revision = saved.revision; document?.modifiedAt = saved.modifiedAt
                isDirty = change != stamp; if failureContext == .save { error = nil }
                documents.removeAll { $0.id == saved.id }; documents.append(GuideSummary(saved))
                documents.sort { $0.modifiedAt > $1.modifiedAt }
                scheduleSearch()
                return true
            } catch { self.failureContext = .save; self.error = Self.message(error); return false }
        }
        saving = task
        guard await task.value else { return false }
        return isDirty ? await flush() : true
    }
    func finishPendingWork() async -> Bool {
        if let panel { self.panel = nil; panel.cancel(nil) }
        if let operation { await operation.value }
        return await flush()
    }
    static func libraryKey(_ store: ProjectStore) -> String {
        ProjectArchive.hash(Data(store.root.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
    }
    func addProjects(_ ids: [UUID], from projects: ProjectStore, replacing: UUID? = nil, at position: GuideInsertion = .end,
                     captured: Bool = false, prepare: @escaping @MainActor () async -> Bool) {
        guard requestFeature(.guides) else { return }
        guard let documentID = document?.id, !ids.isEmpty else { return }
        run { [self] in
            guard await prepare(), await flush() else { return }
            guard replacing != nil || (document?.steps.count ?? 0) + ids.count <= 100 else { throw ProjectError.documentTooLarge }
            let key = Self.libraryKey(projects)
            let steps = try await Task.detached(priority: .userInitiated) {
                var result: [GuideStep] = []
                for id in ids {
                    try Task.checkCancellation()
                    result.append(try GuideExporter.snapshot(await projects.load(id), library: key))
                }
                return result
            }.value
            guard requestFeature(.guides) else { return }
            guard var value = document, value.id == documentID else { throw ProjectError.staleRevision }
            if let replacing {
                guard let index = value.steps.firstIndex(where: { $0.id == replacing }), let step = steps.first else { throw ProjectError.invalidDocument }
                value.steps[index].png = step.png
                value.steps[index].sourceProjectID = step.sourceProjectID; value.steps[index].sourceLibrary = step.sourceLibrary
                value.steps[index].sourceRevision = step.sourceRevision
            } else { try value.insertSteps(steps, at: position) }
            _ = try value.validated()
            remember(); document = value
            selectedStep = replacing ?? steps.first?.id; stepToReveal = selectedStep
            if captured, replacing == nil { lastCapturedStep = steps.last?.id }
            changed()
            _ = await flush()
        }
    }
    func showPreview() {
        guard document?.steps.isEmpty == false, selectedDocumentIDs.count <= 1 else { return }
        run(context: .preview) { [self] in
            guard await flush(), let value = document else { return }
            preview = try await Task.detached(priority: .userInitiated) { try GuideExporter.pdf(value) }.value
        }
    }
    enum Output: Equatable { case pdf, markdown, workingCopy }
    static var guideType: UTType { UTType(exportedAs: "com.snaprivo.guide", conformingTo: .data) }
    func chooseExport(_ output: Output) {
        guard !isBusy, !isSuspended, panel == nil, selectedDocumentIDs.count <= 1, let document else { return }
        let dialog: NSSavePanel
        if output == .markdown {
            let open = NSOpenPanel(); open.canChooseFiles = false; open.canChooseDirectories = true
            open.canCreateDirectories = true; open.allowsMultipleSelection = false
            open.message = String(localized: "Im gewählten Ordner entsteht ein neuer Ordner mit Anleitung.md und den sichtbaren PNG-Bildern.")
            dialog = open
        } else {
            dialog = NSSavePanel()
            dialog.allowedContentTypes = output == .pdf ? [.pdf] : [Self.guideType]
            dialog.nameFieldStringValue = String(document.title.prefix(100)).replacingOccurrences(of: "/", with: "-") + (output == .pdf ? ".pdf" : ".snaprivoguide")
        }
        dialog.title = output == .pdf ? String(localized: "Anleitung als PDF exportieren") : output == .markdown ? String(localized: "Markdown-Zielordner wählen") : String(localized: "Bearbeitbare Anleitung exportieren")
        panel = dialog
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, self.panel === dialog else { return }
            self.panel = nil
            guard response == .OK, let url = dialog.url else { return }
            let target = output == .markdown ? url.appendingPathComponent("Snaprivo-\(UUID().uuidString.prefix(8))", isDirectory: true) : url
            self.export(output, to: target, access: url)
        }
        if let window = NSApp.keyWindow { dialog.beginSheetModal(for: window, completionHandler: completion) }
        else { dialog.begin(completionHandler: completion) }
    }
    func export(_ output: Output, to url: URL, access: URL? = nil) {
        guard selectedDocumentIDs.count <= 1 else { return }
        run(context: .output(output)) { [self] in
            guard await flush(), let value = document else { return }
            let scope = access ?? url, granted = scope.startAccessingSecurityScopedResource()
            defer { if granted { scope.stopAccessingSecurityScopedResource() } }
            try await Task.detached(priority: .userInitiated) {
                switch output {
                case .pdf: try GuideExporter.pdf(value).write(to: url, options: .atomic)
                case .markdown: try GuideExporter.markdown(value, to: url)
                case .workingCopy: try GuideExporter.cleanCopy(value).encoded(portable: true).write(to: url, options: .atomic)
                }
            }.value
            notice = String(localized: "Anleitung exportiert: \(url.lastPathComponent)")
        }
    }
    func chooseImport() {
        guard !isBusy, !isSuspended, panel == nil else { return }
        let dialog = NSOpenPanel(); dialog.allowedContentTypes = [Self.guideType]; dialog.allowsMultipleSelection = false
        dialog.title = String(localized: "Bearbeitbare Anleitung importieren"); panel = dialog
        dialog.begin { [weak self] response in
            guard let self, self.panel === dialog else { return }
            self.panel = nil
            if response == .OK, let url = dialog.url { self.importCopy(url) }
        }
    }
    func importCopy(_ url: URL) { run { [self] in try await readExternalCopy(url) } }
    func importExternalCopy(_ url: URL) async {
        if let operation { await operation.value }
        guard !isBusy, !isSuspended else { return }
        isBusy = true; defer { isBusy = false }
        do { try await readExternalCopy(url) } catch { self.error = Self.message(error) }
    }
    private func readExternalCopy(_ url: URL) async throws {
        guard await flush() else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        var value = try await Task.detached { try GuideExporter.cleanCopy(GuideDocument.read(url)) }.value
        value.id = UUID(); value.revision = 0; value.modifiedAt = .now
        for i in value.steps.indices { value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil; value.steps[i].sourceRevision = nil }
        try await store.create(value)
        install(value)
        await refresh()
    }
    func createFromProjects(_ ids: [UUID], from projects: ProjectStore, prepare: @escaping @MainActor () async -> Bool) {
        guard requestFeature(.guides) else { return }
        run { [self] in
            guard await prepare(), await flush() else { return }
            guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count else { throw ProjectError.documentTooLarge }
            let key = Self.libraryKey(projects), style = document?.style ?? .standard
            let steps = try await Task.detached(priority: .userInitiated) {
                var result: [GuideStep] = []
                for id in ids { result.append(try GuideExporter.snapshot(await projects.load(id), library: key)) }
                return result
            }.value
            guard requestFeature(.guides) else { return }
            let value = GuideDocument(title: String(localized: "Neue Anleitung"), style: style, steps: steps, includesCover: document?.includesCover ?? true)
            try await store.create(value)
            install(value)
            await refresh()
        }
    }
}
