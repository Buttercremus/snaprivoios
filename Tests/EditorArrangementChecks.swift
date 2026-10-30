import AppKit
import SnagForgeDomain

@MainActor enum EditorArrangementChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Arrangement-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        var a = EditorObject(kind: .rectangle, start: CGPoint(x: 80, y: 80), end: CGPoint(x: 180, y: 150))
        a.fill = EditorFill(isEnabled: true)
        var b = EditorObject(kind: .rectangle, start: CGPoint(x: 320, y: 210), end: CGPoint(x: 440, y: 300))
        b.fill = EditorFill(isEnabled: true)
        let c = EditorObject(kind: .ellipse, start: CGPoint(x: 500, y: 340), end: CGPoint(x: 550, y: 390))
        let document = ProjectDocument(title: "Arrangement", pixelSize: PixelSize(width: 640, height: 480)!, objects: [a, b, c], resizedSize: PixelSize(width: 960, height: 360)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
        model.setZoom(1); model.tool = .selection; model.selection = a.id
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            let projection = EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
            return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil), modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.00001 }
        let grab = CGPoint(x: 130, y: 115), target = CGPoint(x: 268, y: 150)
        canvas.mouseDown(with: mouse(.leftMouseDown, grab)); canvas.mouseDragged(with: mouse(.leftMouseDragged, target))
        precondition(near(model.preview![0].rect.maxX, b.rect.minX) && canvas.snapGuides.contains(.init(axis: .vertical, position: 320)))
        precondition(model.history.objects == document.objects && !model.hasExportableImage)
        canvas.mouseUp(with: mouse(.leftMouseUp, target))
        let snapped = model.history.objects
        precondition(near(snapped[0].start.x, 220) && canvas.snapGuides.isEmpty)
        model.undo(); precondition(model.history.objects == document.objects); model.redo(); precondition(model.history.objects == snapped)
        model.undo(); model.selection = a.id
        canvas.mouseDown(with: mouse(.leftMouseDown, grab, modifiers: .option)); canvas.mouseDragged(with: mouse(.leftMouseDragged, target, modifiers: .option))
        precondition(near(model.preview![0].start.x, 218) && canvas.snapGuides.isEmpty)
        canvas.mouseUp(with: mouse(.leftMouseUp, target, modifiers: .option)); model.undo()
        model.selectObjectsFromList([a.id, b.id, c.id]); model.alignSelection(.center)
        let aligned = model.history.objects
        precondition(aligned.allSatisfy { near(EditorRenderer.bounds($0).midX, 315) })
        model.undo(); precondition(model.history.objects == document.objects)
        model.selectObjectsFromList([a.id, b.id, c.id]); model.distributeSelection(.horizontal)
        let arranged = model.history.objects
        let gap1 = arranged[1].rect.minX - arranged[0].rect.maxX, gap2 = arranged[2].rect.minX - arranged[1].rect.maxX
        precondition(near(gap1, gap2) && arranged[0] == a && arranged[2] == c)
        model.undo(); precondition(model.history.objects == document.objects)
        model.selectObjectsFromList([a.id, b.id]); model.groupSelection()
        let grouped = model.history.objects, box = a.rect.union(b.rect)
        let corner = CGPoint(x: box.maxX, y: box.maxY), enlarged = CGPoint(x: corner.x + 100, y: corner.y + 80)
        canvas.mouseDown(with: mouse(.leftMouseDown, corner)); canvas.mouseDragged(with: mouse(.leftMouseDragged, enlarged))
        precondition(model.preview != nil && model.history.objects == grouped)
        canvas.mouseUp(with: mouse(.leftMouseUp, enlarged))
        let scaled = model.history.objects
        precondition(near(scaled[1].end.x, enlarged.x) && near(scaled[1].end.y, enlarged.y) && scaled[2] == c)
        precondition(scaled[0].groupID == grouped[0].groupID && scaled[1].groupID == grouped[1].groupID)
        model.undo(); precondition(model.history.objects == grouped); model.redo(); precondition(model.history.objects == scaled)
        let previousRevision = model.document.revision
        model.scaleSelection(width: 1_000_000, height: 10)
        precondition(model.document.revision == previousRevision)
        let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(document.id); precondition(loaded.document.objects == scaled)
        let _ = try loaded.document.validated()
        print("Arrangement checks passed: projected live snapping/guides, Option bypass, center alignment, equal gaps, group corner scaling, one-step undo/redo, limits and persistence.")
    }
}
