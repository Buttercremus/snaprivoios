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
        print("Repeated-tool checks passed: two consecutive arrows, all shape variants, blur/redaction, text/callouts after Escape/Command-Return, one-object undo/redo, explicit Selection and persistence.")
    }
}
