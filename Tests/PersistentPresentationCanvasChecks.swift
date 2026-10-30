import AppKit
import SnagForgeDomain

@main struct PersistentPresentationCanvasChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-PersistentFrame-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let ctx = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        let image = ctx.makeImage()!
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 40, y: 30), end: CGPoint(x: 100, y: 80))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        let transforms: [EditorImageTransform] = [.identity, .clockwise90, .clockwise90.flippedHorizontally(), .identity.flippedVertically()]
        for (index, transform) in transforms.enumerated() {
            let document = ProjectDocument(title: "Synthetic persistent frame", pixelSize: PixelSize(width: 320, height: 180)!,
                objects: [mask], crop: CGRect(x: 20, y: 10, width: 260, height: 140), resizedSize: PixelSize(width: 500, height: 170)!, transform: transform)
            try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
            let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let container = EditorCanvasContainer(model: model); window.contentView = container
            container.frame = CGRect(x: 0, y: 0, width: 900, height: 650); container.synchronizeTransform()
            let backing = window.backingScaleFactor
            var style = EditorPresentation(); style.padding = 70; style.cornerRadius = 24; style.shadowStrength = 0.3
            style.rotationDegrees = [-32.5, 0, 28.5, 75][index]
            style.aspectRatio = .wide; style.alignment = .bottomTrailing
            style.background = .solid(EditorColor(red: 0, green: 0, blue: 1))
            style.border = EditorImageBorder(width: 8, color: EditorColor(red: 0, green: 1, blue: 0))
            model.isEditingPresentation = true
            model.beginPresentationEditing(); model.updatePresentation(style); model.endPresentationEditing()
            let scaleBefore = model.viewport.scale(image: model.viewportImageSize, in: container.bounds, backingScale: backing)
            let canvas = container.canvas
            func projection() -> EditorImageProjection { EditorImageProjection(source: model.sourceRect, destination: canvas.presentationImageRect!) }
            func displayed(_ point: CGPoint) -> CGPoint {
                let source = model.sourceRect, output = model.document.untransformedOutputPixelSize
                let raw = CGPoint(x: (point.x - source.minX) / source.width * CGFloat(output.width),
                                  y: (point.y - source.minY) / source.height * CGFloat(output.height))
                let transformed = raw.applying(model.history.transform.affineTransform(size: CGSize(width: output.width, height: output.height)))
                let geometry = style.geometry(for: model.document.contentPixelSize)!
                let rect = style.previewRect(for: model.document.contentPixelSize, viewport: model.viewport, in: container.bounds, backingScale: backing)!
                let scale = rect.width / CGFloat(geometry.outputSize.width)
                let presented = transformed.applying(geometry.imageTransform)
                return CGPoint(x: rect.minX + presented.x * scale, y: rect.minY + presented.y * scale)
            }
            func renderedCanvas() -> CGImage {
                let output = CGContext(data: nil, width: 900, height: 650, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                output.translateBy(x: 0, y: 650); output.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: output, flipped: true)
                container.draw(container.bounds)
                let origin = canvas.convert(CGPoint.zero, to: container)
                let x = canvas.convert(CGPoint(x: 1, y: 0), to: container), y = canvas.convert(CGPoint(x: 0, y: 1), to: container)
                output.saveGState(); output.clip(to: container.bounds)
                output.concatenate(CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y, c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y))
                canvas.draw(canvas.bounds); output.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                return output.makeImage()!
            }
            for tool in [AnnotationTool.arrow, .text, .rectangle, .blur, .selection] {
                model.tool = tool; model.isEditingPresentation = false; container.synchronizeTransform()
                precondition(model.history.presentation == style && model.document.presentation == style, "Tool switch changed presentation")
                precondition(abs(model.viewport.scale(image: model.viewportImageSize, in: container.bounds, backingScale: backing) - scaleBefore) < 0.000001, "Tool switch changed image scale")
                for point in [CGPoint(x: 70, y: 55), CGPoint(x: 180, y: 100)] {
                    let actual = canvas.convert(projection().viewPoint(point), to: container), expected = displayed(point)
                    precondition(hypot(actual.x - expected.x, actual.y - expected.y) < 0.001, "Native pointer coordinates disagree with exported presentation")
                }
                let rendered = renderedCanvas()
                let rect = style.previewRect(for: model.document.contentPixelSize, viewport: model.viewport, in: container.bounds, backingScale: backing)!
                let background = EditorRenderer.pixelColor(rendered, x: Int(rect.minX + 3), y: Int(rect.minY + 3))!
                precondition(background.blueComponent > 0.99 && background.redComponent < 0.01, "Frame/background disappeared on tool switch")
                let point = displayed(CGPoint(x: 70, y: 55))
                let covered = EditorRenderer.pixelColor(rendered, x: Int(point.x), y: Int(point.y))!
                precondition(covered.redComponent < 0.03 && covered.blueComponent < 0.03, "Native content was not composed above the background")
                let edgePoint = CGPoint(x: model.sourceRect.midX, y: model.sourceRect.minY + model.sourceRect.height * 3 / CGFloat(model.document.untransformedOutputPixelSize.height))
                let edge = displayed(edgePoint)
                let green = EditorRenderer.pixelColor(rendered, x: Int(edge.x), y: Int(edge.y))!
                precondition(green.greenComponent > 0.85 && green.redComponent < 0.1, "Image border disappeared from native canvas")
            }
            model.tool = .arrow; container.synchronizeTransform()
            func event(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(projection().viewPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
            }
            let start = CGPoint(x: 130, y: 100), end = CGPoint(x: 230, y: 120)
            canvas.mouseDown(with: event(.leftMouseDown, start)); canvas.mouseDragged(with: event(.leftMouseDragged, end)); canvas.mouseUp(with: event(.leftMouseUp, end))
            guard let arrow = model.history.objects.last, arrow.kind == .arrow else { preconditionFailure("Cannot annotate the framed image") }
            precondition(hypot(arrow.start.x - start.x, arrow.start.y - start.y) < 0.001 && hypot(arrow.end.x - end.x, arrow.end.y - end.y) < 0.001)
            model.undo(); precondition(model.history.objects == [mask] && model.history.presentation == style)
            model.redo(); precondition(model.history.presentation == style)
            model.tool = .text; model.defaultFontSize = 16
            let textStart = CGPoint(x: 120, y: 50)
            canvas.mouseDown(with: event(.leftMouseDown, textStart)); canvas.mouseUp(with: event(.leftMouseUp, textStart))
            let text = canvas.subviews.first!.subviews.first as! NSTextView
            text.insertText("Live Text", replacementRange: NSRange(location: NSNotFound, length: 0))
            guard let textObject = model.history.objects.last, textObject.kind == .text else { preconditionFailure("Cannot type on the framed image") }
            precondition(hypot(textObject.start.x - textStart.x, textObject.start.y - textStart.y) < 0.001, "Native text was placed at the wrong image coordinate")
            model.finishTextEditing(); canvas.synchronizeTextEditor()
            let wordPoint = CGPoint(x: textStart.x + 5, y: textStart.y + 5)
            canvas.mouseDown(with: event(.leftMouseDown, wordPoint, clicks: 2)); canvas.mouseUp(with: event(.leftMouseUp, wordPoint, clicks: 2))
            let selectedText = canvas.subviews.first!.subviews.first as! NSTextView
            precondition(selectedText.selectedRange() == NSRange(location: 0, length: 4), "Native text selection missed after free rotation/mirroring")
            model.finishTextEditing(); canvas.synchronizeTextEditor()
            model.setZoom(2); model.panImage(by: CGSize(width: 40, height: 20)); container.synchronizeTransform()
            let actual = canvas.convert(projection().viewPoint(start), to: container), expected = displayed(start)
            precondition(hypot(actual.x - expected.x, actual.y - expected.y) < 0.001, "Zoom/pan lost presentation coordinate mapping")
            let saved = await model.flush(); precondition(saved)
            let loaded = try await store.load(document.id); precondition(loaded.document.presentation == style)
            // Removing and restoring the last layout effect must preserve the current pixel scale too.
            model.fitImage(); container.synchronizeTransform()
            let fittedScale = model.viewport.scale(image: model.viewportImageSize, in: container.bounds, backingScale: backing)
            model.updatePresentation(EditorPresentation()); container.synchronizeTransform()
            precondition(abs(model.viewport.scale(image: model.viewportImageSize, in: container.bounds, backingScale: backing) - fittedScale) < 0.000001)
            model.updatePresentation(style); container.synchronizeTransform()
            precondition(abs(model.viewport.scale(image: model.viewportImageSize, in: container.bounds, backingScale: backing) - fittedScale) < 0.000001)
            let restoredSaved = await model.flush(); precondition(restoredSaved)
            window.close()
        }
        print("Persistent presentation canvas checks passed: backgrounds/borders across tool switches, fixed scale, free/global rotations and mirrors, crop/nonuniform resize, live arrow/text coordinates and native word selection, zoom/pan, undo and persistence")
    }
}
