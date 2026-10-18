import AppKit
import Observation
import SnagForgeDomain
import Vision

struct TextRecognitionSnapshot: Sendable {
    let image: CGImage
    let objects: [EditorObject]
    let crop: CGRect?
    let resizedSize: PixelSize?

    func plan(selection: CGRect = .init(x: 0, y: 0, width: 1, height: 1), maximumDimension: Int = TextRecognitionPlan.maximumDimension) throws -> TextRecognitionPlan {
        try TextRecognitionPlan(sourceSize: PixelSize(width: image.width, height: image.height)!, crop: crop,
                                resizedSize: resizedSize, selection: selection, maximumDimension: maximumDimension)
    }
    func render(_ plan: TextRecognitionPlan) throws -> CGImage {
        // Use the export compositor, including masks before downsampling. Never send
        // the immutable original directly to Vision when the editor has annotations.
        try EditorRenderer.render(image: image, objects: objects, crop: plan.sourceArea, resizedSize: plan.outputSize)
    }
}

struct TextRecognitionPreparation: Sendable {
    let preview: CGImage
    let languages: [String]
}

enum TextRecognitionError: Error { case busy, unsupportedLanguage, resourcesUnavailable }

/// One rendering/Vision job at a time, also when a closed sheet is still cancelling.
/// Actor isolation keeps image processing off the main actor. No images or text are persisted.
actor TextRecognitionService {
    typealias Perform = @Sendable (RecognizeTextRequest, CGImage) async throws -> [RecognizedTextObservation]
    static let shared = TextRecognitionService()
    private var isBusy = false
    private var prefersFastRecognition = false
    private let perform: Perform
    init(perform: @escaping Perform = { try await $0.perform(on: $1, orientation: .up) }) {
        self.perform = perform
    }

    func prepare(_ snapshot: TextRecognitionSnapshot) async throws -> TextRecognitionPreparation {
        guard !isBusy else { throw TextRecognitionError.busy }
        isBusy = true; defer { isBusy = false }
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let languages = request.supportedRecognitionLanguages.map(\.minimalIdentifier)
        let preview = try snapshot.render(snapshot.plan(maximumDimension: 1200))
        try Task.checkCancellation()
        return TextRecognitionPreparation(preview: preview, languages: languages)
    }

    func recognize(_ snapshot: TextRecognitionSnapshot, selection: CGRect, language: String) async throws -> TextRecognitionResult {
        guard !isBusy else { throw TextRecognitionError.busy }
        isBusy = true; defer { isBusy = false }
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language.isEmpty
        let supported = request.supportedRecognitionLanguages
        if !language.isEmpty {
            guard let chosen = supported.first(where: { $0.minimalIdentifier == language }) else { throw TextRecognitionError.unsupportedLanguage }
            request.recognitionLanguages = [chosen]
        } else {
            request.recognitionLanguages = supported
        }
        if prefersFastRecognition, let fallback = Self.fastRequest(language: language) { request = fallback }
        let image = try snapshot.render(snapshot.plan(selection: selection))
        try Task.checkCancellation()
        let observations: [RecognizedTextObservation]
        do { observations = try await performWithResourceRetry(request, image: image) }
        catch {
            try Task.checkCancellation()
            guard request.recognitionLevel == .accurate, Self.isModelFailure(error),
                  let fallback = Self.fastRequest(language: language) else { throw error }
            // The fast public Vision engine uses a different model path. Reuse only
            // the already composited pixels, preserving crops and opaque redactions.
            observations = try await performWithResourceRetry(fallback, image: image)
            request = fallback
            prefersFastRecognition = true
        }
        try Task.checkCancellation()
        return TextRecognitionResult(lines: observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingRegion.boundingBox.cgRect
            return RecognizedTextLine(text: candidate.string, confidence: candidate.confidence,
                                      bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }, usedFastRecognition: request.recognitionLevel == .fast)
    }

    private func performWithResourceRetry(_ request: RecognizeTextRequest, image: CGImage) async throws -> [RecognizedTextObservation] {
        do { return try await perform(request, image) }
        catch {
            guard Self.isMissingResource(error) else { throw error }
            try Task.checkCancellation()
            do { return try await perform(request, image) }
            catch {
                try Task.checkCancellation()
                if Self.isMissingResource(error) { throw TextRecognitionError.resourcesUnavailable }
                throw error
            }
        }
    }

    private static func fastRequest(language: String) -> RecognizeTextRequest? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .fast
        // Screenshots contain small UI text; the fast engine's default relative
        // height threshold otherwise drops it on large images.
        request.minimumTextHeightFraction = 0
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language.isEmpty
        let supported = request.supportedRecognitionLanguages
        if language.isEmpty {
            request.recognitionLanguages = supported
        } else {
            guard let chosen = supported.first(where: { $0.minimalIdentifier == language }) else { return nil }
            request.recognitionLanguages = [chosen]
        }
        return request
    }

    private static func isModelFailure(_ error: Error) -> Bool {
        // macOS may surface its model-engine error without wrapping it in VisionError.
        // Inspect only the error domain; never log image data, OCR text or userInfo.
        if (error as NSError).domain == "TextRecognition.CRImageReaderError" { return true }
        guard let error = error as? VisionError else { return false }
        switch error {
        case .internalError, .invalidModel, .operationFailed, .unsupportedComputeDevice: return true
        default: return false
        }
    }

    private static func isMissingResource(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoSuchFileError
    }
}

