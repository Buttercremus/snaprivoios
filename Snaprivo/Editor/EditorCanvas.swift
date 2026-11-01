import SwiftUI
import AppKit
import SnagForgeDomain

/// Operations are injectable so cancellation can be exercised while real canvas jobs are in flight.
struct CanvasRenderClient: Sendable {
    var validateAssets: @Sendable ([EditorObject]) throws -> Void
    var magnifier: @Sendable (CGImage, [EditorObject]) throws -> EditorRenderer.MagnifierPreview
    static let live = Self(validateAssets: { try EditorRenderer.validateAssets($0) },
                           magnifier: { try EditorRenderer.renderMagnifierPreview(image: $0, objects: $1) })
}

struct EditorCanvasColorPicking {
    let sample: (CGPoint, Bool) -> Void
    let move: (CGSize) -> Void
    let cancel: () -> Void
}

struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel
    var colorPicking: EditorCanvasColorPicking? = nil
    func makeNSView(context: Context) -> EditorCanvasContainer { EditorCanvasContainer(model: model) }
    func updateNSView(_ container: EditorCanvasContainer, context: Context) {
        _ = model.objects; _ = model.selectedIDs; _ = model.selection; _ = model.tool; _ = model.editingTextObject
        _ = model.viewport; _ = model.cropDraft; _ = model.document.crop; _ = model.document.resizedSize
        _ = model.isSwitchingImage; _ = model.document.canvasRect; _ = model.history.transform
        _ = model.isSourceImageSelected; _ = model.history.presentation
        container.updateModel(model)
        let view = container.canvas
        container.synchronizeTransform()
        view.synchronizeViewport()
        view.synchronizeTextEditor()
        view.synchronizeFocus()
        container.synchronizeColorPicking(colorPicking)
        view.synchronizeQuickOptions()
        view.window?.invalidateCursorRects(for: view)
        view.refreshComposition()
        view.needsDisplay = true
    }
    static func dismantleNSView(_ container: EditorCanvasContainer, coordinator: ()) {
        let view = container.canvas
        view.closeQuickOptions()
        view.model.endStyleEditing()
        view.model.finishTextEditing()
    }
}

/// Transform the native coordinate system, including TextKit and hit testing.
/// A layer-only rotation would leave mouse coordinates and the insertion caret behind.
@MainActor
final class EditorCanvasContainer: NSView {
    private(set) var canvas: CanvasView
    private(set) var colorPickingView: CanvasColorPickingView?
    private var mirroredWidth: CGFloat?
    private struct ProjectionState: Equatable {
        let bounds: CGRect
        let transform: EditorImageTransform
        let presentation: EditorPresentation?
        let viewport: EditorViewport
        let imageSize: CGSize
        let sourceRect: CGRect
        let backingScale: CGFloat
    }
    private var applied: ProjectionState?
    private var requestedWallpaper: PresentationBackground?
    private var wallpaper: CGImage?
    private var wallpaperTask: Task<Void, Never>?
    private var isSynchronizing = false
    override var isFlipped: Bool { true }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1 }
    private var presentation: EditorPresentation? {
        let model = canvas.model
        return model.cropDraft == nil && model.history.presentation.requiresCanvasLayout ? model.history.presentation : nil
    }
    init(model: EditorModel) {
        canvas = CanvasView(model: model)
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        addSubview(canvas)
        usePreparedWallpaper(model)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func updateModel(_ model: EditorModel) {
        guard canvas.model !== model else { return }
        let previous = canvas
        previous.closeQuickOptions(); previous.cancelRendering()
        canvas = CanvasView(model: model)
        mirroredWidth = nil; applied = nil
        wallpaperTask?.cancel(); wallpaperTask = nil; wallpaper = nil; requestedWallpaper = nil
        usePreparedWallpaper(model)
        model.focusRequest += 1
        // Retain the parent layer and replace its fully prepared native content in one display pass.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        addSubview(canvas, positioned: .above, relativeTo: previous)
        synchronizeTransform(); canvas.refreshComposition()
        previous.removeFromSuperview()
        needsDisplay = true
        CATransaction.commit()
    }
    private func usePreparedWallpaper(_ model: EditorModel) {
        guard let prepared = model.initialCanvas, prepared.project == model.document.id, prepared.revision == model.document.revision else { return }
        wallpaper = prepared.wallpaper; requestedWallpaper = model.history.presentation.background
        model.initialCanvas = nil
    }
    override func layout() {
        super.layout(); synchronizeTransform()
        colorPickingView?.frame = bounds
    }
    func synchronizeColorPicking(_ actions: EditorCanvasColorPicking?) {
        if canvas.isPickingColor != (actions != nil) {
            canvas.isPickingColor = actions != nil
            canvas.updateTrackingAreas()
        }
        guard let actions else {
            if let picker = colorPickingView {
                if window?.firstResponder === picker { window?.makeFirstResponder(canvas) }
                picker.removeFromSuperview(); colorPickingView = nil
            }
            return
        }
        canvas.closeQuickOptions()
        if let picker = colorPickingView {
            picker.actions = actions
            if window?.firstResponder === canvas { window?.makeFirstResponder(picker) }
        }
        else {
            let picker = CanvasColorPickingView(actions: actions)
            picker.frame = bounds; picker.autoresizingMask = [.width, .height]
            addSubview(picker); colorPickingView = picker
            window?.makeFirstResponder(picker)
        }
    }
    /// The export's top-left pixel space in the unchanged editor viewport.
    var colorPickingImageRect: CGRect {
        let model = canvas.model
        if let presentation, let rect = presentation.previewRect(for: model.document.contentPixelSize,
            viewport: model.viewport, in: bounds, backingScale: backingScale) { return rect }
        return canvas.convert(canvas.imageRect, to: self)
    }
    func synchronizeTransform() {
        guard !isSynchronizing else { return }
        let model = canvas.model, transform = model.history.transform
        let state = ProjectionState(bounds: bounds, transform: transform, presentation: presentation,
            viewport: model.viewport, imageSize: model.imageSize, sourceRect: model.sourceRect, backingScale: backingScale)
        guard state != applied else { return }
        isSynchronizing = true; defer { isSynchronizing = false }
        applied = state
        if let mirroredWidth {
            canvas.translateOrigin(to: CGPoint(x: mirroredWidth, y: 0))
            canvas.scaleUnitSquare(to: CGSize(width: -1, height: 1))
            self.mirroredWidth = nil
        }
        canvas.frameRotation = 0
        canvas.presentationImageRect = nil; canvas.presentationViewportBounds = nil
        let size: CGSize
        if presentation != nil {
            // A bounded square covers the whole viewport after any rotation.
            // Zoomed pixels can extend beyond it without creating enormous layers.
            let side = ceil(hypot(bounds.width, bounds.height))
            size = CGSize(width: side, height: side)
        } else { size = transform.swapsAxes ? CGSize(width: bounds.height, height: bounds.width) : bounds.size }
        canvas.frame = CGRect(origin: .zero, size: size)
        canvas.bounds = CGRect(origin: .zero, size: size)
        if transform.isMirrored {
            canvas.scaleUnitSquare(to: CGSize(width: -1, height: 1))
            canvas.translateOrigin(to: CGPoint(x: -size.width, y: 0))
            mirroredWidth = size.width
        }
        canvas.frameRotation = CGFloat(transform.quarterTurns * 90) + CGFloat(presentation?.rotationDegrees ?? 0)
        if let presentation, let geometry = presentation.geometry(for: model.document.contentPixelSize),
           let rect = presentation.previewRect(for: model.document.contentPixelSize, viewport: model.viewport, in: bounds, backingScale: backingScale) {
            let center = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: self)
            canvas.setFrameOrigin(CGPoint(x: canvas.frame.origin.x + bounds.midX - center.x,
                                          y: canvas.frame.origin.y + bounds.midY - center.y))
            let scale = rect.width / CGFloat(geometry.outputSize.width)
            let contentCenter = CGPoint(x: CGFloat(model.document.contentPixelSize.width) / 2,
                                        y: CGFloat(model.document.contentPixelSize.height) / 2).applying(geometry.imageTransform)
            let target = CGPoint(x: rect.minX + contentCenter.x * scale, y: rect.minY + contentCenter.y * scale)
            let local = canvas.convert(target, from: self)
            let imageSize = CGSize(width: model.imageSize.width * scale, height: model.imageSize.height * scale)
            canvas.presentationImageRect = CGRect(x: local.x - imageSize.width / 2, y: local.y - imageSize.height / 2,
                                                   width: imageSize.width, height: imageSize.height)
            canvas.presentationViewportBounds = bounds
        } else {
            let visible = canvas.convert(canvas.bounds, to: self)
            canvas.setFrameOrigin(CGPoint(x: canvas.frame.origin.x - visible.minX, y: canvas.frame.origin.y - visible.minY))
        }
        refreshWallpaper(presentation?.background)
        canvas.synchronizeViewport(); canvas.synchronizeTextEditor(); canvas.synchronizeQuickOptions()
        canvas.needsDisplay = true; needsDisplay = true
        canvas.window?.invalidateCursorRects(for: canvas)
    }
    private func refreshWallpaper(_ background: PresentationBackground?) {
        guard requestedWallpaper != background else { return }
        requestedWallpaper = background; wallpaperTask?.cancel(); wallpaper = nil
        guard let background else { return }
        switch background {
        case .asset, .image: break
        default: return
        }
        wallpaperTask = Task { [weak self] in
            let task = Task.detached(priority: .userInitiated) { try EditorRenderer.preparePresentationWallpaper(background) }
            do {
                let prepared = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled, let self, self.requestedWallpaper == background else { return }
                self.wallpaper = prepared; self.needsDisplay = true
            } catch {
                if !Task.isCancelled, let self, self.requestedWallpaper == background { self.canvas.model.error = error.localizedDescription }
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext, let presentation,
              let geometry = presentation.geometry(for: canvas.model.document.contentPixelSize),
              let rect = presentation.previewRect(for: canvas.model.document.contentPixelSize, viewport: canvas.model.viewport,
                                                   in: bounds, backingScale: backingScale) else { return }
        let scale = rect.width / CGFloat(geometry.outputSize.width)
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: bounds); context.translateBy(x: rect.minX, y: rect.minY); context.scaleBy(x: scale, y: scale)
        try? EditorRenderer.drawPresentationScene(nil,
            sourceSize: CGSize(width: canvas.model.document.contentPixelSize.width, height: canvas.model.document.contentPixelSize.height),
            presentation: presentation, in: context, preparedWallpaper: wallpaper, usesPreparedWallpaper: true,
            effectScale: scale * backingScale)
    }
}

