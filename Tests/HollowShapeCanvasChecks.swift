import AppKit
import SnagForgeDomain

@MainActor enum HollowShapeCanvasChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HollowShapes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let doc = ProjectDocument(title: "Hollow shapes", pixelSize: PixelSize(width: 640, height: 480)!,
            crop: CGRect(x: 60, y: 40, width: 520, height: 400), resizedSize: PixelSize(width: 780, height: 400))
        let original = try EditorRenderer.png(image: image, objects: [])
        try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
        func view(_ source: CGPoint) -> CGPoint {
            EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize,
                in: canvas.bounds, backingScale: window.backingScaleFactor)).viewPoint(source)
        }
        func mouse(_ type: NSEvent.EventType, _ source: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(view(source), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(_ start: CGPoint, _ end: CGPoint) {
            canvas.mouseDown(with: mouse(.leftMouseDown, start)); canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
            canvas.mouseUp(with: mouse(.leftMouseUp, end))
        }
        let centre = CGPoint(x: 320, y: 240)
        let cases: [(EditorObject.Kind, CGFloat, CGPoint)] = [
            (.rectangle, 0, CGPoint(x: 240, y: 90)), (.rectangle, 30, CGPoint(x: 240, y: 90)),
            (.ellipse, 0, CGPoint(x: 440, y: 360)), (.triangle, 0, CGPoint(x: 420, y: 240)),
            (.diamond, 0, CGPoint(x: 420, y: 165)), (.star, 0, CGPoint(x: 320, y: 90))
        ]
        for zoom: CGFloat in [0.5, 1, 4] {
            model.setZoom(zoom)
            for (kind, corner, edge) in cases {
                var shape = EditorObject(kind: kind, start: CGPoint(x: 120, y: 90), end: CGPoint(x: 520, y: 390))
                shape.cornerRadius = corner
                model.history = EditorHistory(objects: [shape], crop: doc.crop, resizedSize: doc.resizedSize)
                model.selection = nil; model.tool = .ellipse
                precondition(canvas.canvasCursor(at: view(centre)) === NSCursor.crosshair, "Empty shape interior blocked drawing: \(kind)")
                precondition(canvas.canvasCursor(at: view(edge)) === CanvasView.objectMoveCursor, "Visible contour could not be grabbed: \(kind)")
                model.selection = shape.id
                precondition(canvas.canvasCursor(at: view(centre)) === NSCursor.crosshair, "Selection made an empty interior draggable")
                model.selection = nil
                drag(edge, CGPoint(x: edge.x + 12, y: edge.y + 8))
                precondition(model.history.objects == [shape.translated(by: CGSize(width: 12, height: 8))] && model.tool == .ellipse,
                             "Contour drag created a shape or changed its geometry")
                model.undo(); precondition(model.history.objects == [shape])
                shape.fill = EditorFill(isEnabled: true, opacity: 0.4)
                model.history = EditorHistory(objects: [shape], crop: doc.crop, resizedSize: doc.resizedSize); model.selection = nil
                precondition(canvas.canvasCursor(at: view(centre)) === CanvasView.objectMoveCursor, "Visible fill stopped being draggable")
                shape.fill?.opacity = 0
                model.history = EditorHistory(objects: [shape], crop: doc.crop, resizedSize: doc.resizedSize)
                precondition(canvas.canvasCursor(at: view(centre)) === NSCursor.crosshair, "Invisible fill blocked drawing")
                shape.stroke = EditorStroke(isEnabled: false)
                model.history = EditorHistory(objects: [shape], crop: doc.crop, resizedSize: doc.resizedSize)
                precondition(canvas.canvasCursor(at: view(edge)) === NSCursor.crosshair, "Hidden contour intercepted the cursor")
            }
        }
        model.setZoom(1)
        var ellipse = EditorObject(kind: .ellipse, start: CGPoint(x: 120, y: 90), end: CGPoint(x: 520, y: 390))
        model.history = EditorHistory(objects: [ellipse], crop: doc.crop, resizedSize: doc.resizedSize); model.selection = nil
        precondition(canvas.canvasCursor(at: view(CGPoint(x: 130, y: 100))) === NSCursor.crosshair,
                     "An ellipse still used its rectangular bounding box")
        // An underlying visible object stays reachable through a transparent shape.
        var lower = EditorObject(kind: .rectangle, start: CGPoint(x: 250, y: 180), end: CGPoint(x: 390, y: 300))
        lower.fill = EditorFill(isEnabled: true)
        model.history = EditorHistory(objects: [lower, ellipse], crop: doc.crop, resizedSize: doc.resizedSize)
        canvas.mouseDown(with: mouse(.leftMouseDown, centre)); canvas.mouseUp(with: mouse(.leftMouseUp, centre))
        precondition(model.selection == lower.id, "An empty upper shape swallowed the lower object")
        ellipse.drawingStyle = .handDrawn
        model.history = EditorHistory(objects: [ellipse], crop: doc.crop, resizedSize: doc.resizedSize); model.selection = nil
        precondition(canvas.canvasCursor(at: view(centre)) === NSCursor.crosshair)
        precondition(canvas.canvasCursor(at: view(CGPoint(x: 456, y: 129))) === CanvasView.objectMoveCursor,
                     "Hand-drawn ellipse did not use its displayed path")

        ellipse.drawingStyle = nil
        model.history = EditorHistory(objects: [ellipse], crop: doc.crop, resizedSize: doc.resizedSize); model.selection = ellipse.id
        model.tool = .ellipse
        drag(CGPoint(x: 240, y: 180), CGPoint(x: 360, y: 300))
        let nested = model.history.objects
        precondition(nested.count == 2 && nested[0] == ellipse && nested[1].kind == .ellipse && nested[1].rect == CGRect(x: 240, y: 180, width: 120, height: 120),
                     "Drawing inside a circle edited the outer circle")
        precondition(model.tool == .ellipse && model.selection == nested[1].id)
        model.undo(); precondition(model.history.objects == [ellipse])
        model.redo(); precondition(model.history.objects == nested)
        let saved = await model.flush(), loaded = try await store.load(doc.id)
        precondition(saved && loaded.document.objects == nested)
        print("Hollow shape checks passed: nested circles, six contours, visible/transparent fills, hidden outlines, lower-layer picking, hand-drawn paths, zoom/crop/nonuniform output, contour movement, undo/redo and reload.")
    }
}
