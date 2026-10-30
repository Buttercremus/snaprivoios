import AppKit
import SnagForgeDomain

private final class GeometryResults: @unchecked Sendable {
    let lock = NSLock()
    var values: [CGSize] = []
}

/// An offscreen, synthetic AppKit canvas. No input is sent to the user's apps.
@main
struct CanvasChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--annotation-tools-only") {
            try await DrawingWorkflowChecks.run()
        try await EditorArrangementChecks.run()
        try await AnnotationToolsChecks.run()
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-Canvas-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 80))
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 80, width: 240, height: 80))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let document = ProjectDocument(title: "Canvas Test", pixelSize: PixelSize(width: 240, height: 160)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model)
        model.focusRequest += 1
        canvas.synchronizeFocus()
        precondition(canvas.lastFocusRequest != model.focusRequest, "Focus was consumed before the replacement canvas had a window")
        window.contentView = canvas
        precondition(window.firstResponder === canvas && canvas.lastFocusRequest == model.focusRequest)
        canvas.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        // Exercise the existing editing fixture at an explicit 1.7pt/image-pixel
        // magnification. Fit now keeps small images at actual pixels instead.
        canvas.synchronizeViewport()
        model.setZoom(1.7 * window.backingScaleFactor)
        func event(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            let local = CGPoint(x: 36 + point.x * 1.7, y: 24 + point.y * 1.7)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: modifiers, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func pixel(_ point: CGPoint) -> NSColor {
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let ratio = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
            return bitmap.colorAt(x: Int((36 + point.x * 1.7) * ratio), y: Int((24 + point.y * 1.7) * ratio))!.usingColorSpace(.deviceRGB)!
        }
        func close(_ rect: CGRect, _ expected: CGRect) -> Bool {
            abs(rect.minX - expected.minX) < 0.0001 && abs(rect.minY - expected.minY) < 0.0001 &&
            abs(rect.width - expected.width) < 0.0001 && abs(rect.height - expected.height) < 0.0001
        }
        func hasSize(_ object: EditorObject?, _ size: CGSize) -> Bool {
            guard let object else { return false }
            return abs(object.rect.width - size.width) < 0.0001 && abs(object.rect.height - size.height) < 0.0001
        }
        model.tool = .arrow
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 30, y: 110)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 180, y: 110)))
        precondition(model.history.objects.isEmpty && model.preview?.count == 1, "Gesture committed before mouse-up")
        precondition(model.isCanvasGestureActive && !model.hasExportableImage, "Live canvas gesture did not block image export")
        precondition(pixel(CGPoint(x: 90, y: 110)).redComponent > 0.7, "Arrow absent while mouse is held")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 180, y: 110)))
        precondition(model.hasExportableImage, "Mouse-up did not restore image export")
        precondition(model.tool == .arrow, "Drawing switched away from the arrow tool")
        model.tool = .selection
        let initialArrow = model.history.objects[0]
        model.selection = initialArrow.id
        model.isSwitchingImage = true
        let switchingRevision = model.document.revision
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 40, y: 40)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 100, y: 80)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 80)))
        let blockedDelete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: blockedDelete); model.undo()
        precondition(model.history.objects == [initialArrow] && model.document.revision == switchingRevision && model.preview == nil)
        precondition(!canvas.acceptsFirstResponder && canvas.hitTest(CGPoint(x: 100, y: 100)) == nil)
        precondition(pixel(CGPoint(x: 90, y: 110)).redComponent > 0.7, "Suspending input blanked the old canvas")
        precondition(model.pngShareItem == nil && model.pngShareItemForToolbar != nil && model.hasConfirmedImageForToolbar)
        window.makeFirstResponder(nil); model.focusRequest += 1; canvas.synchronizeFocus()
        precondition(window.firstResponder !== canvas && canvas.lastFocusRequest != model.focusRequest)
        model.isSwitchingImage = false
        canvas.synchronizeFocus()
        precondition(window.firstResponder === canvas && canvas.lastFocusRequest == model.focusRequest)
        precondition(canvas.acceptsFirstResponder && model.hasExportableImage)
        canvas.mouseDown(with: event(.leftMouseDown, initialArrow.end))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 150, y: 125)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 120, y: 140)))
        precondition(model.preview?.first?.start == initialArrow.start && model.preview?.first?.end == CGPoint(x: 120, y: 140),
                     "Dragging the tip moved the whole arrow or did not preview its direction")
        precondition(model.history.objects == [initialArrow], "Endpoint drag committed before mouse-up")
        precondition(pixel(CGPoint(x: 75, y: 125)).redComponent > 0.7, "Rotated arrow not drawn during endpoint drag")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 140)))
        let rotatedArrow = model.history.objects[0]
        model.undo(); precondition(model.history.objects == [initialArrow], "Endpoint drag needs more than one undo")
        model.redo(); precondition(model.history.objects == [rotatedArrow], "Endpoint redo lost the final position")
        let endpointSaved = await model.flush()
        let endpointReloaded = try await store.load(document.id)
        precondition(endpointSaved && endpointReloaded.document.objects == [rotatedArrow], "Rotated arrow not persisted")
        let endpointPNG = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: endpointReloaded.document.objects))!
        var rgba = [Int](repeating: 0, count: 4)
        endpointPNG.getPixel(&rgba, atX: 75, y: 125)
        precondition(rgba[0] > 200, "PNG did not use the rotated arrow coordinates")
        endpointPNG.getPixel(&rgba, atX: 175, y: 110)
        precondition(rgba[0] < 10 && rgba[2] > 240, "PNG retained the old arrow direction")
        model.selection = rotatedArrow.id
        // Grabbing off-centre does not snap the endpoint to the pointer.
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 32, y: 112)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 62, y: 92)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 62, y: 92)))
        let movedStart = model.history.objects[0]
        precondition(hypot(movedStart.start.x - 60, movedStart.start.y - 90) < 0.001 && movedStart.end == rotatedArrow.end, "Start handle jumped or moved the tip")
        model.undo(); precondition(model.history.objects == [rotatedArrow])
        model.redo(); precondition(model.history.objects == [movedStart])
        model.selection = movedStart.id
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 75, y: 102.5)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 85, y: 107.5)))
        let translated = movedStart.translated(by: CGSize(width: 10, height: 5)), shaftPreview = model.preview!.first!
        precondition(hypot(shaftPreview.start.x - translated.start.x, shaftPreview.start.y - translated.start.y) < 0.001 &&
                     hypot(shaftPreview.end.x - translated.end.x, shaftPreview.end.y - translated.end.y) < 0.001,
                     "Shaft drag no longer translates the whole arrow")
        let cancelDrag = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: cancelDrag)
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 85, y: 107.5)))
        precondition(model.preview == nil && model.history.objects == [movedStart], "Escape committed a cancelled gesture")
        // Directly grabbing an unselected tip also edits the endpoint.
        model.selection = nil
        canvas.mouseDown(with: event(.leftMouseDown, movedStart.end))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 160, y: 100)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 160, y: 100)))
        precondition(model.history.objects[0].start == movedStart.start && model.history.objects[0].end == CGPoint(x: 160, y: 100),
                     "Unselected tip cannot be grabbed directly")
        model.undo(); precondition(model.history.objects == [movedStart])
        model.undo(); precondition(model.history.objects == [rotatedArrow])
        model.undo(); precondition(model.history.objects == [initialArrow])
        model.selection = initialArrow.id
        canvas.mouseDown(with: event(.leftMouseDown, initialArrow.end))
        canvas.mouseUp(with: event(.leftMouseUp, initialArrow.end))
        model.undo(); precondition(model.history.objects.isEmpty, "Drag is not one undo step")
        // Exercise real mouse routing for every handle, including reverse-drawn shapes.
        var resizeShape = EditorObject(kind: .rectangle, start: CGPoint(x: 120, y: 110), end: CGPoint(x: 40, y: 50))
        resizeShape.fill = EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 1, blue: 0))
        for handle in EditorResizeHandle.allCases {
            model.commit([resizeShape]); model.selection = resizeShape.id; model.tool = .selection
            let grab = handle.point(in: resizeShape.rect)
            canvas.mouseDown(with: event(.leftMouseDown, grab))
            let target = CGPoint(x: grab.x + 12, y: grab.y + 8)
            canvas.mouseDragged(with: event(.leftMouseDragged, target))
            let expected = EditorGeometry.resized(resizeShape.rect, handle: handle, delta: CGSize(width: 12, height: 8), minimum: CGSize(width: 4 / 1.7, height: 4 / 1.7))
            precondition(close(model.preview!.first!.rect, expected) && model.history.objects == [resizeShape], "Handle did not resize live or committed too soon")
            canvas.mouseUp(with: event(.leftMouseUp, target))
            let resized = model.history.objects[0]
            precondition(resized.id == resizeShape.id && resized.fill == resizeShape.fill && resized.lineWidth == resizeShape.lineWidth)
            model.undo(); precondition(model.history.objects == [resizeShape], "Resize needs more than one undo")
            model.redo(); precondition(model.history.objects == [resized])
        }
        model.commit([resizeShape]); model.selection = resizeShape.id
        // A near-centre grab must not jump to the pointer, and Escape discards the preview.
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 42, y: 51)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 22, y: 26)))
        let expanded = model.preview![0]
        precondition(close(expanded.rect, CGRect(x: 20, y: 25, width: 100, height: 85)), "Resize handle snapped to the pointer")
        precondition(pixel(CGPoint(x: 30, y: 40)).greenComponent > 0.8, "Resized fill absent before mouse-up")
        canvas.keyDown(with: cancelDrag)
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 22, y: 26)))
        precondition(model.preview == nil && model.history.objects == [resizeShape], "Escape committed a resize")
        model.selection = resizeShape.id
        canvas.mouseDown(with: event(.leftMouseDown, resizeShape.rect.origin))
        canvas.mouseUp(with: event(.leftMouseUp, resizeShape.rect.origin))
        model.undo(); precondition(model.history.objects != [resizeShape], "Clicking a resize handle consumed undo")
        model.commit([])
        func flags(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56)!
        }
        // Shift may be pressed/released while the pointer is stationary.
        for kind in [AnnotationTool.rectangle, .ellipse] {
            for dx: CGFloat in [-50, 50] {
                for dy: CGFloat in [-25, 25] {
                    model.tool = kind; model.selection = nil
                    let anchor = CGPoint(x: 120, y: 80), target = CGPoint(x: 120 + dx, y: 80 + dy)
                    canvas.mouseDown(with: event(.leftMouseDown, anchor))
                    canvas.mouseDragged(with: event(.leftMouseDragged, target))
                    precondition(hasSize(model.preview?.last, CGSize(width: 50, height: 25)))
                    canvas.flagsChanged(with: flags(.shift))
                    precondition(hasSize(model.preview?.last, CGSize(width: 50, height: 50)), "Pressing Shift without mouse movement did not constrain shape")
                    canvas.flagsChanged(with: flags([]))
                    precondition(hasSize(model.preview?.last, CGSize(width: 50, height: 25)), "Releasing Shift did not restore free drawing")
                    canvas.mouseUp(with: event(.leftMouseUp, target, modifiers: .shift))
                    precondition(hasSize(model.history.objects.last, CGSize(width: 50, height: 50)))
                    model.undo(); precondition(model.history.objects.isEmpty)
                }
            }
        }
        model.commit([resizeShape]); model.tool = .selection; model.selection = resizeShape.id
        let bottomRight = CGPoint(x: 120, y: 110), sizeTarget = CGPoint(x: 145, y: 117)
        canvas.mouseDown(with: event(.leftMouseDown, bottomRight))
        canvas.mouseDragged(with: event(.leftMouseDragged, sizeTarget))
        canvas.flagsChanged(with: flags(.shift))
        precondition(close(model.preview!.first!.rect, CGRect(x: 40, y: 50, width: 105, height: 105)), "Shift resize moved the opposite corner")
        canvas.flagsChanged(with: flags([]))
        precondition(close(model.preview!.first!.rect, CGRect(x: 40, y: 50, width: 105, height: 67)))
        canvas.mouseUp(with: event(.leftMouseUp, sizeTarget))
        let resizedShape = model.history.objects[0]
        let resizeSaved = await model.flush()
        let resizeReloaded = try await store.load(document.id)
        precondition(resizeSaved && resizeReloaded.document.objects == [resizedShape], "Resized shape not persisted")
        let resizePNG = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [resizedShape]))!
        precondition(resizePNG.colorAt(x: 135, y: 105)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "PNG retained the old shape size")
        model.commit([]); model.selection = nil; model.tool = .arrow
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 20, y: 110)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 140, y: 125), modifiers: .shift))
        precondition(abs(model.preview!.last!.end.y - 110) < 0.0001, "Shift arrow did not snap horizontally")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 140, y: 125), modifiers: .shift))
        let straightArrow = model.history.objects[0]
        model.tool = .selection
        canvas.mouseDown(with: event(.leftMouseDown, straightArrow.start))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 24, y: 50), modifiers: .shift))
        let diagonal = model.preview![0]
        precondition(diagonal.end == straightArrow.end && abs(abs(diagonal.end.x - diagonal.start.x) - abs(diagonal.end.y - diagonal.start.y)) < 0.0001,
                     "Shift on the start handle did not keep the tip anchored at 45 degrees")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 24, y: 50), modifiers: .shift))
        model.undo(); precondition(model.history.objects == [straightArrow])
        model.undo(); precondition(model.history.objects.isEmpty)
        var callout = EditorObject(kind: .callout, start: CGPoint(x: 50, y: 50), text: "Hinweis mit Text", fontSize: 14, textWidth: 100)
        callout.textHeight = 40; callout.fill = resizeShape.fill
        model.commit([callout]); model.tool = .selection; model.selection = callout.id
        let box = EditorRenderer.calloutBox(callout), corner = CGPoint(x: box.maxX, y: box.maxY)
        let calloutTarget = CGPoint(x: corner.x + 30, y: corner.y + 25)
        canvas.mouseDown(with: event(.leftMouseDown, corner))
        canvas.mouseDragged(with: event(.leftMouseDragged, calloutTarget))
        let resizedCallout = model.preview![0]
        precondition(abs(resizedCallout.textWidth! - 130) < 0.0001 && abs(resizedCallout.textHeight! - 65) < 0.0001 && resizedCallout.fontSize == callout.fontSize && resizedCallout.text == callout.text,
                     "Callout resize changed text/font or failed to update its frame")
        precondition(pixel(CGPoint(x: 180, y: 115)).greenComponent > 0.8, "Callout frame did not update live")
        canvas.mouseUp(with: event(.leftMouseUp, calloutTarget))
        let calloutSaved = await model.flush()
        let calloutLoaded = try await ProjectStore(root: root).load(document.id)
        precondition(calloutSaved && calloutLoaded.document.objects == [resizedCallout], "Callout size lost after reload")
        let calloutPNG = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: calloutLoaded.document.objects))!
        precondition(calloutPNG.colorAt(x: 180, y: 115)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "PNG lost resized callout frame")
        model.undo(); precondition(model.history.objects == [callout]); model.redo()
        precondition(model.history.objects == [resizedCallout])
        model.undo(); model.selection = callout.id
        canvas.mouseDown(with: event(.leftMouseDown, box.origin))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: box.minX + 60, y: box.minY + 40)))
        let narrowCallout = model.preview![0]
        precondition(abs(EditorRenderer.calloutBox(narrowCallout).maxY - box.maxY) < 0.0001 &&
                     EditorRenderer.textRect(narrowCallout).height > 40 && narrowCallout.fontSize == callout.fontSize,
                     "Narrow callout clipped wrapped text or lost the opposite anchor")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: box.minX + 60, y: box.minY + 40)))
        model.undo(); precondition(model.history.objects == [callout])
        model.commit([])
        model.defaultShapeFill = EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 1, blue: 0))
        model.defaultShapeStroke = EditorStroke(isEnabled: false)
        for kind in [EditorObject.Kind.triangle, .diamond, .star] {
            model.selectShape(kind)
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 40, y: 100)))
            canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 120, y: 145)))
            precondition(model.preview?.first?.kind == kind && pixel(CGPoint(x: 80, y: 125)).greenComponent > 0.8,
                         "Selected polygon not drawn live")
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 145)))
            precondition(model.history.objects.first?.kind == kind && model.history.objects.first?.effectiveStroke.isEnabled == false)
            model.undo(); precondition(model.history.objects.isEmpty, "Polygon creation not one undo step")
        }
        model.selectShape(.rectangle)
        model.defaultShapeStroke = EditorStroke()
        model.tool = .rectangle
        model.defaultShapeFill = EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 1, blue: 0))
        model.defaultCornerRadius = 12
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 40, y: 100)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 120, y: 145)))
        precondition(pixel(CGPoint(x: 40, y: 125)).redComponent > 0.7, "Rectangle absent before mouse-up")
        precondition(pixel(CGPoint(x: 80, y: 125)).greenComponent > 0.8, "Shape fill absent while drawing")
        precondition(pixel(CGPoint(x: 40, y: 100)).blueComponent > 0.8, "Rounded corner ignored during preview")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 145)))
        model.beginStyleEditing()
        var translucent = model.activeFill; translucent.opacity = 0.4
        model.updateStyle(fill: translucent)
        let liveFill = pixel(CGPoint(x: 80, y: 125))
        precondition(liveFill.greenComponent > 0.2 && liveFill.greenComponent < 0.8 && liveFill.blueComponent > 0.2,
                     "Style slider change absent from live canvas")
        model.endStyleEditing(); model.undo()
        precondition(pixel(CGPoint(x: 80, y: 125)).greenComponent > 0.8, "Fill undo absent from canvas")
        model.undo()
        model.tool = .blur
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 80, y: 60)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 160, y: 100)))
        try await Task.sleep(for: .milliseconds(300))
        let mixed = pixel(CGPoint(x: 120, y: 79))
        precondition(mixed.redComponent > 0.1 && mixed.blueComponent > 0.1, "Blur absent during held drag")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 160, y: 100))); model.undo()
        model.tool = .text
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 25, y: 35)))
        guard let text = canvas.subviews.first?.subviews.first as? NSTextView else { fatalError("No inline text view on canvas") }
        text.insertText("Live\nText", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(model.history.objects.last?.text == "Live\nText", "Typing is not live in the document")
        precondition(model.history.objects.last?.start == CGPoint(x: 25, y: 35), "Text did not use clicked image position")
        let saved = await model.flush()
        precondition(saved, "Inline draft could not be saved")
        let reloaded = try await store.load(document.id)
        precondition(reloaded.document.objects.last?.text == "Live\nText", "Inline draft lost after reload")
        // Native selection replaces characters, rather than creating another object.
        text.setSelectedRange(NSRange(location: 0, length: 4))
        text.insertText("Hallo", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(model.history.objects.last?.text == "Hallo\nText" && model.history.objects.count == 1)
        text.breakUndoCoalescing()
        try await Task.sleep(for: .milliseconds(30))
        let undo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        precondition(canvas.performKeyEquivalent(with: undo), "Canvas swallowed native text undo")
        precondition(model.history.objects.last?.text == "Live\nText", "Cmd+Z did not undo the word replacement")
        let redo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "Z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        precondition(canvas.performKeyEquivalent(with: redo))
        precondition(model.history.objects.last?.text == "Hallo\nText", "Shift+Cmd+Z did not redo the word replacement")
        text.selectAll(nil)
        precondition(text.selectedRange().length == 10, "Cmd+A does not select the inline text")
        // Escape ends editing like a normal text box; it does not discard typing.
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                                      charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        text.keyDown(with: escape)
        precondition(canvas.subviews.isEmpty, "Text field remains after editing")
        precondition(model.history.objects.last?.text == "Hallo\nText", "Escape discarded typing")
        model.undo(); precondition(model.history.objects.isEmpty, "Typing is not one document undo step")
        model.redo()
        let completedText = model.history.objects[0]
        model.tool = .text
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 35, y: 40), clicks: 2))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 35, y: 40), clicks: 2))
        let editing = canvas.subviews.first!.subviews.first as! NSTextView
        precondition(editing.selectedRange().length == 5, "Double-click did not select the word")
        precondition(model.editingTextObject?.id == completedText.id && model.history.objects.count == 1, "Text click created a duplicate")
        model.finishTextEditing(); canvas.synchronizeTextEditor()
        model.undo(); precondition(model.history.objects.isEmpty, "No-op text selection consumed undo")

        model.tool = .text; model.defaultFontSize = 14
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 20, y: 30)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 110, y: 90)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 110, y: 90)))
        let boxed = canvas.subviews.first!.subviews.first as! NSTextView
        boxed.insertText("Eins zwei drei vier fünf sechs sieben", replacementRange: NSRange(location: NSNotFound, length: 0))
        let boxObject = model.history.objects.last!
        precondition(boxObject.textWidth == 90 && boxObject.start == CGPoint(x: 20, y: 30), "Dragged text box lost its width or origin")
        let textRect = EditorRenderer.textRect(boxObject)
        precondition(textRect.height > boxObject.fontSize * 2, "Text box does not wrap")
        let lines = boxed.layoutManager!.usedRect(for: boxed.textContainer!).height
        precondition(abs(lines - textRect.height) < 2, "Inline layout and exported text disagree")
        model.finishTextEditing(); canvas.synchronizeTextEditor(); model.tool = .selection
        let rightHandle = CGPoint(x: textRect.maxX + 3 / 1.7, y: textRect.midY)
        canvas.mouseDown(with: event(.leftMouseDown, rightHandle))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: rightHandle.x + 50, y: rightHandle.y)))
        precondition(abs((model.preview?.last?.textWidth ?? 0) - 140) < 0.001, "Text width is not live during resize")
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: rightHandle.x + 50, y: rightHandle.y)))
        model.undo(); precondition(model.history.objects.last == boxObject, "Text width resize did not undo in one step")
        model.redo()
        let final = await model.flush(); precondition(final)
        let restored = try await store.load(document.id)
        precondition(abs((restored.document.objects.last?.textWidth ?? 0) - 140) < 0.001, "Text width lost after save/reload")

        // Renderer audit: long text measurements are cached by content/width/style,
        // remain safe under concurrent reads, and invalidate when the content changes.
        var longText = boxObject
        longText.text = String(repeating: "Langer Beispieltext ", count: 8_000)
        longText.textWidth = 180
        EditorRenderer.resetTextGeometryCacheStatistics()
        let coldSize = EditorRenderer.textRect(longText).size
        let warmSize = EditorRenderer.textRect(longText).size
        precondition(coldSize == warmSize && coldSize.height > 100, "Long text geometry cache changed the measured result")
        var translatedGeometry = longText
        translatedGeometry.start.x += 240
        translatedGeometry.end.x += 240
        precondition(EditorRenderer.textRect(translatedGeometry).size == coldSize, "Translated text did not reuse invariant geometry")
        var invalidated = longText
        invalidated.text = "Kurz"
        precondition(EditorRenderer.textRect(invalidated).size != coldSize, "Text content did not invalidate geometry")
        let geometryStats = EditorRenderer.textGeometryCacheStatistics
        precondition(geometryStats.misses >= 2 && geometryStats.hits >= 1, "Text geometry cache did not record expected hit/miss invalidation")
        let concurrentText = longText
        let parallelResults = GeometryResults()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            let measured = EditorRenderer.textRect(concurrentText).size
            parallelResults.lock.lock(); parallelResults.values.append(measured); parallelResults.lock.unlock()
        }
        precondition(parallelResults.values.count == 8 && parallelResults.values.allSatisfy { $0 == coldSize }, "Concurrent text measurements disagreed")
        let smallEstimate = EditorRenderer.rasterMemoryEstimate(image: image, maxDimension: 32)
        let fullEstimate = EditorRenderer.rasterMemoryEstimate(image: image)
        precondition(smallEstimate < fullEstimate && EditorRenderer.rasterBudgetSnapshot.reserved == 0,
                     "Raster budget estimate or release is invalid")
        _ = try EditorRenderer.render(image: image, objects: [])
        precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0, "Raster budget reservation was not released")
        var groupA = EditorObject(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 60))
        groupA.fill = EditorFill(isEnabled: true)
        let groupB = EditorObject(kind: .rectangle, start: CGPoint(x: 100, y: 80), end: CGPoint(x: 160, y: 120))
        model.commit([groupA, groupB]); model.tool = .selection
        model.select(groupA.id); model.select(groupB.id, extending: true); model.groupSelection()
        let beforeGroupMove = model.history.objects
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 50, y: 40)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 60, y: 50)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 60, y: 50)))
        precondition(model.history.objects[0].start == CGPoint(x: 30, y: 30))
        precondition(model.history.objects[1].start == CGPoint(x: 110, y: 90))
        model.undo(); precondition(model.history.objects == beforeGroupMove)
        print("Group canvas checks passed: dragging translates both selected objects and one undo restores both.")
        print("Canvas checks passed: all eight shape handles, reverse geometry, grab offset, live fill, Shift press/release and arrow snapping; callout frame/reflow, opposite anchor, resize undo/reload/PNG; existing arrow handles, cancel/no-op and native text editing.")
        try await DrawingWorkflowChecks.run()
        try await EditorArrangementChecks.run()
        try await AnnotationToolsChecks.run()
        try await ZoomCanvasChecks.run()
        try await CropCanvasChecks.run()
        try await RepeatedToolCanvasChecks.run()
        try await InstructionToolChecks.run()
        try await SelectionGripChecks.run()
        try await CanvasExpansionChecks.run()
        try await HollowShapeCanvasChecks.run()
        try await KeyboardEditingChecks.run()
    }
}
