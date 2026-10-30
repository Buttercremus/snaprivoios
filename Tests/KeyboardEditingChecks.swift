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
    }
}
