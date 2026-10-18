import AppKit
import SnagForgeDomain

@main struct SavedStyleChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3 {
            try processRestart(phase: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }
        _ = NSApplication.shared
        let suite = "Snaprivo-SavedStyles-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        var preferences = AppPreferences(defaults: defaults)
        let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        var object = EditorObject(kind: .callout, start: CGPoint(x: 100, y: 80), text: "Synthetic target", fontSize: 22, textWidth: 220)
        object.calloutTip = CGPoint(x: 60, y: 230)
        let doc = ProjectDocument(title: "Saved styles (synthetic)", pixelSize: PixelSize(width: 600, height: 400)!, objects: [object],
            crop: CGRect(x: 20, y: 20, width: 560, height: 360), resizedSize: PixelSize(width: 280, height: 180))
        let store = ProjectStore(root: root)
        try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.selection = object.id
        var source = object
        source.text = "PRIVATE SOURCE TEXT MUST NOT BE STORED"
        source.fontSize = 35; source.lineWidth = 9
        source.color = EditorColor(red: 0, green: 0.3, blue: 0.8)
        source.textStyle = EditorTextStyle(family: "Helvetica", weight: .bold, italic: true, alignment: .center)
        source.fill = EditorFill(isEnabled: true, color: EditorColor(red: 1, green: 0.8, blue: 0.1), opacity: 0.6)
        let style = EditorSavedStyle(object: source)
        try preferences.saveStyle(name: "Support", style: style)
        let id = preferences.savedStyles[0].id
        let saved = defaults.data(forKey: "editor.savedStyles.v1")!
        precondition(!String(data: saved, encoding: .utf8)!.contains(source.text))
        let reopenedPreferences = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(reopenedPreferences.savedStyles == preferences.savedStyles)
        try reopenedPreferences.renameStyle(id, to: "Handbuch")
        precondition(AppPreferences(defaults: defaults).savedStyles[0].name == "Handbuch")

        model.applySavedStyle(style)
        let styled = model.history.objects
        precondition(styled[0].text == object.text && styled[0].calloutTip == object.calloutTip)
        precondition(styled[0].fontSize == source.fontSize && styled[0].fill == source.fill)
        precondition(model.document.revision == 1)
        model.undo()
        precondition(model.history.objects == [object] && !model.history.canUndo)
        model.redo(); precondition(model.history.objects == styled)
        model.selection = object.id
        let revision = model.document.revision
        model.applySavedStyle(style)
        precondition(model.document.revision == revision, "Reapplying the same style changed the document")
        model.applySavedStyle(EditorSavedStyle(object: EditorObject(kind: .arrow, start: .zero)))
        precondition(model.history.objects == styled && model.document.revision == revision)
        model.isCanvasGestureActive = true
        precondition(model.currentSavedStyle == nil)
        model.applySavedStyle(EditorSavedStyle(object: object))
        precondition(model.history.objects == styled)
        model.isCanvasGestureActive = false

        // No selected object: change future drawing defaults without a document edit.
        model.selection = nil; model.tool = .callout
        model.applySavedStyle(style)
        let next = model.makeObject(kind: .callout, start: CGPoint(x: 40, y: 50))
        precondition(next.fontSize == source.fontSize && next.fill == source.fill && next.text.isEmpty)
        precondition(model.document.revision == revision)
        try reopenedPreferences.removeStyle(id)
        precondition(AppPreferences(defaults: defaults).savedStyles.isEmpty && model.history.objects == styled)
        preferences = AppPreferences(defaults: defaults)
        try preferences.saveStyle(name: "Blaues Handbuch", style: style)

        let flushed = await model.flush()
        precondition(flushed)
        let loaded = try await ProjectStore(root: root).load(doc.id)
        precondition(loaded.document.objects == styled && loaded.original == original)
        let restored = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        let rendered = try EditorRenderer.png(image: image, objects: styled, crop: doc.crop, resizedSize: doc.resizedSize)
        let reopenedPNG = try EditorRenderer.png(image: image, objects: restored.history.objects, crop: restored.history.crop, resizedSize: restored.history.resizedSize)
        precondition(rendered == reopenedPNG)
        let beforeStylePNG = try EditorRenderer.png(image: image, objects: [object], crop: doc.crop, resizedSize: doc.resizedSize)
        precondition(rendered != beforeStylePNG)

        // Finish inline typing before the independent, single style undo step.
        model.tool = .selection; model.selection = object.id
        model.editText(at: object.start, object: styled[0]); model.updateText("Edited synthetic text")
        model.applySavedStyle(EditorSavedStyle(object: object))
        precondition(model.editingTextObject == nil && model.history.objects[0].fontSize == object.fontSize)
        model.undo()
        precondition(model.history.objects[0].text == "Edited synthetic text" && model.history.objects[0].fontSize == source.fontSize)
        model.undo(); precondition(model.history.objects == styled)
        let flushedAgain = await model.flush(); precondition(flushedAgain)

        // Malformed/future preferences must remain byte-identical, never silently replaced.
        for invalid in [Data(#"{"version":2,"styles":[]}"#.utf8), Data("not JSON".utf8)] {
            defaults.set(invalid, forKey: "editor.savedStyles.v1")
            let blocked = AppPreferences(defaults: defaults)
            precondition(blocked.styleLibraryError != nil)
            do { try blocked.saveStyle(name: "Blocked", style: style); preconditionFailure("Invalid data overwritten") }
            catch { precondition(defaults.data(forKey: "editor.savedStyles.v1") == invalid) }
        }
        defaults.set(saved, forKey: "editor.savedStyles.v1")

        print("Saved style checks passed: preferences reopen/rename/delete, appearance-only storage, one undo step, no-op/mismatch/gesture guards, new-object defaults, inline text boundary, autosave/reopen, identical cropped/resized PNG and corrupt/future-data preservation.")
    }
    @MainActor private static func processRestart(phase: String, suite: String) throws {
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(defaults: defaults)
        if phase == "--persist-write" {
            var arrow = EditorObject(kind: .arrow, start: .zero, lineWidth: 17)
            arrow.color = EditorColor(red: 0.1, green: 0.4, blue: 0.9)
            try preferences.saveStyle(name: "Restart Blue", style: EditorSavedStyle(object: arrow))
            print("Saved style written; this process now exits.")
        } else {
            precondition(phase == "--persist-read")
            defer { defaults.removePersistentDomain(forName: suite) }
            precondition(preferences.savedStyles.count == 1)
            let item = preferences.savedStyles[0]
            precondition(item.name == "Restart Blue" && item.style.family == .arrow && item.style.lineWidth == 17
                && item.style.color == EditorColor(red: 0.1, green: 0.4, blue: 0.9))
            print("Saved style process restart passed: name, tool, color and width restored in a new executable launch.")
        }
    }
}
