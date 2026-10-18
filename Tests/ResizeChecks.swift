import AppKit
import SnagForgeDomain

@main struct ResizeChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        try checkVectorSharpness()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Resize-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var pixels = [UInt8](repeating: 0, count: 640 * 480 * 4)
        for y in 0..<480 { for x in 0..<640 {
            let index = (y * 640 + x) * 4
            pixels[index] = y < 240 ? 255 : 0; pixels[index + 2] = y < 240 ? 0 : 255
            pixels[index + 3] = x < 20 ? 0 : 255
        } }
        let image = CGImage(width: 640, height: 480, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 2560,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 80, y: 120), end: CGPoint(x: 220, y: 180), lineWidth: 16)
        arrow.color = EditorColor(red: 0, green: 1, blue: 0)
        let text = EditorObject(kind: .text, start: CGPoint(x: 80, y: 260), text: "Hallo Resize", fontSize: 32, textWidth: 220)
        let crop = CGRect(x: 0, y: 80, width: 480, height: 320), size = PixelSize(width: 240, height: 80)!
        let original = try EditorRenderer.png(image: image, objects: [])
        let store = ProjectStore(root: root)
        let doc = ProjectDocument(title: "Resize (synthetisch)", pixelSize: PixelSize(width: 640, height: 480)!, objects: [arrow, text], crop: crop)
        try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        precondition(model.applyImageSize(size) && model.document.objects == doc.objects && model.document.crop == crop)
        let revision = model.document.revision
        precondition(model.applyImageSize(size) && model.document.revision == revision, "Same size created another undo/save")
        precondition(!model.applyImageSize(PixelSize(width: 32769, height: 100)!) && model.document.revision == revision)
        model.undo(); precondition(model.document.resizedSize == nil && !model.history.canUndo)
        model.redo(); precondition(model.document.outputPixelSize == size)
        let png = try EditorRenderer.png(image: image, objects: model.history.objects, crop: crop, resizedSize: size)
        let bitmap = NSBitmapImageRep(data: png)!
        precondition(bitmap.pixelsWide == 240 && bitmap.pixelsHigh == 80)
        func color(_ x: Int, _ y: Int) -> NSColor { bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)! }
        precondition(color(150, 10).redComponent > 0.9 && color(150, 70).blueComponent > 0.9, "Resized crop flipped")
        precondition(color(2, 20).alphaComponent < 0.01, "Resize lost transparency")
        precondition(color(70, 16).greenComponent > 0.85, "Arrow did not scale with the image")
        let thumb = NSBitmapImageRep(data: try EditorRenderer.thumbnail(image: image, objects: doc.objects, crop: crop, resizedSize: PixelSize(width: 960, height: 160)))!
        precondition(thumb.pixelsWide == 420 && thumb.pixelsHigh == 70, "Thumbnail ignored output aspect ratio")
        let identity = try EditorRenderer.png(image: image, objects: doc.objects, crop: crop, resizedSize: PixelSize(width: 480, height: 320))
        let unscaled = try EditorRenderer.png(image: image, objects: doc.objects, crop: crop)
        precondition(identity == unscaled, "100% altered pixels")
        do { _ = try EditorRenderer.png(image: image, objects: [], resizedSize: PixelSize(width: 10001, height: 10000)); preconditionFailure("Invalid output exported") }
        catch EditorRenderer.ExportError.render { }

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeViewport(); window.makeFirstResponder(canvas)
        func projection() -> EditorImageProjection {
            EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
        }
        func event(_ type: NSEvent.EventType, _ source: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(projection().viewPoint(source), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        for zoom: CGFloat in [0, 1, 4] {
            if zoom == 0 { model.fitImage() } else { model.setZoom(zoom) }
            model.tool = .selection; model.selection = arrow.id
            let end = CGPoint(x: 240, y: 200)
            canvas.mouseDown(with: event(.leftMouseDown, arrow.end)); canvas.mouseDragged(with: event(.leftMouseDragged, end))
            precondition(model.preview?.first.map { hypot($0.end.x - end.x, $0.end.y - end.y) < 0.001 } == true && model.history.objects.first == arrow, "Resized arrow preview/coordinates failed at \(zoom): \(String(describing: model.preview?.first))")
            canvas.mouseUp(with: event(.leftMouseUp, end))
            precondition(model.history.objects.first?.start == arrow.start && model.history.objects.first.map { hypot($0.end.x - end.x, $0.end.y - end.y) < 0.001 } == true)
            model.undo(); precondition(model.history.objects.first == arrow && model.document.resizedSize == size)
        }
        model.fitImage(); model.tool = .rectangle
        let shapeStart = CGPoint(x: 300, y: 120), shapeEnd = CGPoint(x: 420, y: 200), shapeNext = CGPoint(x: 440, y: 220)
        canvas.mouseDown(with: event(.leftMouseDown, shapeStart)); canvas.mouseDragged(with: event(.leftMouseDragged, shapeEnd))
        precondition(model.preview?.last.map { hypot($0.end.x - shapeEnd.x, $0.end.y - shapeEnd.y) < 0.001 } == true, "Shape preview missed the pointer after resize")
        canvas.mouseUp(with: event(.leftMouseUp, shapeEnd)); model.tool = .selection; model.selection = model.history.objects.last!.id
        canvas.mouseDown(with: event(.leftMouseDown, shapeEnd)); canvas.mouseUp(with: event(.leftMouseUp, shapeNext))
        precondition(model.history.objects.last.map { hypot($0.end.x - shapeNext.x, $0.end.y - shapeNext.y) < 0.001 } == true, "Shape handle failed after nonuniform resize")
        model.undo(); model.undo(); precondition(model.history.objects == doc.objects)
        model.fitImage(); model.tool = .text
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 90, y: 270), clicks: 2))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 90, y: 270), clicks: 2))
        let editor = canvas.subviews.first!.subviews.first as! NSTextView
        precondition(editor.selectedRange().length == 5, "Word selection failed after nonuniform resize")
        let textProjection = projection()
        precondition(abs(editor.frame.width / editor.bounds.width - textProjection.scaleX) < 0.001 &&
                     abs(editor.frame.height / editor.bounds.height - textProjection.scaleY) < 0.001, "Text view scale differs from PNG")
        editor.insertText("Guten", replacementRange: NSRange(location: NSNotFound, length: 0)); editor.breakUndoCoalescing()
        editor.undoManager?.undo()
        precondition(model.history.objects.last?.text == text.text, "Native text undo failed after resize")
        model.finishTextEditing(); canvas.synchronizeTextEditor(); window.makeFirstResponder(canvas)
        model.beginCrop(); model.cropDraft = CGRect(x: 0, y: 0, width: 640, height: 480); model.applyCrop()
        precondition(model.document.outputPixelSize == PixelSize(width: 320, height: 120), "Crop did not preserve resize factors")
        model.undo(); precondition(model.document.crop == crop && model.document.resizedSize == size)
        model.beginImageResize(); let unchanged = model.document
        model.undo(); precondition(model.document == unchanged, "Sheet let document undo run behind it")
        model.isShowingImageSize = false
        let saved = await model.flush(); precondition(saved)
        let loaded = try await ProjectStore(root: root).load(doc.id)
        precondition(loaded.document == model.document && loaded.original == original)
        let listing = try await store.list()
        let savedThumb = NSBitmapImageRep(data: listing.items.first!.thumbnail!)!
        precondition(savedThumb.pixelsWide == 240 && savedThumb.pixelsHigh == 80, "Autosave thumbnail lost resize")
        let restored = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        precondition(restored.document.outputPixelSize == size && restored.history.objects == doc.objects)
        var redundant = doc; redundant.resizedSize = PixelSize(width: 480, height: 320)
        let normalized = EditorModel(image: image, document: redundant, generation: 0, store: store, onSaved: {})
        normalized.beginCrop(); normalized.applyCrop()
        precondition(normalized.document.resizedSize == nil && normalized.history.resizedSize == nil && normalized.document.revision == 1,
                     "Crop normalization left document and history out of sync")
        let normalizedSaved = await normalized.saveCopy(); precondition(normalizedSaved)
        let board = NSPasteboard(name: NSPasteboard.Name("SnagForge-Resize-\(UUID())"))
        defer { board.releaseGlobally() }
        restored.copyPNG(to: board)
        for _ in 0..<1000 where restored.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!restored.isExporting && board.data(forType: .png) == png, "Clipboard differs after restart")
        let copied = await restored.saveCopy(); precondition(copied, "Saving resized project as copy failed")
        let copy = try await store.load(restored.document.id)
        precondition(copy.document.id != doc.id && copy.document.resizedSize == size && copy.original == original)
        print("Resize checks passed: crop/resize/identity PNG, orientation/alpha/arrow pixels, thumbnail aspect, limits, live arrow editing at fit/100%/400%, scaled native word selection and undo, shared crop/history, autosave/reopen, private PNG clipboard and save-copy original preservation.")
    }

    static func checkVectorSharpness() throws {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        var outline = EditorObject(kind: .rectangle, start: CGPoint(x: 32.5, y: 8.5), end: CGPoint(x: 50.5, y: 30.5), lineWidth: 1)
        outline.color = EditorColor(red: 0, green: 0, blue: 0)
        var text = EditorObject(kind: .text, start: CGPoint(x: 4, y: 4), text: "HI", fontSize: 14)
        text.color = outline.color
        let image = context.makeImage()!
        for crop in [CGRect(x: 0, y: 0, width: 64, height: 48), CGRect(x: 2, y: 2, width: 60, height: 44)] {
            let size = PixelSize(width: Int(crop.width * 2), height: Int(crop.height * 2))!
            let bitmap = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [outline, text], crop: crop, resizedSize: size))!
            let shiftX = Int(crop.minX * 2), shiftY = Int(crop.minY * 2)
            func red(_ x: Int, _ y: Int) -> Int {
                var rgba = [Int](repeating: 0, count: 4)
                bitmap.getPixel(&rgba, atX: x - shiftX, y: y - shiftY)
                return rgba[0]
            }
            precondition(red(63, 40) == 255 && red(64, 40) == 0 && red(65, 40) == 0 && red(66, 40) == 255,
                         "Vector edge was scaled from an intermediate bitmap instead of rasterized at output resolution")
            // A straight glyph stem needs at most one antialiased pixel at each edge.
            // Scaling already rasterized 14px text to 28px produces a wider grey fringe.
            let stem = (8..<15).map { red($0, 24) }
            precondition(stem.contains(0) && stem.filter { $0 > 0 && $0 < 255 }.count <= 2,
                         "Exported text has a resampled grey fringe around its vertical stem")
        }
        print("Vector sharpness checks passed: cropped/uncropped 200% PNG renders crisp vector edges and text stems at destination resolution.")
    }
}
