import AppKit
import Observation
import UniformTypeIdentifiers
import SnagForgeDomain

@MainActor @Observable final class GuideModel {
    let store: GuideStore
    private(set) var documents: [GuideSummary] = []
    private(set) var document: GuideDocument?
    var selectedStep: UUID?
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
        do { let result = try await store.list(); documents = result.documents; issues = result.issues }
        catch { issues = [error.localizedDescription] }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !isSuspended, panel == nil else { return }
        isBusy = true; error = nil; notice = nil
        operation = Task {
            defer { isBusy = false; operation = nil }
            do { try await action() }
            catch { self.error = Self.message(error) }
        }
    }
    func create() {
        run { [self] in
            guard await flush() else { return }
            let value = GuideDocument(title: String(localized: "Neue Anleitung"))
            try await store.create(value); document = value; selectedStep = nil
            await refresh()
        }
    }
    func open(_ id: UUID) {
        guard id != document?.id else { return }
        run { [self] in
            guard await flush() else { return }
            let loaded = try await store.load(id), value = loaded.document
            try await Task.detached { try GuideExporter.validateImages(value) }.value
            document = value; selectedStep = value.steps.first?.id; preview = nil
            if loaded.recovered { notice = String(localized: "Vorheriger Speicherstand wiederhergestellt") }
        }
    }
    func saveAsCopy() {
        run { [self] in
            timer?.cancel(); timer = nil
            if let saving { _ = await saving.value }
            guard var value = document else { return }
            value.id = UUID(); value.revision = 0; value.modifiedAt = .now
            try await store.create(value)
            document = value; isDirty = false; preview = nil; error = nil
            await refresh()
        }
    }
    func edit(_ mutation: (inout GuideDocument) -> Void) {
        guard !isBusy, !isSuspended, var value = document else { return }
        mutation(&value)
        guard value != document else { return }
        document = value; change += 1; isDirty = true; preview = nil
        timer?.cancel()
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            _ = await self?.flush()
        }
    }
    func editStep(_ id: UUID, _ mutation: (inout GuideStep) -> Void) {
        edit { value in
            if let i = value.steps.firstIndex(where: { $0.id == id }) { mutation(&value.steps[i]) }
        }
    }
    @discardableResult func flush() async -> Bool {
        timer?.cancel(); timer = nil
        if let saving, !(await saving.value) { return false }
        guard isDirty, let snapshot = document else { return true }
        guard !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = String(localized: "Bitte gib einen Anleitungstitel ein."); return false
        }
        let stamp = change
        isSaving = true
        let task = Task { [self] in
            defer { isSaving = false; saving = nil }
            do {
                let saved = try await store.save(snapshot, expectedRevision: snapshot.revision)
                document?.revision = saved.revision; document?.modifiedAt = saved.modifiedAt
                isDirty = change != stamp; error = nil
                documents.removeAll { $0.id == saved.id }; documents.append(GuideSummary(saved))
                documents.sort { $0.modifiedAt > $1.modifiedAt }
                return true
            } catch { self.error = Self.message(error); return false }
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
    func addProjects(_ ids: [UUID], from projects: ProjectStore, replacing: UUID? = nil,
                     prepare: @escaping @MainActor () async -> Bool) {
        guard document != nil, !ids.isEmpty else { return }
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
            guard var value = document else { return }
            if let replacing, let index = value.steps.firstIndex(where: { $0.id == replacing }), let step = steps.first {
                value.steps[index].png = step.png
                value.steps[index].sourceProjectID = step.sourceProjectID; value.steps[index].sourceLibrary = step.sourceLibrary
            } else { value.steps += steps; selectedStep = steps.first?.id }
            _ = try value.validated()
            document = value; change += 1; isDirty = true; preview = nil
            _ = await flush()
        }
    }
    func showPreview() {
        guard let value = document, !value.steps.isEmpty else { return }
        run { [self] in
            guard await flush() else { return }
            preview = try await Task.detached(priority: .userInitiated) { try GuideExporter.pdf(value) }.value
        }
    }
    enum Output { case pdf, markdown, workingCopy }
    static var guideType: UTType { UTType(exportedAs: "com.snaprivo.guide", conformingTo: .data) }
    func chooseExport(_ output: Output) {
        guard !isBusy, !isSuspended, panel == nil, let document else { return }
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
        run { [self] in
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
        for i in value.steps.indices { value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil }
        try await store.create(value)
        document = value; selectedStep = value.steps.first?.id; preview = nil
        await refresh()
    }
    func createFromProjects(_ ids: [UUID], from projects: ProjectStore, prepare: @escaping @MainActor () async -> Bool) {
        run { [self] in
            guard await prepare(), await flush() else { return }
            guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count else { throw ProjectError.documentTooLarge }
            let key = Self.libraryKey(projects), style = document?.style ?? .standard
            let steps = try await Task.detached(priority: .userInitiated) {
                var result: [GuideStep] = []
                for id in ids { result.append(try GuideExporter.snapshot(await projects.load(id), library: key)) }
                return result
            }.value
            let value = GuideDocument(title: String(localized: "Neue Anleitung"), style: style, steps: steps)
            try await store.create(value)
            document = value; selectedStep = steps.first?.id; preview = nil
            await refresh()
        }
    }
}
