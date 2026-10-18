import AppKit
import SnagForgeDomain
import Vision

actor MissingVisionResource {
    private(set) var calls = 0
    let persistent: Bool
    let code: Int
    init(persistent: Bool = false, code: Int = NSFileReadNoSuchFileError) { self.persistent = persistent; self.code = code }
    func perform(_ request: RecognizeTextRequest, image: CGImage) async throws -> [RecognizedTextObservation] {
        calls += 1
        if persistent || calls == 1 {
            throw NSError(domain: NSCocoaErrorDomain, code: code,
                          userInfo: [NSFilePathErrorKey: "/Synthetic/Vision/manifest.json"])
        }
        var availableRequest = request
        availableRequest.recognitionLevel = .fast
        return try await availableRequest.perform(on: image, orientation: .up)
    }
}

actor DelayedTextRecognition {
    private var continuation: CheckedContinuation<TextRecognitionResult, Never>?
    private(set) var calls = 0
    func run() async -> TextRecognitionResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: TextRecognitionResult) { continuation?.resume(returning: result); continuation = nil }
}

actor FailingAccurateEngine {
    private(set) var counts = [0, 0]
    let failFast: Bool
    init(failFast: Bool = false) { self.failFast = failFast }
    func run(_ request: RecognizeTextRequest, image: CGImage) async throws -> [RecognizedTextObservation] {
        if request.recognitionLevel == .accurate {
            counts[0] += 1
            throw NSError(domain: "TextRecognition.CRImageReaderError", code: 0)
        }
        counts[1] += 1
        if failFast { throw VisionError.operationFailed("Synthetic fast engine failure") }
        return try await request.perform(on: image, orientation: .up)
    }
}

