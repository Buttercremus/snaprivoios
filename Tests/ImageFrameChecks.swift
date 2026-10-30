import AppKit
import SnagForgeDomain

@main struct ImageFrameChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-ImageFrames-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        func solid(_ color: NSColor, width: Int, height: Int) -> CGImage {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(color.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)); return ctx.makeImage()!
        }
        let original = solid(.white, width: 240, height: 160), blue = solid(.blue, width: 100, height: 100)
        let asset = try EditorImageAsset(png: EditorRenderer.png(image: blue, objects: []), size: PixelSize(width: 100, height: 100)!)
        var inserted = EditorObject(kind: .image, start: CGPoint(x: 100, y: 20), end: CGPoint(x: 200, y: 120)); inserted.imageAsset = asset
        let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 240, height: 160)!, objects: [inserted])
        try await store.create(document, original: EditorRenderer.png(image: original, objects: []), thumbnail: nil)
        let model = EditorModel(image: original, document: document, generation: 0, store: store, onSaved: {})
        model.selectObjectFromList(inserted.id)
        let defaultCorner = model.defaultCornerRadius, defaultStroke = model.defaultShapeStroke
        model.beginStyleEditing(); model.updateSelectedImageFrame(radius: 10, border: nil)
        model.updateSelectedImageFrame(radius: 30, border: EditorImageBorder(width: 6, color: EditorColor(red: 0, green: 1, blue: 0))); model.endStyleEditing()
        precondition(model.defaultCornerRadius == defaultCorner && model.defaultShapeStroke == defaultStroke)
        let result = try EditorRenderer.render(image: original, objects: model.history.objects)
        let corner = EditorRenderer.pixelColor(result, x: 100, y: 20)!, edge = EditorRenderer.pixelColor(result, x: 150, y: 21)!, center = EditorRenderer.pixelColor(result, x: 150, y: 70)!
        precondition(corner.redComponent > 0.99 && corner.greenComponent > 0.99, "Image corner was not clipped")
        precondition(edge.greenComponent > 0.99 && edge.blueComponent < 0.01, "Image border not rendered")
        precondition(center.blueComponent > 0.99 && center.redComponent < 0.01)
        model.undo(); precondition(model.history.objects == [inserted], "Image frame slider did not group undo")
        model.redo(); precondition(model.history.objects[0].cornerRadius == 30)
        let container = EditorCanvasContainer(model: model); container.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        container.synchronizeTransform(); let canvas = container.canvas
        let backing = NSScreen.main?.backingScaleFactor ?? 1
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        for zoom in [nil, 8.0] as [CGFloat?] {
            model.selectObjectFromList(inserted.id)
            if let zoom { model.setZoom(zoom); model.panImage(by: CGSize(width: 40, height: 20)) }
            else { model.fitImage() }
            let viewport = model.viewport, before = model.document
            let rect = viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: backing)
            // Stay clear of the selected object's enlarged resize-grip targets.
            let pixel = zoom == nil ? CGPoint(x: 40, y: 20) : CGPoint(x: 80, y: 70)
            let point = CGPoint(x: rect.minX + rect.width * pixel.x / 240, y: rect.minY + rect.height * pixel.y / 160)
            canvas.mouseDown(with: event(.leftMouseDown, at: point)); canvas.mouseUp(with: event(.leftMouseUp, at: point))
            precondition(model.isSourceImageSelected && !model.isEditingPresentation && model.selection == nil, "Source selection entered presentation mode")
            precondition(model.viewport == viewport && model.document == before, "Source selection changed zoom/pan or the document")
            precondition(model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: backing) == rect, "Source selection shrank or shifted the image")
        }
        // Frame edits stay on the same interactive canvas and use the export mask.
        model.fitImage()
        var sourceFrame = model.history.presentation
        sourceFrame.cornerRadius = 30; sourceFrame.border = EditorImageBorder(width: 6, color: EditorColor(red: 0, green: 1, blue: 0))
        model.beginPresentationEditing(); model.updatePresentation(sourceFrame); model.endPresentationEditing()
        precondition(model.isSourceImageSelected && !model.isEditingPresentation)
        let frameContext = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        frameContext.translateBy(x: 0, y: 600); frameContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: frameContext, flipped: true)
        canvas.draw(canvas.bounds); NSGraphicsContext.restoreGraphicsState()
        let framedCanvas = frameContext.makeImage()!
        let rect = model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: backing)
        let background = EditorRenderer.pixelColor(framedCanvas, x: 0, y: 0)!, rounded = EditorRenderer.pixelColor(framedCanvas, x: Int(rect.minX + 1), y: Int(rect.minY + 1))!
        let sourceBorder = EditorRenderer.pixelColor(framedCanvas, x: Int(rect.midX), y: Int(rect.minY + 1))!
        precondition(abs(background.redComponent - rounded.redComponent) < 0.01 && abs(background.greenComponent - rounded.greenComponent) < 0.01, "Source corner did not update on the editable canvas")
        precondition(sourceBorder.greenComponent > 0.99 && sourceBorder.redComponent < 0.01, "Source border did not update on the editable canvas")
        let croppedDocument = ProjectDocument(title: "Synthetic cropped frame", pixelSize: document.pixelSize,
            crop: CGRect(x: 20, y: 20, width: 160, height: 100), resizedSize: PixelSize(width: 320, height: 100)!, presentation: sourceFrame)
        let croppedModel = EditorModel(image: original, document: croppedDocument, generation: 0, store: store, onSaved: {})
        croppedModel.isEditingPresentation = false
        let croppedContainer = EditorCanvasContainer(model: croppedModel); croppedContainer.frame = container.frame; croppedContainer.synchronizeTransform()
        frameContext.clear(CGRect(x: 0, y: 0, width: 800, height: 600))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: frameContext, flipped: true)
        croppedContainer.canvas.draw(croppedContainer.canvas.bounds); NSGraphicsContext.restoreGraphicsState()
        let croppedFrame = frameContext.makeImage()!
        let croppedRect = croppedModel.viewport.imageRect(image: croppedModel.imageSize, in: croppedContainer.canvas.bounds, backingScale: backing)
        let croppedCorner = EditorRenderer.pixelColor(croppedFrame, x: Int(croppedRect.minX + 1), y: Int(croppedRect.minY + 1))!
        let croppedEdge = EditorRenderer.pixelColor(croppedFrame, x: Int(croppedRect.midX), y: Int(croppedRect.minY + 1))!
        precondition(abs(croppedCorner.redComponent - background.redComponent) < 0.01 && croppedEdge.greenComponent > 0.99 && croppedEdge.redComponent < 0.01, "Cropped/non-uniformly resized source frame used incorrect coordinates")
        model.undo(); precondition(model.history.presentation.isIdentity)
        model.selectObjectFromList(inserted.id); precondition(!model.isSourceImageSelected && model.selection == inserted.id)
        model.selectSourceImage(); model.tool = .arrow; precondition(!model.isSourceImageSelected)
        model.tool = .selection
        let sourceScale = model.viewport.scale(image: model.imageSize, in: canvas.bounds, backingScale: backing)
        model.isEditingPresentation = true
        func previewScale() -> CGFloat {
            model.viewport.scale(image: model.history.presentation.previewReferenceSize(for: document.contentPixelSize), in: canvas.bounds, backingScale: backing)
        }
        precondition(abs(previewScale() - sourceScale) < 0.000001, "Opening Gestaltung shrank the existing image")
        for padding in [40, 200, 500] {
            var padded = model.history.presentation; padded.padding = padding; model.updatePresentation(padded)
            precondition(abs(previewScale() - sourceScale) < 0.000001, "Padding shrank the inner image")
            precondition(model.document.outputPixelSize.width == 240 + padding * 2 && model.document.outputPixelSize.height == 160 + padding * 2)
        }
        model.fitImage()
        let fitted = previewScale()
        var padded = model.history.presentation; padded.padding = 300; model.updatePresentation(padded)
        precondition(abs(previewScale() - fitted) < 0.000001, "Padding after explicit Fit shrank the image")
        model.updatePresentation(.init()); model.isEditingPresentation = false
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 70, y: 70)); mask.color = EditorColor(red: 0, green: 0, blue: 0)
        model.commit([mask])
        let texture = try EditorRenderer.render(image: original, objects: [mask])
        model.isEditingPresentation = true
        let view = PresentationPreviewView(model: model, image: texture); view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        var style = EditorPresentation(); style.padding = 40; style.cornerRadius = 24; style.border = EditorImageBorder(width: 4, color: EditorColor(red: 0, green: 1, blue: 0))
        style.background = .gradient(PresentationGradient(colors: [EditorColor(red: 0, green: 0, blue: 1), EditorColor(red: 0, green: 1, blue: 0)], angle: 135))
        for angle in [-72.0, -17.5, 0, 24.6, 90, 150] {
            style.rotationDegrees = angle; model.updatePresentation(style)
            let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0, y: 600); ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
            let output = ctx.makeImage()!, geometry = style.geometry(for: document.pixelSize)!
            precondition(EditorRenderer.pixelColor(output, x: 0, y: 0)!.alphaComponent < 0.01, "Background escaped its presentation canvas")
            let previewRect = style.previewRect(for: document.pixelSize, viewport: model.viewport, in: view.bounds, backingScale: 2)!
            let local = CGPoint(x: 45, y: 45).applying(geometry.imageTransform)
            let scale = previewRect.width / CGFloat(geometry.outputSize.width)
            let sample = EditorRenderer.pixelColor(output, x: Int(previewRect.minX + local.x * scale), y: Int(previewRect.minY + local.y * scale))!
            precondition(sample.redComponent < 0.02 && sample.blueComponent < 0.02 && sample.alphaComponent > 0.99, "Live view did not rotate the unchanged texture immediately")
            precondition(view.image === texture)
        }
        let flushed = await model.flush(); precondition(flushed)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.presentation?.border == style.border)
        let reopened = EditorModel(image: original, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        reopened.isEditingPresentation = false; reopened.commit([inserted]); reopened.selectObjectFromList(inserted.id)
        reopened.updateSelectedImageFrame(radius: 30, border: EditorImageBorder())
        let finalSave = await reopened.flush(); precondition(finalSave)
        let persisted = try await store.load(document.id)
        precondition(persisted.document.objects[0].cornerRadius == 30 && persisted.document.objects[0].stroke?.isEnabled == true)
        // Individual rotation stays live at a fixed scale, expands the canvas once,
        // and preserves the opposite anchor while resizing in rotated coordinates.
        var rotationImage = inserted
        rotationImage.start = CGPoint(x: 160, y: 40); rotationImage.end = CGPoint(x: 280, y: 100)
        let rotationDoc = ProjectDocument(title: "Synthetic rotated image", pixelSize: document.pixelSize, objects: [rotationImage])
        try await store.create(rotationDoc, original: EditorRenderer.png(image: original, objects: []), thumbnail: nil)
        let rotationModel = EditorModel(image: original, document: rotationDoc, generation: 0, store: store, onSaved: {})
        let rotatedContainer = EditorCanvasContainer(model: rotationModel); rotatedContainer.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        rotatedContainer.synchronizeTransform(); let rotatedCanvas = rotatedContainer.canvas
        rotationModel.selectObjectFromList(rotationImage.id)
        let fixedScale = rotationModel.viewport.scale(image: rotationModel.imageSize, in: rotatedCanvas.bounds, backingScale: backing)
        rotationModel.beginStyleEditing()
        for angle in [15.0, 45, 90, 32.5] {
            rotationModel.updateSelectedImageRotation(angle)
            precondition(rotationModel.history.objects[0].imageRotationDegrees == angle)
            precondition(rotationModel.history.canvasRect == nil, "Live rotation prematurely changed canvas geometry")
        }
        rotationModel.endStyleEditing()
        precondition(rotationModel.history.canvasRect != nil)
        precondition(abs(fixedScale - rotationModel.viewport.scale(image: rotationModel.imageSize, in: rotatedCanvas.bounds, backingScale: backing)) < 0.000001)
        rotationModel.undo(); precondition(rotationModel.history.objects == [rotationImage] && rotationModel.history.canvasRect == nil)
        rotationModel.redo(); rotationModel.selectObjectFromList(rotationImage.id)
        let rotated = rotationModel.history.objects[0]
        let exported = try EditorRenderer.render(image: original, objects: [rotated], canvasRect: rotationModel.history.canvasRect)
        let bounds = rotationModel.history.canvasRect!
        let centerPixel = EditorRenderer.pixelColor(exported, x: Int(rotated.rect.midX - bounds.minX), y: Int(rotated.rect.midY - bounds.minY))!
        precondition(centerPixel.blueComponent > 0.99 && centerPixel.redComponent < 0.01)
        func rotationPoint(_ p: CGPoint) -> CGPoint {
            let viewRect = rotationModel.viewport.imageRect(image: rotationModel.imageSize, in: rotatedCanvas.bounds, backingScale: backing)
            return EditorImageProjection(source: rotationModel.sourceRect, destination: viewRect).viewPoint(p)
        }
        func rotationEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: rotatedCanvas.convert(rotationPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // Start in the rotated painted image, outside its unrotated rectangular box.
        rotationModel.selection = nil
        let hit = CGPoint(x: rotated.rect.midX + 46, y: rotated.rect.midY + 20).applying(rotated.imageRotationTransform)
        rotatedCanvas.mouseDown(with: rotationEvent(.leftMouseDown, hit)); rotatedCanvas.mouseUp(with: rotationEvent(.leftMouseUp, hit))
        precondition(rotationModel.selection == rotated.id, "Rotated image hit testing missed visible content")
        let anchor = rotated.start.applying(rotated.imageRotationTransform)
        let handle = rotated.end.applying(rotated.imageRotationTransform)
        let target = CGPoint(x: rotated.end.x + 35, y: rotated.end.y + 15).applying(rotated.imageRotationTransform)
        rotatedCanvas.mouseDown(with: rotationEvent(.leftMouseDown, handle))
        rotatedCanvas.mouseDragged(with: rotationEvent(.leftMouseDragged, target))
        rotatedCanvas.mouseUp(with: rotationEvent(.leftMouseUp, target))
        let resized = rotationModel.history.objects[0]
        let fixedAnchor = resized.start.applying(resized.imageRotationTransform)
        precondition(abs(anchor.x - fixedAnchor.x) < 0.001 && abs(anchor.y - fixedAnchor.y) < 0.001, "Rotated resize moved its opposite corner")
        precondition(resized.rect.width > rotated.rect.width + 25 && resized.rect.height > rotated.rect.height + 5)
        precondition(resized.imageRotationDegrees == rotated.imageRotationDegrees)
        let rotationSaved = await rotationModel.flush(); precondition(rotationSaved)
        let rotationReload = try await store.load(rotationDoc.id)
        precondition(rotationReload.document.objects == rotationModel.history.objects && rotationReload.document.canvasRect == rotationModel.history.canvasRect)
        print("Image frame checks passed: per-image clipping/border, grouped undo, source selection preserving canvas/zoom/pan, editable source frame, padding adds canvas without shrinking, immediate unchanged-texture rotation, and persistence")
    }
}
