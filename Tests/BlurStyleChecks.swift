import AppKit
import SnagForgeDomain

@main struct BlurStyleChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-BlurStyles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let width = 256, height = 160
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<height {
            for x in 0..<width {
                ctx.setFillColor(NSColor(srgbRed: (x / 3).isMultiple(of: 2) ? 0.9 : 0.2,
                    green: CGFloat(y % 23) / 30 + 0.1, blue: CGFloat((x + y) % 19) / 30 + 0.3, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = ctx.makeImage()!
        var object = EditorObject(kind: .blur, start: CGPoint(x: 40, y: 48), end: CGPoint(x: 216, y: 112)); object.blurRadius = 24
        let document = ProjectDocument(title: "Synthetic filter", pixelSize: PixelSize(width: width, height: height)!, objects: [object])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.selectObjectFromList(object.id)
        let container = EditorCanvasContainer(model: model); container.frame = CGRect(x: 0, y: 0, width: 800, height: 600); container.synchronizeTransform()
        let canvas = container.canvas, backing = NSScreen.main?.backingScaleFactor ?? 1
        model.setZoom(backing)
        let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: backing)
        func canvasColor(x: Int = 128, y: Int = 80) -> NSColor {
            let bitmap = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            bitmap.translateBy(x: 0, y: 600); bitmap.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
            canvas.draw(canvas.bounds); NSGraphicsContext.restoreGraphicsState()
            return EditorRenderer.pixelColor(bitmap.makeImage()!, x: Int(rect.minX) + x, y: Int(rect.minY) + y)!
        }
        func equal(_ a: NSColor, _ b: NSColor) -> Bool {
            abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02 && abs(a.blueComponent - b.blueComponent) < 0.02
        }
        let pending = canvasColor()
        precondition(pending.redComponent < 0.01 && pending.greenComponent < 0.01 && pending.blueComponent < 0.01, "Pending filter exposed unfiltered pixels")
        var outputs = Set<Data>()
        var completedColor: NSColor?
        for style in EditorBlurStyle.allCases {
            model.updateStyle(blurStyle: style)
            if let completedColor {
                precondition(equal(canvasColor(), completedColor), "Changing filter style flashed a placeholder over a completed frame")
            }
            let rendered = try EditorRenderer.render(image: image, objects: model.history.objects)
            let expected = EditorRenderer.pixelColor(rendered, x: 128, y: 80)!
            precondition(equal(EditorRenderer.pixelColor(image, x: 20, y: 20)!, EditorRenderer.pixelColor(rendered, x: 20, y: 20)!), "Filter escaped its rectangle")
            precondition(!equal(expected, EditorRenderer.pixelColor(image, x: 128, y: 80)!), "Filter did not change the selected region")
            outputs.insert(try EditorRenderer.png(image: rendered, objects: []))
            canvas.refreshComposition()
            var ready = false
            for _ in 0..<300 {
                if equal(canvasColor(), expected) { ready = true; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(ready, "Canvas did not match exported filter pixels")
            completedColor = expected
            let shared = try await model.pngShareItemForToolbar!.writeTemporaryPNG(in: root)
            let sharedImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(shared as CFURL, nil)!, 0, nil)!
            precondition(equal(expected, EditorRenderer.pixelColor(sharedImage, x: 128, y: 80)!), "Shared PNG used a different filter")
            precondition(model.makeObject(kind: .blur, start: .zero).effectiveBlurStyle == style)
            let saved = await model.flush(); precondition(saved)
            let reopened = try await store.load(document.id)
            precondition(reopened.document.objects[0].effectiveBlurStyle == style)
            var mask = EditorObject(kind: .redact, start: CGPoint(x: 100, y: 60), end: CGPoint(x: 156, y: 100)); mask.color = EditorColor(red: 0, green: 0, blue: 0)
            let covered = try EditorRenderer.render(image: image, objects: [mask] + model.history.objects)
            let coveredPixel = EditorRenderer.pixelColor(covered, x: 128, y: 80)!
            precondition(coveredPixel.redComponent < 0.01 && coveredPixel.greenComponent < 0.01 && coveredPixel.blueComponent < 0.01, "Opaque mask was filtered or reordered")
        }
        precondition(outputs.count == 3, "Blur styles produced identical output")
        let unmoved = model.history.objects
        let moved = [unmoved[0].translated(by: CGSize(width: 20, height: 0))]
        model.commit(moved)
        let newlyCovered = canvasColor(x: 230, y: 80)
        let expectedMoved = try EditorRenderer.render(image: image, objects: moved)
        precondition(equal(newlyCovered, EditorRenderer.pixelColor(expectedMoved, x: 230, y: 80)!), "Cached movement did not immediately filter the newly covered region")
        precondition(equal(canvasColor(x: 45, y: 80), EditorRenderer.pixelColor(image, x: 45, y: 80)!), "Moving the filter left its previous pixels behind")
        precondition(equal(canvasColor(), completedColor!), "Moving a filter flashed its already filtered overlap")
        model.commit(unmoved)
        // No await between pointer updates and pixel reads: movement must reuse prepared source pixels.
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = container
        defer { window.close() }
        model.snapsToObjects = false
        model.selectObjectFromList(unmoved[0].id)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let local = CGPoint(x: rect.minX + point.x, y: rect.minY + point.y)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 128, y: 80)))
        for offset in 1...20 {
            canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 128 + offset, y: 80)))
            let expected = try EditorRenderer.render(image: image, objects: model.objects)
            let sample = model.objects[0].rect.maxX >= 232 ? 225 : Int(model.objects[0].rect.midX)
            precondition(equal(canvasColor(x: sample, y: 80), EditorRenderer.pixelColor(expected, x: sample, y: 80)!), "Live filter pixels lagged behind the mouse")
        }
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 148, y: 80)))
        model.undo(); precondition(model.history.objects == unmoved, "Blur movement was not one undo step")
        model.selectObjectFromList(unmoved[0].id)
        // Pixelated squares retain one sampled color inside each block.
        var pixels = object; pixels.blurStyle = .pixelate; pixels.blurRadius = 24
        let pixelated = try EditorRenderer.render(image: image, objects: [pixels])
        precondition(equal(EditorRenderer.pixelColor(pixelated, x: 121, y: 73)!, EditorRenderer.pixelColor(pixelated, x: 125, y: 77)!), "Pixelation did not produce stable blocks")
        let before = model.history.objects
        model.beginStyleEditing(); model.updateStyle(blur: 16, blurStyle: .pixelate); model.updateStyle(blur: 40); model.endStyleEditing()
        model.undo(); precondition(model.history.objects == before, "Filter gesture did not group undo")
        model.redo(); precondition(model.history.objects[0].effectiveBlurStyle == .pixelate && model.history.objects[0].blurRadius == 40)
        let saved = await model.flush(); precondition(saved)
        print("Blur checks passed: three filters, bounded/stable blocks, pending-frame coverage, immediate cached mouse movement and source restoration, live/export/share agreement, masks, grouped undo, persistence and defaults")
    }
}
