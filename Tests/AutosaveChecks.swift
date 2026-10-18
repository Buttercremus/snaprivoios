import AppKit
import SnagForgeDomain

@main
struct AutosaveChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Autosave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let document = ProjectDocument(title: "Autosave Test", pixelSize: PixelSize(width: 240, height: 160)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 180, y: 90))
        model.commit([arrow])
        // Verify the actual debounce path without pressing Save.
        try await Task.sleep(for: .milliseconds(900))
        precondition(!model.isDirty && model.saveError == nil, "Autosave did not commit")
        let loaded = try await ProjectStore(root: root).load(document.id)
        precondition(loaded.document.objects == [arrow], "Autosave lost editable object")
        let reopened = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        reopened.selection = arrow.id
        reopened.updateStyle(width: 17, font: 48)
        precondition(reopened.history.objects[0].lineWidth == 17, "Reloaded object cannot be edited")
        reopened.undo()
        let undoSaved = await reopened.flush()
        precondition(undoSaved && !reopened.isDirty)
        let undone = try await store.load(document.id)
        precondition(undone.document.objects == [arrow], "Undo state not saved")
        reopened.redo()
        let first = Task { await reopened.flush() }
        var moved = reopened.history.objects
        moved[0] = moved[0].translated(by: CGSize(width: 15, height: 10))
        reopened.commit(moved)
        let second = Task { await reopened.flush() }
        let firstResult = await first.value, secondResult = await second.value
        precondition(firstResult && secondResult && !reopened.isDirty, "Concurrent flush lost latest edit")
        let final = try await store.load(document.id)
        precondition(final.document.objects == moved, "Latest moved/style state not saved")
        let blocked = root.appendingPathComponent("\(document.id.uuidString).snagforge/Revisions/\(reopened.document.revision + 1).json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        reopened.commit([])
        let failed = await reopened.flush()
        precondition(!failed && reopened.isDirty && reopened.saveError != nil, "Write failure must remain dirty")
        try FileManager.default.removeItem(at: blocked)
        let retry = await reopened.flush()
        precondition(retry && !reopened.isDirty && reopened.saveError == nil, "Save retry failed")
        // A second editor must not overwrite an externally saved generation, even with more local edits.
        let competingDocument = try await store.load(document.id)
        let competitor = EditorModel(image: image, document: competingDocument.document, generation: competingDocument.generation, store: store, onSaved: {})
        reopened.commit([arrow])
        let externalSaved = await reopened.flush()
        precondition(externalSaved)
        competitor.commit([arrow]); competitor.commit(moved)
        let conflict = await competitor.flush()
        precondition(!conflict && competitor.isDirty, "Stale editor overwrote newer generation")
        let copied = await competitor.saveCopy()
        precondition(copied && !competitor.isDirty && competitor.document.id != document.id, "Conflict copy not saved")
        let preserved = try await store.load(competitor.document.id)
        let unchanged = try await store.load(document.id)
        precondition(preserved.document.objects == moved && unchanged.document.objects == [arrow], "Conflict copy lost either editor's changes")
        reopened.editText(at: CGPoint(x: 30, y: 40))
        reopened.updateText("Direkt im Bild\nZweite Zeile")
        let draft = reopened.editingTextObject!
        try await Task.sleep(for: .milliseconds(900))
        let live = try await store.load(reopened.document.id)
        precondition(live.document.objects.last == draft, "Typing draft not autosaved")
        reopened.updateText("Direkt im Bild\nFertig")
        reopened.finishTextEditing()
        reopened.undo()
        precondition(reopened.history.objects == [arrow], "Inline typing was not one undo step")
        reopened.redo()
        let completed = reopened.history.objects
        reopened.editText(at: completed.last!.start, object: completed.last)
        reopened.updateText("Verwerfen")
        reopened.finishTextEditing(cancel: true)
        precondition(reopened.history.objects == completed, "Escape lost the original text")
        let textSaved = await reopened.flush()
        let textLoaded = try await store.load(reopened.document.id)
        precondition(textSaved && textLoaded.document.objects == completed, "Inline text not saved after finish/cancel")
        var rectangle = EditorObject(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 150, y: 120), lineWidth: 4)
        rectangle.fill = EditorFill(isEnabled: true, color: EditorColor(red: 0.2, green: 0.8, blue: 0.4), opacity: 0.6)
        rectangle.cornerRadius = 18
        let styledDocument = ProjectDocument(title: "Regler", pixelSize: document.pixelSize, objects: [rectangle])
        try await store.create(styledDocument, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let styled = EditorModel(image: image, document: styledDocument, generation: 0, store: store, onSaved: {})
        styled.selection = rectangle.id
        styled.beginStyleEditing()
        for width: CGFloat in [7, 15, 27] { styled.updateStyle(width: width) }
        let liveStyleSaved = await styled.flush()
        let liveStyle = try await store.load(styledDocument.id)
        precondition(liveStyleSaved && liveStyle.document.objects[0].lineWidth == 27, "Slider draft not saved during gesture")
        styled.updateStyle(width: 31); styled.endStyleEditing()
        styled.undo()
        precondition(styled.history.objects == [rectangle] && !styled.history.canUndo, "Slider movement requires more than one undo")
        styled.redo()
        precondition(styled.history.objects[0].lineWidth == 31, "Slider redo lost final value")
        styled.selection = rectangle.id
        styled.beginStyleEditing()
        for opacity in [0.2, 0.4, 0.8] {
            var fill = styled.activeFill; fill.opacity = opacity; styled.updateStyle(fill: fill)
        }
        styled.endStyleEditing(); styled.undo()
        precondition(styled.history.objects[0].effectiveFill.opacity == 0.6, "Opacity slider did not undo as one change")
        styled.redo(); styled.selection = rectangle.id
        styled.updateStyle(corner: 35)
        let stylesSaved = await styled.flush()
        let stylesLoaded = try await ProjectStore(root: root).load(styledDocument.id)
        let afterRestart = EditorModel(image: image, document: stylesLoaded.document, generation: stylesLoaded.generation, store: store, onSaved: {})
        precondition(stylesSaved && afterRestart.history.objects == styled.history.objects, "Restart lost fill, opacity or radius")
        afterRestart.selection = rectangle.id
        var noFill = afterRestart.activeFill; noFill.isEnabled = false
        afterRestart.updateStyle(fill: noFill); afterRestart.undo()
        precondition(afterRestart.history.objects[0].effectiveFill.isEnabled, "Restored fill cannot be edited and undone")
        afterRestart.selection = rectangle.id
        let beforeShape = afterRestart.history.objects[0]
        afterRestart.selectShape(.diamond)
        let diamond = afterRestart.history.objects[0]
        precondition(diamond.kind == .diamond && diamond.id == beforeShape.id && diamond.rect == beforeShape.rect &&
                     diamond.fill == beforeShape.fill && diamond.lineWidth == beforeShape.lineWidth,
                     "Changing shape lost geometry, identity or style")
        afterRestart.undo(); precondition(afterRestart.history.objects == [beforeShape], "Shape conversion is not one undo step")
        afterRestart.redo(); afterRestart.selection = diamond.id
        afterRestart.updateStyle(color: EditorColor(red: 0, green: 0.4, blue: 1), width: 5,
            fill: EditorFill(isEnabled: true, opacity: 0.2), stroke: EditorStroke(style: .dotted))
        let preset = afterRestart.history.objects[0]
        afterRestart.undo(); precondition(afterRestart.history.objects == [diamond], "Style preset is not one undo step")
        afterRestart.redo()
        let shapeSaved = await afterRestart.flush()
        let shapeLoaded = try await ProjectStore(root: root).load(afterRestart.document.id)
        precondition(shapeSaved && shapeLoaded.document.objects == [preset], "Shape or border lost after save/restart")
        afterRestart.selection = preset.id
        afterRestart.updateStyle(stroke: EditorStroke(isEnabled: false)); afterRestart.undo()
        precondition(afterRestart.history.objects == [preset], "Disabling border cannot be undone after reload")
        let baseline = afterRestart.history.objects
        afterRestart.tool = .callout
        afterRestart.editText(at: CGPoint(x: 30, y: 40))
        afterRestart.updateText("Text")
        afterRestart.beginStyleEditing(); afterRestart.updateStyle(font: 42, fill: noFill); afterRestart.endStyleEditing()
        afterRestart.updateText("Text mit Stil"); afterRestart.finishTextEditing()
        precondition(afterRestart.history.objects.last?.fontSize == 42 && afterRestart.history.objects.last?.effectiveFill.isEnabled == false)
        afterRestart.undo()
        precondition(afterRestart.history.objects == baseline, "Inline style slider split the text transaction")
        _ = await afterRestart.flush()
        try await checkCropAutosave()
        print("Autosave checks passed: shape conversion, border styles and atomic style presets; live sliders, restart/edit/undo, inline text, debounce, concurrent flush, retry, conflict copy.")
    }
}


