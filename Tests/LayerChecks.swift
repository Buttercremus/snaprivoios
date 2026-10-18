import AppKit
import SnagForgeDomain

@main struct LayerChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Layers-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        func shape(_ start: CGPoint, _ end: CGPoint, color: EditorColor) -> EditorObject {
            var value = EditorObject(kind: .rectangle, start: start, end: end)
            value.fill = EditorFill(isEnabled: true, color: color); value.stroke = EditorStroke(isEnabled: false)
            return value
        }
        let red = shape(CGPoint(x: 40, y: 30), CGPoint(x: 180, y: 130), color: EditorColor(red: 1, green: 0, blue: 0))
        let blue = shape(CGPoint(x: 80, y: 60), CGPoint(x: 160, y: 110), color: EditorColor(red: 0, green: 0, blue: 1))
        let blur = EditorObject(kind: .blur, start: CGPoint(x: 100, y: 70), end: CGPoint(x: 150, y: 100))
        let doc = ProjectDocument(title: "Layer-Abnahme (synthetisch)", pixelSize: PixelSize(width: 240, height: 160)!,
                                  objects: [red, blue, blur], crop: CGRect(x: 20, y: 10, width: 200, height: 140),
                                  resizedSize: PixelSize(width: 100, height: 70))
        let store = ProjectStore(root: root); try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeViewport(); window.makeFirstResponder(canvas)
        func projection() -> EditorImageProjection {
            EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
        }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(projection().viewPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func pick() {
            let point = CGPoint(x: 120, y: 80)
            canvas.mouseDown(with: event(.leftMouseDown, point)); canvas.mouseUp(with: event(.leftMouseUp, point))
        }
        func png() throws -> Data {
            try EditorRenderer.png(image: image, objects: model.history.objects, crop: model.document.crop, resizedSize: model.document.resizedSize)
        }
        func assertPixel(isBlue: Bool) throws {
            let bitmap = NSBitmapImageRep(data: try png())!, color = bitmap.colorAt(x: 50, y: 35)!.usingColorSpace(.deviceRGB)!
            precondition(bitmap.pixelsWide == 100 && bitmap.pixelsHigh == 70)
            precondition(isBlue ? color.blueComponent > 0.95 && color.redComponent < 0.05 : color.redComponent > 0.95 && color.blueComponent < 0.05,
                         "PNG overlap does not match layer order")
            // Mirrors the representable update after a model-only layer command.
            canvas.needsDisplay = true
            let view = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: view)
            let point = projection().viewPoint(CGPoint(x: 120, y: 80)), scale = CGFloat(view.pixelsWide) / canvas.bounds.width
            let visible = view.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.sRGB)!
            // Verify the visible layer by its dominant channel; exact sRGB pixels are checked in PNG above.
            precondition(isBlue ? visible.blueComponent > visible.redComponent + 0.5 : visible.redComponent > visible.blueComponent + 0.5,
                         "Canvas and PNG differ at overlap (expected blue: \(isBlue), actual: \(visible))")
        }
        pick(); precondition(model.selection == blue.id, "A lower blur stole the top vector's hit")
        try assertPixel(isBlue: true)
        model.moveSelection(.backward)
        precondition(model.history.objects == [blue, red, blur] && model.selection == blue.id)
        try assertPixel(isBlue: false)
        model.selection = nil; pick(); precondition(model.selection == red.id, "Picking did not follow reordered paint order")
        model.undo(); precondition(model.history.objects == doc.objects && !model.history.canUndo)
        model.selection = blue.id; let noOpRevision = model.document.revision
        model.moveSelection(.front)
        precondition(model.document.revision == noOpRevision && model.history.canRedo, "No-op layer action consumed redo")
        model.redo(); try assertPixel(isBlue: false)
        model.selection = blue.id; model.moveSelection(.front); try assertPixel(isBlue: true)
        let beforeDuplicate = model.history.objects
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2)!
        precondition(canvas.performKeyEquivalent(with: key))
        let copy = model.selectedObject!
        precondition(copy.id != blue.id && model.history.objects.last == copy && copy.start == CGPoint(x: 112, y: 92) && copy.end == CGPoint(x: 192, y: 142))
        precondition(copy.fill == blue.fill && copy.stroke == blue.stroke && model.document.crop == doc.crop && model.document.resizedSize == doc.resizedSize)
        model.updateStyle(fill: EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 1, blue: 0)))
        precondition(model.history.objects.first(where: { $0.id == blue.id }) == blue, "Editing a copy modified its source")
        model.undo(); precondition(model.history.objects.last == copy)
        model.undo(); precondition(model.history.objects == beforeDuplicate)
        model.redo(); precondition(model.history.objects.last == copy, "Redo changed duplicate identity")
        model.selection = copy.id
        let unchanged = model.document
        model.isCanvasGestureActive = true; model.duplicateSelection(); model.moveSelection(.back)
        precondition(model.document == unchanged)
        model.isCanvasGestureActive = false; model.isShowingImageSize = true; model.duplicateSelection(); model.moveSelection(.back)
        precondition(model.document == unchanged)
        model.isShowingImageSize = false; model.cropDraft = model.originalRect; model.duplicateSelection(); model.moveSelection(.back)
        precondition(model.document == unchanged); model.cropDraft = nil
        model.selection = blur.id; model.moveSelection(.front)
        precondition(model.document == unchanged, "Blur crossed into the vector stratum")
        // Live text is finished before the object action; typing and duplication remain separate undo steps.
        let beforeText = model.history.objects
        model.editText(at: CGPoint(x: 50, y: 40)); model.updateText("Layer Text")
        let textID = model.selection!, typed = model.history.objects.last!
        model.duplicateSelection(); let textCopy = model.selectedObject!
        precondition(model.editingTextObject == nil && textCopy.id != textID && textCopy.text == "Layer Text")
        model.undo(); precondition(model.history.objects == beforeText + [typed])
        model.undo(); precondition(model.history.objects == beforeText)
        model.selection = copy.id; model.moveSelection(.back)
        for _ in 0..<300 where model.isDirty || model.isSaving { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!model.isDirty && model.saveError == nil, "Layer changes did not autosave")
        let expected = model.document, expectedPNG = try png()
        let loaded = try await ProjectStore(root: root).load(doc.id)
        precondition(loaded.document == expected && loaded.original == original)
        let listing = try await store.list()
        precondition(listing.items.first!.thumbnail == expectedPNG, "Saved preview differs from reordered PNG")
        let restored = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        precondition(restored.history.objects == expected.objects && !restored.history.canUndo)
        let board = NSPasteboard(name: NSPasteboard.Name("SnagForge-Layers-\(UUID())"))
        defer { board.releaseGlobally() }
        restored.copyPNG(to: board)
        for _ in 0..<1000 where restored.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(board.data(forType: .png) == expectedPNG, "Clipboard lost saved layer order")
        restored.selection = copy.id; restored.moveSelection(.front)
        let copySaved = await restored.saveCopy(); precondition(copySaved)
        let savedCopy = try await store.load(restored.document.id)
        precondition(savedCopy.document.objects == restored.history.objects && savedCopy.original == original)
        // The schema's object cap must never be exceeded by the duplicate action.
        let many = (0..<10_000).map { _ in EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 1, y: 1)) }
        let capped = EditorModel(image: image, document: ProjectDocument(title: "Limit", pixelSize: doc.pixelSize, objects: many), generation: 0, store: store, onSaved: {})
        capped.selection = many[0].id; precondition(!capped.canDuplicateSelection)
        capped.duplicateSelection(); precondition(capped.history.objects == many && !capped.isDirty)
        print("Layer checks passed: cropped/resized canvas picking and PNG overlap, blur stratum, one-step ordering/duplicate undo and redo identity, Cmd-D, independent styles, interaction guards, text-session boundaries, object cap, debounced autosave/reopen, identical thumbnail/private clipboard and save-copy preservation.")
    }
}
