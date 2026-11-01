import AppKit
import SnagForgeDomain

@MainActor enum KeyboardEditingChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyboardEditing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 80, y: 80))
        var callout = EditorObject(kind: .callout, start: CGPoint(x: 60, y: 60), end: CGPoint(x: 110, y: 90), text: "Text")
        callout.calloutTip = CGPoint(x: 130, y: 110)
        var marker = EditorObject(kind: .highlight, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 80, y: 50))
        marker.highlightStyle = EditorHighlightStyle(mode: .freehand, points: [marker.start, marker.end])
        let document = ProjectDocument(title: "Keyboard", pixelSize: PixelSize(width: 200, height: 160)!, objects: [arrow, callout, marker])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.frame.size = CGSize(width: 500, height: 400); canvas.synchronizeViewport()
        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
        }
        model.selection = arrow.id; model.tool = .arrow
        for zoom in [0.5, 1.0, 3.0] {
            model.setZoom(zoom)
            let before = model.history.objects
            canvas.keyDown(with: key(124))
            precondition(model.history.objects[0] == before[0].translated(by: CGSize(width: 1, height: 0)))
            precondition(model.selection == arrow.id && model.tool == .arrow)
            precondition(model.history.objects[1] == before[1])
            model.undo(); precondition(model.history.objects == before)
            model.redo(); precondition(model.history.objects[0].start.x == before[0].start.x + 1)
            model.selection = arrow.id
        }
        let beforeDirections = model.history.objects[0]
        canvas.keyDown(with: key(123, modifiers: .shift))
        canvas.keyDown(with: key(126))
        canvas.keyDown(with: key(125, modifiers: .shift))
        canvas.keyDown(with: key(124, repeatKey: true))
        precondition(model.history.objects[0] == beforeDirections.translated(by: CGSize(width: -9, height: 9)))

        model.selectAllObjects(); model.groupSelection()
        let grouped = model.history.objects
        canvas.keyDown(with: key(124, modifiers: .shift))
        precondition(model.history.objects == grouped.map { $0.translated(by: CGSize(width: 10, height: 0)) }, "Group/callout/freehand translation diverged")
        model.undo(); precondition(model.history.objects == grouped, "A keypress needs more than one undo")
        model.redo()

        // Free output proportions require different source deltas on X and Y.
        precondition(model.applyImageSize(PixelSize(width: 400, height: 80)!))
        model.selection = arrow.id
        let scaled = model.history.objects
        canvas.keyDown(with: key(124)); canvas.keyDown(with: key(125))
        precondition(model.history.objects == scaled.map { $0.translated(by: CGSize(width: 0.5, height: 2)) })
        let savedObjects = model.history.objects
        let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.objects == savedObjects && loaded.document.resizedSize == PixelSize(width: 400, height: 80))

        let revision = model.document.revision
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control] { canvas.keyDown(with: key(124, modifiers: modifier)) }
        precondition(model.document.revision == revision, "Modified system/navigation keys moved an object")
        model.isCanvasGestureActive = true
        precondition(!model.nudgeSelection(by: CGSize(width: 1, height: 0)))
        canvas.keyDown(with: key(124)); model.isCanvasGestureActive = false
        model.isSwitchingImage = true; canvas.keyDown(with: key(124)); model.isSwitchingImage = false
        model.beginCrop(); canvas.keyDown(with: key(124)); model.cancelCrop()
        precondition(model.document.revision == revision, "A draft/gesture/switch allowed keyboard movement")
        model.editText(at: callout.start, object: model.history.objects[1])
        canvas.synchronizeTextEditor()
        precondition(!model.canNudgeSelection && !model.nudgeSelection(by: CGSize(width: 1, height: 0)))
        precondition(model.history.objects == savedObjects, "Text cursor editing moved the callout")
        model.finishTextEditing(); canvas.synchronizeTextEditor()

        // Reaching the edge shares the existing canvas-growth/undo semantics.
        model.selection = arrow.id
        let beforeGrowth = model.history.objects, area = model.document.outputRect
        precondition(model.nudgeSelection(by: CGSize(width: -200, height: 0)))
        precondition(model.document.outputRect.minX < area.minX)
        model.undo(); precondition(model.history.objects == beforeGrowth && model.document.outputRect == area)
        print("Keyboard checks passed: 1/10 output-pixel steps, all directions, key repeat, zoom/Retina independence, free resize, groups/callout tips/freehand paths, selection/tool retention, undo/redo, persistence, draft/text/modifier guards and canvas-growth undo.")
        try await checkDeletion(image: image, store: store)
        try await checkCommandFocus(image: image, store: store)
    }

    private static func checkDeletion(image: CGImage, store: ProjectStore) async throws {
        let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 80, y: 100))
        let text = EditorObject(kind: .text, start: CGPoint(x: 100, y: 40), text: "Text")
        let document = ProjectDocument(title: "Delete keys", pixelSize: PixelSize(width: 200, height: 160)!, objects: [shape, text])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 500, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = EditorCanvasContainer(model: model); window.contentView = container
        container.frame.size = CGSize(width: 500, height: 400); container.synchronizeTransform()
        let canvas = container.canvas
        window.orderFront(nil)
        func deleteKey(_ code: UInt16) -> NSEvent {
            let character = code == 51 ? "\u{7F}" : "\u{F728}"
            return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        for toolbarFocused in [false, true] {
            for code: UInt16 in [51, 117] {
                model.selection = shape.id
                window.makeFirstResponder(canvas)
                if toolbarFocused {
                    canvas.showQuickOptions(for: shape.id)
                    precondition(canvas.quickOptionsObjectID == shape.id && window.firstResponder !== canvas,
                                 "The regression must send Delete to the focused quick toolbar")
                    try await Task.sleep(for: .milliseconds(30))
                }
                window.sendEvent(deleteKey(code))
                precondition(model.history.objects == [text] && model.selectedIDs.isEmpty,
                             "Delete key \(code) did not remove the selection with toolbar focus \(toolbarFocused)")
                precondition(canvas.quickOptionsObjectID == nil && window.firstResponder === canvas,
                             "Deletion must dismiss the toolbar and restore canvas focus (toolbar: \(toolbarFocused), key: \(code), responder: \(String(describing: window.firstResponder)))")
                model.undo(); precondition(model.history.objects == [shape, text], "Deletion must be one undo step")
                model.redo(); precondition(model.history.objects == [text])
                model.undo()
            }
        }
        model.selection = text.id
        model.editText(at: text.start, object: text); canvas.synchronizeTextEditor()
        let editor = window.firstResponder as! NSTextView
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.keyDown(with: deleteKey(51))
        precondition(editor.string == "Tex" && model.history.objects.contains { $0.id == text.id },
                     "Inline Delete must edit characters without removing the text object")
        model.finishTextEditing(); canvas.synchronizeTextEditor()
        print("Delete checks passed: backward/forward deletion with canvas or quick-toolbar focus, untouched neighbours, toolbar dismissal, focus restoration, undo/redo and inline text protection.")
    }

    private static func checkCommandFocus(image: CGImage, store: ProjectStore) async throws {
        let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 70, y: 100))
        let text = EditorObject(kind: .text, start: CGPoint(x: 100, y: 40), text: "Canvas text")
        let document = ProjectDocument(title: "Command focus", pixelSize: PixelSize(width: 200, height: 160)!, objects: [shape, text])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 700, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 400))
        let container = EditorCanvasContainer(model: model)
        container.frame = CGRect(x: 0, y: 0, width: 500, height: 400); root.addSubview(container)
        let field = NSTextView(frame: CGRect(x: 520, y: 20, width: 160, height: 80))
        field.string = "Other input"; root.addSubview(field)
        window.contentView = root; container.synchronizeTransform(); window.orderFront(nil)
        let canvas = container.canvas
        func command(_ character: String, code: UInt16, extra: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, extra], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }

        window.makeFirstResponder(canvas)
        model.editText(at: text.start, object: text); canvas.synchronizeTextEditor()
        let inline = window.firstResponder as! NSTextView
        inline.setSelectedRange(NSRange(location: 3, length: 0))
        window.makeFirstResponder(field)
        precondition(!canvas.performKeyEquivalent(with: command("a", code: 0)),
                     "An inactive inline editor stole Select All from another text field")
        precondition(inline.selectedRange() == NSRange(location: 3, length: 0))
        model.finishTextEditing(); canvas.synchronizeTextEditor()

        let outside = NSView(frame: CGRect(x: 520, y: 120, width: 160, height: 80))
        root.addSubview(outside); window.makeFirstResponder(nil)
        let revision = model.document.revision
        precondition(!canvas.performKeyEquivalent(with: command("d", code: 2)),
                     "The canvas stole a command without owning keyboard focus")
        precondition(model.document.revision == revision)

        window.makeFirstResponder(canvas); model.selection = shape.id
        for extra: NSEvent.ModifierFlags in [.option, .control, .shift] {
            precondition(!canvas.performKeyEquivalent(with: command("d", code: 2, extra: extra)),
                         "A different shortcut duplicated the selected object")
        }
        precondition(model.history.objects == [shape, text])
        precondition(canvas.performKeyEquivalent(with: command("d", code: 2)))
        precondition(model.history.objects.count == 3)
        model.undo(); precondition(model.history.objects == [shape, text])

        model.selection = shape.id; canvas.showQuickOptions(for: shape.id)
        precondition(canvas.quickOptionsObjectID == shape.id)
        let toolbar = container.subviews.first { $0 !== canvas }!
        let toolbarText = NSTextView(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        toolbar.addSubview(toolbarText); window.makeFirstResponder(toolbarText)
        canvas.closeQuickOptions()
        precondition(window.firstResponder === canvas,
                     "Dismissing a toolbar with focused descendants lost canvas focus")

        let beforeGesture = model.history.objects
        let from = shape.start, to = CGPoint(x: from.x + 8, y: from.y + 6)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let projection = EditorImageProjection(source: model.sourceRect, destination: rect)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, from))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, to))
        let pending = model.preview
        precondition(model.isCanvasGestureActive && pending != nil)
        precondition(canvas.performKeyEquivalent(with: command("z", code: 6)))
        precondition(model.history.objects == beforeGesture && model.preview == pending,
                     "Undo changed history or discarded a preview during a held resize")
        precondition(canvas.performKeyEquivalent(with: command("z", code: 6, extra: .shift)))
        model.removeSelection()
        precondition(model.history.objects == beforeGesture && model.preview == pending,
                     "Redo or Delete changed the document during a held resize")
        canvas.mouseUp(with: mouse(.leftMouseUp, to))
        precondition(!model.isCanvasGestureActive && model.history.objects == pending)
        model.undo(); precondition(model.history.objects == beforeGesture)
        print("Command focus checks passed: inactive inline editors, unrelated responders, exact shortcut modifiers, toolbar descendant focus and held-gesture Undo/Redo/Delete protection with one-step release undo.")
    }
}
