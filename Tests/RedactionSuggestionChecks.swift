import AppKit
import SnagForgeDomain

private actor RedactionGate {
    private var continuation: CheckedContinuation<TextRecognitionResult, Never>?
    private(set) var calls = 0
    func result() async -> TextRecognitionResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: TextRecognitionResult) {
        continuation?.resume(returning: result); continuation = nil
    }
}

@main struct RedactionSuggestionChecks {
    @MainActor static func waitUntil(line: UInt = #line, seconds: Int = 20, _ condition: () async -> Bool) async throws {
        for _ in 0..<(seconds * 200) {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Redaction workflow timed out at call line \(line)")
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Redaction-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        var base = EditorObject(kind: .rectangle, start: CGPoint(x: 110, y: 60), end: CGPoint(x: 140, y: 80))
        base.color = .init(red: 1, green: 0, blue: 0)
        let document = ProjectDocument(title: "Synthetic redaction", pixelSize: PixelSize(width: 800, height: 400)!,
            objects: [base], crop: CGRect(x: 100, y: 50, width: 600, height: 300), resizedSize: PixelSize(width: 900, height: 150)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let editor = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        editor.isShowingRedactionSuggestions = true
        let fake = TextRecognitionResult(lines: [
            .init(text: "user@example.com", confidence: 1, bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)),
            .init(text: "+49 123 4567890", confidence: 1, bounds: CGRect(x: 0.2, y: 0.5, width: 0.4, height: 0.1))
        ])
        let prepare: RedactionSuggestionModel.Prepare = { snapshot in
            TextRecognitionPreparation(preview: try snapshot.render(snapshot.plan()), languages: [])
        }
        let model = RedactionSuggestionModel(editor: editor, prepare: prepare, recognize: { _, _, _ in fake })
        model.start(); try await waitUntil { !model.isBusy }
        precondition(model.preview != nil && model.canApply, "Own sheet must allow reviewed masks")
        precondition(model.suggestions.count == 2)
        let bounds = model.suggestions[0].bounds
        precondition(abs(bounds.minX - 160) < 0.001 && abs(bounds.minY - 110) < 0.001 && abs(bounds.width - 180) < 0.001)
        model.selected.insert(UUID()); precondition(!model.canApply); model.selected = Set(model.suggestions.map(\.id))
        precondition(model.apply()); let covered = editor.history.objects
        precondition(covered.count == 3 && covered.suffix(2).allSatisfy { $0.kind == .redact })
        let rendered = try EditorRenderer.render(image: image, objects: covered, crop: document.crop, resizedSize: document.resizedSize)
        precondition(EditorRenderer.pixelColor(rendered, x: 225, y: 37)!.redComponent < 0.01)
        precondition(EditorRenderer.pixelColor(rendered, x: 600, y: 30)!.redComponent > 0.99)
        editor.undo(); precondition(editor.history.objects == [base], "Apply must be one undo")
        editor.redo(); precondition(editor.history.objects == covered)
        precondition(!model.apply() && model.notice != nil, "Stale suggestions must not be applied twice")
        let saved = await editor.flush(); precondition(saved)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.objects == covered)
        let png = try EditorRenderer.png(image: image, objects: covered, crop: document.crop, resizedSize: document.resizedSize)
        let reopenedPNG = try EditorRenderer.png(image: image, objects: loaded.document.objects, crop: loaded.document.crop, resizedSize: loaded.document.resizedSize)
        precondition(reopenedPNG == png)

        // The injected recognizer deliberately ignores cancellation. A retry must
        // drain it, rebase the changed document, and start exactly one replacement.
        let retryGate = RedactionGate()
        let retry = RedactionSuggestionModel(editor: editor, prepare: prepare, recognize: { _, _, _ in await retryGate.result() })
        retry.start(); try await waitUntil { await retryGate.calls == 1 }
        editor.commit([base]); let currentRevision = editor.document.revision
        retry.retry(); precondition(retry.isBusy)
        await retryGate.finish(fake)
        try await waitUntil { await retryGate.calls == 2 }
        precondition(retry.baseRevision == currentRevision && retry.suggestions.isEmpty)
        await retryGate.finish(fake); try await waitUntil { !retry.isBusy }
        precondition(retry.canApply && retry.apply())

        // Closing after requesting a retry must suppress both the late result and
        // the queued replacement, even when the recognizer ignores cancellation.
        let cancelGate = RedactionGate()
        let canceled = RedactionSuggestionModel(editor: editor, prepare: prepare, recognize: { _, _, _ in await cancelGate.result() })
        canceled.start(); try await waitUntil { await cancelGate.calls == 1 }
        canceled.retry(); canceled.cancel(); await cancelGate.finish(fake)
        try await waitUntil { !canceled.isBusy }
        let calls = await cancelGate.calls
        precondition(calls == 1 && canceled.preview == nil && canceled.suggestions.isEmpty && !canceled.canApply)

        // Exercise the production Vision path on synthetic source pixels as well.
        var label = EditorObject(kind: .text, start: CGPoint(x: 70, y: 90), text: "user@example.com", fontSize: 36)
        label.color = .init(red: 0, green: 0, blue: 0)
        let textImage = try EditorRenderer.render(image: image, objects: [label])
        let visionEditor = EditorModel(image: textImage,
            document: ProjectDocument(title: "Synthetic Vision", pixelSize: PixelSize(width: 800, height: 400)!),
            generation: 0, store: store, onSaved: {})
        visionEditor.isShowingRedactionSuggestions = true
        let vision = RedactionSuggestionModel(editor: visionEditor)
        vision.start(); try await waitUntil(seconds: 120) { !vision.isBusy }
        precondition(vision.suggestions.contains { $0.categories.contains(.email) }, "Production Vision did not recognize the synthetic email")
        print("Redaction checks passed: production Vision, original/crop/resize mapping, review guards, black PNG pixels, one undo/redo, persistence, stale refusal, drained retry/rebase and late cancellation without restart.")
    }
}
