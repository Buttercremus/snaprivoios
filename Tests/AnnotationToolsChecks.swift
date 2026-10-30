import AppKit
import SnagForgeDomain

enum AnnotationToolsChecks {
    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-AnnotationTools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let ctx = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        ctx.translateBy(x: 0, y: 480); ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 330, y: 235, width: 10, height: 10))
        let image = ctx.makeImage()!, store = ProjectStore(root: root)
        let doc = ProjectDocument(title: "Synthetic annotations", pixelSize: PixelSize(width: 640, height: 480)!, resizedSize: PixelSize(width: 960, height: 480)!)
        try await store.create(doc, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame.size = CGSize(width: 800, height: 600)
        canvas.synchronizeViewport()
        func local(_ point: CGPoint) -> CGPoint {
            EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds,
                backingScale: window.backingScaleFactor)).viewPoint(point)
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(local(point), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        // Bending is live, preserves both endpoints, and is a single undo step.
        for style in EditorDrawingStyle.allCases {
            var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 60, y: 70), end: CGPoint(x: 460, y: 70), lineWidth: 6)
            arrow.drawingStyle = style
            model.history = EditorHistory(objects: [arrow], resizedSize: PixelSize(width: 960, height: 480)!)
            model.selection = arrow.id; model.tool = .selection; model.setZoom(1.25)
            let handle = EditorArrow.bendHandle(for: arrow), target = CGPoint(x: handle.x, y: handle.y + 65)
            precondition(canvas.canvasCursor(at: local(handle)) === NSCursor.crosshair)
            canvas.mouseDown(with: mouse(.leftMouseDown, handle)); canvas.mouseDragged(with: mouse(.leftMouseDragged, target))
            let live = model.preview![0]
            precondition(live.start == arrow.start && live.end == arrow.end && live.hitsArrow(target, tolerance: 1))
            precondition(model.history.objects == [arrow] && !model.hasExportableImage)
            canvas.mouseUp(with: mouse(.leftMouseUp, target))
            let bent = model.history.objects[0]
            precondition(bent.arrowBend != nil && model.hasExportableImage)
            model.undo(); precondition(model.history.objects == [arrow]); model.redo(); model.selection = arrow.id
            precondition(model.history.objects == [bent])
            canvas.mouseDown(with: mouse(.leftMouseDown, target)); canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: target.x, y: target.y + 30)))
            canvas.keyDown(with: escape); precondition(model.preview == nil && model.history.objects == [bent])
            model.selection = arrow.id; model.straightenArrow()
            precondition(model.history.objects[0].hitsArrow(CGPoint(x: 260, y: 70), tolerance: 1))
        }
        // Drawing a callout shows its complete body before the first character, in either direction.
        model.history = EditorHistory(); model.tool = .callout; model.fitImage()
        for (a, b) in [
            (CGPoint(x: 70, y: 60), CGPoint(x: 300, y: 180)),
            (CGPoint(x: 300, y: 180), CGPoint(x: 70, y: 60)),
            (CGPoint(x: 70, y: 180), CGPoint(x: 300, y: 60)),
            (CGPoint(x: 300, y: 60), CGPoint(x: 70, y: 180))
        ] {
            canvas.mouseDown(with: mouse(.leftMouseDown, a)); canvas.mouseDragged(with: mouse(.leftMouseDragged, b))
            let callout = model.editingTextObject!, box = EditorRenderer.calloutBox(callout)
            precondition(callout.text.isEmpty && callout.calloutTip == a)
            precondition(!box.contains(a), "The anchored tip must stay outside the body")
            precondition(abs(box.width - (230 - 24 * 230 / hypot(230, 120))) < 0.001)
            precondition(abs(box.height - (120 - 24 * 120 / hypot(230, 120))) < 0.001)
            precondition(window.firstResponder === canvas, "Dragging must not focus the text editor")
            precondition(model.objects.contains(where: { $0.id == callout.id }), "The body must be visible during drawing")
            canvas.mouseUp(with: mouse(.leftMouseUp, b))
            precondition(model.editingTextObject?.id == callout.id && window.firstResponder is NSTextView)
            model.finishTextEditing(); canvas.synchronizeTextEditor()
            precondition(model.history.objects == [callout], "An intentionally empty callout must remain visible")
            model.undo(); precondition(model.history.objects.isEmpty); model.redo(); precondition(model.history.objects == [callout])
            model.commit([])
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 70, y: 60)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 180)))
        canvas.keyDown(with: escape); canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 180)))
        precondition(model.history.objects.isEmpty && model.editingTextObject == nil)
        canvas.synchronizeTextEditor()
        // Lenses preview while drawing, stay round when resizing, and keep their zoom after reload.
        model.tool = .magnifier
        precondition(!model.activeMagnifierOffset)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 240, y: 160)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 400, y: 280)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 280)))
        let normal = model.history.objects[0]
        precondition(normal.magnifierSource == nil && normal.rect.size == CGSize(width: 160, height: 160))
        model.updateMagnifierOffset(true)
        precondition(model.history.objects[0].magnifierSource == CGPoint(x: normal.rect.midX, y: normal.rect.midY))
        model.updateMagnifierOffset(false)
        precondition(model.history.objects[0] == normal)
        model.undo(); precondition(model.history.objects[0].magnifierSource != nil)
        model.redo(); precondition(model.history.objects[0] == normal)
        model.commit([]); model.selection = nil
        model.updateMagnifierOffset(true)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 240, y: 160)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 400, y: 280)))
        precondition(model.preview?.last?.magnifierSource == CGPoint(x: 240, y: 160))
        precondition(model.preview?.last?.rect.midX == 400 && model.preview?.last?.rect.midY == 280)
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 280)))
        let lens = model.history.objects[0]
        precondition(lens.kind == .magnifier && lens.effectiveMagnification == 2)
        model.updateMagnification(3); model.undo(); precondition(model.history.objects[0].effectiveMagnification == 2)
        model.redo(); precondition(model.history.objects[0].effectiveMagnification == 3)
        let corner = lens.end
        canvas.mouseDown(with: mouse(.leftMouseDown, corner)); canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: corner.x + 30, y: corner.y + 10)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: corner.x + 30, y: corner.y + 10)))
        precondition(abs(model.history.objects[0].rect.width - model.history.objects[0].rect.height) < 0.000001, "Lens aspect ratio changed: \(model.history.objects[0].rect)")
        model.undo(); precondition(model.history.objects[0].rect == lens.rect)
        let beforeMove = model.history.objects[0]
        let center = CGPoint(x: beforeMove.rect.midX, y: beforeMove.rect.midY)
        let target = CGPoint(x: center.x + 25, y: center.y + 15)
        canvas.mouseDown(with: mouse(.leftMouseDown, center)); canvas.mouseDragged(with: mouse(.leftMouseDragged, target))
        canvas.mouseUp(with: mouse(.leftMouseUp, target))
        precondition(model.history.objects[0].magnifierSource == beforeMove.magnifierSource)
        precondition(model.history.objects[0].rect.midX == center.x + 25)
        let source = beforeMove.magnifierSource!, newSource = CGPoint(x: source.x - 20, y: source.y - 10)
        let movedRect = model.history.objects[0].rect
        canvas.mouseDown(with: mouse(.leftMouseDown, source)); canvas.mouseDragged(with: mouse(.leftMouseDragged, newSource))
        canvas.mouseUp(with: mouse(.leftMouseUp, newSource))
        precondition(model.history.objects[0].magnifierSource == newSource && model.history.objects[0].rect == movedRect)
        model.undo(); precondition(model.history.objects[0].magnifierSource == source); model.redo()
        let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(doc.id)
        precondition(loaded.document.objects == model.history.objects)
        // Mode switching at the right edge must include the entire lens in the output.
        for cropped in [false, true] {
            var edge = EditorObject(kind: .magnifier, start: CGPoint(x: 520, y: 160), end: CGPoint(x: 620, y: 260), lineWidth: 4)
            edge.color = EditorColor(red: 0, green: 0, blue: 0)
            let edgeDoc = ProjectDocument(title: "Edge lens", pixelSize: PixelSize(width: 640, height: 480)!, objects: [edge],
                crop: cropped ? CGRect(x: 400, y: 100, width: 240, height: 240) : nil,
                resizedSize: cropped ? PixelSize(width: 480, height: 360)! : nil)
            try await store.create(edgeDoc, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
            let edgeModel = EditorModel(image: image, document: edgeDoc, generation: 0, store: store, onSaved: {})
            edgeModel.selection = edge.id
            edgeModel.updateMagnifierOffset(true)
            let shifted = edgeModel.history.objects[0], area = edgeModel.document.outputRect
            precondition(shifted.magnifierSource == CGPoint(x: 570, y: 210))
            precondition(area.contains(EditorRenderer.paintedBounds(shifted)), "Mode switch clips lens ink at the right edge")
            let expandedCanvas = edgeModel.history.canvasRect, expandedCrop = edgeModel.history.crop, expandedSize = edgeModel.history.resizedSize
            edgeModel.undo()
            precondition(edgeModel.history.objects == [edge] && edgeModel.history.canvasRect == nil && edgeModel.history.crop == edgeDoc.crop && edgeModel.history.resizedSize == edgeDoc.resizedSize)
            edgeModel.redo()
            precondition(edgeModel.history.objects == [shifted] && edgeModel.history.canvasRect == expandedCanvas && edgeModel.history.crop == expandedCrop && edgeModel.history.resizedSize == expandedSize)
            let didSave = await edgeModel.flush(); precondition(didSave)
            let reopened = try await store.load(edgeDoc.id)
            precondition(reopened.document == edgeModel.document)
            let png = try EditorRenderer.png(image: image, objects: reopened.document.objects, crop: reopened.document.crop,
                resizedSize: reopened.document.resizedSize, canvasRect: reopened.document.canvasRect)
            let bitmap = NSBitmapImageRep(data: png)!
            let x = Int((shifted.rect.maxX - 1 - area.minX) * CGFloat(bitmap.pixelsWide) / area.width)
            let y = Int((shifted.rect.midY - area.minY) * CGFloat(bitmap.pixelsHigh) / area.height)
            let rim = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            precondition(rim.alphaComponent > 0.9 && rim.redComponent < 0.3, "Export lost the right lens rim")
        }
        try checkRendering(image: image)
        print("Annotation checks passed: live bends in every style at nonuniform scale, cancel/undo/straighten; empty live callouts and reverse drags; magnifier create/resize/zoom/reload; enlarged pixels, masks and cropped/resized exports.")
    }

    private static func checkRendering(image: CGImage) throws {
        var lens = EditorObject(kind: .magnifier, start: CGPoint(x: 240, y: 160), end: CGPoint(x: 400, y: 320), lineWidth: 3)
        lens.magnification = 2
        func color(_ image: CGImage, x: Int, y: Int) -> NSColor { EditorRenderer.pixelColor(image, x: x, y: y)! }
        let magnified = try EditorRenderer.render(image: image, objects: [lens])
        precondition(color(image, x: 355, y: 240).redComponent > 0.9)
        precondition(color(magnified, x: 355, y: 240).blueComponent > 0.9 && color(magnified, x: 355, y: 240).redComponent < 0.1)
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 329, y: 234), end: CGPoint(x: 341, y: 246))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        let masked = try EditorRenderer.render(image: image, objects: [lens, mask])
        let black = color(masked, x: 355, y: 240)
        precondition(black.redComponent < 0.1 && black.greenComponent < 0.1 && black.blueComponent < 0.1, "Lens revealed masked source pixels")
        var offset = lens
        offset.magnifierSource = CGPoint(x: 335, y: 240)
        offset.start = CGPoint(x: 40, y: 40); offset.end = CGPoint(x: 160, y: 160)
        let offsetImage = try EditorRenderer.render(image: image, objects: [offset])
        precondition(color(offsetImage, x: 100, y: 100).blueComponent > 0.9)
        let offsetMasked = try EditorRenderer.render(image: image, objects: [offset, mask])
        let protected = color(offsetMasked, x: 100, y: 100)
        precondition(protected.redComponent < 0.1 && protected.blueComponent < 0.1, "Offset lens revealed redacted pixels")
        let cropped = try EditorRenderer.render(image: image, objects: [lens, mask], crop: CGRect(x: 200, y: 120, width: 240, height: 240), resizedSize: PixelSize(width: 480, height: 360)!)
        let resizedBlack = color(cropped, x: 310, y: 180)
        precondition(resizedBlack.redComponent < 0.1 && resizedBlack.blueComponent < 0.1)
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 60, y: 70), end: CGPoint(x: 460, y: 70), lineWidth: 5)
        arrow.arrowBend = CGPoint(x: 260, y: 180)
        let bent = try EditorRenderer.render(image: image, objects: [arrow])
        precondition(color(bent, x: 260, y: 180).greenComponent < 0.4 && color(bent, x: 260, y: 70).greenComponent > 0.9)
        var outputs = Set<Data>()
        for style in EditorDrawingStyle.allCases {
            var sample = EditorObject(kind: .ellipse, start: CGPoint(x: 60, y: 260), end: CGPoint(x: 200, y: 400), lineWidth: 4)
            sample.drawingStyle = style
            outputs.insert(try EditorRenderer.png(image: image, objects: [sample]))
        }
        precondition(outputs.count == EditorDrawingStyle.allCases.count, "Drawing styles must have distinct output")
        let blank = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        blank.setFillColor(NSColor.white.cgColor); blank.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        var samples: [EditorObject] = []
        for (index, style) in EditorDrawingStyle.allCases.enumerated() {
            let y = CGFloat(index) * 116 + 30
            var line = EditorObject(kind: .arrow, start: CGPoint(x: 35, y: y + 15), end: CGPoint(x: 280, y: y + 15), lineWidth: 5)
            line.drawingStyle = style; line.arrowBend = CGPoint(x: 160, y: y + 48)
            var shape = EditorObject(kind: .ellipse, start: CGPoint(x: 340, y: y), end: CGPoint(x: 455, y: y + 68), lineWidth: 4)
            shape.drawingStyle = style
            var rectangle = EditorObject(kind: .rectangle, start: CGPoint(x: 500, y: y), end: CGPoint(x: 610, y: y + 68), lineWidth: 4)
            rectangle.drawingStyle = style; rectangle.cornerRadius = 16
            let label = EditorObject(kind: .text, start: CGPoint(x: 35, y: y - 18), text: style.rawValue, fontSize: 14)
            samples += [line, shape, rectangle, label]
        }
        let preview = try EditorRenderer.png(image: blank.makeImage()!, objects: samples)
        let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/CanvasTests/AnnotationStyles.png")
        try preview.write(to: destination)
    }
}