@main struct TextRecognitionChecks {
    @MainActor static func main() async throws {
        let blank = makeBlank(width: 1200, height: 700)
        func label(_ text: String, y: CGFloat) -> EditorObject {
            var object = EditorObject(kind: .text, start: CGPoint(x: 50, y: y), text: text, fontSize: 44)
            object.color = EditorColor(red: 0, green: 0, blue: 0)
            return object
        }
        // Synthetic source pixels, independent from the editable annotation layer.
        let source = try EditorRenderer.render(image: blank, objects: [label("TOP SECRET 12345", y: 50), label("BOTTOM PUBLIC 67890", y: 430)])
        let snapshot = TextRecognitionSnapshot(image: source, objects: [], crop: nil, resizedSize: nil)
        checkEditorEntry(snapshot)
        let service = TextRecognitionService()
        let preparation = try await service.prepare(snapshot)
        let english = preparation.languages.first { $0.hasPrefix("en") }!
        let german = preparation.languages.first { $0.hasPrefix("de") }!
        precondition(preparation.preview.width == 1200 && !preparation.languages.isEmpty)
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let whole = try await service.recognize(snapshot, selection: full, language: english)
        precondition(whole.text.contains("TOP SECRET 12345") && whole.text.contains("BOTTOM PUBLIC 67890"))
        precondition(whole.lines.first!.bounds.minY < 0.3 && whole.lines.last!.bounds.minY > 0.5, "Vision coordinates are not top-left")
        progress("full image")
        let bottom = try await service.recognize(snapshot, selection: CGRect(x: 0, y: 0.5, width: 1, height: 0.5), language: english)
        precondition(!bottom.text.contains("SECRET") && bottom.text.contains("BOTTOM PUBLIC 67890"), "Region recognized pixels outside its area")
        progress("selected area")
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 1000, y: 150))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        let edited = TextRecognitionSnapshot(image: source, objects: [mask, label("EDITABLE ANNOTATION", y: 250)],
                                             crop: CGRect(x: 20, y: 20, width: 1100, height: 600),
                                             resizedSize: PixelSize(width: 550, height: 300))
        let visible = try await service.recognize(edited, selection: full, language: english)
        precondition(!visible.text.contains("SECRET") && !visible.text.contains("12345"), "OCR exposed redacted original")
        precondition(visible.text.contains("EDITABLE ANNOTATION") && visible.text.contains("PUBLIC"), "OCR ignored visible edits/crop/resize")
        progress("visible edited/redacted image")
        let germanImage = try EditorRenderer.render(image: blank, objects: [label("Grüße aus München", y: 100), label("English sample text", y: 230)])
        let bilingual = TextRecognitionSnapshot(image: germanImage, objects: [], crop: nil, resizedSize: nil)
        let de = try await service.recognize(bilingual, selection: full, language: german)
        precondition(de.text.contains("Grüße aus München"))
        progress("German language")
        let automatic = try await service.recognize(bilingual, selection: full, language: "")
        precondition(automatic.text.contains("München") && automatic.text.contains("English sample text"))
        progress("automatic language")
        let empty = try await service.recognize(TextRecognitionSnapshot(image: blank, objects: [], crop: nil, resizedSize: nil), selection: full, language: english)
        precondition(empty.text.isEmpty && !empty.hasUncertainText)
        do {
            _ = try await service.recognize(snapshot, selection: full, language: "not-a-supported-language")
            preconditionFailure("Unsupported language silently accepted")
        } catch TextRecognitionError.unsupportedLanguage {}
        let cancelled = Task { try await service.recognize(snapshot, selection: full, language: english) }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled request produced a result") }
        catch is CancellationError {}
        // Large raster + annotations exercises the real bounded renderer, not just the plan.
        let large = TextRecognitionSnapshot(image: makeBlank(width: 6000, height: 3000), objects: [label("LARGE IMAGE TEST", y: 180)], crop: nil, resizedSize: nil)
        let largePlan = try large.plan()
        let rendered = try await Task.detached { try large.render(largePlan) }.value
        precondition(rendered.width == 4096 && rendered.height == 2048 && largePlan.isDownsampled)
        let largeResult = try await service.recognize(large, selection: full, language: english)
        precondition(largeResult.text.contains("LARGE IMAGE TEST"))
        progress("large image")
        try await checkModelFallback(snapshot: edited, language: english)
        try await checkMissingResources(snapshot: edited, language: english)
        try await checkSession(snapshot: snapshot, preparation: preparation)
        print("OCR checks passed: real local Vision, English/German/automatic language, top-left region, visible annotations/crop/resize, redacted source excluded, blank/unsupported/cancelled requests, bounded 18 MP image, late cancellation, retry, uncertain result and corrected plain-text clipboard. No OCR content logged.")
    }

    private static func checkModelFallback(snapshot: TextRecognitionSnapshot, language: String) async throws {
        let engine = FailingAccurateEngine()
        let service = TextRecognitionService(perform: { try await engine.run($0, image: $1) })
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        for _ in 0..<2 {
            let result = try await service.recognize(snapshot, selection: full, language: language)
            precondition(result.usedFastRecognition && result.text.contains("EDITABLE ANNOTATION"))
            precondition(!result.text.contains("SECRET") && !result.text.contains("12345"))
        }
        let counts = await engine.counts
        precondition(counts == [1, 2], "Successful fallback must avoid repeated failing model initialization")
        var fast = RecognizeTextRequest()
        fast.recognitionLevel = .fast
        let fastLanguages = fast.supportedRecognitionLanguages.map(\.minimalIdentifier)
        let accurateLanguages = RecognizeTextRequest().supportedRecognitionLanguages.map(\.minimalIdentifier)
        if let unsupported = accurateLanguages.first(where: { !fastLanguages.contains($0) }) {
            let limitedEngine = FailingAccurateEngine()
            let limited = TextRecognitionService(perform: { try await limitedEngine.run($0, image: $1) })
            do {
                _ = try await limited.recognize(snapshot, selection: full, language: unsupported)
                preconditionFailure("Fallback silently changed the selected language")
            } catch {
                precondition((error as NSError).domain == "TextRecognition.CRImageReaderError")
            }
            let limitedCounts = await limitedEngine.counts
            precondition(limitedCounts == [1, 0])
        }
        let failed = FailingAccurateEngine(failFast: true)
        let broken = TextRecognitionService(perform: { try await failed.run($0, image: $1) })
        do {
            _ = try await broken.recognize(snapshot, selection: full, language: language)
            preconditionFailure("Both failed engines returned a result")
        } catch VisionError.operationFailed {}
        let failedCounts = await failed.counts
        precondition(failedCounts == [1, 1], "Fallback must be bounded")
        let cancelled = TextRecognitionService(perform: { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw VisionError.invalidModel("Synthetic model failure")
        })
        let job = Task { try await cancelled.recognize(snapshot, selection: full, language: language) }
        do { _ = try await job.value; preconditionFailure("Cancelled model failure was retried") }
        catch is CancellationError {}
        progress("model fallback, redactions, remembered engine, bounded failure and cancellation")
    }

    private static func checkMissingResources(snapshot: TextRecognitionSnapshot, language: String) async throws {
        let missing = MissingVisionResource()
        let recovered = TextRecognitionService(perform: { try await missing.perform($0, image: $1) })
        let result = try await recovered.recognize(snapshot, selection: CGRect(x: 0, y: 0, width: 1, height: 1), language: language)
        precondition(result.text.contains("EDITABLE ANNOTATION") && !result.text.contains("SECRET"), "Resource recovery changed the visible/redacted OCR input")
        let calls = await missing.calls; precondition(calls == 2)
        let permanent = MissingVisionResource(persistent: true)
        let unavailable = TextRecognitionService(perform: { try await permanent.perform($0, image: $1) })
        do {
            _ = try await unavailable.recognize(snapshot, selection: CGRect(x: 0, y: 0, width: 1, height: 1), language: language)
            preconditionFailure("Missing resources silently produced a successful OCR result")
        } catch TextRecognitionError.resourcesUnavailable {}
        let failedCalls = await permanent.calls; precondition(failedCalls == 2, "Missing resources caused an unbounded retry")
        let denied = MissingVisionResource(persistent: true, code: NSFileReadNoPermissionError)
        let otherFailure = TextRecognitionService(perform: { try await denied.perform($0, image: $1) })
        do {
            _ = try await otherFailure.recognize(snapshot, selection: CGRect(x: 0, y: 0, width: 1, height: 1), language: language)
            preconditionFailure("A permission failure was swallowed")
        } catch {
            precondition((error as NSError).code == NSFileReadNoPermissionError)
        }
        let deniedCalls = await denied.calls; precondition(deniedCalls == 1, "Retried an unrelated permission failure")
        let cancelled = TextRecognitionService(perform: { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        })
        let cancelledJob = Task {
            try await cancelled.recognize(snapshot, selection: CGRect(x: 0, y: 0, width: 1, height: 1), language: language)
        }
        do {
            _ = try await cancelledJob.value
            preconditionFailure("A cancelled resource lookup was retried")
        } catch is CancellationError {}
        progress("missing manifest recovery, bounded failure and cancellation")
    }

    @MainActor private static func checkSession(snapshot: TextRecognitionSnapshot, preparation: TextRecognitionPreparation) async throws {
        let result = TextRecognitionResult(lines: [RecognizedTextLine(text: "Synthetic uncertain result", confidence: 0.4, bounds: .zero)], usedFastRecognition: true)
        let delayed = DelayedTextRecognition()
        let model = TextRecognitionModel(snapshot: snapshot, prepare: { _ in preparation }, recognize: { _, _, _ in await delayed.run() })
        model.prepare(); try await waitUntil { !model.isBusy }
        precondition(model.canRecognize && !model.canCopy)
        model.recognize(); model.recognize()
        for _ in 0..<1000 {
            if await delayed.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let firstCallCount = await delayed.calls
        precondition(firstCallCount == 1)
        model.cancel(); precondition(model.isBusy && model.isCancelling && !model.canRecognize)
        await delayed.finish(result); try await waitUntil { !model.isBusy }
        precondition(!model.hasResult && model.text.isEmpty && model.notice != nil, "Late cancelled result reached the UI")
        model.recognize()
        for _ in 0..<1000 {
            if await delayed.calls == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await delayed.finish(result); try await waitUntil { !model.isBusy }
        precondition(model.hasResult && model.hasUncertainText && model.canCopy && model.notice != nil)
        let board = NSPasteboard(name: NSPasteboard.Name("Snaprivo-OCR-Test-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("Stale synthetic HTML", forType: .html)
        model.text = "Corrected Grüße\nSecond line"
        precondition(model.copy(to: board) && board.string(forType: .string) == model.text)
        precondition(board.types?.contains(.string) == true && model.didCopy)
        precondition(board.data(forType: .html) == nil && board.data(forType: .png) == nil && board.data(forType: .rtf) == nil)
        model.text = ""; precondition(!model.didCopy && !model.canCopy && !model.copy(to: board) && !model.isEmptyResult)
        let failed = TextRecognitionModel(snapshot: snapshot, prepare: { _ in preparation }, recognize: { _, _, _ in throw TextRecognitionError.unsupportedLanguage })
        failed.prepare(); try await waitUntil { !failed.isBusy }
        failed.recognize(); try await waitUntil { !failed.isBusy }
        precondition(failed.notice != nil && !failed.hasResult && !failed.canCopy && failed.canRecognize)
        let brokenPreview = TextRecognitionModel(snapshot: snapshot, prepare: { _ in throw TextRecognitionError.busy })
        brokenPreview.prepare(); try await waitUntil { !brokenPreview.isBusy }
        precondition(brokenPreview.notice != nil && brokenPreview.preview == nil && !brokenPreview.canRecognize)
    }
    @MainActor private static func checkEditorEntry(_ snapshot: TextRecognitionSnapshot) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-OCR-Entry-" + UUID().uuidString)
        let document = ProjectDocument(title: "Synthetic OCR entry", pixelSize: PixelSize(width: snapshot.image.width, height: snapshot.image.height)!)
        let editor = EditorModel(image: snapshot.image, document: document, generation: 0, store: ProjectStore(root: root), onSaved: {})
        editor.isCanvasGestureActive = true; editor.beginTextRecognition()
        precondition(!editor.isShowingTextRecognition)
        editor.isCanvasGestureActive = false; editor.cropDraft = editor.originalRect; editor.beginTextRecognition()
        precondition(!editor.isShowingTextRecognition)
        editor.cropDraft = nil; editor.beginTextRecognition()
        precondition(editor.isShowingTextRecognition && !editor.hasExportableImage && !editor.isDirty && !editor.history.canUndo)
        editor.isShowingTextRecognition = false
        precondition(editor.hasExportableImage && editor.document == document)
    }
    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("OCR session failed to settle")
    }
    private static func makeBlank(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
    private static func progress(_ stage: String) {
        // Test phase metadata only; never print recognized contents.
        FileHandle.standardOutput.write(Data("OCR check passed: \(stage)\n".utf8))
    }
}
