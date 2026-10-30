import AppKit
import SnagForgeDomain

@MainActor enum InstructionToolChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-InstructionTools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x: 100, y: 350, width: 200, height: 10))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        let document = ProjectDocument(title: "Markieren und Liste (synthetisch)", pixelSize: PixelSize(width: 640, height: 480)!)
        let store = ProjectStore(root: root)
        try await store.create(document, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.snapsToObjects = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.frame.size = CGSize(width: 800, height: 600); canvas.synchronizeViewport()
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let projection = EditorImageProjection(source: model.sourceRect,
                destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
            return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func click(_ point: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, point)); canvas.mouseUp(with: event(.leftMouseUp, point))
        }
        func drag(_ points: [CGPoint]) {
            canvas.mouseDown(with: event(.leftMouseDown, points[0]))
            for point in points.dropFirst() { canvas.mouseDragged(with: event(.leftMouseDragged, point)) }
            canvas.mouseUp(with: event(.leftMouseUp, points.last!))
        }
        model.tool = .steps
        for point in [CGPoint(x: 400, y: 80), CGPoint(x: 500, y: 80), CGPoint(x: 580, y: 180)] { click(point) }
        precondition(model.history.objects.compactMap { $0.stepStyle?.label } == ["1", "2", "3"] && model.tool == .steps)
        model.undo(); precondition(model.nextStepLabel == "3" && model.history.objects.count == 2)
        model.redo(); precondition(model.nextStepLabel == "4" && model.history.objects.count == 3)
        model.selection = nil
        var style = model.defaultStepStyle; style.numbering = .letters; style.shape = .pointer
        model.updateStepStyle(style)
        click(CGPoint(x: 400, y: 350)); click(CGPoint(x: 500, y: 350))
        precondition(model.history.objects.suffix(2).compactMap { $0.stepStyle?.label } == ["A", "B"])
        style = model.activeStepStyle; style.index = 26; model.updateStepStyle(style)
        precondition(model.nextStepLabel == "AA")
        click(CGPoint(x: 580, y: 350)); precondition(model.history.objects.last?.stepStyle?.label == "AA")
        let step = model.history.objects.last!
        model.duplicateSelection(); precondition(model.history.objects.last?.stepStyle?.label == "AB" && model.history.objects.last?.id != step.id)
        model.undo(); precondition(model.history.objects.last == step)
        model.tool = .selection; model.selection = step.id
        model.beginStyleEditing(); model.updateStepSize(96); model.updateStepSize(120); model.endStyleEditing()
        precondition(model.selectedObject?.rect.width == 120 && model.selectedObject?.stepStyle == step.stepStyle)
        model.undo(); precondition(model.history.objects.last == step)
        model.selection = step.id
        drag([CGPoint(x: step.rect.midX, y: step.rect.midY), CGPoint(x: step.rect.midX - 20, y: step.rect.midY - 15)])
        precondition(model.history.objects.last == step.translated(by: CGSize(width: -20, height: -15)))
        model.undo(); precondition(model.history.objects.last == step)
        model.selection = step.id
        drag([CGPoint(x: step.rect.maxX, y: step.rect.maxY), CGPoint(x: step.rect.maxX + 20, y: step.rect.maxY + 10)])
        let resizedStep = model.history.objects.last!
        precondition(resizedStep.id == step.id && resizedStep.stepStyle == step.stepStyle && resizedStep.rect.width > step.rect.width
                     && abs(resizedStep.rect.width - resizedStep.rect.height) < 0.001, "Badge handle resize lost its square geometry or style")
        model.undo(); precondition(model.history.objects.last == step)

        model.setHighlightMode(.rectangle)
        drag([CGPoint(x: 80, y: 100), CGPoint(x: 350, y: 150)])
        let rectangle = model.history.objects.last!
        precondition(rectangle.kind == .highlight && model.tool == .highlight && rectangle.highlightStyle?.points.isEmpty == true)
        let marked = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: model.history.objects))!
        let paper = marked.colorAt(x: 90, y: 110)!.usingColorSpace(.deviceRGB)!
        let ink = marked.colorAt(x: 150, y: 125)!.usingColorSpace(.deviceRGB)!
        precondition(paper.redComponent > 0.95 && paper.blueComponent > 0.5 && paper.blueComponent < 0.8, "Textmarker is opaque or missing")
        precondition(ink.redComponent < 0.01 && ink.greenComponent < 0.01 && ink.blueComponent < 0.01, "Textmarker weakened black source text")
        model.tool = .selection; model.selection = rectangle.id
        drag([rectangle.end, CGPoint(x: rectangle.end.x + 20, y: rectangle.end.y + 10)])
        precondition(model.history.objects.last?.end == CGPoint(x: rectangle.end.x + 20, y: rectangle.end.y + 10)
                     && model.history.objects.last?.highlightStyle == rectangle.highlightStyle, "Rectangle marker handle resize lost geometry or style")
        model.undo(); precondition(model.history.objects.last == rectangle)
        model.setHighlightMode(.freehand)
        let beforeStroke = model.history.objects
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 70, y: 210)))
        precondition(model.preview?.last?.highlightStyle?.points == [CGPoint(x: 70, y: 210)], "Initial marker dot was not previewed")
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 70, y: 210)))
        precondition(model.preview == nil && model.history.objects == beforeStroke && model.tool == .highlight, "Escape committed a canceled marker stroke or changed tools")
        let path = [CGPoint(x: 80, y: 220), CGPoint(x: 200, y: 240), CGPoint(x: 140, y: 300), CGPoint(x: 80, y: 220)]
        drag(path)
        let freehand = model.history.objects.last!
        precondition(freehand.highlightStyle?.points == path && model.tool == .highlight, "Closed freehand stroke did not commit or changed tool")
        click(CGPoint(x: 350, y: 280))
        precondition(model.history.objects.last?.highlightStyle?.points.count == 1, "Freehand click did not create a dot")
        let dotted = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: model.history.objects))!
        precondition(dotted.colorAt(x: 350, y: 280)!.usingColorSpace(.deviceRGB)!.blueComponent < 0.8, "Freehand dot was not rendered")
        model.tool = .selection; model.selection = freehand.id
        drag([CGPoint(x: 130, y: 228), CGPoint(x: 150, y: 243)])
        precondition(model.history.objects.first { $0.id == freehand.id } == freehand.translated(by: CGSize(width: 20, height: 15)), "Freehand hit testing or movement lost path points")
        model.undo(); model.selection = freehand.id
        model.beginStyleEditing(); model.updateHighlightOpacity(0.25); model.updateHighlightOpacity(0.45); model.endStyleEditing()
        model.undo(); precondition(model.history.objects.first { $0.id == freehand.id } == freehand)
        model.redo(); precondition(model.history.objects.first { $0.id == freehand.id }?.highlightStyle?.opacity == 0.45)

        // Every badge shape renders both background and fitted glyphs, including long labels.
        var previous: Data?
        for (index, shape) in EditorStepShape.allCases.enumerated() {
            var badge = EditorObject(kind: .step, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 120))
            badge.stepStyle = EditorStepStyle(index: index == 3 ? 10000 : index + 1, numbering: index.isMultiple(of: 2) ? .numbers : .letters, shape: shape)
            let png = try EditorRenderer.png(image: image, objects: [badge])
            let bitmap = NSBitmapImageRep(data: png)!
            var glyphPixels = 0, fillPixels = 0
            for y in 40..<100 { for x in 40..<100 where EditorRenderer.stepPath(badge).contains(CGPoint(x: x, y: y)) {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.greenComponent > 0.9 && color.blueComponent > 0.9 { glyphPixels += 1 }
                if color.redComponent > 0.8 && color.greenComponent < 0.3 { fillPixels += 1 }
            } }
            precondition(glyphPixels > 10 && fillPixels > 100 && png != previous, "Badge shape or glyph missing")
            previous = png
        }
        let preview = try EditorRenderer.png(image: image, objects: model.history.objects)
        try preview.write(to: URL(fileURLWithPath: "/tmp/Snaprivo-InstructionTools-Preview.png"))
        var redact = EditorObject(kind: .redact, start: CGPoint(x: 390, y: 60), end: CGPoint(x: 430, y: 100))
        redact.color = EditorColor(red: 0, green: 0, blue: 0)
        let protected = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [redact] + model.history.objects,
            resizedSize: PixelSize(width: 320, height: 240)))!
        let hidden = protected.colorAt(x: 205, y: 40)!.usingColorSpace(.deviceRGB)!
        precondition(hidden.redComponent == 0 && hidden.greenComponent == 0 && hidden.blueComponent == 0 && hidden.alphaComponent == 1,
                     "Instruction objects painted over an opaque redaction")

        model.beginCrop(); model.cropDraft = CGRect(x: 40, y: 40, width: 560, height: 400); model.applyCrop()
        precondition(model.applyImageSize(PixelSize(width: 280, height: 200)!))
        let png = try EditorRenderer.png(image: image, objects: model.history.objects, crop: model.document.crop, resizedSize: model.document.resizedSize)
        let output = NSBitmapImageRep(data: png)!
        precondition(output.pixelsWide == 280 && output.pixelsHigh == 200)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Snaprivo-Instructions-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        model.copyPNG(to: pasteboard)
        for _ in 0..<500 where model.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!model.isExporting && model.error == nil && pasteboard.data(forType: .png) == png)
        let saved = await model.flush(); precondition(saved)
        let loaded = try await ProjectStore(root: root).load(document.id)
        let reopened = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        reopened.snapsToObjects = false
        precondition(reopened.history.objects == model.history.objects && reopened.document.outputPixelSize == PixelSize(width: 280, height: 200))
        precondition(reopened.nextStepIndex == 4)
        reopened.defaultStepStyle.numbering = .letters; precondition(reopened.nextStepLabel == "AB")
        precondition(NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil) != nil && NSImage(systemSymbolName: "list.number", accessibilityDescription: nil) != nil)
        print("Instruction tools passed: click numbering, A/Z/AA/AB, duplicate/undo, badge movement/handle resize and grouped size edits, rectangle resize/freehand/closed-loop/dot markers, initial preview/Escape, readable source text, all badge shapes/glyphs, redaction order, crop/resize PNG/clipboard equality and persistence/reopened counters.")
    }
}
