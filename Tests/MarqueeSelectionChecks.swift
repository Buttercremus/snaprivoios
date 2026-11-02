import AppKit
import SnagForgeDomain

/// Real canvas events in an offscreen window; only synthetic pixels and project files.
@MainActor enum MarqueeSelectionChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Marquee-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        var a = EditorObject(kind: .rectangle, start: CGPoint(x: 80, y: 80), end: CGPoint(x: 180, y: 150))
        a.fill = EditorFill(isEnabled: true)
        var b = EditorObject(kind: .rectangle, start: CGPoint(x: 260, y: 180), end: CGPoint(x: 340, y: 250))
        b.fill = EditorFill(isEnabled: true)
        let c = EditorObject(kind: .ellipse, start: CGPoint(x: 460, y: 340), end: CGPoint(x: 550, y: 410))
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 220, y: 300), end: CGPoint(x: 340, y: 300))
        let original = [a, b, c, arrow]
        let transforms: [EditorImageTransform] = [.identity, .clockwise90, .clockwise90.flippedHorizontally()]
        for transform in transforms {
            let document = ProjectDocument(title: "Marquee", pixelSize: PixelSize(width: 640, height: 480)!,
                objects: original, crop: CGRect(x: 40, y: 40, width: 560, height: 400),
                resizedSize: PixelSize(width: 840, height: 300)!, transform: transform)
            try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
            let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
            model.snapsToObjects = false
            let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 900, height: 700),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let container = EditorCanvasContainer(model: model); window.contentView = container
            container.frame.size = CGSize(width: 900, height: 700); container.synchronizeTransform()
            let canvas = container.canvas
            func mouse(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                let rect = canvas.presentationImageRect ?? model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
                let projection = EditorImageProjection(source: model.sourceRect, destination: rect)
                return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil),
                    modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func key(_ code: UInt16) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: code)!
            }
            func drag(_ from: CGPoint, _ to: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
                canvas.mouseDown(with: mouse(.leftMouseDown, from, modifiers: modifiers))
                canvas.mouseDragged(with: mouse(.leftMouseDragged, to, modifiers: modifiers))
                canvas.mouseUp(with: mouse(.leftMouseUp, to, modifiers: modifiers))
            }
            for zoom: Double in [0.65, 1.6] {
                model.selection = c.id
                model.setZoom(zoom); container.synchronizeTransform()
                let revision = model.document.revision
                let anchor = CGPoint(x: 50, y: 50), end = CGPoint(x: 365, y: 270)
                canvas.mouseDown(with: mouse(.leftMouseDown, anchor))
                precondition(canvas.marqueeRect == nil && !model.isCanvasGestureActive)
                canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
                let frame = canvas.marqueeRect!
                precondition(abs(frame.minX - 50) < 0.0001 && abs(frame.minY - 50) < 0.0001 &&
                    abs(frame.width - 315) < 0.0001 && abs(frame.height - 220) < 0.0001)
                precondition(model.isCanvasGestureActive && !model.canActOnSelection && !model.hasExportableImage)
                canvas.keyDown(with: key(51)); model.undo()
                precondition(model.history.objects == original && model.document.revision == revision,
                    "Delete/Undo must not run during a marquee gesture")
                precondition(model.selectedIDs == [c.id], "Marquee must remain a transient preview until release")
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                canvas.mouseUp(with: mouse(.leftMouseUp, end))
                precondition(model.selectedIDs == [a.id, b.id] && canvas.marqueeRect == nil && !model.isSourceImageSelected)
                precondition(model.document.revision == revision && model.history.objects == original)
                canvas.keyDown(with: key(51))
                precondition(model.history.objects == [c, arrow], "Delete must remove every marked object and preserve neighbours")
                model.undo(); precondition(model.history.objects == original, "Multi-delete must be one undo step")
                model.redo(); precondition(model.history.objects == [c, arrow]); model.undo()

                // Reverse direction, partial intersections, and Shift adding to the previous selection.
                model.selection = c.id
                drag(end, anchor, modifiers: .shift)
                precondition(model.selectedIDs == [a.id, b.id, c.id])
                model.selection = nil
                drag(CGPoint(x: 205, y: 165), CGPoint(x: 150, y: 130))
                precondition(model.selectedIDs == [a.id], "An intersected object must join the marquee")

                // A horizontal arrow has a zero-height logical rect but visible painted bounds.
                model.selection = nil
                drag(CGPoint(x: 190, y: 280), CGPoint(x: 360, y: 320))
                precondition(model.selectedIDs == [arrow.id])

                model.selection = c.id
                canvas.mouseDown(with: mouse(.leftMouseDown, anchor))
                canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
                canvas.keyDown(with: key(53))
                canvas.mouseUp(with: mouse(.leftMouseUp, end))
                precondition(model.selectedIDs == [c.id] && canvas.marqueeRect == nil && !model.isCanvasGestureActive,
                    "Escape must preserve the pre-gesture selection")

                // Empty drags clear selection without selecting/deleting the original image.
                drag(CGPoint(x: 380, y: 60), CGPoint(x: 420, y: 110))
                precondition(model.selectedIDs.isEmpty && !model.isSourceImageSelected)
                canvas.mouseDown(with: mouse(.leftMouseDown, anchor))
                canvas.mouseUp(with: mouse(.leftMouseUp, anchor))
                precondition(model.isSourceImageSelected && model.selectedIDs.isEmpty, "A plain background click must still select the source")

                // Starting outside the cropped image is allowed; cropped-out objects stay excluded.
                model.selection = nil
                drag(CGPoint(x: 30, y: 30), end)
                precondition(model.selectedIDs == [a.id, b.id])
            }
            model.selection = a.id
            canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 50, y: 50)))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 365, y: 270)))
            model.tool = .arrow; canvas.synchronizeMarqueeSelection()
            precondition(canvas.marqueeRect == nil && !model.isCanvasGestureActive && model.selectedIDs == [a.id])
            canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 365, y: 270)))
            model.tool = .selection

            let hidden = EditorObject(kind: .rectangle, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 25, y: 25))
            model.commit(original + [hidden]); model.selection = nil
            drag(CGPoint(x: 0, y: 0), CGPoint(x: 35, y: 35))
            precondition(model.selectedIDs.isEmpty, "Objects entirely outside the crop must stay unselected")
            model.undo(); precondition(model.history.objects == original)

            // Group membership remains atomic when only one member intersects the frame.
            model.selectObjects([a.id, c.id]); model.groupSelection()
            model.selection = nil
            drag(CGPoint(x: 50, y: 50), CGPoint(x: 200, y: 165))
            precondition(model.selectedIDs == [a.id, c.id])
            let grouped = model.history.objects
            canvas.keyDown(with: key(117))
            precondition(model.history.objects == [b, arrow])
            model.undo(); precondition(model.history.objects == grouped)
            model.redo(); precondition(model.history.objects == [b, arrow])
            let saved = await model.flush(); precondition(saved)
            let loaded = try await store.load(document.id)
            precondition(loaded.document.objects == [b, arrow] && loaded.document.crop == document.crop && loaded.document.transform == transform)
        }
        print("Marquee checks passed: live frame, transient selection, forward/reverse/partial/Shift selection, zoom/nonuniform resize/crop/rotation/mirroring, horizontal arrows, outside-image starts, Escape/tool cancellation, plain source click, grouped backward/forward deletion, single undo/redo and persistence.")
    }
}