@MainActor private func checkCropAutosave() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-CropAutosave-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
    let image = context.makeImage()!, store = ProjectStore(root: root)
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 180, y: 90))
    let document = ProjectDocument(title: "Crop Autosave", pixelSize: PixelSize(width: 240, height: 160)!, objects: [arrow])
    let original = try EditorRenderer.png(image: image, objects: [])
    try await store.create(document, original: original, thumbnail: nil)
    let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
    let crop = CGRect(x: 30, y: 20, width: 160, height: 110)
    model.beginCrop(); model.cropDraft = crop
    try await Task.sleep(for: .milliseconds(900))
    let draft = try await store.load(document.id)
    precondition(draft.document.crop == nil && draft.generation == 0 && !model.isDirty, "Unconfirmed crop autosaved")
    model.applyCrop()
    try await Task.sleep(for: .milliseconds(900))
    let committed = try await ProjectStore(root: root).load(document.id)
    precondition(!model.isDirty && committed.document.crop == crop && committed.document.objects == [arrow] && committed.original == original, "Autosave lost crop or rewrote original")
    let listing = try await store.list(), thumbnail = NSBitmapImageRep(data: listing.items[0].thumbnail!)!
    precondition(thumbnail.pixelsWide == 160 && thumbnail.pixelsHigh == 110, "Library thumbnail ignored crop")
    let reopened = EditorModel(image: image, document: committed.document, generation: committed.generation, store: store, onSaved: {})
    reopened.beginCrop(); reopened.restoreOriginal(); reopened.applyCrop(); reopened.undo()
    precondition(reopened.document.crop == crop && !reopened.history.canUndo, "Restore original did not undo in one step")
    reopened.redo(); _ = await reopened.flush()
    let restored = try await store.load(document.id)
    precondition(restored.document.crop == nil && restored.original == original && restored.document.objects == [arrow])
    reopened.undo(); _ = await reopened.flush()
    let saved = try await store.load(document.id)
    let stale = EditorModel(image: image, document: saved.document, generation: saved.generation, store: store, onSaved: {})
    reopened.commit([arrow.translated(by: CGSize(width: 4, height: 5))]); _ = await reopened.flush()
    stale.beginCrop(); stale.cropDraft = CGRect(x: 40, y: 30, width: 100, height: 80); stale.applyCrop()
    let failed = await stale.flush(); precondition(!failed && stale.isDirty && stale.saveError != nil)
    let copied = await stale.saveCopy(); precondition(copied && !stale.isDirty)
    let copy = try await store.load(stale.document.id), unchanged = try await store.load(document.id)
    precondition(copy.document.crop == stale.document.crop && copy.document.objects == [arrow] && copy.original == original, "Conflict copy flattened or lost crop")
    precondition(unchanged.document.crop == crop && unchanged.document.objects == reopened.history.objects, "Conflict copy modified existing project")
    print("Crop autosave checks passed: drafts stay transient, debounce/restart, cropped library thumbnail, original bytes unchanged, restore/undo/redo and stale-save conflict copy.")
}