/// Intercepts picking without replacing, resizing or rotating the editable canvas.
@MainActor
final class CanvasColorPickingView: NSView {
    var actions: EditorCanvasColorPicking
    private var tracking: NSTrackingArea?
    private var isPanning = false
    private var container: EditorCanvasContainer? { superview as? EditorCanvasContainer }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(actions: EditorCanvasColorPicking) {
        self.actions = actions
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Pipette"))
        setAccessibilityHelp(String(localized: "Maus bewegen: Farbe ansehen · Klicken: Farbe festhalten · Pfeiltasten: Pixel wählen · Esc: beenden"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    static let pipetteCursor: NSCursor = {
        let image = NSImage(size: CGSize(width: 26, height: 26), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 3, y: 23)); path.line(to: CGPoint(x: 5, y: 16))
            path.line(to: CGPoint(x: 14, y: 7)); path.line(to: CGPoint(x: 19, y: 12))
            path.line(to: CGPoint(x: 10, y: 21)); path.close()
            path.lineWidth = 3; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.stroke(); NSColor.black.setFill(); path.fill()
            let bulb = NSBezierPath(ovalIn: CGRect(x: 14, y: 2, width: 10, height: 10))
            bulb.lineWidth = 3; NSColor.white.setStroke(); bulb.stroke(); NSColor.black.setFill(); bulb.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 3, y: 23))
    }()
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(area); tracking = area
    }
    func cursor(at point: CGPoint) -> NSCursor {
        if isPanning { return .closedHand }
        if container?.canvas.isSpaceHeld == true { return .openHand }
        return container?.colorPickingImageRect.contains(point) == true ? Self.pipetteCursor : .arrow
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor(at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)))
    }
    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }
    private func sample(_ event: NSEvent, fixed: Bool) {
        guard let container, !container.canvas.model.isSwitchingImage else { return }
        let point = convert(event.locationInWindow, from: nil), rect = container.colorPickingImageRect
        guard bounds.contains(point), rect.width > 0, rect.height > 0, rect.contains(point) else { return }
        actions.sample(CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height), fixed)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) { cursorUpdate(with: event); sample(event, fixed: false) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if container?.canvas.isSpaceHeld == true {
            isPanning = true; container?.canvas.mouseDown(with: event)
            window?.makeFirstResponder(self)
        } else { sample(event, fixed: true) }
        cursorUpdate(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        if isPanning { container?.canvas.mouseDragged(with: event) }
        else { sample(event, fixed: true) }
    }
    override func mouseUp(with event: NSEvent) {
        if isPanning { container?.canvas.mouseUp(with: event); isPanning = false }
        cursorUpdate(with: event)
    }
    override func scrollWheel(with event: NSEvent) { container?.canvas.scrollWheel(with: event); mouseMoved(with: event) }
    override func magnify(with event: NSEvent) { container?.canvas.magnify(with: event) }
    override func smartMagnify(with event: NSEvent) { container?.canvas.smartMagnify(with: event) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { actions.cancel() }
        else if (123...126).contains(event.keyCode), event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            actions.move(CGSize(width: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                              height: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0))
        } else if event.keyCode == 49 { container?.canvas.keyDown(with: event) }
        else { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) { container?.canvas.keyUp(with: event) }
}

