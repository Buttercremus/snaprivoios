import AppKit
import SnagForgeDomain

@MainActor enum SelectionGripChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Grips-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.darkGray.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = context.makeImage()!, store = ProjectStore(root: root)
        let document = ProjectDocument(title: "Synthetic selection grips", pixelSize: PixelSize(width: 640, height: 480)!)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 720), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas
        canvas.frame.size = CGSize(width: 960, height: 720); canvas.synchronizeViewport()
        let frame = CGRect(x: 170, y: 120, width: 300, height: 240)
        let shape = EditorObject(kind: .rectangle, start: frame.origin, end: CGPoint(x: frame.maxX, y: frame.maxY))
        func projection() -> EditorImageProjection {
            EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(
                image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
        }
        func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func offset(_ point: CGPoint, _ delta: CGSize) -> CGPoint { CGPoint(x: point.x + delta.width, y: point.y + delta.height) }
        func near(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height) < 0.001
        }
        func checkPixels(_ path: String? = nil) throws {
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let ratio = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
            func white(_ point: CGPoint) -> Bool {
                let color = bitmap.colorAt(x: Int(point.x * ratio), y: Int(point.y * ratio))!.usingColorSpace(.deviceRGB)!
                return color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95
            }
            func whiteRun(_ centre: CGPoint, horizontal: Bool) -> CGFloat {
                var count = 1
                // Stop at the outline instead of counting nearby grips on a small selection.
                for direction in [-1, 1] {
                    for step in 1...40 {
                        let delta = CGFloat(direction * step) / ratio
                        guard white(CGPoint(x: centre.x + (horizontal ? delta : 0), y: centre.y + (horizontal ? 0 : delta))) else { break }
                        count += 1
                    }
                }
                return CGFloat(count) / ratio
            }
            for handle in EditorResizeHandle.allCases {
                let centre = projection().viewPoint(handle.point(in: frame))
                precondition(white(centre), "Editor grip lost its white centre")
                let expected: CGSize = switch handle {
                case .top, .bottom: CGSize(width: 20.5, height: 6.5)
                case .left, .right: CGSize(width: 6.5, height: 20.5)
                default: CGSize(width: 8.5, height: 8.5)
                }
                let measured = CGSize(width: whiteRun(centre, horizontal: true), height: whiteRun(centre, horizontal: false))
                precondition(abs(measured.width - expected.width) < 2.5 && abs(measured.height - expected.height) < 2.5,
                             "Grip \(handle): measured \(measured), expected \(expected), scale \(projection().scaleX)/\(projection().scaleY), crop \(model.cropDraft != nil)")
                if handle.isCorner {
                    precondition(!white(offset(centre, CGSize(width: 4.5, height: 4.5))), "Corner grip became square")
                }
            }
            if let path { try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }
        }
        func enlargedGrab(_ handle: EditorResizeHandle) -> CGPoint {
            let centre = projection().viewPoint(handle.point(in: frame))
            let delta: CGSize = switch handle {
            case .top, .bottom: CGSize(width: 0, height: handle.movesTop ? -9 : 9)
            case .left, .right: CGSize(width: handle.movesLeft ? -9 : 9, height: 0)
            default: CGSize(width: handle.movesLeft ? -9 : 9, height: handle.movesTop ? -9 : 9)
            }
            return offset(centre, delta)
        }
        for output in [PixelSize(width: 640, height: 480)!, PixelSize(width: 960, height: 240)!] {
            precondition(model.applyImageSize(output))
            for zoom: CGFloat in [0.5, 1, 4] {
                model.commit([shape]); model.selection = shape.id; model.tool = .selection; model.setZoom(zoom)
                try checkPixels(output.width == 640 && zoom == 1 ? "/tmp/Snaprivo-EditorGrips.png" : nil)
                let png = try EditorRenderer.png(image: image, objects: [shape], resizedSize: model.document.resizedSize)
                for handle in EditorResizeHandle.allCases {
                    model.selection = shape.id
                    let from = enlargedGrab(handle), to = offset(from, CGSize(width: 12, height: 8))
                    let p = projection(), delta = CGSize(width: 12 / p.scaleX, height: 8 / p.scaleY)
                    canvas.mouseDown(with: mouse(.leftMouseDown, at: from))
                    canvas.mouseUp(with: mouse(.leftMouseUp, at: to))
                    let expected = EditorGeometry.resized(frame, handle: handle, delta: delta, minimum: CGSize(width: 4 / p.scaleX, height: 4 / p.scaleY))
                    precondition(near(model.history.objects[0].rect, expected), "Extended form grip \(handle) at \(p.scaleX)/\(p.scaleY): \(model.history.objects[0].rect) instead of \(expected)")
                    model.undo(); precondition(model.history.objects == [shape], "Form resize was not one undo step")
                }
                let unchanged = try EditorRenderer.png(image: image, objects: model.history.objects, resizedSize: model.document.resizedSize)
                precondition(unchanged == png, "Selection chrome affected exported PNG pixels")
                model.beginCrop(); model.cropDraft = frame; model.setZoom(zoom)
                try checkPixels(output.width == 640 && zoom == 1 ? "/tmp/Snaprivo-CropGrips.png" : nil)
                for handle in EditorResizeHandle.allCases {
                    model.cropDraft = frame
                    let from = enlargedGrab(handle), to = offset(from, CGSize(width: 12, height: 8))
                    let p = projection(), delta = CGSize(width: 12 / p.scaleX, height: 8 / p.scaleY)
                    canvas.mouseDown(with: mouse(.leftMouseDown, at: from))
                    canvas.mouseUp(with: mouse(.leftMouseUp, at: to))
                    precondition(model.cropDraft == EditorCrop.resized(frame, handle: handle, by: delta, in: document.pixelSize),
                                 "Extended crop grip did not resize the intended edge")
                }
                model.cancelCrop()
            }
        }
        // Closest handle wins when enlarged hit areas overlap on a tiny shape or crop.
        model.setZoom(1)
        let tiny = EditorObject(kind: .rectangle, start: CGPoint(x: 300, y: 220), end: CGPoint(x: 314, y: 238))
        model.commit([tiny]); model.selection = tiny.id
        let from = projection().viewPoint(EditorResizeHandle.right.point(in: tiny.rect)), to = offset(from, CGSize(width: 12, height: 0))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: from)); canvas.mouseUp(with: mouse(.leftMouseUp, at: to))
        precondition(model.history.objects[0].rect.height == tiny.rect.height && model.history.objects[0].rect.width > tiny.rect.width)
        model.undo()
        model.beginCrop(); model.cropDraft = tiny.rect
        let cropFrom = projection().viewPoint(EditorResizeHandle.right.point(in: tiny.rect))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: cropFrom)); canvas.mouseUp(with: mouse(.leftMouseUp, at: offset(cropFrom, CGSize(width: 12, height: 0))))
        precondition(model.cropDraft!.height == tiny.rect.height && model.cropDraft!.width > tiny.rect.width)
        model.cancelCrop()
        let saved = await model.flush(); precondition(saved)
        print("Shared grip checks passed: actual round/pill pixels and constant point sizes at 50/100/400%, unlocked image aspect ratio, expanded form/crop hit targets in all eight directions, tiny overlapping handles, one-step undo and unchanged PNG pixels.")
    }
}
