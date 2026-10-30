import AppKit
import SnagForgeDomain

@MainActor enum DrawingWorkflowChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-DrawingWorkflow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let document = ProjectDocument(title: "Drawing workflow", pixelSize: PixelSize(width: 640, height: 480)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            let projection = EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
            return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil), modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> NSColor { EditorRenderer.pixelColor(image, x: x, y: y)! }
        model.tool = .pen
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 40, y: 60)))
        precondition(model.preview?.last?.penStroke?.points.count == 1 && model.history.objects.isEmpty)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 120, y: 60)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 180, y: 100)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 180, y: 100)))
        let pen = model.history.objects[0]
        precondition(pen.kind == .pen && pen.penStroke?.points.count == 3 && model.tool == .pen)
        let penImage = try EditorRenderer.render(image: image, objects: [pen])
        precondition(pixel(penImage, 41, 60).greenComponent < 0.4)
        model.undo(); precondition(model.history.objects.isEmpty); model.redo(); precondition(model.history.objects == [pen])
        model.selection = nil
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 250, y: 90)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 250, y: 90)))
        precondition(model.history.objects.count == 2, "A pen tap must make a visible dot")
        let dots = try EditorRenderer.render(image: image, objects: model.history.objects)
        precondition(pixel(dots, 250, 90).greenComponent < 0.4)
        var first = EditorObject(kind: .spotlight, start: CGPoint(x: 80, y: 150), end: CGPoint(x: 260, y: 270))
        first.spotlightStyle = .init(opacity: 0.6)
        var second = EditorObject(kind: .spotlight, start: CGPoint(x: 170, y: 180), end: CGPoint(x: 310, y: 300))
        second.spotlightStyle = .init(opacity: 0.4)
        let focused = try EditorRenderer.render(image: image, objects: [first, second])
        precondition(abs(pixel(focused, 20, 20).redComponent - 0.4) < 0.03, "Spotlight must dim the outside")
        precondition(pixel(focused, 200, 200).redComponent > 0.98 && pixel(focused, 120, 190).redComponent > 0.98,
                     "Overlapping focus areas must stay bright")
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 190, y: 190), end: CGPoint(x: 220, y: 220)); mask.color = .init(red: 0, green: 0, blue: 0)
        let protected = try EditorRenderer.render(image: image, objects: [mask, first, second])
        precondition(pixel(protected, 200, 200).redComponent < 0.01)
        model.commit([]); model.tool = .spotlight
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 300)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 200, y: 300)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 200, y: 300)))
        precondition(model.history.objects.isEmpty, "A zero-height spotlight must not create an invalid document")
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 400, y: 330)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 250)))
        precondition(model.preview?.last?.rect == CGRect(x: 300, y: 250, width: 100, height: 80))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 250)))
        let focus = model.history.objects[0]
        model.updateSpotlightStyle(.init(shape: .ellipse, opacity: 0.7)); model.undo(); precondition(model.history.objects[0] == focus)
        model.redo(); precondition(model.history.objects[0].spotlightStyle?.shape == .ellipse)
        model.commit([pen, first, second, mask]); let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.objects == model.history.objects)
        let originalExport = try EditorRenderer.png(image: image, objects: model.history.objects, crop: CGRect(x: 20, y: 20, width: 600, height: 420), resizedSize: PixelSize(width: 900, height: 420)!)
        let reloadedExport = try EditorRenderer.png(image: image, objects: loaded.document.objects, crop: CGRect(x: 20, y: 20, width: 600, height: 420), resizedSize: PixelSize(width: 900, height: 420)!)
        precondition(originalExport == reloadedExport)
        print("Drawing workflow passed: opaque smoothed pen/dots, live reverse spotlight, overlapping bright holes, masks, undo/redo, persistence and crop/nonuniform export equality.")
    }
}
