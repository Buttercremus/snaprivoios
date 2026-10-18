import SwiftUI
import AppKit
import SnagForgeDomain

struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel
    func makeNSView(context: Context) -> CanvasView { CanvasView(model: model) }
    func updateNSView(_ view: CanvasView, context: Context) {
        _ = model.objects; _ = model.selectedIDs; _ = model.selection; _ = model.tool; _ = model.editingTextObject
        _ = model.viewport; _ = model.cropDraft; _ = model.document.crop; _ = model.document.resizedSize
        _ = model.isSwitchingImage
        view.model = model
        view.synchronizeViewport()
        view.synchronizeTextEditor()
        view.synchronizeFocus()
        view.window?.invalidateCursorRects(for: view)
        view.refreshComposition()
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: CanvasView, coordinator: ()) {
        view.model.endStyleEditing()
        view.model.finishTextEditing()
    }
}

@MainActor
final class CanvasView: NSView, NSTextViewDelegate {
    var model: EditorModel
    var lastFocusRequest = 0
    private var start: CGPoint?
    private var original: [EditorObject] = []
    private var draggedID: UUID?
    private var gestureObject: EditorObject?
    private var filteredImage: CGImage?
    private var renderedBlurs: [EditorObject] = []
    private var requestedBlurs: [EditorObject] = []
    private var assetTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var textView: InlineTextView?
    private var textClipView: NSView?
    private var textID: UUID?
    private var creatingText = false
    private var creationRect: CGRect?
    private var textSelectionAnchor: NSRange?
    private var textSelectionGranularity: NSSelectionGranularity = .selectByCharacter
    private var textResizeFromLeft: Bool?
    private var arrowEndpoint: ArrowEndpoint?
    private var draggingCalloutTip = false
    private var resizeHandle: EditorResizeHandle?
    private var lastDragPoint: CGPoint?
    private var isSpaceHeld = false
    private var panGesture: (anchor: CGPoint, viewport: EditorViewport)?
    private enum CropAction { case draw, move, resize(EditorResizeHandle) }
    private var cropGesture: (anchor: CGPoint, rect: CGRect, action: CropAction)?
    private enum ArrowEndpoint { case start, end }