@MainActor @Observable
final class TextRecognitionModel {
    typealias Prepare = @Sendable (TextRecognitionSnapshot) async throws -> TextRecognitionPreparation
    typealias Recognize = @Sendable (TextRecognitionSnapshot, CGRect, String) async throws -> TextRecognitionResult
    let snapshot: TextRecognitionSnapshot
    var selection = CGRect(x: 0, y: 0, width: 1, height: 1)
    var language = ""
    var text = "" { didSet { didCopy = false } }
    private(set) var preview: CGImage?
    private(set) var languages: [String] = []
    private(set) var isBusy = false
    private(set) var isCancelling = false
    private(set) var hasResult = false
    private(set) var isEmptyResult = false
    private(set) var hasUncertainText = false
    private(set) var didCopy = false
    private(set) var notice: String?
    @ObservationIgnored private let prepareImage: Prepare
    @ObservationIgnored private let recognizeImage: Recognize
    @ObservationIgnored private var task: Task<Void, Never>?
    var plan: TextRecognitionPlan? { try? snapshot.plan(selection: selection) }
    var canRecognize: Bool { preview != nil && !isBusy && plan != nil }
    var canCopy: Bool { hasResult && !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(snapshot: TextRecognitionSnapshot,
         prepare: @escaping Prepare = { try await TextRecognitionService.shared.prepare($0) },
         recognize: @escaping Recognize = { try await TextRecognitionService.shared.recognize($0, selection: $1, language: $2) }) {
        self.snapshot = snapshot; prepareImage = prepare; recognizeImage = recognize
    }
    func prepare() {
        guard preview == nil, !isBusy else { return }
        isBusy = true; notice = nil
        task = Task {
            defer { isBusy = false; isCancelling = false; task = nil }
            do {
                let value = try await prepareImage(snapshot)
                try Task.checkCancellation()
                preview = value.preview; languages = value.languages
            } catch { handle(error) }
        }
    }
    func recognize() {
        guard canRecognize else { return }
        let area = selection, chosenLanguage = language
        isBusy = true; notice = nil; text = ""; hasResult = false; isEmptyResult = false; hasUncertainText = false
        task = Task {
            defer { isBusy = false; isCancelling = false; task = nil }
            do {
                let result = try await recognizeImage(snapshot, area, chosenLanguage)
                try Task.checkCancellation()
                text = result.text; isEmptyResult = result.text.isEmpty
                hasUncertainText = result.hasUncertainText; hasResult = true
                if result.usedFastRecognition {
                    notice = String(localized: "Die Standarderkennung ist auf diesem Mac derzeit nicht verfügbar. Der Text wurde mit der schnellen Erkennung gelesen. Prüfe das Ergebnis besonders sorgfältig.")
                }
            } catch { handle(error) }
        }
    }
    func cancel() {
        guard isBusy else { return }
        isCancelling = true; task?.cancel()
    }
    @discardableResult func copy(to pasteboard: NSPasteboard = .general) -> Bool {
        guard canCopy else { return false }
        pasteboard.clearContents()
        didCopy = pasteboard.setString(text, forType: .string)
        if !didCopy { notice = String(localized: "Der Text konnte nicht kopiert werden. Versuche es erneut.") }
        return didCopy
    }
    private func handle(_ error: Error) {
        if Task.isCancelled || error is CancellationError { notice = String(localized: "Texterkennung abgebrochen.") }
        else if case TextRecognitionError.busy = error { notice = String(localized: "Eine vorherige Texterkennung wird noch beendet. Versuche es gleich erneut.") }
        else if case TextRecognitionError.unsupportedLanguage = error { notice = String(localized: "Diese Sprache ist für die Texterkennung nicht verfügbar. Wähle eine andere Sprache.") }
        else if case TextRecognitionError.resourcesUnavailable = error { notice = String(localized: "macOS konnte die lokalen Texterkennungsdateien nicht laden. Versuche es später erneut.") }
        else { notice = String(localized: "Die Texterkennung ist fehlgeschlagen. Versuche einen kleineren Bereich oder eine andere Sprache.") }
    }
}
