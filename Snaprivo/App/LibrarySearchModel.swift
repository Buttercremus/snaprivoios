import AppKit
import ImageIO
import Observation
import SnagForgeDomain

@MainActor @Observable
final class LibrarySearchModel {
    typealias Recognize = @Sendable (LoadedProject) async throws -> String
    private(set) var isIndexing = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var failures = 0
    private(set) var changeVersion = 0
    private(set) var error: String?
    private(set) var notice: String?
    @ObservationIgnored private let index: LibraryContentIndex
    @ObservationIgnored private let recognize: Recognize
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var signature: String?

    init(cacheURL: URL, recognize: @escaping Recognize = LibrarySearchModel.recognizeProject) {
        index = LibraryContentIndex(url: cacheURL); self.recognize = recognize
    }
    func synchronize(documents: [ProjectDocument], store: ProjectStore, enabled: Bool, rebuild: Bool = false, retry: Bool = false) {
        let signature = store.root.path + ":\(enabled):" + documents.map { "\($0.id):\($0.revision)" }.sorted().joined(separator: ",")
        guard rebuild || retry || signature != self.signature else { return }
        self.signature = signature
        let previous = task
        previous?.cancel(); request = UUID()
        let request = request
        error = nil; notice = nil; isIndexing = enabled; total = documents.count; completed = 0; failures = 0
        changeVersion += 1
        task = Task {
            defer { if self.request == request { isIndexing = false; task = nil; changeVersion += 1 } }
            do {
                let epoch = try await index.configure(library: store.root.standardizedFileURL.path, enabled: enabled, documents: documents, rebuild: rebuild)
                try Task.checkCancellation()
                guard self.request == request else { return }
                changeVersion += 1
                // Revoke/erase immediately, but serialize actual OCR across refreshes.
                // A cancelled Vision call may still be returning on its actor.
                await previous?.value
                try Task.checkCancellation()
                guard self.request == request, enabled else { return }
                let missing = try await index.missing(documents, epoch: epoch)
                try Task.checkCancellation()
                guard self.request == request else { return }
                completed = documents.count - missing.count
                for document in missing {
                    try Task.checkCancellation()
                    do {
                        let loaded = try await store.load(document.id)
                        let key = try await Task.detached { try LibrarySearch.imageKey(document) }.value
                        guard try await Task.detached(operation: { try LibrarySearch.imageKey(loaded.document) }).value == key else { throw LibraryIndexError.staleSession }
                        let text = try await recognize(loaded)
                        try Task.checkCancellation()
                        let latest = try await store.readDocument(document.id)
                        guard try await Task.detached(operation: { try LibrarySearch.imageKey(latest) }).value == key else { throw LibraryIndexError.staleSession }
                        try await index.record(text, for: loaded.document, epoch: epoch)
                    } catch is CancellationError { throw CancellationError() }
                    catch TextRecognitionError.busy {
                        try Task.checkCancellation()
                        guard self.request == request else { return }
                        notice = String(localized: "Die Texterkennung ist gerade belegt. Setze die Indexierung später fort."); break
                    } catch {
                        try Task.checkCancellation()
                        guard self.request == request else { return }
                        failures += 1
                    }
                    guard self.request == request else { return }
                    completed += 1; changeVersion += 1
                }
                let recovered = await index.recoveredCache
                try Task.checkCancellation()
                guard self.request == request else { return }
                if recovered {
                    notice = String(localized: "Der beschädigte Suchcache wurde neu angelegt. Projekte bleiben erhalten.")
                }
            } catch {
                guard self.request == request else { return }
                if Task.isCancelled { notice = String(localized: "Indexierung abgebrochen. Bereits erkannte Projekte bleiben durchsuchbar.") }
                else if !enabled { self.error = String(localized: "Der OCR-Suchcache konnte nicht entfernt werden. OCR wird nicht verwendet. Versuche das Entfernen erneut.") }
                else { self.error = String(localized: "Der Suchindex konnte nicht aktualisiert werden. Titel, Tags und Sammlungen bleiben durchsuchbar.") }
            }
        }
    }
    @discardableResult func cancel() -> Task<Void, Never>? { task?.cancel(); return task }
    func finish() async { await task?.value }
    func matches(query: String, documents: [ProjectDocument], includeOCR: Bool) async throws -> Set<UUID> {
        try await index.search(query, documents: documents, includeOCR: includeOCR)
    }
    nonisolated static func recognizeProject(_ loaded: LoadedProject) async throws -> String {
        let work = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(loaded.original as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width == loaded.document.pixelSize.width, image.height == loaded.document.pixelSize.height else { throw ProjectError.invalidDocument }
            let document = loaded.document
            let snapshot = TextRecognitionSnapshot(image: image, objects: document.objects, crop: document.crop, resizedSize: document.resizedSize)
            return try await TextRecognitionService.shared.recognize(snapshot, selection: CGRect(x: 0, y: 0, width: 1, height: 1), language: "").text
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