    func refreshComposition() {
        let assets = model.objects.filter { $0.imageAsset.map { EditorRenderer.cachedAssetImage($0) == nil } == true }
        if !assets.isEmpty, assetTask == nil {
            assetTask = Task { [weak self] in
                defer { self?.assetTask = nil }
                do { try await Task.detached { try EditorRenderer.validateAssets(assets) }.value }
                catch { self?.model.error = error.localizedDescription }
                self?.needsDisplay = true
            }
        }
        requestedBlurs = model.objects.filter { $0.kind == .blur }
        if requestedBlurs.isEmpty { filteredImage = nil; renderedBlurs = [] }
        guard renderTask == nil, requestedBlurs != renderedBlurs else { return }
        // At most one filter job. Show completed frames, then process the latest
        // pointer position. Continuous movement never restarts a debounce.
        renderTask = Task { [weak self] in
            guard let self else { return }
            defer { renderTask = nil }
            while requestedBlurs != renderedBlurs {
                let snapshot = requestedBlurs, image = model.image
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        // Keep untouched text at source resolution even when a blur is present.
                        try EditorRenderer.render(image: image, objects: snapshot)
                    }.value
                    if !requestedBlurs.isEmpty { filteredImage = result; renderedBlurs = snapshot }
                    else { filteredImage = nil; renderedBlurs = [] }
                } catch {
                    renderedBlurs = snapshot; model.error = error.localizedDescription
                }
                needsDisplay = true
            }
        }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { !model.isSwitchingImage }
    override func hitTest(_ point: NSPoint) -> NSView? {
        model.isSwitchingImage ? nil : super.hitTest(point)
    }
    init(model: EditorModel) {
        self.model = model; super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Bildfläche"))
        setAccessibilityHelp(String(localized: "Scrollen verschiebt das Bild. Leertaste und Ziehen schwenkt. ⌘ plus Mausrad oder Aufziehen auf dem Trackpad zoomt."))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    private var imageRect: CGRect {
        model.viewport.imageRect(image: model.imageSize, in: bounds, backingScale: backingScale)
    }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1 }
    private var projection: EditorImageProjection { EditorImageProjection(source: model.sourceRect, destination: imageRect) }
    private var scaleX: CGFloat { projection.scaleX }
    private var scaleY: CGFloat { projection.scaleY }
    private var scale: CGFloat { min(scaleX, scaleY) }
    private func viewPoint(_ point: CGPoint) -> CGPoint { projection.viewPoint(point) }
    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        projection.sourcePoint(convert(event.locationInWindow, from: nil))
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { projection.distance(a, b) }
    func synchronizeViewport() {
        model.viewportBounds = bounds; model.viewportBackingScale = backingScale
    }
    func synchronizeFocus() {
        // SwiftUI can request focus before the replacement canvas has joined its window.
        guard lastFocusRequest != model.focusRequest, !model.isSwitchingImage, let window else { return }
        if model.editingTextObject != nil || window.makeFirstResponder(self) {
            lastFocusRequest = model.focusRequest
        }
    }
    private func viewportChanged() {
        synchronizeTextEditor(); needsDisplay = true; displayIfNeeded()
        window?.invalidateCursorRects(for: self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeViewport()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: window)
        }
        synchronizeFocus()
    }
    @objc private func windowResigned(_ notification: Notification) {
        isSpaceHeld = false
        if panGesture != nil { panGesture = nil; model.isCanvasGestureActive = false }
        if let cropGesture { model.cropDraft = cropGesture.rect; self.cropGesture = nil; model.isCanvasGestureActive = false; needsDisplay = true }
        window?.invalidateCursorRects(for: self)
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeViewport(); viewportChanged()
    }
    override func magnify(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        guard !model.isCanvasGestureActive else { return }
        synchronizeViewport()
        model.zoomBy(exp(event.magnification), at: convert(event.locationInWindow, from: nil))
        viewportChanged()
    }
    override func smartMagnify(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        guard !model.isCanvasGestureActive else { return }
        synchronizeViewport()
        if model.viewport.zoom == nil { model.setZoom(1, at: convert(event.locationInWindow, from: nil)) }
        else { model.fitImage() }
        viewportChanged()
    }
    override func scrollWheel(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        guard !model.isCanvasGestureActive else { return }
        synchronizeViewport()
        if event.modifierFlags.contains(.command) {
            model.zoomBy(exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)),
                         at: convert(event.locationInWindow, from: nil))
        } else {
            let speed: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            let horizontal = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
            model.panImage(by: CGSize(width: (horizontal ? event.scrollingDeltaY : event.scrollingDeltaX) * speed,
                                     height: horizontal ? 0 : event.scrollingDeltaY * speed))
        }
        viewportChanged()
    }
    private func hit(_ point: CGPoint) -> EditorObject? {
        EditorLayers.paintOrder(model.history.objects).reversed().first {
            object in
            if object.kind == .arrow {
                if object.effectiveDrawingStyle == .handDrawn {
                    let origin = viewPoint(.zero)
                    var transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: origin.x, ty: origin.y)
                    let path = EditorHandDrawn.path(for: object).copy(using: &transform)!
                    return path.copy(strokingWithWidth: max(16, object.lineWidth * max(scaleX, scaleY) * 4),
                                     lineCap: .round, lineJoin: .round, miterLimit: 10).contains(viewPoint(point))
                }
                var projected = object; projected.start = viewPoint(object.start); projected.end = viewPoint(object.end)
                return projected.hitsArrow(viewPoint(point), tolerance: max(8, object.lineWidth * max(scaleX, scaleY) * 2))
            }
            if object.kind == .callout {
                return EditorRenderer.calloutPath(object).contains(point)
                    || EditorRenderer.calloutBox(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY).contains(point)
            }
            if object.kind == .step { return EditorRenderer.stepPath(object).contains(point) }
            if object.kind == .highlight, object.effectiveHighlightStyle.mode == .freehand {
                return EditorRenderer.highlightPath(object).copy(strokingWithWidth: object.lineWidth + 8 / scale,
                    lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
            }
            return EditorRenderer.bounds(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY).contains(point)
        }
    }
    private func endpoint(at point: CGPoint, of object: EditorObject) -> ArrowEndpoint? {
        guard object.kind == .arrow else { return nil }
        let fromStart = visible(object.start) ? distance(object.start, point) : .infinity
        let fromEnd = visible(object.end) ? distance(object.end, point) : .infinity
        guard min(fromStart, fromEnd) <= 10 else { return nil }
        return fromEnd <= fromStart ? .end : .start
    }
    private func visible(_ point: CGPoint) -> Bool {
        let rect = model.sourceRect
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
    private func resizeBox(_ object: EditorObject) -> CGRect? {
        if (object.kind.isShape || object.kind == .image) || object.kind == .redact || object.kind == .step
            || object.kind == .highlight && object.effectiveHighlightStyle.mode == .rectangle { return object.rect }
        if object.kind == .callout { return EditorRenderer.calloutBox(object) }
        return nil
    }
    private func handle(at point: CGPoint, of object: EditorObject) -> EditorResizeHandle? {
        guard let rect = resizeBox(object) else { return nil }
        // Find the closest handle even on small shapes with overlapping hit areas.
        return EditorResizeHandle.allCases.filter {
            visible($0.point(in: rect)) && gripHitRect($0, in: rect).contains(viewPoint(point))
        }.min {
            let a = $0.point(in: rect), b = $1.point(in: rect)
            return distance(a, point) < distance(b, point)
        }
    }
    private func gripHitRect(_ handle: EditorResizeHandle, in rect: CGRect) -> CGRect {
        SelectionGrips.hitRect(at: viewPoint(handle.point(in: rect)), shape: handle.gripShape)
    }
    private func resizeCursor(_ handle: EditorResizeHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch handle {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
    override func resetCursorRects() {
        if isSpaceHeld || panGesture != nil {
            addCursorRect(bounds, cursor: panGesture == nil ? .openHand : .closedHand)
            return
        }
        addCursorRect(imageRect, cursor: model.tool == .selection ? .arrow : model.tool == .text || model.tool == .callout ? .iBeam : .crosshair)
        if let crop = model.cropDraft {
            if crop != model.originalRect {
                let origin = viewPoint(crop.origin)
                addCursorRect(CGRect(origin: origin, size: CGSize(width: crop.width * scaleX, height: crop.height * scaleY)).intersection(imageRect), cursor: .openHand)
            }
            for handle in EditorResizeHandle.allCases {
                addCursorRect(gripHitRect(handle, in: crop), cursor: resizeCursor(handle))
            }
            return
        }
        if model.tool == .selection, let object = model.selectedObject, object.kind == .arrow {
            for point in [object.start, object.end] where visible(point) {
                let point = viewPoint(point)
                addCursorRect(CGRect(x: point.x - 10, y: point.y - 10,
                                     width: 20, height: 20), cursor: .crosshair)
            }
        }
        if model.tool == .selection, let object = model.selectedObject, object.kind == .text || object.kind == .callout {
            let rect = textBoxRect(object)
            let origin = viewPoint(rect.origin)
            addCursorRect(CGRect(x: origin.x, y: origin.y,
                                 width: rect.width * scaleX, height: rect.height * scaleY).intersection(imageRect), cursor: .iBeam)
            if model.editingTextObject == nil, object.kind == .text {
                for handle in textWidthHandles(object) where visible(handle) {
                    let handle = viewPoint(handle)
                    addCursorRect(SelectionGrips.hitRect(at: handle, shape: .vertical), cursor: .resizeLeftRight)
                }
            }
        }
        if model.tool == .selection, model.editingTextObject == nil,
           let object = model.selectedObject, let rect = resizeBox(object) {
            for handle in EditorResizeHandle.allCases {
                guard visible(handle.point(in: rect)) else { continue }
                addCursorRect(gripHitRect(handle, in: rect), cursor: resizeCursor(handle))
            }
        }
        if model.tool == .selection, let object = model.selectedObject, object.kind == .callout,
           model.editingTextObject == nil, visible(EditorRenderer.calloutTip(object)) {
            let tip = viewPoint(EditorRenderer.calloutTip(object))
            addCursorRect(CGRect(x: tip.x - 10, y: tip.y - 10, width: 20, height: 20), cursor: .crosshair)
        }
    }
    override func layout() {
        super.layout()
        synchronizeViewport()
        synchronizeTextEditor()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill(); bounds.fill()
        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY); context.scaleBy(x: scaleX, y: scaleY)
        context.translateBy(x: -model.sourceRect.minX, y: -model.sourceRect.minY)
        context.clip(to: model.sourceRect)
        let displayedImage = filteredImage ?? model.image
        let pixels = context.convertToDeviceSpace(CGRect(x: 0, y: 0, width: model.image.width, height: model.image.height)).standardized.size
        let pixelScaleX = pixels.width / CGFloat(displayedImage.width)
        let pixelScaleY = pixels.height / CGFloat(displayedImage.height)
        // Preserve exact pixels at 100% and integer magnifications. Fractional
        // scales/downsampling use high quality directly from the source image.
        let integerScale = pixelScaleX >= 1 && pixelScaleY >= 1
            && abs(pixelScaleX - pixelScaleX.rounded()) < 0.0001
            && abs(pixelScaleY - pixelScaleY.rounded()) < 0.0001
        context.interpolationQuality = integerScale ? .none : .high
        EditorRenderer.drawBase(image: displayedImage, in: context,
                                size: CGSize(width: model.image.width, height: model.image.height))
        EditorRenderer.drawAnnotations(objects: model.objects, in: context, editingTextID: model.editingTextObject?.id, cachedAssetsOnly: true)
        let selected = model.editingTextObject ?? model.objects.first { $0.id == model.selection }
        if model.selectedIDs.count > 1 {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1.5 / scale)
            for object in model.objects where model.selectedIDs.contains(object.id) {
                context.stroke(EditorRenderer.bounds(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY))
            }
        } else if let selected { drawOutline(selected, in: context) }
        else if let object = gestureObject, object.kind == .blur { drawOutline(object, in: context) }
        if let creationRect {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1 / scale)
            context.stroke(creationRect)
        }
        if let crop = model.cropDraft { drawCrop(crop, in: context) }
        context.restoreGState()
    }
    private func drawCrop(_ crop: CGRect, in context: CGContext) {
        let mask = CGMutablePath(); mask.addRect(model.originalRect); mask.addRect(crop)
        context.addPath(mask); context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.drawPath(using: .eoFill)
        context.setStrokeColor(NSColor.white.cgColor); context.setLineWidth(3 / scale); context.stroke(crop)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1 / scale); context.stroke(crop)
        context.saveGState(); context.clip(to: crop)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        for fraction: CGFloat in [1 / 3, 2 / 3] {
            context.move(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.minY))
            context.addLine(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.maxY))
            context.move(to: CGPoint(x: crop.minX, y: crop.minY + crop.height * fraction))
            context.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + crop.height * fraction))
        }
        context.strokePath(); context.restoreGState()
        context.saveGState()
        context.translateBy(x: model.sourceRect.minX, y: model.sourceRect.minY)
        context.scaleBy(x: 1 / scaleX, y: 1 / scaleY)
        for handle in EditorResizeHandle.allCases {
            let source = handle.point(in: crop)
            let centre = CGPoint(x: (source.x - model.sourceRect.minX) * scaleX, y: (source.y - model.sourceRect.minY) * scaleY)
            SelectionGrips.draw(at: centre, shape: handle.gripShape, in: context)
        }
        context.restoreGState()
    }
    private func cropHandle(at point: CGPoint, in rect: CGRect) -> EditorResizeHandle? {
        return EditorResizeHandle.allCases.filter { gripHitRect($0, in: rect).contains(viewPoint(point)) }.min {
            let a = $0.point(in: rect), b = $1.point(in: rect)
            return distance(a, point) < distance(b, point)
        }
    }
    private func updateCrop(with event: NSEvent) {
        guard let gesture = cropGesture else { return }
        let point = pixelPoint(event), size = model.document.pixelSize
        let delta = CGSize(width: point.x - gesture.anchor.x, height: point.y - gesture.anchor.y)
        switch gesture.action {
        case .move: model.cropDraft = EditorCrop.moved(gesture.rect, by: delta, in: size)
        case .resize(let handle): model.cropDraft = EditorCrop.resized(gesture.rect, handle: handle, by: delta, in: size)
        case .draw:
            if hypot(delta.width, delta.height) * scale >= 3 {
                model.cropDraft = EditorCrop.normalized(CGRect(x: gesture.anchor.x, y: gesture.anchor.y,
                                                              width: delta.width, height: delta.height), in: size) ?? gesture.rect
            }
        }
        needsDisplay = true; displayIfNeeded()
    }
    private func textBoxRect(_ object: EditorObject) -> CGRect {
        let measured = EditorRenderer.textRect(object)
        let minimumWidth: CGFloat = object.textWidth == nil ? (object.text.isEmpty ? 100 / scaleX : 24 / scaleX) : 0
        return CGRect(origin: measured.origin, size: CGSize(width: max(measured.width, minimumWidth),
                                                           height: max(measured.height, object.fontSize * 1.3)))
    }
    private func textWidthHandles(_ object: EditorObject) -> [CGPoint] {
        let rect = textBoxRect(object).insetBy(dx: -3 / scaleX, dy: -3 / scaleY)
        return [CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)]
    }
    private func drawOutline(_ object: EditorObject, in context: CGContext) {
        // Draw selection chrome in view points, so unlocked aspect ratios never stretch handles or strokes.
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: model.sourceRect.minX, y: model.sourceRect.minY)
        context.scaleBy(x: 1 / scaleX, y: 1 / scaleY)
        func point(_ source: CGPoint) -> CGPoint {
            CGPoint(x: (source.x - model.sourceRect.minX) * scaleX, y: (source.y - model.sourceRect.minY) * scaleY)
        }
        func rect(_ source: CGRect) -> CGRect {
            CGRect(origin: point(source.origin), size: CGSize(width: source.width * scaleX, height: source.height * scaleY))
        }
        context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1.5)
        context.setFillColor(NSColor.white.cgColor)
        if object.kind == .arrow {
            for source in [object.start, object.end] {
                SelectionGrips.draw(at: point(source), shape: .corner, in: context)
            }
            return
        }
        if object.kind == .callout, model.editingTextObject == nil {
            SelectionGrips.draw(at: point(EditorRenderer.calloutTip(object)), shape: .corner, in: context)
        }
        let outline: CGRect
        if object.kind == .callout, model.editingTextObject == nil { outline = EditorRenderer.calloutBox(object) }
        else if object.kind == .text || object.kind == .callout { outline = textBoxRect(object) }
        else { outline = EditorRenderer.bounds(object) }
        let viewRect = rect(outline)
        context.stroke(resizeBox(object) != nil && model.editingTextObject == nil ? viewRect : viewRect.insetBy(dx: -3, dy: -3))
        if model.editingTextObject == nil, let box = resizeBox(object) {
            for handle in EditorResizeHandle.allCases {
                SelectionGrips.draw(at: point(handle.point(in: box)), shape: handle.gripShape, in: context)
            }
        } else if object.kind == .text, model.editingTextObject == nil {
            for source in textWidthHandles(object) {
                SelectionGrips.draw(at: point(source), shape: .vertical, in: context)
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        synchronizeViewport()
        defer { model.isCanvasGestureActive = start != nil || textSelectionAnchor != nil || panGesture != nil || cropGesture != nil }
        // Reset gesture state before any early return (e.g. clicks outside the image).
        start = nil; draggedID = nil; gestureObject = nil; arrowEndpoint = nil; resizeHandle = nil; draggingCalloutTip = false; lastDragPoint = nil
        model.preview = nil
        model.endStyleEditing()
        let previousSelection = model.selection
        model.finishTextEditing()
        synchronizeTextEditor()
        creatingText = false; creationRect = nil; textSelectionAnchor = nil; textResizeFromLeft = nil
        window?.makeFirstResponder(self)
        if isSpaceHeld {
            panGesture = (convert(event.locationInWindow, from: nil), model.viewport)
            window?.invalidateCursorRects(for: self)
            return
        }
        let point = pixelPoint(event)
        if let crop = model.cropDraft {
            if !event.modifierFlags.contains(.option), let handle = cropHandle(at: point, in: crop) {
                cropGesture = (point, crop, .resize(handle))
            } else if imageRect.contains(convert(event.locationInWindow, from: nil)) {
                let move = crop != model.originalRect && crop.contains(point) && !event.modifierFlags.contains(.option)
                cropGesture = (point, crop, move ? .move : .draw)
            }
            needsDisplay = true
            return
        }
        if model.tool == .selection, let object = model.selectedObject, object.kind == .callout,
           visible(EditorRenderer.calloutTip(object)), distance(EditorRenderer.calloutTip(object), point) <= 10 {
            draggingCalloutTip = true; draggedID = object.id; start = point; original = model.history.objects
            needsDisplay = true
            return
        }
        // Visible handles also accept clicks just outside the image at its edges.
        if model.tool == .selection, let object = model.selectedObject, let handle = handle(at: point, of: object) {
            resizeHandle = handle; draggedID = object.id; start = point; original = model.history.objects
            needsDisplay = true
            return
        }
        if model.tool == .selection, let object = model.selectedObject, let endpoint = endpoint(at: point, of: object) {
            arrowEndpoint = endpoint; draggedID = object.id; start = point; original = model.history.objects
            needsDisplay = true
            return
        }
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { model.selection = nil; needsDisplay = true; return }
        if model.tool == .steps {
            model.placeStep(at: point); needsDisplay = true; window?.invalidateCursorRects(for: self)
            return
        }
        if model.tool == .selection, let object = model.selectedObject, object.kind == .text,
           let edge = textWidthHandles(object).firstIndex(where: {
               visible($0) && SelectionGrips.hitRect(at: viewPoint($0), shape: .vertical).contains(viewPoint(point))
           }) {
            textResizeFromLeft = edge == 0
            draggedID = object.id; start = point; original = model.history.objects
            return
        }
        if model.tool == .text || model.tool == .callout {
            if let object = hit(point), object.kind == .text || object.kind == .callout {
                beginTextSelection(object, with: event)
                return
            }
            model.editText(at: point); start = point; creatingText = true
            synchronizeTextEditor()
            needsDisplay = true
            return
        }
        if model.tool == .selection {
            let object = hit(point)
            if let object, event.modifierFlags.contains(.shift) {
                model.select(object.id, extending: true); needsDisplay = true; return
            }
            if let object {
                if !model.selectedIDs.contains(object.id) { model.select(object.id) }
            } else { model.selection = nil }
            if model.selectedIDs.count > 1 {
                draggedID = object?.id; start = point; original = model.history.objects
                needsDisplay = true; return
            }
            if let object, (object.kind == .text || object.kind == .callout),
               textBoxRect(object).contains(point), (event.clickCount >= 2 || previousSelection == object.id) {
                beginTextSelection(object, with: event)
                return
            }
            draggedID = object?.id
            if let object { arrowEndpoint = endpoint(at: point, of: object) }
        }
        start = point; original = model.history.objects
        if let kind = model.drawingKind {
            guard model.history.objects.count < 10_000 else { start = nil; model.notice = String(localized: "Die Projektgrenze von 10.000 Objekten ist erreicht."); return }
            model.selection = nil
            gestureObject = model.makeObject(kind: kind, start: point, end: point)
            if kind == .highlight, gestureObject?.highlightStyle?.mode == .freehand, let object = gestureObject {
                model.preview = original + [object]
            }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if cropGesture != nil { updateCrop(with: event); return }
        if let panGesture {
            let point = convert(event.locationInWindow, from: nil)
            model.viewport = panGesture.viewport
            model.panImage(by: CGSize(width: point.x - panGesture.anchor.x, height: point.y - panGesture.anchor.y))
            viewportChanged()
            return
        }
        if let anchor = textSelectionAnchor, let editor = textView {
            let index = editor.characterIndexForInsertion(at: editor.convert(event.locationInWindow, from: nil))
            let extent = editor.selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: textSelectionGranularity)
            let lower = min(anchor.location, extent.location), upper = max(NSMaxRange(anchor), NSMaxRange(extent))
            editor.setSelectedRange(NSRange(location: lower, length: upper - lower))
            return
        }
        guard start != nil else { return }
        let point = pixelPoint(event)
        lastDragPoint = point
        updateDrag(at: point, modifiers: event.modifierFlags)
    }
    override func flagsChanged(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if start != nil, let point = lastDragPoint, !creatingText, textSelectionAnchor == nil {
            updateDrag(at: point, modifiers: event.modifierFlags)
        } else { super.flagsChanged(with: event) }
    }
    private func updateDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let start else { return }
        let constrained = modifiers.contains(.shift)
        if creatingText {
            guard distance(point, start) >= 5 else { return }
            let rect = CGRect(x: max(model.sourceRect.minX, min(start.x, point.x)), y: max(model.sourceRect.minY, min(start.y, point.y)),
                              width: max(40 / scaleX, abs(point.x - start.x)), height: abs(point.y - start.y))
            let width = min(rect.width, model.sourceRect.maxX - rect.minX)
            creationRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            model.positionText(at: rect.origin, width: max(1, width))
            synchronizeTextEditor()
        } else if let fromLeft = textResizeFromLeft, let draggedID,
                  let object = original.first(where: { $0.id == draggedID }) {
            let oldWidth = textBoxRect(object).width
            let delta = point.x - start.x
            let width = max(24 / scaleX, oldWidth + (fromLeft ? -delta : delta))
            model.preview = original.map {
                guard $0.id == draggedID else { return $0 }
                var next = $0; next.textWidth = width
                if fromLeft { next.start.x = object.start.x + oldWidth - width }
                return next
            }
        } else if draggingCalloutTip, let draggedID, let object = original.first(where: { $0.id == draggedID }) {
            let previous = EditorRenderer.calloutTip(object)
            model.preview = original.map {
                guard $0.id == draggedID else { return $0 }
                var next = $0
                next.calloutTip = CGPoint(x: previous.x + point.x - start.x, y: previous.y + point.y - start.y)
                return next
            }
        } else if let resizeHandle, let draggedID,
                  let object = original.first(where: { $0.id == draggedID }) {
            let resized = resizedObject(object, handle: resizeHandle,
                                        delta: CGSize(width: point.x - start.x, height: point.y - start.y), constrained: constrained)
            model.preview = original.map { $0.id == draggedID ? resized : $0 }
        } else if let arrowEndpoint, let draggedID,
                  let object = original.first(where: { $0.id == draggedID }) {
            // Use the pointer delta so a grab near the centre of a handle never jumps.
            let previous = arrowEndpoint == .start ? object.start : object.end
            var nextPoint = CGPoint(x: previous.x + point.x - start.x, y: previous.y + point.y - start.y)
            if constrained, point != start {
                nextPoint = EditorGeometry.constrainedEnd(from: arrowEndpoint == .start ? object.end : object.start,
                                                         to: nextPoint, kind: .arrow)
            }
            model.preview = original.map {
                guard $0.id == draggedID else { return $0 }
                var next = $0
                if arrowEndpoint == .start { next.start = nextPoint } else { next.end = nextPoint }
                return next
            }
        } else if var object = gestureObject {
            if object.kind == .highlight, var highlight = object.highlightStyle, highlight.mode == .freehand {
                if let previous = highlight.points.last, hypot(point.x - previous.x, point.y - previous.y) > 0.01 {
                    if highlight.points.count < EditorHighlightStyle.maximumPoints { highlight.points.append(point) }
                    else { model.notice = String(localized: "Maximale Strichlänge erreicht. Beginne eine weitere Markierung.") }
                }
                object.highlightStyle = highlight; object.end = point
            } else {
                object.end = constrained ? EditorGeometry.constrainedEnd(from: object.start, to: point, kind: object.kind) : point
            }
            gestureObject = object
            model.preview = original + [object]
        } else if let draggedID {
            model.preview = original.map { model.selectedIDs.contains($0.id) || $0.id == draggedID ? $0.translated(by: CGSize(width: point.x - start.x, height: point.y - start.y)) : $0 }
        }
        refreshComposition()
        needsDisplay = true
        // Mouse tracking must not wait for a SwiftUI body update.
        displayIfNeeded()
    }
    private func resizedObject(_ object: EditorObject, handle: EditorResizeHandle, delta: CGSize, constrained: Bool) -> EditorObject {
        guard let old = resizeBox(object) else { return object }
        let isCallout = object.kind == .callout
        let minimum = isCallout ? CGSize(width: 48, height: 21) : object.kind == .step ? CGSize(width: 24, height: 24) : CGSize(width: 4 / scaleX, height: 4 / scaleY)
        let ratio: CGFloat? = object.kind == .step ? old.width / max(1, old.height)
            : constrained ? (object.kind == .rectangle || object.kind == .ellipse ? 1 : old.width / max(1, old.height)) : nil
        let rect = EditorGeometry.resized(old, handle: handle, delta: delta, minimum: minimum, aspectRatio: ratio)
        guard rect != old else { return object }
        var next = object
        if isCallout {
            next.calloutTip = EditorRenderer.calloutTip(object)
            next.start = CGPoint(x: rect.minX + 12, y: rect.minY + 10)
            next.textWidth = rect.width - 24
            next.textHeight = nil
            // Width changes reflow text. Never clip it when a frame is made smaller.
            let height = max(rect.height, EditorRenderer.textRect(next).height + 20)
            next.textHeight = max(1, height - 20)
            if handle.movesTop { next.start.y = old.maxY - height + 10 }
        } else {
            next.start = rect.origin; next.end = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return next
    }
    override func mouseUp(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        defer { model.isCanvasGestureActive = false }
        if cropGesture != nil {
            updateCrop(with: event); cropGesture = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        if panGesture != nil {
            mouseDragged(with: event); panGesture = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        if textSelectionAnchor != nil { textSelectionAnchor = nil; return }
        guard let start else { return }
        mouseDragged(with: event)
        if creatingText {
            self.start = nil; creatingText = false; creationRect = nil
            needsDisplay = true
            return
        }
        let point = pixelPoint(event)
        let isFreehand = gestureObject?.kind == .highlight && gestureObject?.highlightStyle?.mode == .freehand
        if let preview = model.preview, model.tool == .selection || isFreehand || distance(point, start) >= 5 {
            model.commit(preview)
            if model.tool != .selection { model.selection = preview.last?.id }
        } else { model.preview = nil }
        self.start = nil; draggedID = nil; gestureObject = nil; textResizeFromLeft = nil; arrowEndpoint = nil; resizeHandle = nil; draggingCalloutTip = false; lastDragPoint = nil
        refreshComposition(); needsDisplay = true; window?.invalidateCursorRects(for: self)
    }

    private func beginTextSelection(_ object: EditorObject, with event: NSEvent) {
        start = nil; draggedID = nil; gestureObject = nil
        model.editText(at: object.start, object: object)
        synchronizeTextEditor()
        guard let editor = textView else { return }
        // Use AppKit's character and word boundaries, including Unicode and bidi.
        let index = editor.characterIndexForInsertion(at: editor.convert(event.locationInWindow, from: nil))
        textSelectionGranularity = event.clickCount >= 3 ? .selectByParagraph : event.clickCount == 2 ? .selectByWord : .selectByCharacter
        let range = editor.selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: textSelectionGranularity)
        editor.setSelectedRange(range); textSelectionAnchor = range
        needsDisplay = true
    }

    func synchronizeTextEditor() {
        guard let object = model.editingTextObject else {
            if let textView {
                textView.delegate = nil; textClipView?.removeFromSuperview()
                self.textView = nil; textClipView = nil; textID = nil
            }
            return
        }
        if textID != object.id {
            textView?.delegate = nil; textClipView?.removeFromSuperview()
            let storage = NSTextStorage(), layout = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 1_000_000, height: 1_000_000))
            storage.addLayoutManager(layout); layout.addTextContainer(container)
            let editor = InlineTextView(frame: .zero, textContainer: container)
            editor.isRichText = false; editor.importsGraphics = false
            editor.drawsBackground = false; editor.allowsUndo = true
            editor.isHorizontallyResizable = false; editor.isVerticallyResizable = false
            editor.textContainerInset = .zero
            editor.textContainer?.lineFragmentPadding = 0
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.containerSize = CGSize(width: 1_000_000, height: 1_000_000)
            editor.setAccessibilityLabel(object.kind == .callout ? String(localized: "Callout im Bild") : String(localized: "Text im Bild"))
            editor.setAccessibilityIdentifier("editor.inlineText")
            editor.onFinish = { [weak self] cancel in
                guard let self else { return }
                model.finishTextEditing(cancel: cancel)
                synchronizeTextEditor(); needsDisplay = true
                window?.makeFirstResponder(self)
            }
            editor.string = object.text; editor.delegate = self
            textView = editor; textID = object.id
            let clip = FlippedClipView(frame: .zero)
            clip.wantsLayer = true; clip.layer?.masksToBounds = true
            addSubview(clip); clip.addSubview(editor); textClipView = clip
            editor.setSelectedRange(NSRange(location: (object.text as NSString).length, length: 0))
        }
        guard let editor = textView else { return }
        // Lay out in image pixels, then scale the view. Scaling the font itself
        // changes optical metrics and can wrap different words than the PNG.
        let font = EditorRenderer.font(object)
        if editor.font != font { editor.font = font }
        let color = EditorRenderer.color(object)
        if editor.textColor != color { editor.textColor = color }
        editor.insertionPointColor = .controlAccentColor
        let attributes = EditorRenderer.textAttributes(object)
        // Uniform object typography; preserve the native selection/caret while updating layout.
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            editor.defaultParagraphStyle = paragraph
            if editor.alignment != paragraph.alignment { editor.alignment = paragraph.alignment }
        }
        editor.typingAttributes = attributes
        let rect = EditorRenderer.textRect(object)
        editor.textContainer?.containerSize = CGSize(width: EditorRenderer.textContainerWidth(object), height: 1_000_000)
        let clipRect = imageRect.intersection(bounds)
        textClipView?.frame = clipRect.isNull ? .zero : clipRect
        let origin = viewPoint(object.start)
        editor.frame = CGRect(x: origin.x - (textClipView?.frame.minX ?? 0), y: origin.y - (textClipView?.frame.minY ?? 0),
                              width: max(object.textWidth == nil ? (object.text.isEmpty ? 100 : 24) : 1, rect.width * scaleX + 6),
                              height: max((font.ascender - font.descender + font.leading) * scaleY + 6, rect.height * scaleY + 6))
        editor.bounds = CGRect(origin: .zero, size: CGSize(width: editor.frame.width / scaleX, height: editor.frame.height / scaleY))
        if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
        if window?.firstResponder === self { window?.makeFirstResponder(editor) }
    }
    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        model.updateText(textView.string)
        synchronizeTextEditor()
        needsDisplay = true; displayIfNeeded()
    }
    override func keyDown(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if (event.keyCode == 36 || event.keyCode == 76), model.cropDraft != nil {
            model.applyCrop(); needsDisplay = true; window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 49, !event.modifierFlags.contains(.command), !model.isCanvasGestureActive {
            isSpaceHeld = true; window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 53 {
            if let panGesture { model.viewport = panGesture.viewport }
            panGesture = nil; isSpaceHeld = false; model.isCanvasGestureActive = false
            cropGesture = nil
            if model.cropDraft != nil { model.cancelCrop() }
            model.finishTextEditing(cancel: true)
            model.preview = nil; start = nil; draggedID = nil; gestureObject = nil; model.selection = nil
            creatingText = false; creationRect = nil; textSelectionAnchor = nil; textResizeFromLeft = nil; arrowEndpoint = nil; resizeHandle = nil; draggingCalloutTip = false; lastDragPoint = nil
            refreshComposition(); needsDisplay = true
        } else if event.keyCode == 51 || event.keyCode == 117 { model.removeSelection() }
        else { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if event.keyCode == 49 { isSpaceHeld = false; window?.invalidateCursorRects(for: self) }
        else { super.keyUp(with: event) }
    }
    override func resignFirstResponder() -> Bool {
        isSpaceHeld = false; window?.invalidateCursorRects(for: self)
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !model.isSwitchingImage else { return super.performKeyEquivalent(with: event) }
        if let editor = textView, window?.firstResponder === editor { return editor.performKeyEquivalent(with: event) }
        if window?.firstResponder is NSTextView { return super.performKeyEquivalent(with: event) }
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": event.modifierFlags.contains(.shift) ? model.redo() : model.undo(); return true
        case "c": model.copyPNG(); return true
        case "d": model.duplicateSelection(); return true
        case "a": model.selectAllObjects(); return true
        case "g": model.groupSelection(ungroup: event.modifierFlags.contains(.shift)); return true
        case "+", "=": model.zoomBy(1.25); viewportChanged(); return true
        case "-": model.zoomBy(1 / 1.25); viewportChanged(); return true
        case "1": model.setZoom(1); viewportChanged(); return true
        case "0": model.fitImage(); viewportChanged(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
    override func magnify(with event: NSEvent) { superview?.magnify(with: event) }
    override func smartMagnify(with event: NSEvent) { superview?.smartMagnify(with: event) }
    override func scrollWheel(with event: NSEvent) { superview?.scrollWheel(with: event) }
}

private final class InlineTextView: NSTextView {
    // A text session must never undo an object or a previously closed text field.
    private let typingUndo = UndoManager()
    override var undoManager: UndoManager? { typingUndo }
    var onFinish: ((Bool) -> Void)?
    override func magnify(with event: NSEvent) { superview?.magnify(with: event) }
    override func smartMagnify(with event: NSEvent) { superview?.smartMagnify(with: event) }
    override func scrollWheel(with event: NSEvent) { superview?.scrollWheel(with: event) }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        caret.size.width = 1 / max(0.001, frame.width / bounds.width)
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }
    private func handleTextShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            breakUndoCoalescing()
            if event.modifierFlags.contains(.shift) { if typingUndo.canRedo { typingUndo.redo() } }
            else if typingUndo.canUndo { typingUndo.undo() }
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "v": pasteAsPlainText(nil)
        default: return false
        }
        return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleTextShortcut(event) || super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handleTextShortcut(event) { return }
        if event.keyCode == 53 { onFinish?(false) }
        else if event.keyCode == 36, event.modifierFlags.contains(.command) { onFinish?(false) }
        else { super.keyDown(with: event) }
    }
}
