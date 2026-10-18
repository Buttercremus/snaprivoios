import AppKit
import SnagForgeDomain

/// Synthetic native events are delivered only to an offscreen test view.
@MainActor enum ZoomCanvasChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Zoom-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        context.setStrokeColor(NSColor.lightGray.cgColor); context.setLineWidth(2)
        for x in stride(from: 0, through: 3840, by: 120) { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: 2160)) }
        for y in stride(from: 0, through: 2160, by: 120) { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: 3840, y: y)) }
        context.strokePath()
        for (index, color) in [NSColor.blue, .green, .orange, .purple].enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: index % 2 == 0 ? 0 : 3600, y: index < 2 ? 0 : 1920, width: 240, height: 240))
        }
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let png = try EditorRenderer.png(image: image, objects: [])
        try png.write(to: URL(fileURLWithPath: "/tmp/SnagForge-Zoom-Abnahme-3840.png"), options: .atomic)
        let document = ProjectDocument(title: "Zoom-Abnahme (synthetisch)", pixelSize: PixelSize(width: 3840, height: 2160)!)
        try await store.create(document, original: png, thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model)
        window.contentView = canvas; canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeViewport(); window.makeFirstResponder(canvas)
        func mouse(_ type: NSEvent.EventType, _ local: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func point(_ pixel: CGPoint) -> CGPoint {
            let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let scale = rect.width / model.imageSize.width
            return CGPoint(x: rect.minX + pixel.x * scale, y: rect.minY + pixel.y * scale)
        }
        func event(_ type: NSEvent.EventType, _ pixel: CGPoint, clicks: Int = 1) -> NSEvent { mouse(type, point(pixel), clicks: clicks) }
        func key(_ code: UInt16, _ character: String, type: NSEvent.EventType = .keyDown, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 0.001 }
        for zoom: CGFloat in [0, 0.5, 1, 4] {
            model.fitImage()
            if zoom > 0 { model.setZoom(zoom) }
            model.panImage(by: CGSize(width: 35, height: -25))
            model.commit([]); model.selection = nil; model.tool = .arrow
            let start = CGPoint(x: 1800, y: 1000), end = CGPoint(x: 1980, y: 1080)
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            precondition(near(model.preview!.last!.start, start) && near(model.preview!.last!.end, end), "Zoom changed live arrow image coordinates")
            let beforeZoom = model.viewport
            model.zoomBy(1.25); model.fitImage()
            precondition(model.viewport == beforeZoom, "Zoom interrupted a drawing gesture")
            canvas.mouseUp(with: event(.leftMouseUp, end))
            let arrow = model.history.objects[0], tip = CGPoint(x: 2010, y: 1120)
            model.tool = .selection
            canvas.mouseDown(with: event(.leftMouseDown, end))
            canvas.mouseDragged(with: event(.leftMouseDragged, tip))
            precondition(near(model.preview![0].end, tip) && near(model.preview![0].start, start), "Arrow handle failed at zoom \(zoom)")
            canvas.mouseUp(with: event(.leftMouseUp, tip))
            model.undo(); precondition(model.history.objects == [arrow])
            model.redo(); precondition(near(model.history.objects[0].end, tip))

            let shape = EditorObject(kind: .rectangle, start: start, end: end)
            model.commit([shape]); model.selection = shape.id; model.tool = .selection
            canvas.mouseDown(with: event(.leftMouseDown, end))
            canvas.mouseDragged(with: event(.leftMouseDragged, tip))
            precondition(near(model.preview![0].end, tip) && near(model.preview![0].start, start), "Shape handle failed after zoom/pan")
            canvas.mouseUp(with: event(.leftMouseUp, tip)); model.undo()
            precondition(model.history.objects == [shape])

            model.commit([]); model.selection = nil; model.tool = .text
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseUp(with: event(.leftMouseUp, start))
            let text = canvas.subviews.first!.subviews.first as! NSTextView
            text.insertText("Hallo Zoom", replacementRange: NSRange(location: NSNotFound, length: 0))
            precondition(near(model.history.objects[0].start, start), "Text placed at wrong image pixel")
            let textObject = model.history.objects[0]
            model.finishTextEditing(); canvas.synchronizeTextEditor()
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: start.x + 10, y: start.y + 10), clicks: 2))
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x + 10, y: start.y + 10), clicks: 2))
            let selectedText = canvas.subviews.first!.subviews.first as! NSTextView
            precondition(selectedText.selectedRange() == NSRange(location: 0, length: 5), "Word selection missed after zoom/pan")
            selectedText.insertText("Guten", replacementRange: NSRange(location: NSNotFound, length: 0))
            selectedText.breakUndoCoalescing()
            precondition(canvas.performKeyEquivalent(with: key(6, "z", modifiers: .command)))
            precondition(model.history.objects[0].text == "Hallo Zoom", "Native text undo failed at zoom")
            model.finishTextEditing(); canvas.synchronizeTextEditor()
            precondition(model.history.objects == [textObject], "Selecting text created an extra object or changed its position")
        }

        let objects = model.history.objects, revision = model.document.revision
        let rendered = try EditorRenderer.png(image: image, objects: objects)
        model.setZoom(4); canvas.synchronizeTextEditor(); window.makeFirstResponder(canvas)
        let before = model.viewport
        canvas.keyDown(with: key(49, " "))
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 400, y: 300)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 480, y: 350)))
        precondition(model.viewport != before && model.history.objects == objects, "Space-drag drew an object instead of panning")
        canvas.keyDown(with: key(53, "\u{1B}"))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 480, y: 350)))
        precondition(model.viewport == before && !model.isCanvasGestureActive, "Escape failed to restore pan")
        canvas.keyDown(with: key(49, " "))
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 400, y: 300)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 480, y: 350)))
        canvas.keyUp(with: key(49, " ", type: .keyUp))
        precondition(model.viewport != before && !model.isCanvasGestureActive)
        precondition(canvas.performKeyEquivalent(with: key(18, "1", modifiers: .command)) && model.viewport.zoom == 1)
        precondition(canvas.performKeyEquivalent(with: key(24, "+", modifiers: .command)) && model.viewport.zoom == 1.25)
        precondition(canvas.performKeyEquivalent(with: key(27, "-", modifiers: .command)) && model.viewport.zoom == 1)
        precondition(canvas.performKeyEquivalent(with: key(29, "0", modifiers: .command)) && model.viewport.zoom == nil)
        precondition(model.document.revision == revision && model.history.objects == objects, "Viewport modified the document/autosave revision")
        let afterViewChanges = try EditorRenderer.png(image: image, objects: model.history.objects)
        precondition(afterViewChanges == rendered, "Zoom changed PNG pixels")
        let output = NSBitmapImageRep(data: rendered)!
        precondition(output.pixelsWide == 3840 && output.pixelsHigh == 2160, "Zoom changed export resolution")
        model.undo(); precondition(model.history.objects.isEmpty, "View changes consumed object undo")
        let flushed = await model.flush(); precondition(flushed)
        try await checkSmallImagePixels(store: store)
        try await checkBlurPreservesSourcePixels(store: store)
        print("Zoom canvas checks passed: 4K fit/50/100/400%, panned arrow endpoints and shape handles, native word selection/text undo, gesture protection, Space-drag/cancel, keyboard zoom, unchanged revision/PNG pixels and resolution.")
    }

    private static func checkBlurPreservesSourcePixels(store: ProjectStore) async throws {
        let width = 4097, height = 513
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            context.setFillColor((x.isMultiple(of: 2) ? NSColor.black : .white).cgColor)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let image = context.makeImage()!
        let blur = EditorObject(kind: .blur, start: CGPoint(x: 1950, y: 200), end: CGPoint(x: 2100, y: 300))
        let document = ProjectDocument(title: "4K-Unschärfe (synthetisch)", pixelSize: PixelSize(width: width, height: height)!, objects: [blur])
        let model = EditorModel(image: image, document: document, generation: 0, store: store, automaticallyFitsImage: false, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 801, height: 603), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.synchronizeViewport(); canvas.refreshComposition()
        let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
        let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        let backing = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        func sample(_ x: Int, _ y: Int) -> CGFloat {
            let bx = Int((rect.minX * backing).rounded()) + x
            let by = Int((rect.minY * backing).rounded()) + y
            return bitmap.colorAt(x: bx, y: by)!.usingColorSpace(.deviceRGB)!.redComponent
        }
        var finished = false
        for _ in 0..<1000 {
            try await Task.sleep(for: .milliseconds(10))
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            if (0.2...0.8).contains(sample(2020, 250)) { finished = true; break }
        }
        precondition(finished, "Background blur did not appear in the native canvas")
        let exported = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [blur]))!
        for x in 1800..<1900 {
            let expected: CGFloat = x.isMultiple(of: 2) ? 0 : 1
            precondition(abs(sample(x, 250) - expected) < 0.01, "A blur elsewhere softened untouched 4K source pixels in the preview")
            precondition(abs(exported.colorAt(x: x, y: 250)!.usingColorSpace(.deviceRGB)!.redComponent - expected) < 0.01,
                         "A blur elsewhere softened untouched source pixels in PNG")
        }
        let revision = model.document.revision
        model.setAutomaticallyFitsImage(true)
        precondition(model.viewport.zoom == nil)
        model.setZoom(2)
        precondition(model.automaticallyFitsImage && model.viewport.zoom == 2, "Opening preference prevented explicit zoom")
        model.setAutomaticallyFitsImage(false)
        precondition(model.viewport.zoom == 1 && model.document.revision == revision && !model.history.canUndo)
        model.isCanvasGestureActive = true
        model.setAutomaticallyFitsImage(true)
        precondition(!model.automaticallyFitsImage && model.viewport.zoom == 1, "Fit preference interrupted a gesture")
        model.isCanvasGestureActive = false
        print("4K sharpness checks passed: completed background blur preserves untouched one-pixel stripes in canvas/PNG; fit preference and manual zoom leave document/history unchanged.")
    }

    private static func checkSmallImagePixels(store: ProjectStore) async throws {
        let width = 449, height = 441
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            context.setFillColor((x.isMultiple(of: 2) ? NSColor.black : .white).cgColor)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let image = context.makeImage()!
        let document = ProjectDocument(title: "Pixelraster (synthetisch)", pixelSize: PixelSize(width: width, height: height)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 801, height: 603), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        for size in [CGSize(width: 801, height: 603), CGSize(width: 923, height: 701)] {
            canvas.frame.size = size; canvas.synchronizeViewport()
            for zoom: CGFloat in [0, 1, 2] {
                if zoom == 0 { model.fitImage() } else { model.setZoom(zoom) }
                let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                let backing = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
                let magnification = zoom == 0 ? 1 : zoom
                precondition(abs(rect.width * backing - CGFloat(width) * magnification) < 0.001, "Fit enlarged a small source image")
                let firstX = Int((rect.minX * backing).rounded()), y = Int((rect.midY * backing).rounded())
                for x in max(0, firstX)..<min(bitmap.pixelsWide, firstX + width * Int(magnification)) {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let expected: CGFloat = ((x - firstX) / Int(magnification)).isMultiple(of: 2) ? 0 : 1
                    precondition(abs(color.redComponent - expected) < 0.01, "Source pixels softened at fit/100/200% or after resizing the view")
                }
            }
        }
        precondition(model.document.revision == document.revision && !model.history.canUndo, "View sizing modified the document")
        print("Small-image pixel checks passed: 449×441 one-pixel stripes stay exact at fit/100/200% in two odd-sized native views.")
    }
}
