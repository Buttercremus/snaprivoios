import AppKit
import CoreTransferable
import Observation
import SnagForgeDomain
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorModel {
    @ObservationIgnored var requestFeature: @MainActor (ProFeature) -> Bool = { _ in true }
    @ObservationIgnored var hasProAccess: @MainActor () -> Bool = { true }
    let image: CGImage
    @ObservationIgnored var initialCanvas: EditorCanvasPreparation?
    /// Freeze outgoing document input while retaining its rendered UI until the replacement is ready.
    var isSwitchingImage = false
    private(set) var document: ProjectDocument
    var name: String { document.title }
    @discardableResult func updateMetadata(title: String? = nil, favorite: Bool? = nil, tags: [String]? = nil, collections: [String]? = nil) -> Bool {
        guard (tags == nil && collections == nil) || requestFeature(.organization) else { return false }
        guard !isSwitchingImage else { return false }
        // Validate the whole metadata edit before changing any part of the document.
        guard let nextTags = try? ProjectOrganization.normalized(tags ?? document.tags, limit: ProjectOrganization.maximumTags),
              let nextCollections = try? ProjectOrganization.normalized(collections ?? document.collections, limit: ProjectOrganization.maximumCollections) else { return false }
        if let title {
            let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 1024 else { return false }
            if value != document.title { document.title = value; changed() }
        }
        if let favorite, favorite != document.isFavorite { document.isFavorite = favorite; changed() }
        if nextTags != document.tags || nextCollections != document.collections {
            document.tags = nextTags; document.collections = nextCollections; changed()
        }
        return true
    }
    private(set) var savedRevision: Int
    private(set) var isSaving = false
    var saveError: String?
    var isDirty: Bool { document.revision != savedRevision }
    var saveStatus: String { saveError != nil ? String(localized: "Speichern fehlgeschlagen") : isSaving ? String(localized: "Wird gesichert …") : isDirty ? String(localized: "Änderungen werden gesichert …") : String(localized: "Alle Änderungen gesichert") }
    @ObservationIgnored private var store: ProjectStore
    @ObservationIgnored private let onSaved: @MainActor () -> Void
    @ObservationIgnored var onLibraryItemSaved: (@MainActor (ProjectLibraryItem) -> Void)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Bool, Never>?
    typealias PNGWriter = @Sendable (Data, URL) async throws -> Void
    typealias PNGApplicationOpener = @MainActor (URL, URL) async throws -> Void
    @ObservationIgnored private let writePNG: PNGWriter
    @ObservationIgnored private let pngDirectory: @MainActor () -> URL?
    @ObservationIgnored private let openPNGApplication: PNGApplicationOpener
    @ObservationIgnored private let externalOpenRoot: URL
    @ObservationIgnored private var externalOpenTask: Task<Bool, Never>?
    @ObservationIgnored private var applicationPanel: NSOpenPanel?
    @ObservationIgnored private var pngExportTask: Task<Bool, Never>?
    @ObservationIgnored private var pngExportPanel: NSSavePanel?
    private var isFinishingPendingWork = false
    @ObservationIgnored private var hasUnacknowledgedOutputError = false
    var isEditingPresentation = false {
        didSet {
            guard oldValue != isEditingPresentation else { return }
            isSourceImageSelected = false
            if isEditingPresentation { isRecognizingTextInPlace = false }
            let reference = history.presentation.previewReferenceSize(for: document.contentPixelSize)
            preserveViewportScale(from: oldValue || history.presentation.requiresCanvasLayout ? reference : imageSize)
            endPresentationEditing()
        }
    }
    @ObservationIgnored private var isAdjustingPresentation = false
    var history = EditorHistory()
    var preview: [EditorObject]?
    private(set) var isSourceImageSelected = false
    private(set) var selectedIDs: Set<UUID> = [] {
        didSet { isSourceImageSelected = false }
    }
    var selection: UUID? {
        get { history.objects.first { selectedIDs.contains($0.id) }?.id }
        set { selectedIDs = newValue.map { expandedSelection([$0]) } ?? [] }
    }
    func expandedSelection(_ ids: Set<UUID>) -> Set<UUID> {
        let groups = Set(history.objects.filter { ids.contains($0.id) }.compactMap(\.groupID))
        return ids.union(history.objects.filter { $0.groupID.map(groups.contains) == true }.map(\.id))
    }
    func select(_ id: UUID, extending: Bool = false) {
        let group = expandedSelection([id])
        if extending {
            if group.isSubset(of: selectedIDs) { selectedIDs.subtract(group) } else { selectedIDs.formUnion(group) }
        } else { selectedIDs = group }
    }
    func selectObjectFromList(_ id: UUID) {
        guard !isSwitchingImage, !isCanvasGestureActive, cropDraft == nil,
              history.objects.contains(where: { $0.id == id }) else { return }
        isEditingPresentation = false
        isRecognizingTextInPlace = false
        endStyleEditing(); finishTextEditing(); tool = .selection
        // A list row targets one object, including members of a group.
        selectedIDs = [id]
    }
    func selectObjectsFromList(_ ids: Set<UUID>) {
        guard !isSwitchingImage, !isCanvasGestureActive, cropDraft == nil else { return }
        isEditingPresentation = false
        isRecognizingTextInPlace = false
        endStyleEditing(); finishTextEditing(); tool = .selection
        selectedIDs = ids.intersection(history.objects.map(\.id))
    }
    @discardableResult func renameObject(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSwitchingImage, !isCanvasGestureActive, cropDraft == nil,
              !trimmed.isEmpty, trimmed.count <= 120,
              !trimmed.unicodeScalars.contains(where: { $0.value < 32 }),
              history.objects.contains(where: { $0.id == id }) else { return false }
        endStyleEditing(); finishTextEditing()
        commit(history.objects.map { object in var next = object; if next.id == id { next.name = trimmed }; return next })
        return true
    }
    func selectAllObjects() {
        guard !isSwitchingImage, !isCanvasGestureActive, cropDraft == nil else { return }
        finishTextEditing(); tool = .selection; selectedIDs = Set(history.objects.map(\.id)); focusRequest += 1
    }
    func groupSelection(ungroup: Bool = false) {
        guard canActOnSelection, ungroup || selectedIDs.count > 1 else { return }
        let ids = selectedIDs, group = ungroup ? nil : UUID()
        commit(history.objects.map { object in
            var next = object
            if ids.contains(next.id) { next.groupID = group }
            return next
        })
        selectedIDs = ids
    }
    var tool: AnnotationTool = .selection {
        didSet {
            guard tool != oldValue else { return }
            if let feature = ProFeature.required(for: tool), !requestFeature(feature) {
                tool = oldValue; return
            }
            isSourceImageSelected = false
            isEditingPresentation = false
            isRecognizingTextInPlace = false
            if tool == .crop { startCropSession() }
            else if oldValue == .crop { closeCropSession() }
        }
    }
    var isShowingImageSize = false
    var isShowingTextRecognition = false
    var isRecognizingTextInPlace = false
    private var imageRotationDraftArea: CGRect?
    var isShowingRedactionSuggestions = false
    var snapsToObjects = true
    var cropDraft: CGRect?
    @ObservationIgnored private var cropViewport: EditorViewport?
    private(set) var editingTextObject: EditorObject?
    @ObservationIgnored private var textBase: [EditorObject] = []
    @ObservationIgnored private var isEditingStyle = false
    var error: String? {
        didSet { if error == nil { hasUnacknowledgedOutputError = false } }
    }
    private(set) var isExportingPNG = false
    private(set) var isOpeningExternally = false
    var isExporting: Bool { isExportingPNG || isOpeningExternally || copyState == .copying }
    /// Export only a confirmed canvas state. Busy copy feedback must not dim the whole toolbar.
    var hasExportableImage: Bool {
        !isSwitchingImage && hasConfirmedImageForToolbar && !isFinishingPendingWork
    }
    /// A switch blocks actions without fading otherwise unchanged toolbar buttons.
    var hasConfirmedImageForToolbar: Bool {
        cropDraft == nil && hasIdleCanvasForToolbar
    }
    private var hasIdleCanvasForToolbar: Bool {
        !isShowingImageSize && !isShowingTextRecognition && !isShowingRedactionSuggestions && !isCanvasGestureActive && preview == nil && !isOpeningExternally
    }
    var canSwitchEditingTool: Bool {
        hasIdleCanvasForToolbar && !isSwitchingImage && !isExporting && !isFinishingPendingWork
    }
    /// Switching tools discards only the crop preview; output still requires a confirmed image.
    @discardableResult func prepareForEditingTool() -> Bool {
        guard canSwitchEditingTool else { return false }
        if cropDraft != nil { cancelCrop() }
        return true
    }
    /// A value snapshot keeps an open system share independent of later edits or editor replacement.
    var pngShareItem: EditorPNGShare? {
        guard hasExportableImage, !isExportingPNG else { return nil }
        return pngShareItemForToolbar
    }
    var pngShareItemForToolbar: EditorPNGShare? {
        guard hasConfirmedImageForToolbar, !isExportingPNG else { return nil }
        return EditorPNGShare(image: image, objects: history.objects, crop: history.crop,
                              resizedSize: history.resizedSize, title: name, canvasRect: history.canvasRect, transform: history.transform, presentation: history.presentation)
    }
    enum CopyState { case idle, copying, copied }
    private(set) var copyState = CopyState.idle
    private(set) var animateCopyFeedback = false
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?
    var notice: String?
    var objects: [EditorObject] { preview ?? history.objects }
    var focusRequest = 0
    var viewport = EditorViewport()
    private(set) var automaticallyFitsImage: Bool
    @ObservationIgnored var viewportBounds = CGRect.zero
    @ObservationIgnored var viewportBackingScale: CGFloat = 1
    var isCanvasGestureActive = false
    var originalRect: CGRect { EditorCrop.fullRect(document.pixelSize) }
    var fullCanvasRect: CGRect { history.canvasRect ?? originalRect }
    var sourceRect: CGRect { cropDraft == nil ? document.outputRect : fullCanvasRect }
    var imageSize: CGSize { cropDraft != nil ? fullCanvasRect.size : CGSize(width: document.untransformedOutputPixelSize.width, height: document.untransformedOutputPixelSize.height) }
    func beginTextRecognition() {
        guard hasExportableImage, !isExporting else { return }
        guard requestFeature(.textRecognition) else { return }
        endStyleEditing(); finishTextEditing(); isShowingTextRecognition = true
    }
    func beginRedactionSuggestions() {
        guard hasExportableImage, !isExporting, requestFeature(.textRecognition) else { return }
        endStyleEditing(); finishTextEditing(); isShowingRedactionSuggestions = true
    }
    func beginImageResize() {
        guard prepareForEditingTool() else { return }
        endStyleEditing(); finishTextEditing(); isShowingImageSize = true
    }
    @discardableResult func applyImageSize(_ size: PixelSize) -> Bool {
        guard !isSwitchingImage, cropDraft == nil, !isCanvasGestureActive, EditorResize.isValid(size) else { return false }
        endStyleEditing(); finishTextEditing()
        let size = history.transform.applying(to: size)
        let next: PixelSize? = CGSize(width: size.width, height: size.height) == document.outputRect.size ? nil : size
        let old = history.resizedSize
        history.commitResize(next)
        if old != next { resetImageView(); selection = nil; changed() }
        focusRequest += 1
        return true
    }
    var canApplyCrop: Bool { !isSwitchingImage && cropDraft != nil && !isCanvasGestureActive }
    func beginCrop() {
        guard !isSwitchingImage, !isCanvasGestureActive else { return }
        tool = .crop
    }
    private func startCropSession() {
        endStyleEditing(); finishTextEditing()
        selection = nil; preview = nil; notice = nil
        cropViewport = viewport; cropDraft = document.outputRect
        viewport.fit(); focusRequest += 1
    }
    private func closeCropSession() {
        cropDraft = nil
        if let cropViewport { viewport = cropViewport }
        cropViewport = nil; focusRequest += 1
    }
    func cancelCrop() { tool = .selection }
    func applyCrop() {
        guard canApplyCrop, let cropDraft,
              let rect = EditorCrop.normalized(cropDraft, in: fullCanvasRect) else { return }
        let next: CGRect? = rect == fullCanvasRect ? nil : rect
        let old = history.crop, oldResize = history.resizedSize
        let resizedSize: PixelSize?
        do { resizedSize = try EditorResize.preservingScale(from: document.outputRect, to: rect, output: history.resizedSize) }
        catch { self.error = String(localized: "Dieser Ausschnitt überschreitet bei der gewählten Skalierung die Bildgrenze (32.768 Pixel je Kante, 100 Millionen Pixel)."); return }
        history.commitCrop(next, resizedSize: resizedSize)
        self.cropDraft = nil; cropViewport = nil; tool = .selection
        resetImageView()
        if old != next || oldResize != resizedSize { changed() }
    }
    func restoreOriginal() {
        guard !isSwitchingImage, !isCanvasGestureActive else { return }
        if cropDraft != nil { cropDraft = fullCanvasRect; focusRequest += 1 }
        else if history.crop != nil {
            endStyleEditing(); finishTextEditing()
            do {
                let size = try EditorResize.preservingScale(from: document.outputRect, to: fullCanvasRect, output: history.resizedSize)
                history.commitCrop(nil, resizedSize: size); resetImageView(); selection = nil; changed(); focusRequest += 1
            } catch { self.error = String(localized: "Das vollständige Original überschreitet bei dieser Skalierung die Bildgrenze. Verkleinere zuerst die Bildauflösung.") }
        }
    }
    var zoomLabel: String { viewport.zoom.map { "\(Int(($0 * 100).rounded())) %" } ?? String(localized: "Anpassen") }
    var viewportImageSize: CGSize {
        if isRecognizingTextInPlace { return CGSize(width: document.outputPixelSize.width, height: document.outputPixelSize.height) }
        return cropDraft == nil && (isEditingPresentation || history.presentation.requiresCanvasLayout) ? history.presentation.previewReferenceSize(for: document.contentPixelSize) : imageSize
    }
    /// Adding canvas around an image must not refit/shrink its existing pixels.
    private func preserveViewportScale(from previousSize: CGSize) {
        guard viewportBounds.width > 0, viewportBounds.height > 0 else { return }
        viewport.lockScale(image: previousSize, in: viewportBounds, backingScale: viewportBackingScale)
    }
    func setZoom(_ factor: CGFloat, at anchor: CGPoint? = nil) {
        guard !isCanvasGestureActive else { return }
        viewport.setZoom(factor, at: anchor ?? CGPoint(x: viewportBounds.midX, y: viewportBounds.midY),
                         image: viewportImageSize, in: viewportBounds, backingScale: viewportBackingScale)
    }
    func zoomBy(_ factor: CGFloat, at anchor: CGPoint? = nil) {
        let current = viewport.scale(image: viewportImageSize, in: viewportBounds, backingScale: viewportBackingScale) * viewportBackingScale
        setZoom(current * factor, at: anchor)
    }
    func fitImage() {
        guard !isCanvasGestureActive else { return }
        viewport.fit()
    }
    func setAutomaticallyFitsImage(_ enabled: Bool) {
        guard !isCanvasGestureActive else { return }
        automaticallyFitsImage = enabled
        resetImageView()
    }
    private func resetImageView() { viewport = EditorViewport(fitsImage: automaticallyFitsImage) }
    func panImage(by delta: CGSize) {
        viewport.pan(by: delta, image: viewportImageSize, in: viewportBounds, backingScale: viewportBackingScale)
    }
    var defaultRedactionColor = EditorColor(red: 0, green: 0, blue: 0)
    var activeColor: EditorColor {
        if let selectedObject { return selectedObject.color }
        switch activeKind {
        case .redact: return defaultRedactionColor
        case .highlight: return defaultHighlightColor
        case .step: return defaultStepColor
        default: return defaultColor
        }
    }
    var defaultColor = EditorColor()
    var defaultArrowLineWidth: CGFloat = 15
    var defaultLineWidth: CGFloat = 5
    var defaultFontSize: CGFloat = 32
    var defaultTextStyle = EditorTextStyle()
    var activeTextStyle: EditorTextStyle { selectedObject?.effectiveTextStyle ?? defaultTextStyle }
    var defaultPenWidth: CGFloat = 4
    var defaultPenSmoothed = true
    var defaultSpotlightStyle = EditorSpotlightStyle()
    var activePenSmoothed: Bool { selectedObject?.penStroke?.isSmoothed ?? defaultPenSmoothed }
    var activeSpotlightStyle: EditorSpotlightStyle { selectedObject?.spotlightStyle ?? defaultSpotlightStyle }
    var defaultMagnification: CGFloat = 2
    var defaultMagnifierOffset = false
    var activeMagnifierOffset: Bool {
        guard let object = selectedObject, object.kind == .magnifier else { return defaultMagnifierOffset }
        return object.magnifierSource != nil
    }
    var defaultShapeDrawingStyle = EditorDrawingStyle.precise
    var activeMagnification: CGFloat { selectedObject?.effectiveMagnification ?? defaultMagnification }
    var defaultBlurRadius: CGFloat = 12
    var defaultBlurStyle = EditorBlurStyle.gaussian
    var activeBlurStyle: EditorBlurStyle { selectedObject?.effectiveBlurStyle ?? defaultBlurStyle }
    var defaultShapeFill = EditorFill()
    var defaultCalloutFill = EditorFill(isEnabled: true)
    var defaultCornerRadius: CGFloat = 0
    var defaultShapeKind: EditorObject.Kind = .rectangle
    var defaultShapeStroke = EditorStroke()
    var defaultHighlightMode = EditorHighlightMode.rectangle
    var defaultHighlightOpacity: Double = 0.35
    var defaultHighlightColor = EditorColor(red: 1, green: 0.85, blue: 0)
    var defaultHighlightWidth: CGFloat = 28
    var defaultStepStyle = EditorStepStyle()
    var defaultStepColor = EditorColor()
    var defaultStepSize: CGFloat = 72
    /// Tool choice and drawing defaults belong to the editor shell; objects/history belong to the image.
    func inheritToolSettings(from previous: EditorModel) {
        defaultColor = previous.defaultColor; defaultRedactionColor = previous.defaultRedactionColor
        defaultArrowLineWidth = previous.defaultArrowLineWidth; defaultLineWidth = previous.defaultLineWidth
        defaultFontSize = previous.defaultFontSize; defaultTextStyle = previous.defaultTextStyle
        defaultPenWidth = previous.defaultPenWidth; defaultPenSmoothed = previous.defaultPenSmoothed
        defaultSpotlightStyle = previous.defaultSpotlightStyle; snapsToObjects = previous.snapsToObjects
        defaultMagnifierOffset = previous.defaultMagnifierOffset
        defaultMagnification = previous.defaultMagnification; defaultShapeDrawingStyle = previous.defaultShapeDrawingStyle
        defaultBlurRadius = previous.defaultBlurRadius; defaultBlurStyle = previous.defaultBlurStyle; defaultShapeFill = previous.defaultShapeFill
        defaultCalloutFill = previous.defaultCalloutFill; defaultCornerRadius = previous.defaultCornerRadius
        defaultShapeKind = previous.defaultShapeKind; defaultShapeStroke = previous.defaultShapeStroke
        defaultHighlightMode = previous.defaultHighlightMode; defaultHighlightOpacity = previous.defaultHighlightOpacity
        defaultHighlightColor = previous.defaultHighlightColor; defaultHighlightWidth = previous.defaultHighlightWidth
        defaultStepStyle = previous.defaultStepStyle; defaultStepColor = previous.defaultStepColor
        defaultStepSize = previous.defaultStepSize
        defaultArrowDrawingStyle = previous.defaultArrowDrawingStyle
        defaultEllipseDrawingStyle = previous.defaultEllipseDrawingStyle
        tool = previous.tool == .crop || (!hasProAccess() && ProFeature.required(for: previous.tool) != nil) ? .selection : previous.tool
    }
    /// Revocation affects future operations, never the stored objects or output.
    func proAccessDidChange() {
        endStyleEditing(); finishTextEditing()
        if ProFeature.required(for: tool) != nil { tool = .selection }
        if ProFeature.required(for: defaultShapeKind) != nil { defaultShapeKind = .rectangle }
        defaultArrowDrawingStyle = .precise; defaultEllipseDrawingStyle = .precise; defaultShapeDrawingStyle = .precise
        isRecognizingTextInPlace = false; isShowingTextRecognition = false; isShowingRedactionSuggestions = false
        preview = nil
    }
    var selectedObject: EditorObject? { editingTextObject ?? (selectedIDs.count == 1 ? history.objects.first { selectedIDs.contains($0.id) } : nil) }
    var drawingKind: EditorObject.Kind? { tool == .rectangle ? defaultShapeKind : EditorObject.Kind.from(tool) }
    var activeKind: EditorObject.Kind? { selectedIDs.count > 1 ? nil : (editingTextObject?.kind ?? selectedObject?.kind ?? drawingKind) }
    var activeLineWidth: CGFloat { selectedObject?.lineWidth ?? (activeKind == .arrow ? defaultArrowLineWidth : activeKind == .highlight ? defaultHighlightWidth : activeKind == .pen ? defaultPenWidth : defaultLineWidth) }
    var activeFill: EditorFill { selectedObject?.effectiveFill ?? (activeKind == .callout ? defaultCalloutFill : defaultShapeFill) }
    var defaultArrowDrawingStyle = EditorDrawingStyle.precise
    var defaultEllipseDrawingStyle = EditorDrawingStyle.precise
    var activeDrawingStyle: EditorDrawingStyle { selectedObject?.effectiveDrawingStyle ?? (activeKind == .arrow ? defaultArrowDrawingStyle : activeKind == .ellipse ? defaultEllipseDrawingStyle : defaultShapeDrawingStyle) }
    var activeStroke: EditorStroke { selectedObject?.effectiveStroke ?? defaultShapeStroke }
    var activeHighlightStyle: EditorHighlightStyle { selectedObject?.highlightStyle ?? EditorHighlightStyle(mode: defaultHighlightMode, opacity: defaultHighlightOpacity) }
    var activeStepStyle: EditorStepStyle { selectedObject?.stepStyle ?? defaultStepStyle }
    var nextStepIndex: Int? { EditorSteps.nextIndex(in: history.objects, numbering: defaultStepStyle.numbering) }
    var nextStepLabel: String { nextStepIndex.map { defaultStepStyle.numbering.label(for: $0) } ?? "–" }
    var activeStepSize: CGFloat {
        guard let object = selectedObject, object.kind == .step else { return defaultStepSize }
        return min(object.rect.width, object.rect.height)
    }
    func updatePenSmoothed(_ enabled: Bool) {
        guard requestFeature(.advancedEditing) else { return }
        defaultPenSmoothed = enabled
        updateInstructionObject { if $0.kind == .pen { $0.penStroke?.isSmoothed = enabled } }
    }
    func updateSpotlightStyle(_ style: EditorSpotlightStyle) {
        guard style.opacity.isFinite, (0...0.95).contains(style.opacity), requestFeature(.advancedEditing) else { return }
        defaultSpotlightStyle = style
        updateInstructionObject { if $0.kind == .spotlight { $0.spotlightStyle = style } }
    }
    func setHighlightMode(_ mode: EditorHighlightMode) {
        guard requestFeature(.advancedEditing) else { return }
        endStyleEditing(); finishTextEditing()
        defaultHighlightMode = mode; selection = nil; tool = .highlight; focusRequest += 1
    }
    func updateHighlightOpacity(_ opacity: Double) {
        guard requestFeature(.advancedEditing) else { return }
        guard opacity.isFinite else { return }
        defaultHighlightOpacity = min(1, max(0, opacity))
        updateInstructionObject { object in
            guard object.kind == .highlight else { return }
            object.highlightStyle?.opacity = defaultHighlightOpacity
        }
    }
    func updateStepStyle(_ style: EditorStepStyle) {
        guard requestFeature(.advancedEditing) else { return }
        guard (1...EditorSteps.maximumIndex).contains(style.index) else { return }
        defaultStepStyle = style
        updateInstructionObject { if $0.kind == .step { $0.stepStyle = style } }
    }
    func updateStepSize(_ size: CGFloat) {
        guard requestFeature(.advancedEditing) else { return }
        guard size.isFinite else { return }
        defaultStepSize = min(240, max(24, size))
        updateInstructionObject { object in
            guard object.kind == .step else { return }
            let centre = CGPoint(x: object.rect.midX, y: object.rect.midY)
            object.start = CGPoint(x: centre.x - defaultStepSize / 2, y: centre.y - defaultStepSize / 2)
            object.end = CGPoint(x: centre.x + defaultStepSize / 2, y: centre.y + defaultStepSize / 2)
        }
    }
    private func updateInstructionObject(_ update: (inout EditorObject) -> Void) {
        guard !isSwitchingImage, let selection, let index = history.objects.firstIndex(where: { $0.id == selection }) else { return }
        var next = history.objects; update(&next[index])
        if isEditingStyle {
            let old = history.objects; history.updateTransaction(next)
            if old != next { changed() }
        } else { commit(next) }
    }
    func placeStep(at point: CGPoint) {
        guard requestFeature(.advancedEditing) else { return }
        guard tool == .steps, cropDraft == nil, history.objects.count < 10_000 else { return }
        guard let index = nextStepIndex else { notice = String(localized: "Die Folge hat 10.000 Marken erreicht."); return }
        endStyleEditing(); finishTextEditing()
        let size = min(defaultStepSize, sourceRect.width, sourceRect.height)
        let origin = CGPoint(x: min(sourceRect.maxX - size, max(sourceRect.minX, point.x - size / 2)),
                             y: min(sourceRect.maxY - size, max(sourceRect.minY, point.y - size / 2)))
        var object = makeObject(kind: .step, start: origin, end: CGPoint(x: origin.x + size, y: origin.y + size))
        object.stepStyle?.index = index
        commit(history.objects + [object]); selection = object.id
    }
    func selectShape(_ kind: EditorObject.Kind, corner: CGFloat = 0, focusCanvas: Bool = true) {
        guard kind.isShape else { return }
        if let feature = ProFeature.required(for: kind), !requestFeature(feature) { return }
        endStyleEditing()
        defaultShapeKind = kind
        defaultCornerRadius = corner
        if let selected = selectedObject, selected.kind.isShape {
            var next = history.objects
            if let index = next.firstIndex(where: { $0.id == selected.id }) {
                next[index].kind = kind
                next[index].cornerRadius = kind == .rectangle ? corner : nil
                commit(next)
                if tool == .rectangle || tool == .ellipse { tool = kind == .ellipse ? .ellipse : .rectangle }
            }
        } else { tool = kind == .ellipse ? .ellipse : .rectangle }
        if focusCanvas { focusRequest += 1 }
    }
    /// Sliders update the actual document live, including autosave, and finish as one undo step.
    /// During inline typing, style changes belong to the existing text transaction.
    func beginStyleEditing() {
        guard !isSwitchingImage, !isEditingStyle, editingTextObject == nil, selection != nil else { return }
        history.beginTransaction(); isEditingStyle = true
    }
    func endStyleEditing() {
        guard isEditingStyle else { return }
        if let area = imageRotationDraftArea, let canvas = EditorCanvasExtent.expanded(fullCanvasRect, including: area) {
            do {
                let size = try EditorResize.preservingScale(from: document.outputRect, to: area, output: history.resizedSize)
                history.updateTransaction(history.objects, canvasRect: canvas == originalRect ? nil : canvas,
                    crop: history.crop == nil || area == canvas ? nil : area, resizedSize: size)
                changed()
            } catch { self.error = error.localizedDescription }
        }
        imageRotationDraftArea = nil
        history.endTransaction(); isEditingStyle = false
    }
    func updateSelectedImageRotation(_ angle: Double) {
        guard !isSwitchingImage, angle.isFinite, (-180...180).contains(angle),
              let object = selectedObject, object.kind == .image, requestFeature(.insertedImages) else { return }
        var next = history.objects
        guard let index = next.firstIndex(where: { $0.id == object.id }) else { return }
        next[index].imageRotationDegrees = angle == 0 ? nil : angle
        preserveViewportScale(from: imageSize)
        guard next != history.objects, let area = expandedCanvasArea(for: next),
              EditorCanvasExtent.expanded(fullCanvasRect, including: area) != nil else { return }
        if isEditingStyle {
            imageRotationDraftArea = area; history.updateTransaction(next); changed()
        } else { commit(next, expandingCanvas: true) }
    }
    func updateStyle(color: EditorColor? = nil, width: CGFloat? = nil, font: CGFloat? = nil, blur: CGFloat? = nil, blurStyle: EditorBlurStyle? = nil,
                     fill: EditorFill? = nil, corner: CGFloat? = nil, stroke: EditorStroke? = nil, textStyle: EditorTextStyle? = nil, drawingStyle: EditorDrawingStyle? = nil) {
        guard !isSwitchingImage else { return }
        if let kind = activeKind, let feature = ProFeature.required(for: kind), !requestFeature(feature) { return }
        if let drawingStyle, drawingStyle != .precise, !requestFeature(.advancedEditing) { return }
        if let drawingStyle {
            if activeKind == .arrow { defaultArrowDrawingStyle = drawingStyle }
            if activeKind == .ellipse { defaultEllipseDrawingStyle = drawingStyle }
            else if activeKind?.isShape == true { defaultShapeDrawingStyle = drawingStyle }
        }
        if let textStyle { defaultTextStyle = textStyle }
        if let color {
            switch activeKind {
            case .redact: defaultRedactionColor = color
            case .highlight: defaultHighlightColor = color
            case .step: defaultStepColor = color
            default: defaultColor = color
            }
        }
        if let width {
            if activeKind == .arrow { defaultArrowLineWidth = width }
            else if activeKind == .highlight { defaultHighlightWidth = width }
            else if activeKind == .pen { defaultPenWidth = width }
            else { defaultLineWidth = width }
        }
        if let font { defaultFontSize = font }
        if let blur { defaultBlurRadius = blur }
        if let blurStyle, activeKind == .blur { defaultBlurStyle = blurStyle }
        if let fill {
            if activeKind == .callout { defaultCalloutFill = fill } else { defaultShapeFill = fill }
        }
        if let corner { defaultCornerRadius = corner }
        if let stroke { defaultShapeStroke = stroke }
        if var object = editingTextObject {
            if let textStyle { object.textStyle = textStyle }
            if let color { object.color = color }
            if let width { object.lineWidth = width }
            if let font { object.fontSize = font }
            if let fill { object.fill = fill }
            editingTextObject = object
            updateText(object.text)
            return
        }
        guard let selection else { return }
        var next = history.objects
        guard let index = next.firstIndex(where: { $0.id == selection }) else { return }
        if let textStyle { next[index].textStyle = textStyle }
        if let color { next[index].color = color }
        if let width { next[index].lineWidth = width }
        if let font { next[index].fontSize = font }
        if let blur { next[index].blurRadius = blur }
        if let blurStyle, next[index].kind == .blur { next[index].blurStyle = blurStyle == .gaussian ? nil : blurStyle }
        if let fill { next[index].fill = fill }
        if let corner { next[index].cornerRadius = corner }
        if let stroke { next[index].stroke = stroke }
        if let drawingStyle, next[index].supportsHandDrawn { next[index].drawingStyle = drawingStyle }
        if isEditingStyle {
            preview = nil
            let old = history.objects
            history.updateTransaction(next)
            if old != next { changed() }
        } else { commit(next) }
    }
    /// Image frames are local to the selected image and never change drawing defaults.
    func updateSelectedImageFrame(radius: CGFloat, border: EditorImageBorder?) {
        guard !isSwitchingImage, radius.isFinite, (0...1000).contains(radius), border?.isValid != false,
              let selected = selectedObject, selected.kind == .image,
              ProFeature.required(for: .image).map({ requestFeature($0) }) != false else { return }
        var next = history.objects
        guard let index = next.firstIndex(where: { $0.id == selected.id }) else { return }
        next[index].cornerRadius = radius == 0 ? nil : radius
        next[index].stroke = border.map { _ in EditorStroke(isEnabled: true) }
        if let border { next[index].lineWidth = border.width; next[index].color = border.color }
        if isEditingStyle {
            guard next != history.objects else { return }
            history.updateTransaction(next); changed()
        } else { commit(next) }
    }
    func makeObject(kind: EditorObject.Kind, start: CGPoint, end: CGPoint = .zero) -> EditorObject {
        var object = EditorObject(kind: kind, start: start, end: end, fontSize: defaultFontSize,
                                  lineWidth: kind == .arrow ? defaultArrowLineWidth : defaultLineWidth)
        object.color = kind == .redact ? defaultRedactionColor : defaultColor; object.blurRadius = defaultBlurRadius
        if kind == .blur, defaultBlurStyle != .gaussian { object.blurStyle = defaultBlurStyle }
        if kind.isShape { object.fill = defaultShapeFill; object.stroke = defaultShapeStroke; object.drawingStyle = defaultShapeDrawingStyle }
        if kind == .arrow { object.drawingStyle = defaultArrowDrawingStyle }
        if kind == .ellipse { object.drawingStyle = defaultEllipseDrawingStyle }
        if kind == .rectangle { object.cornerRadius = defaultCornerRadius }
        if kind == .text || kind == .callout { object.textStyle = defaultTextStyle }
        if kind == .callout { object.fill = defaultCalloutFill }
        if kind == .highlight {
            object.color = defaultHighlightColor; object.lineWidth = defaultHighlightWidth
            object.highlightStyle = EditorHighlightStyle(mode: defaultHighlightMode, opacity: defaultHighlightOpacity,
                                                         points: defaultHighlightMode == .freehand ? [start] : [])
        }
        if kind == .pen { object.lineWidth = defaultPenWidth; object.penStroke = EditorPenStroke(points: [start], isSmoothed: defaultPenSmoothed) }
        if kind == .spotlight { object.spotlightStyle = defaultSpotlightStyle }
        if kind == .magnifier { object.magnification = defaultMagnification }
        if kind == .step { object.color = defaultStepColor; object.stepStyle = defaultStepStyle }
        return object
    }

    var currentSavedStyle: EditorSavedStyle? {
        guard cropDraft == nil, !isCanvasGestureActive, !isShowingImageSize, let kind = activeKind, kind != .image else { return nil }
        let candidate = selectedObject ?? makeObject(kind: kind, start: .zero,
            end: CGPoint(x: defaultStepSize, y: defaultStepSize))
        let style = EditorSavedStyle(object: candidate)
        return style.isValid ? style : nil
    }
    func applySavedStyle(_ style: EditorSavedStyle) {
        guard requestFeature(.savedStyles) else { return }
        guard !isSwitchingImage, let current = currentSavedStyle, current.family == style.family, style.isValid else { return }
        endStyleEditing(); finishTextEditing()
        if let object = selectedObject, let styled = style.applying(to: object),
           let index = history.objects.firstIndex(where: { $0.id == object.id }) {
            var next = history.objects; next[index] = styled; commit(next)
        }
        // Update only the appearance fields supported by this tool family.
        switch style.family {
        case .pen: defaultColor = style.color; defaultPenWidth = style.lineWidth; defaultPenSmoothed = style.penSmoothed ?? true
        case .spotlight: defaultSpotlightStyle = style.spotlight ?? .init()
        case .magnifier: defaultColor = style.color; defaultLineWidth = style.lineWidth; defaultMagnification = style.magnification ?? 2
        case .arrow: defaultColor = style.color; defaultArrowLineWidth = style.lineWidth
            defaultArrowDrawingStyle = style.drawingStyle ?? .precise
        case .shape:
            defaultColor = style.color; defaultLineWidth = style.lineWidth
            defaultShapeFill = style.fill; defaultShapeStroke = style.stroke
            defaultEllipseDrawingStyle = style.drawingStyle ?? .precise
            defaultShapeDrawingStyle = style.drawingStyle ?? .precise
            if let corner = style.cornerRadius { defaultCornerRadius = corner }
        case .text:
            defaultColor = style.color; defaultFontSize = style.fontSize; defaultTextStyle = style.textStyle
        case .callout:
            defaultColor = style.color; defaultLineWidth = style.lineWidth
            defaultFontSize = style.fontSize; defaultTextStyle = style.textStyle; defaultCalloutFill = style.fill
        case .blur: defaultBlurRadius = style.blurRadius; defaultBlurStyle = style.blurStyle ?? .gaussian
        case .redact: defaultRedactionColor = style.color
        case .highlight:
            defaultHighlightColor = style.color; defaultHighlightWidth = style.lineWidth; defaultHighlightOpacity = style.highlightOpacity
        case .step:
            defaultStepColor = style.color; defaultStepSize = style.stepSize
            defaultStepStyle.shape = style.stepShape; defaultStepStyle.textColor = style.stepTextColor
        }
        focusRequest += 1
    }

    init(image: CGImage, document: ProjectDocument, generation: Int, store: ProjectStore,
         automaticallyFitsImage: Bool = true,
         pngDirectory: @escaping @MainActor () -> URL? = { nil },
         writePNG: @escaping PNGWriter = EditorModel.writePNGData,
         openPNGApplication: @escaping PNGApplicationOpener = EditorModel.openPNGFile,
         externalOpenRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-OpenWith", isDirectory: true),
         onSaved: @escaping @MainActor () -> Void) {
        var restored = document; restored.revision = generation
        self.image = image; self.document = restored
        self.savedRevision = generation; self.store = store; self.writePNG = writePNG; self.onSaved = onSaved
        self.pngDirectory = pngDirectory
        self.openPNGApplication = openPNGApplication; self.externalOpenRoot = externalOpenRoot
        self.history = EditorHistory(objects: document.objects, crop: document.crop, resizedSize: document.resizedSize, canvasRect: document.canvasRect, transform: document.transform, presentation: document.presentation ?? .init())
        self.isEditingPresentation = document.presentation?.isIdentity == false
        self.automaticallyFitsImage = automaticallyFitsImage
        self.viewport = EditorViewport(fitsImage: automaticallyFitsImage)
    }
    /// Geometry previews use this without changing the projection or document until mouse-up.
    func expandedCanvasArea(for objects: [EditorObject]) -> CGRect? {
        let previous = Dictionary(uniqueKeysWithValues: history.objects.map { ($0.id, $0) })
        var area = document.outputRect
        for object in objects where previous[object.id] != object {
            let ink = EditorRenderer.paintedBounds(object)
            if ink.isNull { continue }
            guard let expanded = EditorCanvasExtent.expanded(area, including: ink) else { return nil }
            area = expanded
        }
        return area
    }
    var previewSourceRect: CGRect {
        if let imageRotationDraftArea { return imageRotationDraftArea }
        guard cropDraft == nil, let preview else { return sourceRect }
        return expandedCanvasArea(for: preview) ?? sourceRect
    }
    func commit(_ objects: [EditorObject], expandingCanvas: Bool = false) {
        guard !isSwitchingImage else { return }
        // Cover insertion, duplication and canvas commits as well as toolbar actions.
        // Existing paid objects can still be moved, reordered, renamed or removed.
        let previous = Dictionary(uniqueKeysWithValues: history.objects.map { ($0.id, $0) })
        for object in objects {
            if let feature = ProFeature.required(for: object),
               previous[object.id].map({ ProFeature.required(for: $0) != feature }) ?? true,
               !requestFeature(feature) { preview = nil; return }
        }
        endStyleEditing()
        preview = nil
        let old = history.objects
        guard old != objects else { return }
        if expandingCanvas {
            guard let area = expandedCanvasArea(for: objects),
                  let canvas = EditorCanvasExtent.expanded(fullCanvasRect, including: area) else {
                notice = String(localized: "Die Zeichenfläche kann nicht weiter wachsen (max. 32.768 Pixel je Kante, 100 Millionen Pixel).")
                return
            }
            let output: PixelSize?
            do { output = try EditorResize.preservingScale(from: document.outputRect, to: area, output: history.resizedSize) }
            catch { notice = String(localized: "Die Zeichenfläche kann nicht weiter wachsen (max. 32.768 Pixel je Kante, 100 Millionen Pixel)."); return }
            let crop = history.crop == nil || area == canvas ? nil : area
            history.commit(objects, canvasRect: canvas == originalRect ? nil : canvas, crop: crop, resizedSize: output)
        } else { history.commit(objects) }
        notice = nil; changed()
    }
    var canTransformImage: Bool { hasExportableImage && !isExporting && !isShowingTextRecognition && !isShowingRedactionSuggestions }
    func beginInlineTextRecognition() {
        guard canSwitchEditingTool, requestFeature(.textRecognition), prepareForEditingTool() else { return }
        endPresentationEditing(); endStyleEditing(); finishTextEditing()
        preserveViewportScale(from: viewportImageSize)
        isEditingPresentation = false; selection = nil; isRecognizingTextInPlace.toggle()
    }
    func togglePresentationTool() {
        guard canSwitchEditingTool, requestFeature(.presentation), prepareForEditingTool() else { return }
        endStyleEditing(); finishTextEditing(); isEditingPresentation.toggle()
    }
    func beginFreeRotation() {
        guard prepareForEditingTool() else { return }
        endStyleEditing(); finishTextEditing(); isEditingPresentation = true
    }
    func selectSourceImage() {
        guard canTransformImage, tool == .selection else { return }
        endStyleEditing(); finishTextEditing(); selection = nil; isSourceImageSelected = true
    }
    func beginPresentationEditing() {
        guard canTransformImage, !isAdjustingPresentation else { return }
        endStyleEditing(); finishTextEditing(); history.beginTransaction(); isAdjustingPresentation = true
    }
    func endPresentationEditing() {
        guard isAdjustingPresentation else { return }
        history.endTransaction(); isAdjustingPresentation = false
    }
    func updatePresentation(_ next: EditorPresentation) {
        guard canTransformImage, next.isLayoutValid, next.geometry(for: document.contentPixelSize) != nil,
              next != history.presentation else { return }
        var oldStyle = history.presentation, newStyle = next
        oldStyle.rotationDegrees = 0; newStyle.rotationDegrees = 0
        guard oldStyle == newStyle || requestFeature(.presentation) else { return }
        if !isEditingPresentation, history.presentation.requiresCanvasLayout != next.requiresCanvasLayout {
            preserveViewportScale(from: viewportImageSize)
        }
        if isEditingPresentation, viewport.zoom == nil,
           next.previewReferenceSize(for: document.contentPixelSize) != history.presentation.previewReferenceSize(for: document.contentPixelSize) {
            preserveViewportScale(from: history.presentation.previewReferenceSize(for: document.contentPixelSize))
        }
        if isAdjustingPresentation { history.updatePresentationTransaction(next) }
        else { endStyleEditing(); finishTextEditing(); history.commitPresentation(next) }
        changed()
    }
    func transformImage(_ transform: EditorImageTransform) {
        guard prepareForEditingTool(), canTransformImage else { return }
        endPresentationEditing(); endStyleEditing(); finishTextEditing(); preview = nil; selection = nil
        guard transform != history.transform else { return }
        history.commitTransform(transform); resetImageView(); changed(); focusRequest += 1
    }
    func undo() {
        guard !isSwitchingImage, !isShowingImageSize, !isCanvasGestureActive else { return }
        if cropDraft != nil { cancelCrop(); return }
        endPresentationEditing()
        endStyleEditing()
        finishTextEditing()
        preview = nil; let old = history.objects, crop = history.crop, resizedSize = history.resizedSize, canvasRect = history.canvasRect, transform = history.transform, presentation = history.presentation; history.undo(); selection = nil; focusRequest += 1
        if crop != history.crop || resizedSize != history.resizedSize || canvasRect != history.canvasRect || transform != history.transform { resetImageView() }
        if old != history.objects || crop != history.crop || resizedSize != history.resizedSize || canvasRect != history.canvasRect || transform != history.transform || presentation != history.presentation { changed() }
    }
    func redo() {
        guard !isSwitchingImage, !isShowingImageSize, !isCanvasGestureActive else { return }
        if cropDraft != nil { cancelCrop(); return }
        endPresentationEditing()
        endStyleEditing()
        finishTextEditing()
        preview = nil; let old = history.objects, crop = history.crop, resizedSize = history.resizedSize, canvasRect = history.canvasRect, transform = history.transform, presentation = history.presentation; history.redo(); selection = nil; focusRequest += 1
        if crop != history.crop || resizedSize != history.resizedSize || canvasRect != history.canvasRect || transform != history.transform { resetImageView() }
        if old != history.objects || crop != history.crop || resizedSize != history.resizedSize || canvasRect != history.canvasRect || transform != history.transform || presentation != history.presentation { changed() }
    }
    private func changed() {
        document.presentation = history.presentation.isIdentity ? nil : history.presentation; document.objects = history.objects; document.crop = history.crop; document.resizedSize = history.resizedSize; document.canvasRect = history.canvasRect; document.imageTransform = history.transform == .identity ? nil : history.transform; document.modifiedAt = .now; document.revision += 1
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            _ = await self?.flush()
        }
    }
    /// One write at a time. Edits made during a write are committed in a following revision.
    @discardableResult func flush() async -> Bool {
        debounceTask?.cancel(); debounceTask = nil
        while isDirty {
            if let running = saveTask {
                if !(await running.value) { return false }
                continue
            }
            let snapshot = document, image = image, baseRevision = savedRevision
            isSaving = true
            let task = Task { [self] in
                defer { isSaving = false; saveTask = nil }
                do {
                    // Thumbnail is a cache. A failed thumbnail never prevents saving annotations.
                    let thumbnail = await Task.detached(priority: .utility) {
                        try? EditorRenderer.thumbnail(image: image, objects: snapshot.objects, crop: snapshot.crop, resizedSize: snapshot.resizedSize, canvasRect: snapshot.canvasRect, transform: snapshot.transform, presentation: snapshot.presentation)
                    }.value
                    try await store.save(snapshot, expectedGeneration: baseRevision, thumbnail: thumbnail)
                    savedRevision = snapshot.revision; saveError = nil
                    onLibraryItemSaved?(ProjectLibraryItem(document: snapshot, thumbnail: thumbnail))
                    onSaved()
                    return true
                } catch { saveError = error.localizedDescription; return false }
            }
            saveTask = task
            if !(await task.value) { return false }
        }
        return true
    }
    /// Preserve local edits if another process has saved a newer generation of this project.
    @discardableResult func saveCopy() async -> Bool {
        guard !isSwitchingImage, !isSaving else { return false }
        debounceTask?.cancel(); debounceTask = nil
        let snapshot = document, image = image
        let copy = ProjectDocument(title: String(name.prefix(1015)) + String(localized: " – Kopie"), pixelSize: document.pixelSize, objects: history.objects, crop: history.crop, resizedSize: history.resizedSize, isFavorite: document.isFavorite,
                                   tags: document.tags, collections: document.collections, canvasRect: history.canvasRect, transform: history.transform, presentation: history.presentation)
        isSaving = true
        let task = Task { [self] in
            defer { isSaving = false; saveTask = nil }
            do {
                let (original, thumbnail) = try await Task.detached(priority: .utility) {
                    (try EditorRenderer.png(image: image, objects: []), try? EditorRenderer.thumbnail(image: image, objects: copy.objects, crop: copy.crop, resizedSize: copy.resizedSize, canvasRect: copy.canvasRect, transform: copy.transform, presentation: copy.presentation))
                }.value
                try await store.create(copy, original: original, thumbnail: thumbnail)
                let changedDuringSave = document.revision != snapshot.revision
                document = ProjectDocument(id: copy.id, title: document.title != snapshot.title ? document.title : copy.title, pixelSize: copy.pixelSize, objects: history.objects,
                                           createdAt: copy.createdAt, modifiedAt: changedDuringSave ? document.modifiedAt : copy.modifiedAt,
                                           revision: changedDuringSave ? 1 : 0, crop: history.crop, resizedSize: history.resizedSize, isFavorite: document.isFavorite,
                                           tags: document.tags, collections: document.collections, canvasRect: history.canvasRect, transform: history.transform, presentation: history.presentation)
                savedRevision = 0; saveError = nil
                onLibraryItemSaved?(ProjectLibraryItem(document: copy, thumbnail: thumbnail))
                onSaved()
                return true
            } catch { saveError = error.localizedDescription; return false }
        }
        saveTask = task
        guard await task.value else { return false }
        return await flush()
    }
    var canActOnSelection: Bool {
        cropDraft == nil && !isShowingImageSize && !isCanvasGestureActive &&
        selection.map { id in history.objects.contains { $0.id == id } } == true
    }
    var canNudgeSelection: Bool {
        canActOnSelection && !isSwitchingImage && !isShowingTextRecognition &&
        editingTextObject == nil && preview == nil
    }
    /// Output pixels, independent of zoom, Retina scale and nonuniform image resize.
    @discardableResult func nudgeSelection(by pixels: CGSize) -> Bool {
        guard canNudgeSelection, pixels.width.isFinite, pixels.height.isFinite,
              pixels != .zero else { return false }
        let output = document.untransformedOutputPixelSize, area = document.outputRect
        let pixels = history.transform.sourceVector(fromDisplayed: pixels)
        let delta = CGSize(width: pixels.width * area.width / CGFloat(output.width),
                           height: pixels.height * area.height / CGFloat(output.height))
        let revision = document.revision
        commit(history.objects.map { selectedIDs.contains($0.id) ? $0.translated(by: delta) : $0 }, expandingCanvas: true)
        return document.revision != revision
    }
    var canDuplicateSelection: Bool {
        canActOnSelection && history.objects.count + selectedIDs.count <= 10_000
        && history.objects.reduce(0, { $0 + ($1.imageAsset?.png.count ?? 0) * (selectedIDs.contains($1.id) ? 2 : 1) }) <= 16_000_000
    }
    func canMoveSelection(_ direction: EditorLayerMove) -> Bool {
        guard canActOnSelection, selectedIDs.count == 1, let selection else { return false }
        return EditorLayers.canMove(selection, in: history.objects, direction: direction)
    }
    func duplicateSelection() {
        guard canDuplicateSelection else { return }
        endStyleEditing(); finishTextEditing()
        if selectedIDs.count > 1 {
            var copies: [EditorObject] = [], groups: [UUID: UUID] = [:]
            for object in history.objects where selectedIDs.contains(object.id) {
                var copy = object.duplicated(by: CGSize(width: 16, height: 16))
                if let group = object.groupID {
                    let mapped = groups[group] ?? UUID(); groups[group] = mapped; copy.groupID = mapped
                }
                if let step = copy.stepStyle {
                    guard let next = EditorSteps.nextIndex(in: history.objects + copies, numbering: step.numbering) else { return }
                    copy.stepStyle?.index = next
                }
                copies.append(copy)
            }
            commit(history.objects + copies); tool = .selection
            selectedIDs = Set(copies.map(\.id)); focusRequest += 1; return
        }
        guard let object = selectedObject else { return }
        let preferred = CGSize(width: 16 * document.outputRect.width / CGFloat(document.untransformedOutputPixelSize.width),
                               height: 16 * document.outputRect.height / CGFloat(document.untransformedOutputPixelSize.height))
        let offset = EditorLayers.duplicateOffset(bounds: EditorRenderer.bounds(object), visible: document.outputRect, preferred: preferred)
        var copy = object.duplicated(by: offset)
        if copy.groupID != nil { copy.groupID = UUID() }
        if let step = copy.stepStyle {
            guard let next = EditorSteps.nextIndex(in: history.objects, numbering: step.numbering) else { return }
            copy.stepStyle?.index = next
        }
        commit(history.objects + [copy])
        tool = .selection; selection = copy.id; focusRequest += 1
    }
    func moveSelection(_ direction: EditorLayerMove) {
        guard canMoveSelection(direction) else { return }
        endStyleEditing(); finishTextEditing()
        guard let selection else { return }
        commit(EditorLayers.moving(selection, in: history.objects, direction: direction))
        tool = .selection; focusRequest += 1
    }
    func removeSelection() {
        guard !isSwitchingImage, !isCanvasGestureActive, cropDraft == nil else { return }
        finishTextEditing()
        guard !selectedIDs.isEmpty else { return }
        commit(history.objects.filter { !selectedIDs.contains($0.id) }); self.selection = nil
    }
    func editText(at position: CGPoint, object: EditorObject? = nil, width: CGFloat? = nil) {
        guard !isSwitchingImage else { return }
        let kind = object?.kind ?? (tool == .callout ? .callout : .text)
        if let feature = ProFeature.required(for: kind), !requestFeature(feature) { return }
        endStyleEditing()
        finishTextEditing()
        preview = nil
        textBase = history.objects
        history.beginTransaction()
        editingTextObject = object ?? makeObject(kind: tool == .callout ? .callout : .text, start: position)
        if object == nil {
            editingTextObject?.textWidth = width
            if kind == .callout {
                editingTextObject?.calloutTip = position
                editingTextObject?.start = CGPoint(x: position.x + 36, y: position.y + 34)
                editingTextObject?.textWidth = width ?? 156
                editingTextObject?.textHeight = 44
                updateText("")
            }
        }
        selection = editingTextObject?.id
    }
    func updateText(_ text: String) {
        guard !isSwitchingImage, var object = editingTextObject else { return }
        object.text = text; editingTextObject = object
        var next = textBase
        if let index = next.firstIndex(where: { $0.id == object.id }) { next.remove(at: index) }
        if object.kind == .callout || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let index = textBase.firstIndex(where: { $0.id == object.id }) { next.insert(object, at: index) }
            else { next.append(object) }
        }
        let old = history.objects
        history.updateTransaction(next)
        if old != next { changed() }
    }
    func positionText(at position: CGPoint, width: CGFloat) {
        guard var object = editingTextObject else { return }
        object.start = position; object.textWidth = width
        editingTextObject = object
        updateText(object.text)
    }
    func positionCallout(in rect: CGRect) {
        guard var object = editingTextObject, object.kind == .callout else { return }
        object.start = CGPoint(x: rect.minX + 12, y: rect.minY + 10)
        object.textWidth = max(24, rect.width - 24); object.textHeight = max(1, rect.height - 20)
        editingTextObject = object; updateText(object.text)
    }
    func updateMagnifierOffset(_ offset: Bool) {
        guard requestFeature(.advancedEditing) else { return }
        endStyleEditing()
        defaultMagnifierOffset = offset
        guard !isSwitchingImage, let selection else { return }
        let next = history.objects.map { current in
            guard current.id == selection, current.kind == .magnifier,
                  (current.magnifierSource != nil) != offset else { return current }
            var object = current
            if offset {
                let source = CGPoint(x: object.rect.midX, y: object.rect.midY)
                object = object.translated(by: CGSize(width: object.rect.width, height: 0))
                object.magnifierSource = source
            } else {
                let source = object.magnifierSource!
                object = object.translated(by: CGSize(width: source.x - object.rect.midX, height: source.y - object.rect.midY))
                object.magnifierSource = nil
            }
            return object
        }
        commit(next, expandingCanvas: true)
    }
    func updateMagnification(_ value: CGFloat) {
        guard value.isFinite, (1.5...5).contains(value), requestFeature(.advancedEditing) else { return }
        defaultMagnification = value
        updateInstructionObject { if $0.kind == .magnifier { $0.magnification = value } }
    }
    var activeArrowCurvature: Double {
        guard let object = selectedObject, object.kind == .arrow else { return 0 }
        let dx = object.end.x - object.start.x, dy = object.end.y - object.start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        let bend = EditorArrow.bendHandle(for: object)
        return Double(((bend.x - (object.start.x + object.end.x) / 2) * -dy
            + (bend.y - (object.start.y + object.end.y) / 2) * dx) / lengthSquared * 100)
    }
    func updateArrowCurvature(_ value: Double) {
        guard value.isFinite, let object = selectedObject, object.kind == .arrow else { return }
        let dx = object.end.x - object.start.x, dy = object.end.y - object.start.y
        updateInstructionObject {
            $0.arrowBend = CGPoint(x: (object.start.x + object.end.x) / 2 - dy * value / 100,
                                  y: (object.start.y + object.end.y) / 2 + dx * value / 100)
        }
    }
    func straightenArrow() { updateArrowCurvature(0) }
    func finishTextEditing(cancel: Bool = false) {
        guard editingTextObject != nil else { return }
        let old = history.objects
        if cancel { history.cancelTransaction() } else { history.endTransaction() }
        editingTextObject = nil; textBase = []
        if old != history.objects { changed() }
        if !history.objects.contains(where: { $0.id == selection }) { selection = nil }
        focusRequest += 1
    }
    func exportPNG() {
        guard hasExportableImage, !isExporting, let window = NSApp.keyWindow else { return }
        endStyleEditing(); finishTextEditing()
        let panel = makePNGExportPanel()
        pngExportPanel = panel; isExportingPNG = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.pngExportPanel === panel else { return }
            self.pngExportPanel = nil; self.isExportingPNG = false
            guard response == .OK, let url = panel.url else { return }
            self.exportPNG(to: url)
        }
    }
    func makePNGExportPanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + ".png"
        panel.directoryURL = pngDirectory()
        panel.canCreateDirectories = true
        return panel
    }
    /// Workspace calls this only after flushing and verifying the copied revision.
    func useProjectStore(_ replacement: ProjectStore) { store = replacement }
    /// The dialog and direct callers share this guarded, owned file operation.
    @discardableResult func exportPNG(to url: URL) -> Bool {
        guard hasExportableImage, !isExporting else { return false }
        endStyleEditing(); finishTextEditing()
        isExportingPNG = true; notice = nil
        let image = image, objects = history.objects, crop = history.crop, resizedSize = history.resizedSize, canvasRect = history.canvasRect, transform = history.transform, presentation = history.presentation
        let task = Task { [self] in
            defer { isExportingPNG = false; pngExportTask = nil }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try EditorRenderer.png(image: image, objects: objects, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation)
                }.value
                try await writePNG(data, url)
                notice = String(localized: "PNG gespeichert")
                return true
            } catch {
                hasUnacknowledgedOutputError = true
                self.error = String(localized: "Das PNG konnte nicht gespeichert werden: \(error.localizedDescription)")
                return false
            }
        }
        pngExportTask = task
        return true
    }
    /// Generic image output shares the owned export task, including Quit/project-switch waiting.
    func exportPreparedOutput(to url: URL, produce: @escaping @Sendable () async throws -> Data) async -> Bool {
        guard hasExportableImage, !isExporting else { return false }
        isExportingPNG = true
        let task = Task { [self] in
            defer { isExportingPNG = false; pngExportTask = nil }
            do {
                let data = try await produce(); try await writePNG(data, url)
                notice = String(localized: "Bild gespeichert"); return true
            } catch {
                hasUnacknowledgedOutputError = true; self.error = error.localizedDescription; return false
            }
        }
        pngExportTask = task
        return await task.value
    }
    nonisolated static func writePNGData(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try data.write(to: url, options: .atomic)
        }.value
    }
    func choosePNGApplication() {
        guard hasExportableImage, !isExporting, let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Bild öffnen mit"); panel.prompt = String(localized: "Öffnen")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        applicationPanel = panel; isOpeningExternally = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.applicationPanel === panel else { return }
            self.applicationPanel = nil; self.isOpeningExternally = false
            guard response == .OK, let app = panel.url else { return }
            self.openPNG(with: app)
        }
    }
    @discardableResult func openPNG(with application: URL) -> Bool {
        guard hasExportableImage, !isExporting, application.isFileURL else { return false }
        endStyleEditing(); finishTextEditing()
        guard let item = pngShareItem else { return false }
        isOpeningExternally = true; notice = nil
        externalOpenTask = Task { [self] in
            defer { isOpeningExternally = false; externalOpenTask = nil }
            var temporaryFile: URL?
            do {
                let file = try await item.writeTemporaryPNG(in: externalOpenRoot)
                temporaryFile = file
                try await openPNGApplication(file, application)
                notice = String(localized: "PNG in anderer App geöffnet")
                return true
            } catch {
                if let temporaryFile {
                    _ = await Task.detached { try? FileManager.default.removeItem(at: temporaryFile.deletingLastPathComponent()) }.value
                }
                hasUnacknowledgedOutputError = true
                self.error = String(localized: "Das Bild konnte nicht in der gewählten App geöffnet werden: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }
    static func openPNGFile(_ file: URL, with application: URL) async throws {
        let access = application.startAccessingSecurityScopedResource()
        defer { if access { application.stopAccessingSecurityScopedResource() } }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true; configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.open([file], withApplicationAt: application, configuration: configuration)
    }
    /// Used before quitting or replacing the editor so an export cannot lose its owner.
    @discardableResult func finishPendingWork() async -> Bool {
        isFinishingPendingWork = true
        defer { isFinishingPendingWork = false }
        if let panel = pngExportPanel {
            // A destination has not been confirmed. Cancel the sheet, not a started write.
            pngExportPanel = nil; isExportingPNG = false
            panel.cancel(nil)
        }
        if let panel = applicationPanel {
            applicationPanel = nil; isOpeningExternally = false
            panel.cancel(nil)
        }
        let exported = await pngExportTask?.value ?? true
        let opened = await externalOpenTask?.value ?? true
        endPresentationEditing(); endStyleEditing(); finishTextEditing()
        let saved = await flush()
        // A failed export may already have been awaited by a project switch when Quit arrives.
        // Keep the app open until the error alert has been acknowledged in that case as well.
        return exported && opened && !hasUnacknowledgedOutputError && saved
    }
    func copyPNG(to pasteboard: NSPasteboard = .general, animateFeedback: Bool = false) {
        guard hasExportableImage, !isExporting else { return }
        endStyleEditing()
        copyFeedbackTask?.cancel()
        animateCopyFeedback = animateFeedback
        copyState = .copying
        let image = image, objects = history.objects, crop = history.crop, resizedSize = history.resizedSize, canvasRect = history.canvasRect, transform = history.transform, presentation = history.presentation
        Task { [self] in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try EditorRenderer.png(image: image, objects: objects, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation)
                }.value
                pasteboard.clearContents()
                guard pasteboard.setData(data, forType: .png) else {
                    copyState = .idle; error = String(localized: "Das Bild konnte nicht kopiert werden."); return
                }
                copyState = .copied
                copyFeedbackTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(1600)) }
                    catch { return }
                    self?.copyState = .idle
                }
            } catch { copyState = .idle; self.error = error.localizedDescription }
        }
    }
}

