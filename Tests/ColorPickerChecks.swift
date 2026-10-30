import AppKit
import SwiftUI
import SnagForgeDomain

/// Synthetic native events stay inside an offscreen fixture window.
@main struct ColorPickerChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-ColorPicker-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (rect, color) in [
            (CGRect(x: 0, y: 40, width: 60, height: 40), NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: 60, y: 40, width: 60, height: 40), NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 0, width: 60, height: 40), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: 60, y: 0, width: 60, height: 40), NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 0.5))
        ] { context.setFillColor(color.cgColor); context.fill(rect) }
        context.clear(CGRect(x: 0, y: 70, width: 10, height: 10))
        let image = context.makeImage()!
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 15, y: 15), end: CGPoint(x: 35, y: 35))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        var presentation = EditorPresentation()
        presentation.rotationDegrees = 23; presentation.padding = 20
        presentation.background = .solid(EditorColor(red: 1, green: 0, blue: 1))
        let sourcePoints = [CGPoint(x: 25.375, y: 25.375), CGPoint(x: 45.375, y: 20.375),
                            CGPoint(x: 85.375, y: 20.375), CGPoint(x: 45.375, y: 60.375), CGPoint(x: 85.375, y: 60.375)]
        var caseCount = 0
        for style in [EditorPresentation(), presentation] {
            for transform in EditorImageTransform.allCases {
                let crop = CGRect(x: 10, y: 10, width: 100, height: 60)
                let resized = PixelSize(width: 200, height: 90)!
                let document = ProjectDocument(title: "Synthetic Pipette", pixelSize: PixelSize(width: 120, height: 80)!,
                    objects: [mask], crop: crop, resizedSize: resized, transform: transform, presentation: style)
                let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
                model.isEditingPresentation = false; model.tool = .arrow; model.selection = mask.id
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let container = EditorCanvasContainer(model: model)
                window.contentView = container; container.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
                container.synchronizeTransform()
                let canvas = container.canvas
                let state = ImageColorPickerState(); state.activate(); await state.prepare(model)
                precondition(state.image?.width == document.outputPixelSize.width && state.image?.height == document.outputPixelSize.height)
                let actions = EditorCanvasColorPicking(sample: { state.sample($0, fixed: $1) }, move: { state.move($0) }, cancel: { state.end() })
                let originalViewport = model.viewport
                container.synchronizeColorPicking(actions)
                let picker = container.colorPickingView!
                precondition(window.firstResponder === picker && canvas.isPickingColor && model.viewport == originalViewport)
                precondition(canvas.quickOptionsObjectID == nil && window.attachedSheet == nil)
                func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: picker.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                func key(_ code: UInt16) -> NSEvent {
                    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
                }
                for zoom in [1.0, 2.7, 8.0] {
                    canvas.synchronizeViewport(); model.setZoom(zoom)
                    model.panImage(by: CGSize(width: 12, height: -8))
                    container.synchronizeTransform()
                    let localRect = canvas.presentationImageRect ?? model.viewport.imageRect(image: model.imageSize,
                        in: canvas.bounds, backingScale: window.backingScaleFactor)
                    for source in sourcePoints {
                        let local = CGPoint(x: localRect.minX + (source.x - crop.minX) * localRect.width / crop.width,
                                            y: localRect.minY + (source.y - crop.minY) * localRect.height / crop.height)
                        let shown = canvas.convert(local, to: picker)
                        guard picker.bounds.contains(shown) else { continue }
                        var expected = CGPoint(x: (source.x - crop.minX) * 2, y: (source.y - crop.minY) * 1.5)
                            .applying(transform.affineTransform(size: CGSize(width: 200, height: 90)))
                        if style.requiresCanvasLayout { expected = expected.applying(style.geometry(for: document.contentPixelSize)!.imageTransform) }
                        state.resume(); picker.mouseMoved(with: event(.mouseMoved, at: shown))
                        precondition(state.x == Int(expected.x) && state.y == Int(expected.y),
                            "Canvas/export coordinates differ for \(transform), zoom \(zoom), presentation \(style.requiresCanvasLayout): \(state.x),\(state.y) vs \(expected)")
                        let expectedColor = EditorRenderer.pixelColor(state.image!, x: Int(expected.x), y: Int(expected.y))!
                        precondition(abs(state.color!.redComponent - expectedColor.redComponent) < 0.02
                            && abs(state.color!.greenComponent - expectedColor.greenComponent) < 0.02
                            && abs(state.color!.blueComponent - expectedColor.blueComponent) < 0.02
                            && abs(state.color!.alphaComponent - expectedColor.alphaComponent) < 0.02)
                        precondition(picker.cursor(at: shown) === CanvasColorPickingView.pipetteCursor)
                        picker.mouseDown(with: event(.leftMouseDown, at: shown)); picker.mouseUp(with: event(.leftMouseUp, at: shown))
                        let held = CGPoint(x: state.x, y: state.y)
                        picker.mouseMoved(with: event(.mouseMoved, at: CGPoint(x: shown.x + 5, y: shown.y)))
                        precondition(state.isFixed && CGPoint(x: state.x, y: state.y) == held, "Hover replaced a held pixel")
                        precondition(model.history.objects == [mask] && model.document.revision == 0 && model.selectedIDs == [mask.id]
                            && model.tool == .arrow && !model.isCanvasGestureActive, "Picking edited the document or changed the previous tool")
                        caseCount += 1
                    }
                }
                picker.keyDown(with: key(49))
                let center = CGPoint(x: picker.bounds.midX, y: picker.bounds.midY)
                picker.mouseDown(with: event(.leftMouseDown, at: center))
                picker.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: center.x + 10, y: center.y + 5)))
                picker.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: center.x + 10, y: center.y + 5)))
                picker.keyUp(with: key(49))
                precondition(window.firstResponder === picker && !model.isCanvasGestureActive && model.history.objects == [mask],
                    "Space-panning lost picker focus or edited annotations")
                if style.requiresCanvasLayout {
                    model.setZoom(1); container.synchronizeTransform()
                    let rect = container.colorPickingImageRect
                    let corner = CGPoint(x: rect.minX + rect.width * 0.5 / CGFloat(state.image!.width),
                                         y: rect.minY + rect.height * 0.5 / CGFloat(state.image!.height))
                    picker.mouseDown(with: event(.leftMouseDown, at: corner)); picker.mouseUp(with: event(.leftMouseUp, at: corner))
                    precondition(state.x == 0 && state.y == 0 && state.hex == "#FF00FF", "Presentation background was not sampled")
                }
                state.setPixel(x: Int.min, y: Int.max)
                precondition(state.x == 0 && state.y == state.image!.height - 1)
                picker.keyDown(with: key(124)); precondition(state.x == 1)
                picker.keyDown(with: key(126)); precondition(state.y == state.image!.height - 2)
                state.sample(CGPoint(x: CGFloat.nan, y: 0), fixed: true)
                precondition(state.x == 1, "Invalid coordinate changed the sample")
                picker.keyDown(with: key(53)); container.synchronizeColorPicking(nil)
                precondition(!state.isActive && state.image == nil && container.colorPickingView == nil && !canvas.isPickingColor)
                precondition(window.firstResponder === canvas)
                window.close()
            }
        }
        // Transparent pixels and alpha use exact sRGB export pixels, excluding viewport/checkerboard colors.
        let plain = EditorModel(image: image, document: ProjectDocument(title: "Alpha", pixelSize: PixelSize(width: 120, height: 80)!),
            generation: 0, store: store, onSaved: {})
        let state = ImageColorPickerState(); state.activate(); await state.prepare(plain)
        state.setPixel(x: 2, y: 2); precondition(state.color!.alphaComponent == 0)
        state.setPixel(x: 85, y: 60); precondition(abs(state.color!.alphaComponent - 0.5) < 0.01 && state.hex == "#FFFF00")
        state.setPixel(x: 45, y: 20); precondition(state.hex == "#FF0000")
        state.end()
        let cancelled = Task { await state.prepare(plain) }; cancelled.cancel(); await cancelled.value
        precondition(state.image == nil && state.color == nil)
        print("Color picker passed: \(caseCount) native hover/click samples across all 8 transforms, crop/nonuniform resize, zoom/pan, free rotation/background, held color, cursor, keyboard, focus restoration, unchanged document, exact sRGB/alpha and cancelled rendering.")
    }
}