@MainActor
final class CanvasView: NSView, NSTextViewDelegate {
    var model: EditorModel
    var isPickingColor = false
    var lastFocusRequest = 0
    var presentationImageRect: CGRect?
    var presentationViewportBounds: CGRect?
    private var sourceImageClick: CGPoint?
    private var start: CGPoint?
    private var original: [EditorObject] = []
    private var draggedID: UUID?
    private var gestureObject: EditorObject?
    private(set) var magnifierImage: CGImage?
    private var magnifierSourceSize: CGSize?
    private var magnifierObjects: [EditorObject]?
    private var requestedMagnifierObjects: [EditorObject]?
    private var magnifierTask: Task<Void, Never>?
    private var blurPatches: [EditorBlurPatch] = []
    private var requestedBlurs: [EditorObject] = []
    private var assetTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private let renderClient: CanvasRenderClient
    private var renderingRequest = UUID()
    private var magnifierRequest = UUID()
    private var textView: InlineTextView?
    private var textClipView: NSView?
    private var textID: UUID?
    private var creatingText = false
    private var creationRect: CGRect?
    private var textSelectionAnchor: NSRange?
    private var textSelectionGranularity: NSSelectionGranularity = .selectByCharacter
    private var textResizeFromLeft: Bool?
    private var arrowEndpoint: ArrowEndpoint?
    private var draggingArrowBend = false
    private var draggingMagnifierSource = false
    private var draggingCalloutTip = false
    private var resizeHandle: EditorResizeHandle?
    private var resizingGroupBounds: CGRect?
    private(set) var snapGuides: [EditorArrangement.Guide] = [] {
        // A light trackpad tick when an edge or center engages; holding the snap stays silent.
        didSet { if snapGuides.contains(where: { !oldValue.contains($0) }) { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) } }
    }
    private var lastDragPoint: CGPoint?
    fileprivate var isSpaceHeld = false
    private var panGesture: (anchor: CGPoint, viewport: EditorViewport)?
    private var cursorTrackingArea: NSTrackingArea?
    private var quickToolbar: NSHostingView<EditorQuickOptions>?
    private var quickDismissMonitor: Any?
    private(set) var quickOptionsObjectID: UUID?
    private var clickedObjectID: UUID?
    private enum CropAction { case draw, move, resize(EditorResizeHandle) }
    private var cropGesture: (anchor: CGPoint, rect: CGRect, action: CropAction)?
    private enum ArrowEndpoint { case start, end }

    func cancelRendering() {
        renderingRequest = UUID()
        assetTask?.cancel(); renderTask?.cancel(); magnifierTask?.cancel()
        assetTask = nil; renderTask = nil; magnifierTask = nil
        requestedMagnifierObjects = nil; requestedBlurs = []
    }

    func refreshComposition() {
        refreshMagnifierSource()
        let assets = model.objects.filter { $0.imageAsset.map { EditorRenderer.cachedAssetImage($0) == nil } == true }
        if !assets.isEmpty, assetTask == nil {
            let request = renderingRequest, client = renderClient
            assetTask = Task { [weak self] in
                defer { if self?.renderingRequest == request { self?.assetTask = nil } }
                do {
                    let worker = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        try client.validateAssets(assets)
                        try Task.checkCancellation()
                    }
                    try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                } catch {
                    if !Task.isCancelled, self?.renderingRequest == request, !(error is CancellationError) {
                        self?.model.error = error.localizedDescription
                    }
                }
                guard !Task.isCancelled, self?.renderingRequest == request else { return }
                self?.needsDisplay = true
            }
        }
        requestedBlurs = model.objects.filter { $0.kind == .blur }
        let active = Set(requestedBlurs.map(\.id))
        blurPatches.removeAll { !active.contains($0.objectID) }
        guard renderTask == nil, nextBlurRequest() != nil else { return }
        // Pointer moves inside prepared source pixels only move the clipping mask.
        // Refill ahead of the pointer; coalesce newer positions into one worker.
        let request = renderingRequest
        renderTask = Task { [weak self] in
            guard let self else { return }
            defer { if renderingRequest == request { renderTask = nil } }
            while !Task.isCancelled, renderingRequest == request, let snapshot = nextBlurRequest() {
                let image = model.image, maximumPixels = 8_000_000 / max(1, requestedBlurs.count)
                do {
                    let worker = Task.detached(priority: .userInitiated) { try EditorRenderer.blurPatch(image: image, object: snapshot, maximumPixels: maximumPixels) }
                    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    guard !Task.isCancelled, renderingRequest == request else { return }
                    if let result, requestedBlurs.contains(where: { $0.id == result.objectID }) {
                        // Keep one previous region/style while the next one is prepared.
                        if blurPatches.filter({ $0.objectID == result.objectID }).count >= 2,
                           let old = blurPatches.firstIndex(where: { $0.objectID == result.objectID }) { blurPatches.remove(at: old) }
                        blurPatches.append(result)
                        while blurPatches.count > 1 && blurPatches.reduce(0, { $0 + $1.byteCount }) > 65_000_000 { blurPatches.removeFirst() }
                    }
                } catch {
                    if !Task.isCancelled, renderingRequest == request, !(error is CancellationError) { model.error = error.localizedDescription }
                    return
                }
                needsDisplay = true
            }
        }
    }
    private func nextBlurRequest() -> EditorObject? {
        let bounds = CGRect(x: 0, y: 0, width: model.image.width, height: model.image.height)
        return requestedBlurs.first { object in
            let area = object.rect.intersection(bounds)
            guard !area.isNull, !area.isEmpty else { return false }
            let ahead = area.insetBy(dx: -96, dy: -96).intersection(bounds)
            return !blurPatches.contains { $0.matches(object) && $0.rect.contains(ahead) }
        }
    }
    private func refreshMagnifierSource() {
        guard model.tool == .magnifier || model.objects.contains(where: { $0.kind == .magnifier }) else {
            requestedMagnifierObjects = nil
            magnifierRequest = UUID()
            magnifierTask?.cancel()
            magnifierTask = nil
            magnifierImage = nil; magnifierObjects = nil; magnifierSourceSize = nil
            return
        }
        requestedMagnifierObjects = model.objects.filter { $0.kind != .magnifier }
        guard magnifierTask == nil, magnifierObjects != requestedMagnifierObjects else { return }
        let request = renderingRequest, client = renderClient, magnifierRequest = UUID()
        self.magnifierRequest = magnifierRequest
        magnifierTask = Task { [weak self] in
            guard let self else { return }
            defer { if renderingRequest == request, self.magnifierRequest == magnifierRequest { magnifierTask = nil } }
            while !Task.isCancelled, renderingRequest == request, self.magnifierRequest == magnifierRequest,
                  let snapshot = requestedMagnifierObjects, snapshot != magnifierObjects {
                let image = model.image
                do {
                    let worker = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        let result = try client.magnifier(image, snapshot)
                        try Task.checkCancellation()
                        return result
                    }
                    let rendered = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    guard !Task.isCancelled, renderingRequest == request else { return }
                    // A changed drawing is coalesced into the next round; never publish its obsolete pixels.
                    guard requestedMagnifierObjects == snapshot else { continue }
                    magnifierImage = rendered.image; magnifierSourceSize = rendered.originalSize; magnifierObjects = snapshot
                } catch {
                    guard !Task.isCancelled, renderingRequest == request, !(error is CancellationError) else { return }
                    model.error = error.localizedDescription
                    requestedMagnifierObjects = nil
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
    init(model: EditorModel, renderClient: CanvasRenderClient = .live) {
        self.model = model; self.renderClient = renderClient; super.init(frame: .zero)
        if let prepared = model.initialCanvas, prepared.project == model.document.id, prepared.revision == model.document.revision {
            blurPatches = prepared.blurPatches
            magnifierImage = prepared.magnifierImage; magnifierObjects = prepared.magnifierObjects
            magnifierSourceSize = prepared.magnifierSourceSize
        }
        wantsLayer = true; layer?.masksToBounds = true
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Bildfläche"))
        setAccessibilityHelp(String(localized: "Scrollen verschiebt das Bild. Leertaste und Ziehen schwenkt. ⌘ plus Mausrad oder Aufziehen auf dem Trackpad zoomt."))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    fileprivate var imageRect: CGRect {
        presentationImageRect ?? model.viewport.imageRect(image: model.imageSize, in: bounds, backingScale: backingScale)
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
        model.viewportBounds = presentationViewportBounds ?? bounds; model.viewportBackingScale = backingScale
    }
    func synchronizeFocus() {
        // SwiftUI can request focus before the replacement canvas has joined its window.
        guard lastFocusRequest != model.focusRequest, !model.isSwitchingImage, let window else { return }
        if model.editingTextObject != nil || window.makeFirstResponder(self) {
            lastFocusRequest = model.focusRequest
        }
    }
    private func viewportPoint(_ event: NSEvent) -> CGPoint {
        if presentationViewportBounds != nil, let superview { return superview.convert(event.locationInWindow, from: nil) }
        return convert(event.locationInWindow, from: nil)
    }
    private func viewportChanged() {
        if presentationViewportBounds != nil { (superview as? EditorCanvasContainer)?.synchronizeTransform() }
        closeQuickOptions()
        synchronizeTextEditor(); needsDisplay = true; displayIfNeeded()
        window?.invalidateCursorRects(for: self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closeQuickOptions() }
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
        model.zoomBy(exp(event.magnification), at: viewportPoint(event))
        viewportChanged()
    }
    override func smartMagnify(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        guard !model.isCanvasGestureActive else { return }
        synchronizeViewport()
        if model.viewport.zoom == nil { model.setZoom(1, at: viewportPoint(event)) }
        else { model.fitImage() }
        viewportChanged()
    }
    override func scrollWheel(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        guard !model.isCanvasGestureActive else { return }
        synchronizeViewport()
        if event.modifierFlags.contains(.command) {
            model.zoomBy(exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)),
                         at: viewportPoint(event))
        } else {
            let speed: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            let horizontal = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
            let delta = CGSize(width: (horizontal ? event.scrollingDeltaY : event.scrollingDeltaX) * speed,
                               height: horizontal ? 0 : event.scrollingDeltaY * speed)
            model.panImage(by: presentationViewportBounds == nil ? model.history.transform.sourceVector(fromDisplayed: delta) : delta)
        }
        viewportChanged()
    }
    private func hit(_ point: CGPoint) -> EditorObject? {
        EditorLayers.paintOrder(model.history.objects).reversed().first {
            object in
            if object.kind == .arrow {
                let origin = viewPoint(.zero)
                var transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: origin.x, ty: origin.y)
                let path = EditorArrow.path(for: object).copy(using: &transform)!
                return path.copy(strokingWithWidth: max(16, EditorRenderer.drawingLineWidth(object) * max(scaleX, scaleY) * 2),
                                 lineCap: .round, lineJoin: .round, miterLimit: 10).contains(viewPoint(point))
            }
            if object.kind == .callout {
                return EditorRenderer.calloutPath(object).contains(point)
                    || EditorRenderer.calloutBox(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY).contains(point)
            }
            if object.kind == .pen, let pen = object.penStroke {
                return pen.path.copy(strokingWithWidth: object.lineWidth + 8 / scale, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
            }
            if object.kind == .spotlight { return object.effectiveSpotlightStyle.path(in: object.rect).contains(point) }
            if object.kind == .step { return EditorRenderer.stepPath(object).contains(point) }
            if object.kind == .highlight, object.effectiveHighlightStyle.mode == .freehand {
                return EditorRenderer.highlightPath(object).copy(strokingWithWidth: object.lineWidth + 8 / scale,
                    lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
            }
            if object.kind == .magnifier { return CGPath(ellipseIn: object.rect, transform: nil).contains(point) || (object.magnifierSource != nil && CGPath(ellipseIn: object.magnifierSourceRect, transform: nil).contains(point)) }
            if object.kind.isShape { return hitsShape(object, at: point) }
            if object.kind == .image {
                return object.rect.insetBy(dx: -4 / scaleX, dy: -4 / scaleY).contains(point.applying(object.imageRotationTransform.inverted()))
            }
            return EditorRenderer.bounds(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY).contains(point)
        }
    }
    private func hitsShape(_ object: EditorObject, at point: CGPoint) -> Bool {
        let stroke = object.effectiveStroke, fill = object.effectiveFill
        let padding = stroke.isEnabled ? EditorRenderer.drawingLineWidth(object) / 2 + (object.effectiveDrawingStyle == .sketch ? object.lineWidth : 0) : 0
        guard object.rect.insetBy(dx: -padding - 4 / scaleX, dy: -padding - 4 / scaleY).contains(point) else { return false }
        let path = EditorRenderer.shapePath(object)
        if fill.isEnabled, fill.opacity > 0, path.contains(point) { return true }
        guard stroke.isEnabled else { return false }
        let origin = viewPoint(.zero)
        var transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: origin.x, ty: origin.y)
        let ink = path.copy(strokingWithWidth: EditorRenderer.drawingLineWidth(object),
                            lineCap: stroke.style == .dotted || object.effectiveDrawingStyle != .precise ? .round : .butt,
                            lineJoin: .round, miterLimit: 10).copy(using: &transform)!
        let cursorPoint = viewPoint(point)
        // Keep a four-point grab tolerance in view space, including at nonuniform output scales.
        return ink.contains(cursorPoint) || ink.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(cursorPoint)
    }
    private func endpoint(at point: CGPoint, of object: EditorObject) -> ArrowEndpoint? {
        guard object.kind == .arrow else { return nil }
        let fromStart = visible(object.start) ? distance(object.start, point) : .infinity
        let fromEnd = visible(object.end) ? distance(object.end, point) : .infinity
        guard min(fromStart, fromEnd) <= 10 else { return nil }
        return fromEnd <= fromStart ? .end : .start
    }
    private func visible(_ point: CGPoint) -> Bool {
        let rect = model.previewSourceRect
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
    private func resizeBox(_ object: EditorObject) -> CGRect? {
        if (object.kind.isShape || object.kind == .image) || object.kind == .redact || object.kind == .step || object.kind == .magnifier || object.kind == .spotlight
            || object.kind == .highlight && object.effectiveHighlightStyle.mode == .rectangle { return object.rect }
        if object.kind == .callout { return EditorRenderer.calloutBox(object) }
        return nil
    }
    private func groupBox(in objects: [EditorObject]) -> CGRect? {
        guard model.selectedIDs.count > 1 else { return nil }
        return objects.filter { model.selectedIDs.contains($0.id) }.map(EditorRenderer.bounds).reduce(nil as CGRect?) { partial, rect in partial.map { $0.union(rect) } ?? rect }
    }
    private func groupObject(in objects: [EditorObject]) -> EditorObject? {
        guard let box = groupBox(in: objects) else { return nil }
        return EditorObject(kind: .rectangle, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))
    }
    private func handle(at point: CGPoint, of object: EditorObject) -> EditorResizeHandle? {
        guard let rect = resizeBox(object) else { return nil }
        if object.kind == .image, object.imageRotationDegrees != nil {
            return EditorResizeHandle.allCases.filter { handle in
                let position = handle.point(in: rect).applying(object.imageRotationTransform)
                return visible(position) && SelectionGrips.hitRect(at: viewPoint(position), shape: handle.gripShape).contains(viewPoint(point))
            }.min { distance($0.point(in: rect).applying(object.imageRotationTransform), point) < distance($1.point(in: rect).applying(object.imageRotationTransform), point) }
        }
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
        let source = handle.point(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let displayed = source.applying(model.history.transform.affineTransform(size: CGSize(width: 1, height: 1)))
        let actual = EditorResizeHandle.allCases.min {
            let a = $0.point(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let b = $1.point(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return hypot(a.x - displayed.x, a.y - displayed.y) < hypot(b.x - displayed.x, b.y - displayed.y)
        }!
        let position: NSCursor.FrameResizePosition = switch actual {
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
    private func canEditObjects(modifiers: NSEvent.ModifierFlags) -> Bool {
        model.tool == .selection || (model.drawingKind != nil && !modifiers.contains(.option))
    }
    static let objectMoveCursor: NSCursor = {
        let image = NSImage(size: CGSize(width: 20, height: 20), flipped: false) { _ in
            let transform = NSAffineTransform(); transform.scale(by: 20.0 / 32); transform.concat()
            let points: [CGPoint] = [
                CGPoint(x: 16, y: 2), CGPoint(x: 22, y: 8), CGPoint(x: 18, y: 8), CGPoint(x: 18, y: 14),
                CGPoint(x: 24, y: 14), CGPoint(x: 24, y: 10), CGPoint(x: 30, y: 16), CGPoint(x: 24, y: 22),
                CGPoint(x: 24, y: 18), CGPoint(x: 18, y: 18), CGPoint(x: 18, y: 24), CGPoint(x: 22, y: 24),
                CGPoint(x: 16, y: 30), CGPoint(x: 10, y: 24), CGPoint(x: 14, y: 24), CGPoint(x: 14, y: 18),
                CGPoint(x: 8, y: 18), CGPoint(x: 8, y: 22), CGPoint(x: 2, y: 16), CGPoint(x: 8, y: 10),
                CGPoint(x: 8, y: 14), CGPoint(x: 14, y: 14), CGPoint(x: 14, y: 8), CGPoint(x: 10, y: 8)
            ]
            let path = NSBezierPath(); path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.close(); path.lineJoinStyle = .round; path.lineWidth = 3
            NSColor.white.setStroke(); path.stroke()
            NSColor.black.setFill(); path.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 10, y: 10))
    }()
    private func hasKeyboardFocus(in view: NSView?) -> Bool {
        guard let view, let focused = window?.firstResponder as? NSView else { return false }
        return focused === view || focused.isDescendant(of: view)
    }
    func closeQuickOptions() {
        let restoreFocus = hasKeyboardFocus(in: quickToolbar)
        quickToolbar?.removeFromSuperview()
        quickToolbar = nil; quickOptionsObjectID = nil
        if let quickDismissMonitor { NSEvent.removeMonitor(quickDismissMonitor); self.quickDismissMonitor = nil }
        model.endStyleEditing()
        if restoreFocus { window?.makeFirstResponder(self) }
    }
    private func quickOptionsAnchor(for object: EditorObject) -> CGRect {
        let source = EditorRenderer.bounds(object)
        let local = CGRect(origin: viewPoint(source.origin), size: CGSize(width: source.width * scaleX, height: source.height * scaleY))
            .intersection(imageRect).intersection(bounds)
        return quickOptionsContainer === self ? local : convert(local, to: quickOptionsContainer)
    }
    private var quickOptionsContainer: NSView { superview is EditorCanvasContainer ? superview! : self }
    func showQuickOptions(for id: UUID) {
        guard !isPickingColor, !model.isSwitchingImage, !model.isCanvasGestureActive, model.cropDraft == nil,
              model.editingTextObject == nil, let object = model.selectedObject, object.id == id,
              window?.isVisible == true else { return }
        let anchor = quickOptionsAnchor(for: object)
        guard !anchor.isNull, anchor.width > 0, anchor.height > 0 else { return }
        if quickOptionsObjectID == id, quickToolbar != nil {
            synchronizeQuickOptions()
            return
        }
        closeQuickOptions()
        let host = NSHostingView(rootView: EditorQuickOptions(model: model, objectID: id, dismiss: { [weak self] in
            guard let self else { return }
            closeQuickOptions(); window?.makeFirstResponder(self)
        }))
        quickToolbar = host; quickOptionsObjectID = id
        quickOptionsContainer.addSubview(host)
        // The toolbar is a sibling of the transformed canvas. Route unhandled
        // keys through the canvas before continuing to their shared container.
        host.nextResponder = self
        synchronizeQuickOptions()
        window?.makeFirstResponder(host)
        quickDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.window, let toolbar = self.quickToolbar,
                   !toolbar.frame.contains(toolbar.superview!.convert(event.locationInWindow, from: nil)) {
                    // Canvas clicks decide whether selection actually changes. Keep the
                    // same hosting view alive when the selected object is clicked again.
                    let point = self.convert(event.locationInWindow, from: nil)
                    if event.type != .leftMouseDown || !self.bounds.contains(point) {
                        self.closeQuickOptions()
                    }
                }
            }
            return event
        }
    }
    func synchronizeQuickOptions() {
        guard let quickToolbar else { return }
        guard !model.isSwitchingImage, model.cropDraft == nil, model.editingTextObject == nil,
              let object = model.selectedObject, object.id == quickOptionsObjectID else {
            closeQuickOptions(); return
        }
        let anchor = quickOptionsAnchor(for: object)
        if anchor.isNull || anchor.isEmpty { closeQuickOptions() }
        else {
            let layout = Self.quickOptionsLayout(anchor: anchor, horizontalSize: EditorQuickOptions.horizontalSize(for: object), in: quickOptionsContainer.bounds)
            if quickToolbar.rootView.placement != layout.placement { quickToolbar.rootView.placement = layout.placement }
            quickToolbar.frame = layout.frame
        }
    }
    /// Canvas coordinates are flipped: a smaller y places the toolbar above the object.
    static func quickOptionsLayout(anchor: CGRect, horizontalSize: CGSize, in bounds: CGRect)
        -> (frame: CGRect, placement: EditorQuickOptions.Placement) {
        let available = bounds.insetBy(dx: min(8, bounds.width / 2), dy: min(8, bounds.height / 2))
        let gap: CGFloat = 12
        func fitted(_ origin: CGPoint, size: CGSize) -> CGRect {
            CGRect(x: min(max(available.minX, origin.x), max(available.minX, available.maxX - size.width)),
                   y: min(max(available.minY, origin.y), max(available.minY, available.maxY - size.height)),
                   width: size.width, height: size.height)
        }
        let candidates = EditorQuickOptions.Placement.allCases.map { placement in
            let size = placement.isHorizontal ? horizontalSize : CGSize(width: horizontalSize.height, height: horizontalSize.width)
            let origin: CGPoint
            switch placement {
            case .above: origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
            case .below: origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
            case .right: origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
            case .left: origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
            }
            return (frame: fitted(origin, size: size), placement: placement)
        }
        let fitting = candidates.filter { available.contains($0.frame) }
        let options = fitting.isEmpty ? candidates : fitting
        // Sliding along a canvas edge is fine; avoid covering the selected object whenever possible.
        return options.first { !$0.frame.intersects(anchor.insetBy(dx: -gap, dy: -gap)) }
            ?? options.min { first, second in
                let a = first.frame.intersection(anchor), b = second.frame.intersection(anchor)
                return max(0, a.width) * max(0, a.height) < max(0, b.width) * max(0, b.height)
            }!
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        cursorTrackingArea = nil
        guard !isPickingColor else { return }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(area); cursorTrackingArea = area
    }
    override func resetCursorRects() {
        guard !isPickingColor else { return }
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        addCursorRect(bounds, cursor: canvasCursor(at: point, modifiers: NSEvent.modifierFlags))
    }
    override func cursorUpdate(with event: NSEvent) {
        guard !isPickingColor else { return }
        canvasCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags).set()
    }
    override func mouseEntered(with event: NSEvent) { cursorUpdate(with: event) }
    override func mouseMoved(with event: NSEvent) { cursorUpdate(with: event) }
    func canvasCursor(at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSCursor {
        guard !model.isSwitchingImage else { return .arrow }
        if quickToolbar?.frame.contains(convert(point, to: quickOptionsContainer)) == true { return .arrow }
        if isSpaceHeld || panGesture != nil {
            return panGesture == nil ? .openHand : .closedHand
        }
        if start != nil {
            if let resizeHandle { return resizeCursor(resizeHandle) }
            if textResizeFromLeft != nil { return model.history.transform.swapsAxes ? .resizeUpDown : .resizeLeftRight }
            if arrowEndpoint != nil || draggingArrowBend || draggingCalloutTip { return .crosshair }
            if draggedID != nil { return Self.objectMoveCursor }
        }
        let sourcePoint = projection.sourcePoint(point)
        if canEditObjects(modifiers: modifiers), let group = groupObject(in: model.objects),
           let grip = handle(at: sourcePoint, of: group) { return resizeCursor(grip) }
        if let crop = model.cropDraft {
            if !modifiers.contains(.option), let handle = cropHandle(at: sourcePoint, in: crop) {
                return resizeCursor(handle)
            }
            guard imageRect.contains(point) else { return .arrow }
            return crop != model.fullCanvasRect && crop.contains(sourcePoint) && !modifiers.contains(.option) ? .openHand : .crosshair
        }
        let editsObjects = canEditObjects(modifiers: modifiers)
        let object = editsObjects && imageRect.contains(point) ? hit(sourcePoint) : nil
        if model.tool == .text || model.tool == .callout, let object,
           object.kind == .text || object.kind == .callout, textBoxRect(object).contains(sourcePoint) { return .iBeam }
        if editsObjects, model.editingTextObject == nil, let object = model.selectedObject {
            if object.kind == .callout, visible(EditorRenderer.calloutTip(object)),
               distance(EditorRenderer.calloutTip(object), sourcePoint) <= 10 { return .crosshair }
            if let handle = handle(at: sourcePoint, of: object) { return resizeCursor(handle) }
            if endpoint(at: sourcePoint, of: object) != nil { return .crosshair }
            if object.kind == .arrow, visible(EditorArrow.bendHandle(for: object)), distance(EditorArrow.bendHandle(for: object), sourcePoint) <= 10 { return .crosshair }
            if imageRect.contains(point), object.kind == .text,
               textWidthHandles(object).contains(where: {
                   visible($0) && SelectionGrips.hitRect(at: viewPoint($0), shape: .vertical).contains(point)
               }) { return model.history.transform.swapsAxes ? .resizeUpDown : .resizeLeftRight }
        }
        guard imageRect.contains(point) else { return .arrow }
        if let object {
            if model.selectedIDs.count > 1, model.selectedIDs.contains(object.id) { return Self.objectMoveCursor }
            if object.kind == .text || object.kind == .callout,
               textBoxRect(object).contains(sourcePoint),
               model.tool == .text || model.tool == .callout || model.selection == object.id {
                return .iBeam
            }
            if endpoint(at: sourcePoint, of: object) != nil { return .crosshair }
            return Self.objectMoveCursor
        }
        return model.tool == .selection ? .arrow : model.tool == .text || model.tool == .callout ? .iBeam : .crosshair
    }
    override func layout() {
        super.layout()
        synchronizeViewport()
        synchronizeTextEditor()
        synchronizeQuickOptions()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if presentationImageRect == nil { NSColor.underPageBackgroundColor.setFill(); bounds.fill() }
        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY); context.scaleBy(x: scaleX, y: scaleY)
        context.translateBy(x: -model.sourceRect.minX, y: -model.sourceRect.minY)
        let drawingRect = model.previewSourceRect
        let frame = model.history.presentation
        if model.cropDraft == nil, frame.cornerRadius > 0 || frame.border != nil {
            // Frame sizes are output pixels. Map back to source coordinates so
            // cropped/non-uniformly resized images keep the exported radius/width.
            let source = drawingRect
            let output = CGSize(width: source.width * model.imageSize.width / model.sourceRect.width,
                                height: source.height * model.imageSize.height / model.sourceRect.height)
            context.saveGState()
            context.translateBy(x: source.minX, y: source.minY)
            context.scaleBy(x: source.width / output.width, y: source.height / output.height)
            EditorRenderer.drawFramedContent(in: context, rect: CGRect(origin: .zero, size: output), radius: frame.cornerRadius, border: frame.border) {
                context.saveGState()
                context.scaleBy(x: output.width / source.width, y: output.height / source.height)
                context.translateBy(x: -source.minX, y: -source.minY)
                drawContent(in: context, drawingRect: drawingRect)
                context.restoreGState()
            }
            context.restoreGState()
        } else { drawContent(in: context, drawingRect: drawingRect) }
        let selected = model.editingTextObject ?? model.objects.first { $0.id == model.selection }
        if !isPickingColor {
            if model.selectedIDs.count > 1 {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1.5 / scale)
                for object in model.objects where model.selectedIDs.contains(object.id) {
                    context.stroke(EditorRenderer.bounds(object).insetBy(dx: -4 / scaleX, dy: -4 / scaleY))
                }
                if let group = groupObject(in: model.objects) { drawOutline(group, in: context) }
            } else if let selected { drawOutline(selected, in: context) }
            else if let object = gestureObject, object.kind == .blur { drawOutline(object, in: context) }
        }
        if !snapGuides.isEmpty {
            context.saveGState(); context.setStrokeColor(NSColor.systemPink.cgColor)
            context.setLineDash(phase: 0, lengths: [4 / scale, 3 / scale])
            for guide in snapGuides {
                if guide.axis == .vertical {
                    context.setLineWidth(1 / scaleX); context.move(to: CGPoint(x: guide.position, y: drawingRect.minY)); context.addLine(to: CGPoint(x: guide.position, y: drawingRect.maxY))
                } else {
                    context.setLineWidth(1 / scaleY); context.move(to: CGPoint(x: drawingRect.minX, y: guide.position)); context.addLine(to: CGPoint(x: drawingRect.maxX, y: guide.position))
                }
                context.strokePath()
            }
            context.restoreGState()
        }
        if let creationRect {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1 / scale)
            context.stroke(creationRect)
        }
        if let crop = model.cropDraft { drawCrop(crop, in: context) }
        context.restoreGState()
    }
    private func drawContent(in context: CGContext, drawingRect: CGRect) {
        context.saveGState()
        context.clip(to: drawingRect)
        if model.history.canvasRect != nil || drawingRect != model.sourceRect {
            drawTransparency(in: drawingRect, context: context)
        }
        let displayedImage = model.image
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
        let sourceBounds = CGRect(x: 0, y: 0, width: model.image.width, height: model.image.height)
        for object in model.objects where object.kind == .blur {
            let area = object.rect.intersection(sourceBounds)
            guard !area.isNull, !area.isEmpty else { continue }
            let matching = blurPatches.filter { $0.matches(object) && $0.rect.intersects(area) }
            let fallback = blurPatches.filter { $0.objectID == object.id && $0.rect.intersects(area) }
            let patch = matching.last(where: { $0.rect.contains(area) }) ?? matching.last ?? fallback.last
            context.saveGState()
            if patch?.rect.contains(area) != true {
                // Any not-yet-prepared part stays opaque until filtered pixels exist.
                let path = CGMutablePath(); path.addRect(area)
                if let covered = patch?.rect.intersection(area), !covered.isNull { path.addRect(covered) }
                context.addPath(path); context.clip(using: .evenOdd)
                context.setFillColor(NSColor.black.cgColor); context.fill(area)
            }
            context.restoreGState()
            if let patch { EditorRenderer.drawBlurPatch(patch, clippedTo: area, in: context) }
        }
        EditorRenderer.drawAnnotations(objects: model.objects, in: context, editingTextID: model.editingTextObject?.id, cachedAssetsOnly: true,
                                       magnifierSource: magnifierObjects == model.objects.filter({ $0.kind != .magnifier }) ? magnifierImage : nil,
                                       magnifierSourceSize: magnifierSourceSize)
        context.restoreGState()
    }
    /// A view-only checkerboard makes transparent canvas extension visible without changing exported pixels.
    private func drawTransparency(in rect: CGRect, context: CGContext) {
        context.setFillColor(NSColor.controlBackgroundColor.cgColor); context.fill(rect)
        let visible = CGRect(origin: projection.sourcePoint(bounds.origin),
                             size: CGSize(width: bounds.width / scaleX, height: bounds.height / scaleY)).intersection(rect)
        guard !visible.isNull else { return }
        let cellWidth = 12 / scaleX, cellHeight = 12 / scaleY
        context.setFillColor(NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor)
        for row in Int(floor(visible.minY / cellHeight))...Int(floor(visible.maxY / cellHeight)) {
            for column in Int(floor(visible.minX / cellWidth))...Int(floor(visible.maxX / cellWidth)) where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight))
            }
        }
    }
    private func drawCrop(_ crop: CGRect, in context: CGContext) {
        let mask = CGMutablePath(); mask.addRect(model.fullCanvasRect); mask.addRect(crop)
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
        let point = pixelPoint(event), size = model.fullCanvasRect
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
        if object.kind == .image, object.imageRotationDegrees != nil {
            let path = CGMutablePath()
            for (index, handle) in [EditorResizeHandle.topLeft, .topRight, .bottomRight, .bottomLeft].enumerated() {
                let p = point(handle.point(in: object.rect).applying(object.imageRotationTransform))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath(); context.addPath(path); context.strokePath()
            for handle in EditorResizeHandle.allCases {
                let position = point(handle.point(in: object.rect).applying(object.imageRotationTransform))
                let radians = (object.imageRotationDegrees ?? 0) * .pi / 180
                let tangent = handle.gripShape == .vertical ? CGPoint(x: -sin(radians) * scaleX, y: cos(radians) * scaleY) : CGPoint(x: cos(radians) * scaleX, y: sin(radians) * scaleY)
                context.saveGState(); context.translateBy(x: position.x, y: position.y)
                context.rotate(by: atan2(tangent.y, tangent.x) - (handle.gripShape == .vertical ? .pi / 2 : 0))
                SelectionGrips.draw(at: .zero, shape: handle.gripShape, in: context); context.restoreGState()
            }
            return
        }
        if object.kind == .arrow {
            for source in [object.start, object.end, EditorArrow.bendHandle(for: object)] {
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
        clickedObjectID = nil; sourceImageClick = nil
        synchronizeViewport()
        defer {
            // An object press is only a pending drag. Toggling the shared busy
            // state for a plain click briefly dims/replaces unrelated controls.
            model.isCanvasGestureActive = gestureObject != nil || creatingText || textSelectionAnchor != nil || panGesture != nil || cropGesture != nil
            window?.invalidateCursorRects(for: self)
            cursorUpdate(with: event)
        }
        // Reset gesture state before any early return (e.g. clicks outside the image).
        start = nil; draggedID = nil; gestureObject = nil; arrowEndpoint = nil; draggingArrowBend = false; resizeHandle = nil; resizingGroupBounds = nil; snapGuides = []; draggingCalloutTip = false; draggingMagnifierSource = false; lastDragPoint = nil
        model.preview = nil
        model.endPresentationEditing(); model.endStyleEditing()
        let previousSelection = model.selection
        let previousSelectedIDs = model.selectedIDs
        model.finishTextEditing()
        synchronizeTextEditor()
        creatingText = false; creationRect = nil; textSelectionAnchor = nil; textResizeFromLeft = nil
        window?.makeFirstResponder(self)
        if isSpaceHeld {
            closeQuickOptions()
            panGesture = (viewportPoint(event), model.viewport)
            window?.invalidateCursorRects(for: self)
            return
        }
        let point = pixelPoint(event)
        let editsObjects = canEditObjects(modifiers: event.modifierFlags)
        if let crop = model.cropDraft {
            closeQuickOptions()
            if !event.modifierFlags.contains(.option), let handle = cropHandle(at: point, in: crop) {
                cropGesture = (point, crop, .resize(handle))
            } else if imageRect.contains(convert(event.locationInWindow, from: nil)) {
                let move = crop != model.fullCanvasRect && crop.contains(point) && !event.modifierFlags.contains(.option)
                cropGesture = (point, crop, move ? .move : .draw)
            }
            needsDisplay = true
            return
        }
        let object = editsObjects && imageRect.contains(convert(event.locationInWindow, from: nil)) ? hit(point) : nil
        if object?.id != quickOptionsObjectID || event.clickCount >= 2 || event.modifierFlags.contains(.shift) {
            closeQuickOptions()
        }
        if editsObjects, let group = groupObject(in: model.history.objects), let grip = handle(at: point, of: group) {
            resizeHandle = grip; resizingGroupBounds = group.rect; start = point; original = model.history.objects
            return
        }
        // Native text clicks win over nearby handle hit areas, especially when zoomed out.
        if let object, object.kind == .text || object.kind == .callout, textBoxRect(object).contains(point),
           model.tool == .text || model.tool == .callout || event.clickCount >= 2 {
            beginTextSelection(object, with: event)
            return
        }
        if editsObjects, let object = model.selectedObject, object.kind == .callout,
           visible(EditorRenderer.calloutTip(object)), distance(EditorRenderer.calloutTip(object), point) <= 10 {
            draggingCalloutTip = true; draggedID = object.id; start = point; original = model.history.objects
            return
        }
        if editsObjects, let object, object.kind == .magnifier, object.magnifierSource != nil,
           CGPath(ellipseIn: object.magnifierSourceRect, transform: nil).contains(point),
           !CGPath(ellipseIn: object.rect, transform: nil).contains(point) {
            model.selection = object.id
            draggingMagnifierSource = true; draggedID = object.id; start = point; original = model.history.objects
            return
        }
        // Visible handles also accept clicks just outside the image at its edges.
        if editsObjects, let object = model.selectedObject, let handle = handle(at: point, of: object) {
            resizeHandle = handle; draggedID = object.id; start = point; original = model.history.objects
            return
        }
        if editsObjects, let object = model.selectedObject, let endpoint = endpoint(at: point, of: object) {
            arrowEndpoint = endpoint; draggedID = object.id; start = point; original = model.history.objects
            return
        }
        if editsObjects, let object = model.selectedObject, object.kind == .arrow,
           visible(EditorArrow.bendHandle(for: object)), distance(EditorArrow.bendHandle(for: object), point) <= 10 {
            draggingArrowBend = true; draggedID = object.id; start = point; original = model.history.objects
            return
        }
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else {
            model.selection = nil
            if !previousSelectedIDs.isEmpty { needsDisplay = true }
            return
        }
        if editsObjects, let object = model.selectedObject, object.kind == .text,
           let edge = textWidthHandles(object).firstIndex(where: {
               visible($0) && SelectionGrips.hitRect(at: viewPoint($0), shape: .vertical).contains(viewPoint(point))
           }) {
            textResizeFromLeft = edge == 0
            draggedID = object.id; start = point; original = model.history.objects
            return
        }
        if model.tool == .steps, object == nil {
            model.placeStep(at: point); needsDisplay = true; window?.invalidateCursorRects(for: self)
            return
        }
        if model.tool == .text || model.tool == .callout {
            if let object, object.kind == .text || object.kind == .callout {
                beginTextSelection(object, with: event)
                return
            }
            if object == nil {
                model.editText(at: point); start = point; creatingText = true
                synchronizeTextEditor()
                needsDisplay = true
                return
            }
        }
        if editsObjects {
            if let object, event.modifierFlags.contains(.shift) {
                model.select(object.id, extending: true); needsDisplay = true; return
            }
            if let object {
                if !model.selectedIDs.contains(object.id) { model.select(object.id) }
            } else { model.selection = nil }
            if model.selectedIDs.count > 1 {
                draggedID = object?.id; start = point; original = model.history.objects
                if model.selectedIDs != previousSelectedIDs { needsDisplay = true }
                return
            }
            if let object, (object.kind == .text || object.kind == .callout),
               textBoxRect(object).contains(point), (event.clickCount >= 2 || previousSelection == object.id) {
                beginTextSelection(object, with: event)
                return
            }
            draggedID = object?.id
            if let object { arrowEndpoint = endpoint(at: point, of: object) }
            if arrowEndpoint == nil { clickedObjectID = object?.id }
        }
        // The empty selection background has no gesture to track or redraw.
        guard draggedID != nil || model.drawingKind != nil else {
            if model.tool == .selection, !event.modifierFlags.contains(.shift), model.originalRect.contains(point) {
                sourceImageClick = convert(event.locationInWindow, from: nil)
            }
            if model.selectedIDs != previousSelectedIDs { needsDisplay = true }
            return
        }
        start = point; original = model.history.objects
        if draggedID == nil, let kind = model.drawingKind {
            guard model.history.objects.count < 10_000 else { start = nil; model.notice = String(localized: "Die Projektgrenze von 10.000 Objekten ist erreicht."); return }
            model.selection = nil
            gestureObject = model.makeObject(kind: kind, start: point, end: point)
            if (kind == .highlight && gestureObject?.highlightStyle?.mode == .freehand || kind == .pen), let object = gestureObject {
                model.preview = original + [object]
            }
        }
        if gestureObject != nil || model.selectedIDs != previousSelectedIDs { needsDisplay = true }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if cropGesture != nil { updateCrop(with: event); return }
        if let panGesture {
            let point = viewportPoint(event)
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
        if let start, distance(point, start) >= 3 { clickedObjectID = nil }
        lastDragPoint = point
        updateDrag(at: point, modifiers: event.modifierFlags)
    }
    override func flagsChanged(with event: NSEvent) {
        guard !model.isSwitchingImage else { return }
        if start != nil, let point = lastDragPoint, !creatingText, textSelectionAnchor == nil {
            updateDrag(at: point, modifiers: event.modifierFlags)
        } else { super.flagsChanged(with: event) }
        window?.invalidateCursorRects(for: self)
        cursorUpdate(with: event)
    }
    private func updateDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let start else { return }
        guard gestureObject != nil || creatingText || point != start || model.preview != nil else { return }
        closeQuickOptions()
        model.isCanvasGestureActive = true
        let constrained = modifiers.contains(.shift)
        if creatingText {
            guard distance(point, start) >= 5 else { return }
            let rect = CGRect(x: max(model.sourceRect.minX, min(start.x, point.x)), y: max(model.sourceRect.minY, min(start.y, point.y)),
                              width: max(40 / scaleX, abs(point.x - start.x)), height: abs(point.y - start.y))
            let width = min(rect.width, model.sourceRect.maxX - rect.minX)
            creationRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            if model.editingTextObject?.kind == .callout {
                // Keep the pointer at mouse-down and leave room for the tail.
                // Grow the body toward the pointer in any drag direction.
                let dx = point.x - start.x, dy = point.y - start.y
                let length = max(1, hypot(dx, dy))
                let gapX = 24 * abs(dx) / length
                let gapY = 24 * abs(dy) / length
                let bodyWidth = max(48, abs(dx) - gapX)
                let bodyHeight = max(44, abs(dy) - gapY)
                let origin = CGPoint(x: dx >= 0 ? start.x + gapX : start.x - gapX - bodyWidth,
                                     y: dy >= 0 ? start.y + gapY : start.y - gapY - bodyHeight)
                model.positionCallout(in: CGRect(origin: origin, size: CGSize(width: bodyWidth, height: bodyHeight)))
                creationRect = nil
            } else { model.positionText(at: rect.origin, width: max(1, width)) }
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
        } else if draggingArrowBend, let draggedID, let object = original.first(where: { $0.id == draggedID }) {
            let previous = EditorArrow.bendHandle(for: object)
            model.preview = original.map {
                guard $0.id == draggedID else { return $0 }
                var next = $0
                next.arrowBend = CGPoint(x: previous.x + point.x - start.x, y: previous.y + point.y - start.y)
                return next
            }
        } else if draggingMagnifierSource, let draggedID {
            model.preview = original.map {
                guard $0.id == draggedID, let source = $0.magnifierSource else { return $0 }
                var next = $0
                next.magnifierSource = CGPoint(x: source.x + point.x - start.x, y: source.y + point.y - start.y)
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
        } else if let resizeHandle, let groupBounds = resizingGroupBounds {
            let target = EditorGeometry.resized(groupBounds, handle: resizeHandle,
                delta: CGSize(width: point.x - start.x, height: point.y - start.y), minimum: CGSize(width: 8 / scaleX, height: 8 / scaleY),
                aspectRatio: constrained ? groupBounds.width / max(1, groupBounds.height) : nil)
            model.preview = original.map { object in
                guard model.selectedIDs.contains(object.id) else { return object }
                var input = object
                if input.kind == .callout { input.calloutTip = EditorRenderer.calloutTip(input) }
                return EditorArrangement.scaled(object: input, from: groupBounds, to: target)
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
            if object.kind == .pen, var pen = object.penStroke {
                if let previous = pen.points.last, distance(previous, point) > 0.5 {
                    if pen.points.count < EditorPenStroke.maximumPoints { pen.points.append(point) }
                    else { model.notice = String(localized: "Maximale Strichlänge erreicht. Beginne eine weitere Markierung.") }
                }
                object.penStroke = pen; object.end = point
            } else if object.kind == .highlight, var highlight = object.highlightStyle, highlight.mode == .freehand {
                if let previous = highlight.points.last, hypot(point.x - previous.x, point.y - previous.y) > 0.01 {
                    if highlight.points.count < EditorHighlightStyle.maximumPoints { highlight.points.append(point) }
                    else { model.notice = String(localized: "Maximale Strichlänge erreicht. Beginne eine weitere Markierung.") }
                }
                object.highlightStyle = highlight; object.end = point
            } else {
                if object.kind == .magnifier, model.defaultMagnifierOffset {
                    let radius = max(24, min(160, distance(point, start) / 3))
                    object.magnifierSource = start
                    object.start = CGPoint(x: point.x - radius, y: point.y - radius)
                    object.end = CGPoint(x: point.x + radius, y: point.y + radius)
                } else if object.kind == .magnifier {
                    object.end = EditorGeometry.constrainedEnd(from: object.start, to: point, kind: .ellipse)
                } else {
                    object.end = constrained ? EditorGeometry.constrainedEnd(from: object.start, to: point, kind: object.kind) : point
                }
            }
            gestureObject = object
            model.preview = original + [object]
        } else if let draggedID {
            let ids = model.selectedIDs.union([draggedID])
            var delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            let moving = original.filter { ids.contains($0.id) }.map { EditorRenderer.bounds($0).offsetBy(dx: delta.width, dy: delta.height) }
            if model.snapsToObjects, !modifiers.contains(.option), let bounds = moving.reduce(nil as CGRect?, { partial, rect in partial.map { $0.union(rect) } ?? rect }) {
                let result = EditorArrangement.snap(rect: bounds, candidates: original.filter { !ids.contains($0.id) }.map(EditorRenderer.bounds),
                    canvas: model.sourceRect, tolerance: CGSize(width: 6 / scaleX, height: 6 / scaleY))
                delta.width += result.delta.width; delta.height += result.delta.height; snapGuides = result.guides
            } else { snapGuides = [] }
            model.preview = original.map {
                guard ids.contains($0.id) else { return $0 }
                var moved = $0.translated(by: delta)
                if ids.count == 1, $0.kind == .magnifier { moved.magnifierSource = $0.magnifierSource }
                return moved
            }
        }
        refreshComposition()
        needsDisplay = true
        // Mouse tracking must not wait for a SwiftUI body update.
        displayIfNeeded()
    }
    private func resizedObject(_ object: EditorObject, handle: EditorResizeHandle, delta: CGSize, constrained: Bool) -> EditorObject {
        guard let old = resizeBox(object) else { return object }
        if object.kind == .image, let degrees = object.imageRotationDegrees {
            let angle = degrees * .pi / 180
            let movement = CGPoint(x: delta.width, y: delta.height).applying(CGAffineTransform(rotationAngle: -angle))
            let resized = EditorGeometry.resized(old, handle: handle, delta: CGSize(width: movement.x, height: movement.y),
                minimum: CGSize(width: 4 / scaleX, height: 4 / scaleY), aspectRatio: constrained ? old.width / max(1, old.height) : nil)
            let center = CGPoint(x: resized.midX, y: resized.midY).applying(object.imageRotationTransform)
            var next = object
            next.start = CGPoint(x: center.x - resized.width / 2, y: center.y - resized.height / 2)
            next.end = CGPoint(x: center.x + resized.width / 2, y: center.y + resized.height / 2)
            return next
        }
        let isCallout = object.kind == .callout
        let minimum = isCallout ? CGSize(width: 48, height: 21) : object.kind == .step ? CGSize(width: 24, height: 24) : CGSize(width: 4 / scaleX, height: 4 / scaleY)
        let ratio: CGFloat? = object.kind == .magnifier ? 1 : object.kind == .step ? old.width / max(1, old.height)
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
        if let press = sourceImageClick {
            sourceImageClick = nil
            let release = convert(event.locationInWindow, from: nil)
            if hypot(release.x - press.x, release.y - press.y) <= 3 { model.selectSourceImage() }
            return
        }
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
            synchronizeTextEditor()
            needsDisplay = true
            return
        }
        let point = pixelPoint(event)
        let quickObjectID = clickedObjectID
        let hadPreview = model.preview != nil
        let isFreehand = gestureObject?.kind == .pen || gestureObject?.kind == .highlight && gestureObject?.highlightStyle?.mode == .freehand
        let validFocus = gestureObject?.kind != .spotlight || (gestureObject!.rect.width > 0 && gestureObject!.rect.height > 0)
        if let preview = model.preview, validFocus && (draggedID != nil || resizingGroupBounds != nil || model.tool == .selection || isFreehand || distance(point, start) >= 5) {
            model.commit(preview, expandingCanvas: true)
            if gestureObject != nil { model.selection = preview.last?.id }
        } else { model.preview = nil }
        self.start = nil; draggedID = nil; gestureObject = nil; textResizeFromLeft = nil; arrowEndpoint = nil; draggingArrowBend = false; resizeHandle = nil; resizingGroupBounds = nil; snapGuides = []; draggingCalloutTip = false; draggingMagnifierSource = false; lastDragPoint = nil
        clickedObjectID = nil
        if hadPreview { refreshComposition(); needsDisplay = true }
        window?.invalidateCursorRects(for: self)
        model.isCanvasGestureActive = false
        if let quickObjectID { showQuickOptions(for: quickObjectID) }
    }

    private func beginTextSelection(_ object: EditorObject, with event: NSEvent) {
        closeQuickOptions()
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
        // The canvas owns the complete callout drag; text input starts on release.
        if creatingText, model.editingTextObject?.kind == .callout { return }
        guard let object = model.editingTextObject else {
            if let textView {
                // Finishing text also ends a pending creation/selection drag,
                // even if its mouse-up has not reached the canvas.
                start = nil; draggedID = nil; creatingText = false; creationRect = nil
                textSelectionAnchor = nil; textResizeFromLeft = nil; lastDragPoint = nil
                model.isCanvasGestureActive = false
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
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        if (123...126).contains(event.keyCode), modifiers.isEmpty, !isSpaceHeld,
           model.canNudgeSelection {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGSize
            switch event.keyCode {
            case 123: delta = CGSize(width: -step, height: 0)
            case 124: delta = CGSize(width: step, height: 0)
            case 125: delta = CGSize(width: 0, height: step)
            default: delta = CGSize(width: 0, height: -step)
            }
            closeQuickOptions()
            model.nudgeSelection(by: delta)
            refreshComposition(); needsDisplay = true; window?.invalidateCursorRects(for: self)
        } else if (event.keyCode == 36 || event.keyCode == 76), model.cropDraft != nil {
            model.applyCrop(); needsDisplay = true; window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 49, !event.modifierFlags.contains(.command), !model.isCanvasGestureActive {
            isSpaceHeld = true; window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 53 {
            if quickToolbar != nil { closeQuickOptions(); return }
            if let panGesture { model.viewport = panGesture.viewport }
            panGesture = nil; isSpaceHeld = false; model.isCanvasGestureActive = false
            cropGesture = nil
            if model.cropDraft != nil { model.cancelCrop() }
            model.finishTextEditing(cancel: true)
            model.preview = nil; start = nil; draggedID = nil; gestureObject = nil; model.selection = nil
            creatingText = false; creationRect = nil; textSelectionAnchor = nil; textResizeFromLeft = nil; arrowEndpoint = nil; draggingArrowBend = false; resizeHandle = nil; resizingGroupBounds = nil; snapGuides = []; draggingCalloutTip = false; draggingMagnifierSource = false; lastDragPoint = nil
            refreshComposition(); needsDisplay = true; window?.invalidateCursorRects(for: self)
        } else if event.keyCode == 51 || event.keyCode == 117 {
            guard model.canActOnSelection else { return }
            closeQuickOptions()
            model.removeSelection()
        }
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
        guard !model.isSwitchingImage,
              hasKeyboardFocus(in: self) || hasKeyboardFocus(in: quickToolbar)
                || hasKeyboardFocus(in: (superview as? EditorCanvasContainer)?.colorPickingView)
        else { return false }
        if let eventWindow = event.window, eventWindow !== window { return false }
        if let editor = textView, window?.firstResponder === editor { return editor.performKeyEquivalent(with: event) }
        if window?.firstResponder is NSTextView { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else { return false }
        let character = event.charactersIgnoringModifiers?.lowercased()
        guard !modifiers.contains(.shift) || ["z", "g", "+", "="].contains(character ?? "") else { return false }
        if event.keyCode == 36, let object = model.selectedObject {
            showQuickOptions(for: object.id); return true
        }
        switch character {
        case "z": event.modifierFlags.contains(.shift) ? model.redo() : model.undo(); return true
        case "c": model.copyPNG(); return true
        case "d": model.duplicateSelection(); return true
        case "a": model.selectAllObjects(); return true
        case "g": model.groupSelection(ungroup: event.modifierFlags.contains(.shift)); return true
        case "+", "=": model.zoomBy(1.25); viewportChanged(); return true
        case "-": model.zoomBy(1 / 1.25); viewportChanged(); return true
        case "1": model.setZoom(1); viewportChanged(); return true
        case "0": model.fitImage(); viewportChanged(); return true
        default: return false
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