/// Only flattened PNG bytes cross the share boundary; macOS owns transfer files and their lifetime.
struct EditorPNGShare: Transferable, Sendable {
    let image: CGImage
    let objects: [EditorObject]
    let crop: CGRect?
    let resizedSize: PixelSize?
    let title: String
    var canvasRect: CGRect? = nil
    var transform: EditorImageTransform = .identity
    var presentation: EditorPresentation? = nil

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try EditorRenderer.png(image: item.image, objects: item.objects, crop: item.crop, resizedSize: item.resizedSize, canvasRect: item.canvasRect, transform: item.transform, presentation: item.presentation)
            }.value
        }
        .suggestedFileName { $0.fileName }
    }

    var fileName: String {
        var base = URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
            .components(separatedBy: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while base.utf8.count > 180 { base.removeLast() }
        if base.isEmpty || base == "." || base == ".." { base = String(localized: "Screenshot") }
        return base + ".png"
    }
    /// Keep successful copies available for apps that reopen or save their source later.
    /// These live in the sandbox's temporary directory and are reclaimed by macOS.
    func writeTemporaryPNG(in root: URL) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) {
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try Task.checkCancellation()
                let data = try EditorRenderer.png(image: image, objects: objects, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation)
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(fileName)
                try data.write(to: file, options: .atomic)
                try Task.checkCancellation()
                return file
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        return try await withTaskCancellationHandler(operation: {
            try await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }
}

struct EditorPNGApplication: Identifiable {
    let url: URL
    let name: String
    var id: URL { url }
    @MainActor static func available() -> [Self] {
        let workspace = NSWorkspace.shared
        let preview = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview")
        let urls = (preview.map { [$0] } ?? []) + workspace.urlsForApplications(toOpen: .png)
        var seen = Set<URL>()
        return urls.compactMap { url in
            let url = url.standardizedFileURL
            guard url != Bundle.main.bundleURL.standardizedFileURL, seen.insert(url).inserted else { return nil }
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return Self(url: url, name: name)
        }
    }
}

extension EditorObject.Kind {
    static func from(_ tool: AnnotationTool) -> Self? {
        switch tool {
        case .pen: .pen
        case .spotlight: .spotlight
        case .magnifier: .magnifier
        case .arrow: .arrow
        case .text: .text
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .callout: .callout
        case .blur: .blur
        case .redact: .redact
        case .highlight: .highlight
        case .steps: .step
        default: nil
        }
    }
}
