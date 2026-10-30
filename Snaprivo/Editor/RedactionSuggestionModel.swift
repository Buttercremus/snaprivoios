import AppKit
import Observation
import SnagForgeDomain

@MainActor @Observable
final class RedactionSuggestionModel {
    let editor: EditorModel
    private(set) var snapshot: TextRecognitionSnapshot
    private(set) var baseRevision: Int
    private(set) var baseObjects: [EditorObject]
    private(set) var baseCrop: CGRect?
    private(set) var baseResizedSize: PixelSize?
    private(set) var baseCanvasRect: CGRect?
    private(set) var preview: CGImage?
    private(set) var previewSourceArea: CGRect = .zero
    private(set) var suggestions: [RedactionSuggestion] = []
    var selected = Set<UUID>()
    private(set) var isBusy = false
    private(set) var notice: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retryRequested = false
    typealias Prepare = @Sendable (TextRecognitionSnapshot) async throws -> TextRecognitionPreparation
    typealias Recognize = @Sendable (TextRecognitionSnapshot, CGRect, String) async throws -> TextRecognitionResult
    @ObservationIgnored private let prepareImage: Prepare
    @ObservationIgnored private let recognizeImage: Recognize

    init(editor: EditorModel,
         prepare: @escaping Prepare = { try await TextRecognitionService.shared.prepare($0) },
         recognize: @escaping Recognize = { try await TextRecognitionService.shared.recognize($0, selection: $1, language: $2, preferFast: true) }) {
        self.editor = editor
        self.baseRevision = editor.document.revision
        self.baseObjects = editor.history.objects
        self.baseCrop = editor.history.crop
        self.baseResizedSize = editor.history.resizedSize
        self.baseCanvasRect = editor.history.canvasRect
        self.snapshot = TextRecognitionSnapshot(image: editor.image, objects: editor.history.objects,
                                                crop: editor.history.crop, resizedSize: editor.history.resizedSize,
                                                canvasRect: editor.history.canvasRect)
        self.prepareImage = prepare; self.recognizeImage = recognize
    }
    var canApply: Bool {
        !selected.isEmpty && selected.isSubset(of: Set(suggestions.map(\.id))) && !isBusy &&
        !editor.isSwitchingImage && editor.cropDraft == nil && !editor.isCanvasGestureActive &&
        editor.preview == nil && editor.editingTextObject == nil && !editor.isExporting &&
        !editor.isShowingImageSize && !editor.isShowingTextRecognition
    }
    func start() {
        guard task == nil, !isBusy, preview == nil else { return }
        isBusy = true; notice = nil; generation += 1
        let token = generation, requestSnapshot = snapshot
        task = Task {
            defer { finishRequest() }
            do {
                let preparation = try await prepareImage(requestSnapshot)
                try Task.checkCancellation()
                let plan = try requestSnapshot.plan()
                let result = try await recognizeImage(requestSnapshot, CGRect(x: 0, y: 0, width: 1, height: 1), "")
                try Task.checkCancellation()
                let detected = await Task.detached(priority: .userInitiated) {
                    RedactionSuggestionDetector.detect(lines: result.lines, plan: plan)
                }.value
                try Task.checkCancellation()
                guard token == generation else { return }
                previewSourceArea = plan.sourceArea
                preview = preparation.preview
                suggestions = detected
                selected = Set(suggestions.map(\.id))
                if suggestions.isEmpty { notice = String(localized: "Keine sensiblen Daten erkannt. Prüfe das Bild trotzdem vollständig.") }
            } catch is CancellationError {
                if token == generation && !retryRequested { notice = String(localized: "Vorschläge abgebrochen.") }
            } catch {
                if token == generation { notice = String(localized: "Die Vorschläge konnten nicht erstellt werden. Versuche es erneut.") }
            }
        }
    }
    // A replacement starts only after the canceled request has drained. Vision may
    // return late; it must never overlap a retry or publish after sheet closure.
    private func finishRequest() {
        isBusy = false; task = nil
        guard retryRequested else { return }
        retryRequested = false
        resetForRetry(); start()
    }
    private func resetForRetry() {
        preview = nil; suggestions = []; selected = []; rebase()
    }
    func retry() {
        guard !isBusy else { retryRequested = true; task?.cancel(); return }
        resetForRetry(); start()
    }
    func cancel() {
        generation += 1; retryRequested = false; task?.cancel()
    }
    func toggle(_ id: UUID) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    @discardableResult func apply() -> Bool {
        guard canApply else { return false }
        guard editor.document.revision == baseRevision,
              editor.history.objects == baseObjects, editor.history.crop == baseCrop,
              editor.history.resizedSize == baseResizedSize, editor.history.canvasRect == baseCanvasRect else {
            notice = String(localized: "Das Projekt wurde geändert. Starte die Prüfung erneut."); return false
        }
        guard editor.history.objects.count + selected.count <= 10_000 else {
            notice = String(localized: "Die Projektgrenze von 10.000 Objekten ist erreicht."); return false
        }
        var objects = editor.history.objects
        for suggestion in suggestions where selected.contains(suggestion.id) {
            var mask = EditorObject(kind: .redact,
                                    start: CGPoint(x: suggestion.bounds.minX, y: suggestion.bounds.minY),
                                    end: CGPoint(x: suggestion.bounds.maxX, y: suggestion.bounds.maxY))
            mask.color = EditorColor(red: 0, green: 0, blue: 0)
            objects.append(mask)
        }
        editor.commit(objects)
        return true
    }
    private func rebase() {
        baseRevision = editor.document.revision; baseObjects = editor.history.objects
        baseCrop = editor.history.crop; baseResizedSize = editor.history.resizedSize; baseCanvasRect = editor.history.canvasRect
        snapshot = TextRecognitionSnapshot(image: editor.image, objects: baseObjects, crop: baseCrop, resizedSize: baseResizedSize, canvasRect: baseCanvasRect)
    }
}
