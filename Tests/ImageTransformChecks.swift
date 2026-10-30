import AppKit
import SnagForgeDomain

@main struct ImageTransformChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Transform-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 40, width: 60, height: 40))
        context.setFillColor(NSColor.green.cgColor); context.fill(CGRect(x: 60, y: 0, width: 60, height: 40))
        let image = context.makeImage()!
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30)); mask.color = EditorColor(red: 0, green: 0, blue: 0)
        let document = ProjectDocument(title: "Synthetic transform", pixelSize: PixelSize(width: 120, height: 80)!, objects: [mask])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = EditorCanvasContainer(model: model); window.contentView = container; container.frame = CGRect(x: 0,y:0,width:500,height:400)
        let canvas = container.canvas
        func color(_ image: CGImage, _ point: CGPoint) -> NSColor { EditorRenderer.pixelColor(image, x: Int(point.x), y: Int(point.y))! }
        func same(_ a: NSColor, _ b: NSColor) -> Bool { abs(a.redComponent-b.redComponent)<0.02 && abs(a.greenComponent-b.greenComponent)<0.02 && abs(a.blueComponent-b.blueComponent)<0.02 && abs(a.alphaComponent-b.alphaComponent)<0.02 }
        let samples = [CGPoint(x: 20.5,y:20.5),CGPoint(x:45.5,y:30.5),CGPoint(x:90.5,y:65.5),CGPoint(x:90.5,y:10.5)]
        let baseline = try EditorRenderer.render(image: image, objects: [mask])
        for transform in EditorImageTransform.allCases + [.identity,.mirrored,.identity] {
            model.transformImage(transform); container.synchronizeTransform()
            let result = try EditorRenderer.render(image: image, objects: model.history.objects, transform: transform)
            let expected = transform.applying(to: document.pixelSize)
            precondition(result.width == expected.width && result.height == expected.height)
            for point in samples {
                let destination = point.applying(transform.affineTransform(size: CGSize(width:120,height:80)))
                precondition(same(color(baseline,point),color(result,destination)), "Transformed pixel or opaque redaction changed")
            }
            // AppKit coordinate conversion must match the exported image, including reflections.
            let localRect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let localPoint = CGPoint(x: localRect.minX + 20*localRect.width/120, y: localRect.minY + 30*localRect.height/80)
            let shown = canvas.convert(localPoint,to:container)
            let returned = canvas.convert(shown,from:container)
            precondition(hypot(returned.x-localPoint.x,returned.y-localPoint.y)<0.001)
            let visual = canvas.convert(localRect,to:container)
            let unit = CGPoint(x:20.0/120,y:30.0/80).applying(transform.affineTransform(size:CGSize(width:1,height:1)))
            precondition(abs(shown.x-(visual.minX+unit.x*visual.width))<0.001 && abs(shown.y-(visual.minY+unit.y*visual.height))<0.001, "Native input transform differs from export")
            // All eight symmetries are editable through the existing source-space canvas.
            model.tool = .arrow
            func event(_ type: NSEvent.EventType,_ point: CGPoint) -> NSEvent {
                let location = CGPoint(x:localRect.minX+point.x*localRect.width/120,y:localRect.minY+point.y*localRect.height/80)
                return NSEvent.mouseEvent(with:type,location:canvas.convert(location,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            }
            let before = model.history.objects.count
            canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:45,y:45)))
            canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:100,y:55)))
            canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:100,y:55)))
            precondition(model.history.objects.count == before+1 && model.history.objects.last?.kind == .arrow)
            model.undo(); precondition(model.history.objects == [mask])
        }
        model.transformImage(.clockwise90)
        precondition(model.applyImageSize(PixelSize(width:160,height:240)!))
        precondition(model.document.outputPixelSize == PixelSize(width:160,height:240)!)
        let flushed = await model.flush(); precondition(flushed)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.transform == .clockwise90)
        let reopened = EditorModel(image:image, document:loaded.document,generation:loaded.generation,store:store,onSaved:{})
        precondition(reopened.history.transform == .clockwise90 && reopened.document.outputPixelSize == model.document.outputPixelSize)
        window.close()
        print("Image transform checks passed: all 8 pixel mappings, redactions, native input, undo, resize and persisted reopening")
    }
}
