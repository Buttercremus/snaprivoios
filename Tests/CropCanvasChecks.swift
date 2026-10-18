import AppKit
import SnagForgeDomain

/// Only synthetic events directed to an offscreen view; no system mouse/keyboard injection.
@MainActor enum CropCanvasChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Crop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 280, y: 200), end: CGPoint(x: 350, y: 240))
        let doc = ProjectDocument(title: "Crop-Test", pixelSize: PixelSize(width: 640, height: 480)!, objects: [arrow])
        try await store.create(doc, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame.size = CGSize(width: 800, height: 600)
        canvas.synchronizeViewport(); window.makeFirstResponder(canvas)
        func event(_ type: NSEvent.EventType, _ pixel: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            let area = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let scale = area.width / model.sourceRect.width
            let local = CGPoint(x: area.minX + (pixel.x - model.sourceRect.minX) * scale,
                                y: area.minY + (pixel.y - model.sourceRect.minY) * scale)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: modifiers, timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ code: UInt16, _ char: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                             context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false, keyCode: code)!
        }
        let crop = CGRect(x: 200, y: 150, width: 240, height: 180)
        for zoom: CGFloat in [0, 1, 4] {
            model.beginCrop()
            if zoom != 0 { model.setZoom(zoom); model.panImage(by: CGSize(width: 22, height: -16)) }
            let revision = model.document.revision
            // Reverse direction must produce the same integer rectangle and a live mask.
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: crop.maxX, y: crop.maxY)))
            canvas.mouseDragged(with: event(.leftMouseDragged, crop.origin))
            precondition(model.cropDraft == crop && model.history.crop == nil && model.document.revision == revision, "Crop draft committed too early")
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let area = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let ratio = CGFloat(bitmap.pixelsWide) / canvas.bounds.width, scale = area.width / model.imageSize.width
            // At fit the discarded original pixels are dimmed while the kept pixels stay white.
            if zoom == 0 {
                let outside = bitmap.colorAt(x: Int((area.minX + 100 * scale) * ratio), y: Int((area.minY + 100 * scale) * ratio))!.usingColorSpace(.deviceRGB)!
                let inside = bitmap.colorAt(x: Int((area.minX + 220 * scale) * ratio), y: Int((area.minY + 170 * scale) * ratio))!.usingColorSpace(.deviceRGB)!
                precondition(outside.redComponent < 0.7 && inside.redComponent > 0.95, "Live crop mask missing")
            }
            model.applyCrop(); precondition(model.history.crop == nil, "Crop applied in the middle of a drag")
            canvas.mouseUp(with: event(.leftMouseUp, crop.origin))
            for handle in EditorResizeHandle.allCases {
                model.cropDraft = crop
                let from = handle.point(in: crop), delta = CGSize(width: 10, height: 12)
                let to = CGPoint(x: from.x + delta.width, y: from.y + delta.height)
                canvas.mouseDown(with: event(.leftMouseDown, from))
                canvas.mouseDragged(with: event(.leftMouseDragged, to))
                precondition(model.cropDraft == EditorCrop.resized(crop, handle: handle, by: delta, in: doc.pixelSize), "Crop handle failed at zoom \(zoom)")
                canvas.mouseUp(with: event(.leftMouseUp, to))
            }
            precondition(!model.isCanvasGestureActive && model.canApplyCrop, "Crop controls stayed disabled after resize")
            model.cropDraft = crop
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 290, y: 220)))
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 310, y: 230)))
            precondition(model.cropDraft == crop.offsetBy(dx: 20, dy: 10), "Crop did not move independently of annotations")
            // Option permits a new frame even when the pointer starts inside the existing one.
            canvas.mouseDown(with: event(.leftMouseDown, crop.origin, modifiers: .option))
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: crop.maxX, y: crop.maxY), modifiers: .option))
            precondition(model.cropDraft == crop)
            canvas.keyDown(with: key(36, "\r"))
            precondition(model.document.crop == crop && model.history.objects == [arrow] && model.cropDraft == nil && !model.isCanvasGestureActive)
            precondition(canvas.performKeyEquivalent(with: key(6, "z", modifiers: .command)))
            precondition(model.document.crop == nil && !model.history.canUndo, "Crop is not one undo step")
            precondition(canvas.performKeyEquivalent(with: key(6, "z", modifiers: [.command, .shift])))
            precondition(model.document.crop == crop && model.history.objects == [arrow])
            model.undo() // reset the loop baseline
        }
        model.setZoom(1); let previousViewport = model.viewport, revision = model.document.revision
        model.beginCrop(); model.cropDraft = crop
        canvas.keyDown(with: key(53, "\u{1B}"))
        precondition(model.cropDraft == nil && model.document.crop == nil && model.viewport == previousViewport && model.document.revision == revision, "Cancel changed the saved crop or view")
        model.beginCrop(); model.cropDraft = crop; model.applyCrop()
        // Hidden handles must not react through the gray margin after cropping.
        let hiddenArrow = EditorObject(kind: .arrow, start: CGPoint(x: 190, y: 220), end: CGPoint(x: 300, y: 250))
        model.commit([hiddenArrow]); model.selection = hiddenArrow.id; model.tool = .selection
        canvas.mouseDown(with: event(.leftMouseDown, hiddenArrow.start))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 220, y: 220)))
        precondition(model.history.objects == [hiddenArrow], "An invisible arrow handle remained interactive outside the crop")
        model.undo(); model.selection = nil
        let point = CGPoint(x: 260, y: 180), end = CGPoint(x: 390, y: 280)
        model.tool = .rectangle
        canvas.mouseDown(with: event(.leftMouseDown, point)); canvas.mouseUp(with: event(.leftMouseUp, end))
        let shape = model.history.objects.last!
        precondition(hypot(shape.start.x - point.x, shape.start.y - point.y) < 0.001 && shape.end == end, "Drawing after crop rebased the original coordinates")
        model.selection = shape.id
        model.tool = .selection
        let resized = CGPoint(x: 410, y: 290)
        canvas.mouseDown(with: event(.leftMouseDown, end)); canvas.mouseUp(with: event(.leftMouseUp, resized))
        precondition(model.history.objects.last?.end == resized, "Shape handle failed after crop")
        model.undo(); precondition(model.history.objects.last == shape && model.document.crop == crop)
        model.tool = .text
        let textPoint = CGPoint(x: crop.maxX - 20, y: crop.minY + 12)
        canvas.mouseDown(with: event(.leftMouseDown, textPoint)); canvas.mouseUp(with: event(.leftMouseUp, textPoint))
        let clip = canvas.subviews.first!, text = clip.subviews.first as! NSTextView
        text.insertText("Text am Rand", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(hypot(model.history.objects.last!.start.x - textPoint.x, model.history.objects.last!.start.y - textPoint.y) < 0.001)
        precondition(clip.layer?.masksToBounds == true && text.frame.maxX > clip.bounds.maxX, "Inline text is not clipped to crop")
        model.finishTextEditing(); canvas.synchronizeTextEditor()
        // Exercise the actual asynchronous copy path on a private pasteboard.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SnagForge-Crop-Test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        model.copyPNG(to: pasteboard)
        for _ in 0..<500 where model.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!model.isExporting && model.error == nil)
        let copied = pasteboard.data(forType: .png)!
        let expected = try EditorRenderer.png(image: image, objects: model.history.objects, crop: crop)
        precondition(copied == expected, "Clipboard differs from PNG crop output")
        let copyBitmap = NSBitmapImageRep(data: copied)!
        precondition(copyBitmap.pixelsWide == Int(crop.width) && copyBitmap.pixelsHigh == Int(crop.height))
        model.beginCrop(); model.cropDraft = model.originalRect
        let copyCount = pasteboard.changeCount
        model.copyPNG(to: pasteboard)
        precondition(!model.isExporting && pasteboard.changeCount == copyCount, "Unconfirmed crop was copied")
        model.cancelCrop()
        let committed = model.history.objects
        model.beginCrop(); precondition(model.sourceRect == model.originalRect && model.cropDraft == crop)
        model.restoreOriginal(); model.applyCrop()
        precondition(model.document.crop == nil && model.history.objects == committed, "Restoring original removed annotations")
        model.undo(); precondition(model.document.crop == crop && model.history.objects == committed)
        let saved = await model.flush(); precondition(saved)
        let loaded = try await ProjectStore(root: root).load(doc.id)
        let reopened = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        precondition(reopened.sourceRect == crop && reopened.history.objects == committed && !reopened.history.canUndo)
        reopened.beginCrop(); reopened.cropDraft = CGRect(x: 100, y: 80, width: 400, height: 300); reopened.applyCrop(); reopened.undo()
        precondition(reopened.document.crop == crop, "Reopened crop cannot be adjusted and undone")
        _ = await reopened.flush()
        print("Crop canvas checks passed: live reverse crop at fit/100/400%, all 8 handles, move/new-frame, confirm/cancel/one-step undo, cropped drawing/resize/text clipping, original recovery/restart and asynchronous PNG/clipboard equality.")
    }
}
