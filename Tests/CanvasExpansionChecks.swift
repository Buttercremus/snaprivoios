import AppKit
import SnagForgeDomain

@MainActor enum CanvasExpansionChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasExpansion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
        for x in stride(from: 0, to: 128, by: 2) {
            context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: x, y: 0, width: 1, height: 96))
        }
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        let store = ProjectStore(root: root)
        let cases: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 100, y: 70), CGPoint(x: 175, y: 135)),
            (CGPoint(x: 25, y: 25), CGPoint(x: -35, y: -30)),
            (CGPoint(x: 25, y: 70), CGPoint(x: -35, y: 145)),
            (CGPoint(x: 100, y: 25), CGPoint(x: 180, y: -30))
        ]
        for (start, end) in cases {
            let document = ProjectDocument(title: "Canvas growth", pixelSize: PixelSize(width: 128, height: 96)!)
            try await store.create(document, original: original, thumbnail: nil)
            let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
            model.tool = .rectangle
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            let canvas = CanvasView(model: model); window.contentView = canvas
            canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
            model.setZoom(window.backingScaleFactor)
            func point(_ source: CGPoint) -> CGPoint {
                EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize,
                    in: canvas.bounds, backingScale: window.backingScaleFactor)).viewPoint(source)
            }
            func mouse(_ type: NSEvent.EventType, _ source: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(point(source), to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            let projectionBefore = point(.zero), viewport = model.viewport
            canvas.mouseDown(with: mouse(.leftMouseDown, start)); canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
            precondition(model.history.canvasRect == nil && model.document.outputRect == model.originalRect && model.history.objects.isEmpty,
                         "The canvas grew before mouse-up")
            precondition(point(.zero) == projectionBefore && model.viewport == viewport, "Drawing changed its own projection")
            let sample = point(CGPoint(x: end.x, y: (start.y + end.y) / 2))
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let ratio = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
            let ink = bitmap.colorAt(x: Int(sample.x * ratio), y: Int(sample.y * ratio))!.usingColorSpace(.sRGB)!
            precondition(ink.redComponent > 0.7 && ink.greenComponent < 0.4, "Overhanging ink was clipped during drawing")
            canvas.mouseUp(with: mouse(.leftMouseUp, end))
            let shape = model.history.objects[0], area = model.document.outputRect
            precondition(area.contains(EditorRenderer.paintedBounds(shape)) && area.contains(model.originalRect))
            precondition(model.history.canvasRect == area && model.tool == .rectangle && model.viewport == viewport)
            model.undo()
            precondition(model.history.objects.isEmpty && model.history.canvasRect == nil && !model.history.canUndo,
                         "Form and canvas growth need more than one undo")
            model.redo(); precondition(model.history.objects == [shape] && model.document.outputRect == area)

            model.selection = shape.id
            let grip = point(end), imageRect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let grips = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: grips)
            var visibleOuterGrip = false
            for y in -7...7 { for x in -7...7 {
                let sample = CGPoint(x: grip.x + CGFloat(x), y: grip.y + CGFloat(y))
                guard !imageRect.contains(sample) else { continue }
                let color = grips.colorAt(x: Int(sample.x * ratio), y: Int(sample.y * ratio))!.usingColorSpace(.sRGB)!
                if color.blueComponent > 0.7 && color.redComponent < 0.4 { visibleOuterGrip = true }
            } }
            precondition(visibleOuterGrip, "The enlarged canvas clipped the selected object's handles")

            let centre = CGPoint(x: shape.rect.midX, y: shape.rect.minY)
            let destination = CGPoint(x: centre.x + 160, y: centre.y + 120)
            model.selection = nil
            canvas.mouseDown(with: mouse(.leftMouseDown, centre)); canvas.mouseDragged(with: mouse(.leftMouseDragged, destination))
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false, keyCode: 53)!
            canvas.keyDown(with: escape); canvas.mouseUp(with: mouse(.leftMouseUp, destination))
            precondition(model.preview == nil && model.history.objects == [shape] && model.document.outputRect == area,
                         "Cancelling a preview changed the canvas")
            model.selection = nil
            canvas.mouseDown(with: mouse(.leftMouseDown, centre)); canvas.mouseDragged(with: mouse(.leftMouseDragged, destination))
            canvas.mouseUp(with: mouse(.leftMouseUp, destination))
            precondition(model.document.outputRect.contains(EditorRenderer.paintedBounds(model.history.objects[0])))
            model.undo(); precondition(model.history.objects == [shape] && model.document.outputRect == area)

            // Existing handles must extend the canvas too, in one reversible gesture.
            model.selection = shape.id
            let corner = CGPoint(x: shape.rect.maxX, y: shape.rect.maxY)
            let movedCorner = CGPoint(x: corner.x + 25, y: corner.y + 20)
            canvas.mouseDown(with: mouse(.leftMouseDown, corner)); canvas.mouseDragged(with: mouse(.leftMouseDragged, movedCorner))
            precondition(model.document.outputRect == area)
            canvas.mouseUp(with: mouse(.leftMouseUp, movedCorner))
            precondition(model.history.objects[0].rect.maxX == movedCorner.x && model.document.outputRect.contains(EditorRenderer.paintedBounds(model.history.objects[0])))
            model.undo(); precondition(model.history.objects == [shape] && model.document.outputRect == area)

            let saved = await model.flush(), loaded = try await store.load(document.id)
            precondition(saved && loaded.document.canvasRect == area && loaded.original == original)
            let restored = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        restored.snapsToObjects = false
            precondition(restored.sourceRect == area && restored.history.canvasRect == area)
            let share = restored.pngShareItem!
            let file = try await share.writeTemporaryPNG(in: root.appendingPathComponent("Share"))
            let shared = NSBitmapImageRep(data: try Data(contentsOf: file))!
            precondition(shared.pixelsWide == Int(area.width) && shared.pixelsHigh == Int(area.height))
            let pasteboard = NSPasteboard.withUniqueName(); restored.copyPNG(to: pasteboard)
            for _ in 0..<200 where restored.copyState == .copying { try await Task.sleep(for: .milliseconds(5)) }
            let sharedBytes = try Data(contentsOf: file)
            precondition(pasteboard.data(forType: .png) == sharedBytes, "Clipboard and shared PNG disagree")
            pasteboard.releaseGlobally()
            var excessive = shape; excessive.end.x = 40000
            restored.commit([excessive], expandingCanvas: true)
            precondition(restored.history.objects == [shape] && restored.document.outputRect == area && restored.notice != nil,
                         "Excessive growth committed a partial edit")
        }
        try checkExport(image: image, original: original)
        checkCropAndResize(image: image, store: store)
        print("Canvas expansion passed: four directions, visible overhang/stable projection during dragging, resize, atomic undo/redo, immutable original/reload, PNG/share/clipboard, transparency and limits.")
    }

    private static func checkCropAndResize(image: CGImage, store: ProjectStore) {
        let crop = CGRect(x: 20, y: 10, width: 80, height: 60), size = PixelSize(width: 160, height: 60)!
        let doc = ProjectDocument(title: "Cropped growth", pixelSize: PixelSize(width: 128, height: 96)!, crop: crop, resizedSize: size)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let shape = EditorObject(kind: .rectangle, start: CGPoint(x: -20, y: -30), end: CGPoint(x: 130, y: 110))
        model.commit([shape], expandingCanvas: true)
        precondition(model.document.outputRect == CGRect(x: -23, y: -33, width: 156, height: 146))
        precondition(model.document.outputPixelSize == PixelSize(width: 312, height: 146), "Growth lost unlocked output scaling")
        model.undo()
        precondition(model.document.crop == crop && model.document.resizedSize == size && model.document.canvasRect == nil && !model.history.canUndo)
        model.redo(); let canvas = model.document.fullCanvasRect
        model.beginCrop(); model.cropDraft = CGRect(x: -10, y: -10, width: 100, height: 80); model.applyCrop()
        precondition(model.document.crop?.origin == CGPoint(x: -10, y: -10) && model.document.fullCanvasRect == canvas)
        model.restoreOriginal()
        precondition(model.document.crop == nil && model.document.outputRect == canvas)
        var excessive = shape; excessive.end.x = 20000
        let before = model.document
        model.commit([excessive], expandingCanvas: true)
        precondition(model.document == before && model.notice != nil, "Output-scale overflow committed part of the gesture")
    }

    private static func checkExport(image: CGImage, original: Data) throws {
        let area = CGRect(x: -20, y: -15, width: 220, height: 170)
        let outside = EditorObject(kind: .rectangle, start: CGPoint(x: 155, y: 10), end: CGPoint(x: 180, y: 45))
        let png = try EditorRenderer.png(image: image, objects: [outside], canvasRect: area)
        let bitmap = NSBitmapImageRep(data: png)!, source = NSBitmapImageRep(data: original)!
        precondition(bitmap.pixelsWide == 220 && bitmap.pixelsHigh == 170)
        for y in 0..<96 { for x in 0..<128 {
            var a = [Int](repeating: 0, count: 4), b = a
            source.getPixel(&a, atX: x, y: y); bitmap.getPixel(&b, atX: x + 20, y: y + 15)
            precondition(a == b, "Canvas extension resampled original pixels at \(x),\(y)")
        } }
        precondition(bitmap.colorAt(x: 5, y: 5)!.alphaComponent == 0, "Transparent padding became opaque")
        precondition(bitmap.colorAt(x: 200, y: 40)!.redComponent > 0.7, "Overhanging object absent from PNG")
        let crop = CGRect(x: -10, y: -5, width: 200, height: 150)
        let cut = try EditorRenderer.render(image: image, objects: [outside], crop: crop, canvasRect: area)
        precondition(cut.width == 200 && cut.height == 150)
        let size = PixelSize(width: 440, height: 85)!
        let resized = try EditorRenderer.render(image: image, objects: [outside], resizedSize: size, canvasRect: area)
        precondition(resized.width == 440 && resized.height == 85)
        let thumb = NSBitmapImageRep(data: try EditorRenderer.thumbnail(image: image, objects: [outside], canvasRect: area))!
        precondition(thumb.pixelsWide == 220 && thumb.pixelsHigh == 170)
        let archiveDocument = ProjectDocument(title: "Canvas", pixelSize: PixelSize(width: 128, height: 96)!, objects: [outside], canvasRect: area)
        let archive = try ProjectArchive(document: archiveDocument, original: original)
        let restored = try archive.validatedDocument()
        precondition(restored.canvasRect == area)
    }
}
