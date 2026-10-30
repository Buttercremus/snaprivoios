import AppKit
import SnagForgeDomain

/// Repeated creation through native handlers, with no input sent to other apps.
@MainActor enum RepeatedToolCanvasChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-RepeatedTools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        let cases: [(tool: AnnotationTool, shape: EditorObject.Kind?, corner: CGFloat)] = [
            (.arrow, nil, 0), (.rectangle, .rectangle, 0), (.rectangle, .rectangle, 20),
            (.ellipse, .ellipse, 0), (.rectangle, .triangle, 0), (.rectangle, .diamond, 0),
            (.rectangle, .star, 0), (.blur, nil, 0), (.redact, nil, 0), (.text, nil, 0), (.callout, nil, 0)
        ]
        for item in cases {
            let document = ProjectDocument(title: "Wiederholtes Zeichnen", pixelSize: PixelSize(width: 640, height: 480)!)
            try await store.create(document, original: original, thumbnail: nil)
            let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
            model.tool = item.tool
            if let shape = item.shape { model.selectShape(shape, corner: item.corner) }
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            let canvas = CanvasView(model: model); window.contentView = canvas
            canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
            func mouse(_ type: NSEvent.EventType, _ pixel: CGPoint, clicks: Int = 1) -> NSEvent {
                let projection = EditorImageProjection(source: model.sourceRect,
                    destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
                return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(pixel), to: nil), modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
            }
            func finishText(_ editor: NSTextView, commandReturn: Bool) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: commandReturn ? [.command] : [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: commandReturn ? "\r" : "\u{1B}",
                    charactersIgnoringModifiers: commandReturn ? "\r" : "\u{1B}", isARepeat: false, keyCode: commandReturn ? 36 : 53)!
                editor.keyDown(with: event)
            }
            var created: [EditorObject] = []
            for index in 0..<2 {
                let start = CGPoint(x: 80 + index * 280, y: 70 + index * 200)
                let end = CGPoint(x: start.x + 100, y: start.y + 70)
                canvas.mouseDown(with: mouse(.leftMouseDown, start))
                if item.tool == .text || item.tool == .callout {
                    canvas.mouseUp(with: mouse(.leftMouseUp, start))
                    let editor = canvas.subviews.first!.subviews.first as! NSTextView
                    editor.insertText("Hinweis \(index + 1)", replacementRange: NSRange(location: NSNotFound, length: 0))
                    finishText(editor, commandReturn: index == 1)
                    precondition(model.editingTextObject == nil && canvas.subviews.isEmpty, "Finishing text left an active editor")
                } else {
                    canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
                    canvas.mouseUp(with: mouse(.leftMouseUp, end))
                }
                precondition(model.tool == item.tool, "Creation switched tool \(item.tool) back to selection")
                precondition(model.history.objects.count == index + 1 && model.history.objects.prefix(index) == created[...],
                             "Second gesture edited the first object instead of creating another")
                let object = model.history.objects.last!
                precondition(object.kind == (item.shape ?? EditorObject.Kind.from(item.tool)) && model.selection == object.id)
                if item.corner > 0 { precondition(object.cornerRadius == item.corner) }
                created.append(object)
            }
            precondition(created[0].id != created[1].id)
            model.undo(); precondition(model.history.objects == [created[0]] && model.tool == item.tool)
            model.redo(); precondition(model.history.objects == created && model.tool == item.tool)

            if item.tool == .rectangle, item.shape == .rectangle, item.corner == 0 {
                // Changing the shape variant while drawing must carry into the next gesture.
                model.selection = created[1].id
                model.selectShape(.ellipse)
                precondition(model.tool == .ellipse && model.drawingKind == .ellipse)
                model.selectShape(.star)
                precondition(model.tool == .rectangle && model.drawingKind == .star)
            }
            if item.tool == .text || item.tool == .callout {
                // Finishing a text edit entered through Selection keeps Selection too.
                model.tool = .selection
                let point = CGPoint(x: created[0].start.x + 8, y: created[0].start.y + 6)
                canvas.mouseDown(with: mouse(.leftMouseDown, point, clicks: 2))
                canvas.mouseUp(with: mouse(.leftMouseUp, point, clicks: 2))
                let editor = canvas.subviews.first!.subviews.first as! NSTextView
                finishText(editor, commandReturn: false)
                precondition(model.tool == .selection && model.history.objects == created)
            }
            let expected = model.history.objects
            let saved = await model.flush(); precondition(saved)
            let loaded = try await store.load(document.id)
            precondition(loaded.document.objects == expected, "Repeated objects were not saved")
        }
        checkQuickOptionsPlacement()
        try await checkDirectEditing(image: image, original: original, store: store)
        print("Repeated-tool checks passed: consecutive creation, direct hover/move/resize without switching tools, small/no-op/cancel gestures, arrow hit geometry, groups, Option-overdrawing, adaptive toolbar placement, undo/redo and persistence.")
    }

    private static func checkQuickOptionsPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480), size = CGSize(width: 168, height: 48)
        let cases: [(anchor: CGRect, expected: CGPoint, placement: EditorQuickOptions.Placement)] = [
            (CGRect(x: 260, y: 250, width: 120, height: 50), CGPoint(x: 236, y: 190), .above),
            (CGRect(x: 260, y: 70, width: 120, height: 50), CGPoint(x: 236, y: 10), .above), // only a horizontal row fits above
            (CGRect(x: 260, y: 40, width: 120, height: 50), CGPoint(x: 236, y: 102), .below),
            (CGRect(x: 220, y: 30, width: 120, height: 420), CGPoint(x: 352, y: 156), .right),
            (CGRect(x: 590, y: 30, width: 40, height: 420), CGPoint(x: 530, y: 156), .left),
            (CGRect(x: 0, y: 260, width: 30, height: 40), CGPoint(x: 8, y: 200), .above) // slide along the edge
        ]
        for item in cases {
            let layout = CanvasView.quickOptionsLayout(anchor: item.anchor, horizontalSize: size, in: bounds)
            let expectedSize = item.placement.isHorizontal ? size : CGSize(width: 48, height: 168)
            precondition(layout.frame.origin == item.expected && layout.frame.size == expectedSize && layout.placement == item.placement,
                         "The toolbar must be horizontal above/below and vertical at the sides: \(layout)")
            precondition(bounds.insetBy(dx: 8, dy: 8).contains(layout.frame) && !layout.frame.intersects(item.anchor))
        }
        let offset = CGSize(width: 100, height: 200)
        let shifted = CanvasView.quickOptionsLayout(anchor: cases[0].anchor.offsetBy(dx: offset.width, dy: offset.height), horizontalSize: size,
                                                    in: bounds.offsetBy(dx: offset.width, dy: offset.height))
        precondition(shifted.frame.origin == CGPoint(x: 336, y: 390), "Placement must use the actual canvas bounds")
        let largeObject = CanvasView.quickOptionsLayout(anchor: bounds, horizontalSize: size, in: bounds)
        precondition(bounds.insetBy(dx: 8, dy: 8).contains(largeObject.frame), "A canvas-filling object must keep all toolbar buttons reachable")
        let narrow = CanvasView.quickOptionsLayout(anchor: CGRect(x: 20, y: 200, width: 60, height: 80),
            horizontalSize: CGSize(width: 208, height: 48), in: CGRect(x: 0, y: 0, width: 160, height: 480))
        precondition(narrow.placement == .right && narrow.frame == CGRect(x: 92, y: 136, width: 48, height: 208),
                     "A narrow canvas must use a vertical side toolbar so all buttons remain visible")
    }

    private static func checkDirectEditing(image: CGImage, original: Data, store: ProjectStore) async throws {
        precondition(CanvasView.objectMoveCursor.image.size == CGSize(width: 20, height: 20)
                     && CanvasView.objectMoveCursor.hotSpot == CGPoint(x: 10, y: 10), "The move cursor must stay compact and centred")
        let document = ProjectDocument(title: "Direkte Formbearbeitung", pixelSize: PixelSize(width: 640, height: 480)!,
                                       resizedSize: PixelSize(width: 960, height: 480)!)
        try await store.create(document, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
        func viewPoint(_ pixel: CGPoint) -> CGPoint {
            EditorImageProjection(source: model.sourceRect,
                destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)).viewPoint(pixel)
        }
        func mouse(_ type: NSEvent.EventType, _ pixel: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(viewPoint(pixel), to: nil), modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(from start: CGPoint, to end: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
            canvas.mouseDown(with: mouse(.leftMouseDown, start, modifiers: modifiers))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, end, modifiers: modifiers))
            canvas.mouseUp(with: mouse(.leftMouseUp, end, modifiers: modifiers))
        }
        var shape = EditorObject(kind: .rectangle, start: CGPoint(x: 80, y: 70), end: CGPoint(x: 240, y: 190))
        shape.fill = EditorFill(isEnabled: true)
        let other = EditorObject(kind: .ellipse, start: CGPoint(x: 360, y: 270), end: CGPoint(x: 460, y: 340))
        let centre = CGPoint(x: 160, y: 130), delta = CGSize(width: 18, height: 14)
        model.history = EditorHistory(objects: [shape, other]); model.tool = .selection
        let revisionBeforeClicks = model.document.revision
        let emptyPoint = CGPoint(x: 530, y: 390)
        for selectedID: UUID? in [nil, shape.id] {
            model.selection = selectedID
            canvas.mouseDown(with: mouse(.leftMouseDown, emptyPoint))
            precondition(!model.isCanvasGestureActive && model.preview == nil && model.hasConfirmedImageForToolbar,
                         "A background selection click must not disable or replace toolbar controls")
            canvas.mouseUp(with: mouse(.leftMouseUp, emptyPoint))
            precondition(model.selection == nil && model.document.revision == revisionBeforeClicks)
        }
        for click in [centre, shape.end] {
            model.selection = shape.id
            canvas.mouseDown(with: mouse(.leftMouseDown, click))
            precondition(!model.isCanvasGestureActive && model.preview == nil && model.hasConfirmedImageForToolbar,
                         "Selecting an object or pressing a handle must stay idle until it actually moves")
            canvas.mouseUp(with: mouse(.leftMouseUp, click))
            precondition(model.preview == nil && model.document.revision == revisionBeforeClicks)
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, centre))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: centre.x + 1, y: centre.y + 1)))
        precondition(model.isCanvasGestureActive && model.preview != nil && !model.hasConfirmedImageForToolbar,
                     "Even a one-pixel object move must protect the unconfirmed canvas")
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: centre.x + 1, y: centre.y + 1)))
        precondition(!model.isCanvasGestureActive)
        // A real native hosting view must survive repeated selection clicks.
        // Keep the test window offscreen; events are delivered only to this canvas.
        model.history = EditorHistory(objects: [shape, other]); model.selection = shape.id
        window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000)); window.orderFront(nil)
        canvas.showQuickOptions(for: shape.id)
        let toolbar = canvas.subviews.first!
        for _ in 0..<3 {
            canvas.mouseDown(with: mouse(.leftMouseDown, centre))
            canvas.mouseUp(with: mouse(.leftMouseUp, centre))
            precondition(canvas.subviews.first === toolbar && canvas.quickOptionsObjectID == shape.id,
                         "Clicking the same object must keep its native toolbar and glass identity")
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, centre))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: centre.x + 1, y: centre.y + 1)))
        precondition(canvas.quickOptionsObjectID == nil, "Starting a real drag must dismiss the object toolbar")
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: centre.x + 1, y: centre.y + 1)))
        canvas.closeQuickOptions(); window.orderOut(nil)
        let tools: [AnnotationTool] = [.rectangle, .ellipse, .arrow, .highlight, .steps, .blur, .redact, .text, .callout]
        for (index, tool) in tools.enumerated() {
            // Nonuniform output scaling and zoom must share the exact same hit projection as clicks.
            model.history = EditorHistory(objects: [shape, other], resizedSize: PixelSize(width: 960, height: 480)!)
            model.selection = other.id; model.tool = tool
            model.setZoom(index.isMultiple(of: 2) ? 1.5 : 0.75)
            canvas.updateTrackingAreas()
            precondition(canvas.trackingAreas.count == 1 && canvas.trackingAreas[0].options.contains(.cursorUpdate))
            canvas.mouseMoved(with: mouse(.mouseMoved, centre))
            precondition(NSCursor.current === CanvasView.objectMoveCursor && model.selection == other.id,
                         "Hover must indicate moving without changing the selection")
            canvas.cursorUpdate(with: mouse(.mouseMoved, centre))
            precondition(NSCursor.current === CanvasView.objectMoveCursor)
            let empty = CGPoint(x: 530, y: 390)
            let drawingCursor: NSCursor = tool == .text || tool == .callout ? .iBeam : .crosshair
            precondition(canvas.canvasCursor(at: viewPoint(empty)) === drawingCursor)
            precondition(canvas.canvasCursor(at: viewPoint(centre), modifiers: .option) === drawingCursor)
            drag(from: centre, to: CGPoint(x: centre.x + delta.width, y: centre.y + delta.height))
            let moved = shape.translated(by: delta)
            precondition(model.history.objects == [moved, other] && model.selection == shape.id && model.tool == tool,
                         "Direct movement must preserve the tool, object identity and selected object")
            model.undo(); precondition(model.history.objects == [shape, other])
            model.redo(); precondition(model.history.objects == [moved, other])
            model.selection = shape.id
            let smallStart = CGPoint(x: moved.rect.midX, y: moved.rect.midY)
            drag(from: smallStart, to: CGPoint(x: smallStart.x + 1, y: smallStart.y + 1))
            precondition(abs(model.history.objects[0].start.x - moved.start.x - 1) < 0.0001,
                         "Small direct moves must commit even below the creation threshold")
            model.undo(); precondition(model.history.objects == [moved, other]); model.selection = shape.id
            let revision = model.document.revision
            drag(from: smallStart, to: smallStart)
            precondition(model.document.revision == revision && model.history.objects == [moved, other], "A click added an undo step")
            let corner = CGPoint(x: moved.rect.maxX, y: moved.rect.maxY)
            precondition(canvas.canvasCursor(at: viewPoint(corner)) !== CanvasView.objectMoveCursor,
                         "Visible resize handles need their own cursor")
            drag(from: corner, to: CGPoint(x: corner.x + 24, y: corner.y + 16))
            let resized = model.history.objects[0]
            precondition(abs(resized.rect.width - moved.rect.width - 24) < 0.0001 && resized.start == moved.start)
            precondition(model.history.objects.count == 2 && model.selection == shape.id && model.tool == tool)
            model.undo(); precondition(model.history.objects == [moved, other]); model.selection = shape.id
            canvas.mouseDown(with: mouse(.leftMouseDown, smallStart))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: smallStart.x + 30, y: smallStart.y + 20)))
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
            canvas.keyDown(with: escape)
            precondition(model.preview == nil && model.history.objects == [moved, other] && model.tool == tool && !model.isCanvasGestureActive)
        }
        // The upper painted object wins, while dragging a group keeps every member selected.
        var covering = EditorObject(kind: .rectangle, start: CGPoint(x: 100, y: 70), end: CGPoint(x: 260, y: 190))
        covering.fill = EditorFill(isEnabled: true)
        model.history = EditorHistory(objects: [shape, covering]); model.selection = nil; model.tool = .rectangle
        drag(from: centre, to: CGPoint(x: centre.x + 18, y: centre.y + 14))
        precondition(model.history.objects == [shape, covering.translated(by: delta)] && model.selection == covering.id)
        let group = UUID()
        var grouped = shape; grouped.groupID = group
        var groupedOther = other; groupedOther.groupID = group
        model.history = EditorHistory(objects: [grouped, groupedOther]); model.selection = nil
        drag(from: centre, to: CGPoint(x: centre.x + 18, y: centre.y + 14))
        precondition(model.history.objects == [grouped.translated(by: delta), groupedOther.translated(by: delta)]
                     && model.selectedIDs == [grouped.id, groupedOther.id])
        model.undo(); precondition(model.history.objects == [grouped, groupedOther])

        // A diagonal arrow's empty bounding-box corners must remain available for drawing.
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 80, y: 70), end: CGPoint(x: 240, y: 190), lineWidth: 5)
        model.history = EditorHistory(objects: [arrow, other]); model.selection = nil; model.tool = .arrow
        precondition(canvas.canvasCursor(at: viewPoint(CGPoint(x: 90, y: 180))) === NSCursor.crosshair)
        precondition(canvas.canvasCursor(at: viewPoint(centre)) === CanvasView.objectMoveCursor)
        drag(from: arrow.end, to: CGPoint(x: 260, y: 210))
        precondition(model.history.objects[0].start == arrow.start && model.history.objects[0].end == CGPoint(x: 260, y: 210)
                     && model.selection == arrow.id && model.tool == .arrow)

        model.history = EditorHistory(objects: [shape, other]); model.selection = shape.id; model.tool = .rectangle
        drag(from: centre, to: CGPoint(x: 270, y: 220), modifiers: .option)
        precondition(model.history.objects.count == 3 && model.history.objects.prefix(2) == [shape, other][...],
                     "Option-drag must create over an existing selected object")
        drag(from: CGPoint(x: 520, y: 370), to: CGPoint(x: 600, y: 440))
        precondition(model.history.objects.count == 4 && model.tool == .rectangle, "Direct editing must still allow repeated drawing")
        let focus = model.focusRequest, selected = model.selectedObject!
        model.selectShape(.ellipse, focusCanvas: false)
        precondition(model.focusRequest == focus && model.selectedObject?.id == selected.id
                     && model.selectedObject?.rect == selected.rect && model.selectedObject?.kind == .ellipse,
                     "A quick shape change must preserve the object geometry and keep focus in the popover")
        model.undo(); precondition(model.history.objects.last == selected)
        model.redo(); model.selection = selected.id
        let expected = model.history.objects
        let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.objects == expected, "Direct edits and repeated creation were not saved")
    }
}
