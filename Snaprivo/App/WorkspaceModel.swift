import AppKit
import CoreText
import ImageIO
import Observation
import UniformTypeIdentifiers
import SnagForgeDomain

/// Generated locally from shapes and reserved example data; never reads the screen.
private enum OnboardingExampleImage {
    nonisolated static func make() throws -> CGImage {
        let width = 800, height = 500
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ProjectError.invalidDocument
        }
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        let ink = color(0.12, 0.16, 0.24), muted = color(0.38, 0.43, 0.51), blue = color(0.14, 0.39, 0.91)
        func fill(_ rect: CGRect, _ fill: CGColor, radius: CGFloat = 0) {
            context.setFillColor(fill)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, bold: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes)), context)
        }
        fill(CGRect(x: 0, y: 0, width: width, height: height), color(0.93, 0.95, 0.98))
        fill(CGRect(x: 40, y: 40, width: 720, height: 420), color(1, 1, 1), radius: 18)
        for (index, dot) in [color(0.98, 0.40, 0.37), color(0.98, 0.74, 0.28), color(0.29, 0.77, 0.40)].enumerated() {
            context.setFillColor(dot); context.fillEllipse(in: CGRect(x: 62 + index * 20, y: 428, width: 10, height: 10))
        }
        text(String(localized: "Beispielbild"), x: 144, y: 427, size: 13, color: muted)
        text(String(localized: "Projektübersicht"), x: 76, y: 368, size: 28, color: ink, bold: true)
        text(String(localized: "Nur synthetische Daten – zum Ausprobieren"), x: 76, y: 338, size: 15, color: muted)
        fill(CGRect(x: 76, y: 170, width: 648, height: 132), color(0.96, 0.97, 0.99), radius: 12)
        text(String(localized: "Entwurf prüfen"), x: 100, y: 263, size: 20, color: ink, bold: true)
        text("kunde@example.com", x: 100, y: 229, size: 17, color: muted)
        fill(CGRect(x: 100, y: 193, width: 320, height: 8), color(0.86, 0.89, 0.94), radius: 4)
        fill(CGRect(x: 100, y: 193, width: 214, height: 8), blue, radius: 4)
        fill(CGRect(x: 548, y: 213, width: 148, height: 50), blue, radius: 12)
        text(String(localized: "Freigeben"), x: 576, y: 232, size: 17, color: color(1, 1, 1), bold: true)
        text(String(localized: "Markiere den Button oder decke die Beispieladresse ab."), x: 76, y: 115, size: 16, color: ink)
        text(String(localized: "Danach: Bild kopieren mit ⌘C."), x: 76, y: 86, size: 16, color: muted)
        guard let image = context.makeImage() else { throw ProjectError.invalidDocument }
        return image
    }
}

@MainActor
@Observable
final class WorkspaceModel {
    let screenshot = ScreenshotCoordinator()
    let captureShortcuts: GlobalCaptureShortcuts
    let preferences: AppPreferences
    let search: LibrarySearchModel
    let guides: GuideModel
    let videos: VideoLibraryModel
    let purchases: ProPurchaseModel
    struct GuideImageReturn { let guide: UUID; let step: UUID; let project: UUID }
    private(set) var guideImageReturn: GuideImageReturn?
    var requestedProFeature: ProFeature?
    @ObservationIgnored var onQuickCaptureReady: (@MainActor (EditorModel) -> Void)?
    /// The panel owns the window lifetime; the model only reports that its visible stack changed.
    @ObservationIgnored var onQuickCaptureDismissed: (@MainActor () -> Void)?
    @ObservationIgnored var showWorkspaceWindow: (@MainActor () -> Void)?
    @ObservationIgnored var showPaywallWindow: (@MainActor () -> Void)?
    var showsPaywall = false
    private(set) var quickCaptures: [EditorModel] = []
    var selectedQuickCaptureID: UUID?
    var quickCaptureFocusRequest = 0
    func moveQuickCaptureSelection(by offset: Int) {
        guard !quickCaptures.isEmpty, offset == -1 || offset == 1 else { return }
        let current = quickCaptures.firstIndex { $0.document.id == selectedQuickCaptureID } ?? 0
        selectedQuickCaptureID = quickCaptures[min(max(current + offset, 0), quickCaptures.count - 1)].document.id
    }
    /// Compatibility for commands targeting the most recent capture.
    var quickCapture: EditorModel? {
        get { quickCaptures.first }
        set {
            guard let newValue else {
                quickCaptures.forEach { retainQuickCapturePendingWork($0) }
                quickCaptures.removeAll(); selectedQuickCaptureID = nil
                onQuickCaptureDismissed?()
                return
            }
            quickCaptures.removeAll { $0.document.id == newValue.document.id }
            quickCaptures.insert(newValue, at: 0)
            let evicted = Array(quickCaptures.dropFirst(5))
            evicted.forEach { retainQuickCapturePendingWork($0) }
            quickCaptures = Array(quickCaptures.prefix(5))
            selectedQuickCaptureID = newValue.document.id
        }
    }
    private(set) var hasOpenedExternalFile = false
    var showsOnboarding = false
    var libraryShowsVideos = false
    let storage: StorageLocations
    var captureConfiguration: CaptureConfiguration
    var pendingCapture: UUID?
    /// Guide that receives the next started image capture as its final step.
    @ObservationIgnored var pendingGuideCapture: UUID?
    var isScrollCapture = false
    private(set) var store: ProjectStore
    private(set) var isChangingLibrary = false
    private(set) var isChoosingStorageFolder = false
    var storageError: String?
    var storageNotice: String?
    @ObservationIgnored private var storagePanel: NSOpenPanel?
    @ObservationIgnored private var librarySwitchTask: Task<Bool, Never>?
    var editor: EditorModel? {
        didSet {
            if editor?.document.id != oldValue?.document.id {
                explicitFilmstripSelection = nil
                editorFilmstripCopyNotice = nil
            }
        }
    }
    private var explicitFilmstripSelection: Set<UUID>?
    private(set) var isCopyingSelectedEditorImages = false
    private(set) var editorFilmstripCopyNotice: String?
    @ObservationIgnored private var editorImagesCopyTask: Task<Bool, Never>?
    private(set) var isChangingTrash = false
    private(set) var isUpdatingMetadata = false
    @ObservationIgnored private var metadataTask: Task<Bool, Never>?
    private(set) var isTransferring = false
    var transferNotice: String?
    @ObservationIgnored private var transferTask: Task<Bool, Never>?
    @ObservationIgnored private var quickCaptureInFlight: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var quickCaptureFailure: String?
    @ObservationIgnored private var quickCaptureFailurePresented = false
    @ObservationIgnored private var quickCaptureFailureAcknowledged = false
    @ObservationIgnored var directOCRTask: Task<Void, Never>? {
        didSet { isDirectOCRBusy = directOCRTask != nil }
    }
    private(set) var isDirectOCRBusy = false
    var directCaptureNotice: String?
    var directCaptureReadsCodes = false
    var showsDirectCaptureResult = false
    var directCaptureText = ""
    var directCaptureCodes: [String] = []
    var directCaptureError: String?
    @ObservationIgnored var directCaptureImage: CGImage?
    @ObservationIgnored var directCaptureRequestID = UUID()
    var isImporting = false
    var importError: String?
    var section: WorkspaceSection? = .library
    private(set) var items: [ProjectLibraryItem] = []
    private(set) var trashItems: [ProjectLibraryItem] = []
    private(set) var trashIssues: [String] = []
    private(set) var libraryIssues: [String] = []
    private(set) var isLoading = false
    private(set) var openingProjectID: UUID?
    private(set) var didLoadLibrary = false
    @ObservationIgnored private var openingTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var libraryRefreshRequest = UUID()
    @ObservationIgnored private var savedDuringRefresh: [UUID: ProjectLibraryItem]?
    @ObservationIgnored private let copyCapture: @MainActor (EditorModel) -> Void

    init(root: URL? = nil, defaults: UserDefaults = .standard, bookmarkClient: FolderBookmarkClient = .live,
         purchases: ProPurchaseModel? = nil,
         copyCapture: @escaping @MainActor (EditorModel) -> Void = { $0.copyPNG() }) {
        self.copyCapture = copyCapture
        self.purchases = purchases ?? ProPurchaseModel()
        preferences = AppPreferences(defaults: defaults)
        let cacheRoot = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SnagForge/Search", isDirectory: true)
        search = LibrarySearchModel(cacheURL: cacheRoot.appendingPathComponent(".library-search.sqlite"))
        let guideRoot = root?.appendingPathComponent(".Guides", isDirectory: true) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SnagForge/Guides", isDirectory: true)
        guides = GuideModel(root: guideRoot)
        videos = VideoLibraryModel(root: root?.appendingPathComponent(".Videos", isDirectory: true))
        storage = StorageLocations(defaults: defaults, client: bookmarkClient)
        captureShortcuts = GlobalCaptureShortcuts(defaults: defaults)
        captureConfiguration = preferences.captureConfiguration
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnagForge/Projects", isDirectory: true)
        store = ProjectStore(root: storage.libraryURL ?? root)
        preferences.onOCRIndexingChanged = { [weak self] _ in self?.synchronizeSearch() }
        guides.requestFeature = { [weak self] in self?.requirePro($0) ?? false }
        videos.requestFeature = { [weak self] in self?.requirePro($0) ?? false }
        videos.hasProAccess = { [weak self] in self?.purchases.hasPro ?? false }
        self.purchases.onEntitlementChanged = { [weak self] hasPro in
            guard let self else { return }
            if !hasPro {
                self.editor?.proAccessDidChange()
                self.quickCaptures.forEach { $0.proAccessDidChange() }
                self.dismissDirectCaptureResult()
                self.videos.preview?.discardDraft()
            }
            self.synchronizeSearch()
        }
        screenshot.videoFiles = videos.files
        screenshot.authorizeCapture = { [weak self] scrolling, video in
            self?.authorizeCapture(scrolling: scrolling, video: video) ?? false
        }
        screenshot.onVideoLibraryChange = { [weak self] in
            guard let self else { return }
            await self.videos.refresh(); self.libraryShowsVideos = true; self.section = .library
        }
    }
    func refreshLibrary() async {
        await storage.restoreIfNeeded()
        if storage.isReady, let library = storage.libraryURL,
           store.root.standardizedFileURL != library.standardizedFileURL {
            store = ProjectStore(root: library)
        }
        let request = UUID(), currentStore = store
        libraryRefreshRequest = request; savedDuringRefresh = [:]
        defer { if libraryRefreshRequest == request { savedDuringRefresh = nil } }
        await videos.refresh()
        guard libraryRefreshRequest == request, currentStore === store else { return }
        guard storage.libraryError == nil else {
            libraryIssues = [storage.libraryError!]; didLoadLibrary = true; synchronizeSearch(); return
        }
        do {
            let listing = try await currentStore.list()
            let trash = try await currentStore.listTrash()
            guard libraryRefreshRequest == request, currentStore === store else { return }
            let trashed = Set(trash.items.map(\.id))
            var updated = listing.items
            // A save can finish while this full listing is awaiting the store.
            // Preserve its newer snapshot, but never resurrect a trashed project.
            for item in savedDuringRefresh?.values ?? Dictionary<UUID, ProjectLibraryItem>().values where !trashed.contains(item.id) {
                updated = item.updating(updated)
            }
            items = updated; libraryIssues = listing.issues
            trashItems = trash.items; trashIssues = trash.issues
        } catch {
            guard libraryRefreshRequest == request, currentStore === store else { return }
            libraryIssues = [error.localizedDescription]
        }
        didLoadLibrary = true
        synchronizeSearch()
    }
    func synchronizeSearch(rebuild: Bool = false, retry: Bool = false) {
        // Do not erase a returning Pro user's cache while the receipt or initial
        // library listing is still loading. No recognition starts in this state.
        guard purchases.hasCheckedEntitlement, !purchases.hasPro || didLoadLibrary else { search.cancel(); return }
        search.synchronize(documents: storage.libraryError == nil ? items.map(\.document) : [], store: store,
                           enabled: purchases.hasPro && preferences.ocrIndexingEnabled && storage.libraryError == nil, rebuild: rebuild, retry: retry)
    }
    func showPro(_ feature: ProFeature? = nil) {
        requestedProFeature = feature
        if let showPaywallWindow { showPaywallWindow() }
        else { showsPaywall = true }
    }
    @discardableResult func requirePro(_ feature: ProFeature) -> Bool {
        guard purchases.hasPro else { showPro(feature); return false }
        return true
    }
    @discardableResult func authorizeCapture(scrolling: Bool, video: Bool) -> Bool {
        if video { return requirePro(.video) }
        if scrolling { return requirePro(.scrolling) }
        return true
    }
    func setOCRIndexing(_ enabled: Bool) {
        guard !enabled || requirePro(.textRecognition) else { return }
        preferences.ocrIndexingEnabled = enabled
    }
    private func didSave(_ item: ProjectLibraryItem, in savedStore: ProjectStore) {
        guard savedStore === store else { return }
        items = item.updating(items)
        if savedDuringRefresh != nil { savedDuringRefresh?[item.id] = item }
        synchronizeSearch()
        // The initial scan still discovers other projects. Ordinary saves touch
        // only their committed item, without reloading trash or video metadata.
        if !didLoadLibrary, savedDuringRefresh == nil {
            refreshTask?.cancel()
            refreshTask = Task { await refreshLibrary() }
        }
    }
    func openScreenshot(_ captured: CGImage) {
        if let openingTask {
            Task { await openingTask.value; openScreenshot(captured) }
            return
        }
        openNew(title: String(localized: "Screenshot – ") + Date.now.formatted(date: .abbreviated, time: .standard), copyAfterOpen: preferences.copyAfterCapture, isScreenshot: true) { captured }
    }

    /// Saves the capture as a library project and appends it to the guide, leaving the editor untouched.
    func addCaptureToGuide(_ captured: CGImage, guide: UUID) {
        if let openingTask {
            Task { await openingTask.value; addCaptureToGuide(captured, guide: guide) }
            return
        }
        guard storage.libraryError == nil else { importError = storage.libraryError; return }
        guard !isLoading, !isUpdatingMetadata else { return }
        isLoading = true
        openingTask = Task {
            let title = String(localized: "Screenshot – ") + Date.now.formatted(date: .abbreviated, time: .standard)
            let store = store
            let created: ProjectLibraryItem?
            do {
                let (document, thumbnail) = try await Task.detached(priority: .userInitiated) {
                    try await Self.createProject(title: title, image: captured, in: store)
                }.value
                created = ProjectLibraryItem(document: document, thumbnail: thumbnail)
            } catch {
                created = nil
                importError = String(localized: "Das Projekt konnte nicht angelegt werden: \(error.localizedDescription)")
            }
            isLoading = false; openingTask = nil
            guard let created else { return }
            didSave(created, in: store)
            preferences.completedFirstCapture = true
            section = .guides
            guard guides.document?.id == guide, await guides.finishPendingWork(), guides.document?.id == guide else {
                guides.notice = String(localized: "Die Aufnahme ist in der Bibliothek gesichert, aber die Anleitung ist nicht mehr geöffnet.")
                return
            }
            addGuideProjects([created.id])
        }
    }
    nonisolated private static func createProject(title: String, image: CGImage, in store: ProjectStore) async throws -> (ProjectDocument, Data?) {
        guard let size = PixelSize(width: image.width, height: image.height) else { throw ProjectError.invalidDocument }
        let document = ProjectDocument(title: title, pixelSize: size)
        let original = try EditorRenderer.png(image: image, objects: [])
        let thumbnail = try? EditorRenderer.thumbnail(image: image, objects: [])
        try await store.create(document, original: original, thumbnail: thumbnail)
        return (document, thumbnail)
    }

    /// Uses the normal project/editor path, without capturing pixels or copying automatically.
    func openOnboardingExample() {
        guard canSwitchEditorImage else {
            importError = String(localized: "Beende zuerst die aktuelle Bearbeitung oder Aufnahme, bevor du das Beispiel öffnest.")
            return
        }
        openNew(title: String(localized: "Beispielbild")) { try OnboardingExampleImage.make() }
    }

    func dismissDirectCaptureResult() {
        directCaptureRequestID = UUID()
        directOCRTask?.cancel(); directOCRTask = nil
        showsDirectCaptureResult = false; directCaptureImage = nil
        directCaptureText = ""; directCaptureCodes = []; directCaptureError = nil; directCaptureNotice = nil
    }
    func cancelDirectTextCapture() {
        directOCRTask?.cancel()
        screenshot.cancel()
        dismissDirectCaptureResult()
    }
    func openImage(at url: URL) {
        openNew(title: url.deletingPathExtension().lastPathComponent) {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try ProjectArchive.readRegularFile(url, limit: 512_000_000)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 32768, height <= 32768,
                  Int64(width) * Int64(height) <= 100_000_000,
                  let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height)
                  ] as CFDictionary) else { throw ProjectError.invalidDocument }
            return pixels
        }
    }
    private func openNew(title: String, copyAfterOpen: Bool = false, isScreenshot: Bool = false, decode: @escaping @Sendable () throws -> CGImage) {
        guard storage.libraryError == nil else { importError = storage.libraryError; return }
        guard !isLoading, !isUpdatingMetadata else { return }
        let previous = suspendEditorForImageSwitch()
        isLoading = true
        openingTask = Task {
            defer { resumeEditorAfterImageSwitch(previous); isLoading = false; openingTask = nil }
            do {
                let store = store
                // Finish the old editor while preparing the new pixels. Both
                // operations must complete before replacing its UI/ownership.
                async let previousSaved = previous?.finishPendingWork() != false
                let (image, document, thumbnail) = try await Task.detached(priority: .userInitiated) {
                    let image = try decode()
                    let (document, thumbnail) = try await Self.createProject(title: title, image: image, in: store)
                    return (image, document, thumbnail)
                }.value
                didSave(ProjectLibraryItem(document: document, thumbnail: thumbnail), in: store)
                let newEditor = makeEditor(image: image, document: document, generation: 0)
                // Copy the new screenshot even if unsaved work prevents replacing the editor.
                if copyAfterOpen { copyCapture(newEditor) }
                // Keep a new capture even if the previous editor cannot currently be saved.
                let canReplacePrevious = await previousSaved
                if canReplacePrevious && isScreenshot && preferences.quickPreviewAfterCapture {
                    quickCapture = newEditor
                    onQuickCaptureReady?(newEditor)
                } else if canReplacePrevious {
                    editor = newEditor
                } else {
                    editor?.notice = String(localized: "Das neue Bild ist in der Bibliothek gesichert. Sichere zuerst die bisherigen Änderungen.")
                }
                if isScreenshot && !preferences.completedFirstCapture {
                    preferences.completedFirstCapture = true
                    if canReplacePrevious { editor?.notice = String(localized: "Erste Aufnahme gesichert. Werkzeuge oben wählen, anschließend PNG speichern oder kopieren.") }
                }
                if quickCapture == nil { section = .editor }
            } catch { importError = String(localized: "Das Projekt konnte nicht angelegt werden: \(error.localizedDescription)") }
        }
    }
    private func makeEditor(image: CGImage, document: ProjectDocument, generation: Int) -> EditorModel {
        let next = EditorModel(image: image, document: document, generation: generation, store: store,
                    automaticallyFitsImage: preferences.automaticallyFitsImage,
                    pngDirectory: { [storage] in storage.pngFolder }, onSaved: {})
        let savedStore = store
        next.onLibraryItemSaved = { [weak self] item in self?.didSave(item, in: savedStore) }
        next.requestFeature = { [weak self] in self?.requirePro($0) ?? false }
        next.hasProAccess = { [weak self] in self?.purchases.hasPro ?? false }
        if let editor { next.inheritToolSettings(from: editor) }
        if !purchases.hasPro { next.proAccessDidChange() }
        return next
    }
    private func suspendEditorForImageSwitch() -> EditorModel? {
        guard let editor else { return nil }
        editor.endStyleEditing(); editor.finishTextEditing()
        editor.isSwitchingImage = true
        if section == .editor { NSApp.keyWindow?.makeFirstResponder(nil) }
        return editor
    }
    private func resumeEditorAfterImageSwitch(_ previous: EditorModel?) {
        previous?.isSwitchingImage = false
        if editor === previous { previous?.focusRequest += 1 }
    }
    /// Recent creations only; editing or renaming never moves an item or extends its stay.
    var editorQuickSwitchItems: [ProjectLibraryItem] {
        editorQuickSwitchItems(asOf: .now)
    }
    func editorQuickSwitchItems(asOf now: Date) -> [ProjectLibraryItem] {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        return items.filter { $0.document.createdAt >= cutoff }.sorted {
            if $0.document.createdAt != $1.document.createdAt { return $0.document.createdAt > $1.document.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var canSwitchEditorImage: Bool {
        !isLoading && !isCopyingSelectedEditorImages && canSwitchEditorImageForToolbar
    }
    /// Loading blocks actions without dimming navigation that remains valid for the current image.
    var canSwitchEditorImageForToolbar: Bool {
        !isCopyingSelectedEditorImages && (!isLoading || editor?.isSwitchingImage == true)
            && !isUpdatingMetadata && !isChoosingStorageFolder && !screenshot.isBusy && !guides.isSuspended && storage.libraryError == nil
            && editor?.isCanvasGestureActive != true && editor?.cropDraft == nil
            && editor?.preview == nil && editor?.isShowingImageSize != true && editor?.isShowingTextRecognition != true
    }
    func adjacentEditorImage(_ distance: Int) -> UUID? {
        let ordered = editorQuickSwitchItems
        guard distance == -1 || distance == 1, let selected = editor?.document.id,
              let index = ordered.firstIndex(where: { $0.id == selected }), ordered.indices.contains(index + distance) else { return nil }
        return ordered[index + distance].id
    }
    func switchEditorImage(to id: UUID) {
        guard canSwitchEditorImage, editorQuickSwitchItems.contains(where: { $0.id == id }) else { return }
        explicitFilmstripSelection = nil; editorFilmstripCopyNotice = nil
        openProject(id)
    }

    var editorFilmstripSelectedIDs: Set<UUID> {
        let available = Set(editorQuickSwitchItems.map(\.id))
        if let explicitFilmstripSelection { return explicitFilmstripSelection.intersection(available) }
        return editor.map { available.intersection([$0.document.id]) } ?? []
    }
    func selectEditorFilmstripImage(_ id: UUID, extending: Bool = false) {
        guard canSwitchEditorImage, editorQuickSwitchItems.contains(where: { $0.id == id }) else { return }
        editorFilmstripCopyNotice = nil
        if extending {
            var selection = editorFilmstripSelectedIDs
            if !selection.insert(id).inserted { selection.remove(id) }
            explicitFilmstripSelection = selection
        } else { switchEditorImage(to: id) }
    }
    var canCopySelectedEditorImages: Bool {
        guard canSwitchEditorImage, !isCopyingSelectedEditorImages, !editorFilmstripSelectedIDs.isEmpty else { return false }
        if let editor, editorFilmstripSelectedIDs.contains(editor.document.id) {
            return editor.hasExportableImage && !editor.isExporting
        }
        return true
    }
    /// Multiple independent PNG files are prepared before replacing the pasteboard.
    /// Successful transfer files use the same macOS-managed temporary lifetime as other image transfers.
    @discardableResult func copySelectedEditorImages(
        to pasteboard: NSPasteboard = .general,
        in directory: URL? = nil,
        prepare: @escaping @Sendable (EditorPNGShare, URL) async throws -> URL = { snapshot, root in
            try await snapshot.writeTemporaryPNG(in: root)
        }
    ) -> Task<Bool, Never>? {
        guard canCopySelectedEditorImages else { return nil }
        let selectedIDs = editorFilmstripSelectedIDs
        let orderedIDs = editorQuickSwitchItems.filter { selectedIDs.contains($0.id) }.map(\.id)
        guard !orderedIDs.isEmpty else { return nil }
        var activeSnapshot: EditorPNGShare?
        let activeID = editor?.document.id
        if let editor, selectedIDs.contains(editor.document.id) {
            editor.endStyleEditing(); editor.finishTextEditing()
            guard let snapshot = editor.pngShareItem else { return nil }
            activeSnapshot = snapshot
        }
        let store = store, changeCount = pasteboard.changeCount
        let batchRoot = (directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("EditorClipboardTransfers", isDirectory: true))
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        isCopyingSelectedEditorImages = true
        editorFilmstripCopyNotice = String(localized: "Auswahl wird kopiert …")
        let task = Task { [self, activeSnapshot] in
            defer { isCopyingSelectedEditorImages = false; editorImagesCopyTask = nil }
            do {
                var files: [URL] = []
                for id in orderedIDs {
                    try Task.checkCancellation()
                    let snapshot: EditorPNGShare
                    if id == activeID, let activeSnapshot { snapshot = activeSnapshot }
                    else {
                        let loaded = try await store.load(id)
                        snapshot = try await Task.detached(priority: .userInitiated) {
                            try Task.checkCancellation()
                            guard let source = CGImageSourceCreateWithData(loaded.original as CFData, nil),
                                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                                throw ProjectError.invalidDocument
                            }
                            let document = loaded.document
                            return EditorPNGShare(image: image, objects: document.objects, crop: document.crop,
                                resizedSize: document.resizedSize, title: document.title, canvasRect: document.canvasRect,
                                transform: document.transform, presentation: document.presentation)
                        }.value
                    }
                    files.append(try await prepare(snapshot, batchRoot))
                }
                try Task.checkCancellation()
                guard pasteboard.changeCount == changeCount else {
                    try? await Task.detached { try FileManager.default.removeItem(at: batchRoot) }.value
                    editorFilmstripCopyNotice = String(localized: "Zwischenablage wurde geändert. Bitte erneut kopieren.")
                    return false
                }
                pasteboard.clearContents()
                guard pasteboard.writeObjects(files.map { $0 as NSURL }) else { throw CocoaError(.fileWriteUnknown) }
                editorFilmstripCopyNotice = String(localized: "\(files.count) Bilder kopiert")
                return true
            } catch {
                try? await Task.detached { try FileManager.default.removeItem(at: batchRoot) }.value
                editorFilmstripCopyNotice = nil
                importError = String(localized: "Die ausgewählten Bilder konnten nicht kopiert werden: \(error.localizedDescription)")
                return false
            }
        }
        editorImagesCopyTask = task
        return task
    }
    func switchEditorImage(by distance: Int) {
        guard let id = adjacentEditorImage(distance) else { return }
        switchEditorImage(to: id)
    }
    /// Use the regular, recoverable trash path and keep browsing after removing the open image.
    func trashEditorImage(_ id: UUID) async {
        guard canSwitchEditorImage, editorQuickSwitchItems.contains(where: { $0.id == id }) else { return }
        let wasSelected = editor?.document.id == id
        let next = wasSelected ? adjacentEditorImage(1) ?? adjacentEditorImage(-1) : nil
        if let next {
            switchEditorImage(to: next)
            await openingTask?.value
            guard editor?.document.id == next else { return }
        }
        _ = await changeTrash(id, action: .trash)
    }
    func openProject(_ id: UUID) {
        guard storage.libraryError == nil else { importError = storage.libraryError; return }
        guard !isLoading, !isUpdatingMetadata else { return }
        if editor?.document.id == id { section = .editor; return }
        let previous = suspendEditorForImageSwitch()
        isLoading = true; openingProjectID = id
        openingTask = Task {
            defer { resumeEditorAfterImageSwitch(previous); openingProjectID = nil; isLoading = false; openingTask = nil }
            // The next immutable image can decode while the outgoing editor saves.
            // Publishing it still waits for a successful save/export completion.
            async let previousSaved = previous?.finishPendingWork() != false
            do {
                let loaded = try await store.load(id)
                let (image, prepared) = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(loaded.original as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                          CGImageSourceGetStatus(source) == .statusComplete,
                          image.width == loaded.document.pixelSize.width, image.height == loaded.document.pixelSize.height else {
                        throw ProjectError.invalidDocument
                    }
                    return (image, try EditorCanvasPreparation.prepare(image: image, document: loaded.document))
                }.value
                guard await previousSaved else { return }
                let next = makeEditor(image: image, document: loaded.document, generation: loaded.generation)
                next.initialCanvas = prepared
                editor = next
                if loaded.recovered { editor?.notice = String(localized: "Vorheriger Speicherstand wiederhergestellt") }
                section = .editor
            } catch {
                guard await previousSaved else { return }
                importError = error.localizedDescription
            }
        }
    }
    func updateProjectMetadata(_ id: UUID, title: String? = nil, favorite: Bool? = nil, tags: [String]? = nil, collections: [String]? = nil) async -> Bool {
        guard (tags == nil && collections == nil) || requirePro(.organization) else { return false }
        guard !isLoading, !isUpdatingMetadata, storage.libraryError == nil else { return false }
        isUpdatingMetadata = true
        let task = Task { [self] in
            defer { isUpdatingMetadata = false; metadataTask = nil }
            do {
                if let editor, editor.document.id == id {
                    guard editor.updateMetadata(title: title, favorite: favorite, tags: tags, collections: collections), await editor.flush() else {
                        importError = editor.saveError ?? String(localized: "Die Projektänderung konnte nicht gesichert werden.")
                        return false
                    }
                } else { try await store.updateMetadata(id, title: title, favorite: favorite, tags: tags, collections: collections) }
                await refreshLibrary()
                return true
            } catch { importError = String(localized: "Die Projektänderung konnte nicht gesichert werden: \(error.localizedDescription)"); return false }
        }
        metadataTask = task
        return await task.value
    }
    enum TrashAction { case trash, restore, delete }
    func changeTrash(_ id: UUID, action: TrashAction) async -> Bool {
        guard !isLoading, !isUpdatingMetadata, storage.libraryError == nil else { return false }
        isUpdatingMetadata = true; isChangingTrash = true
        let task = Task { [self] in
            defer { isUpdatingMetadata = false; isChangingTrash = false; metadataTask = nil }
            do {
                if action == .trash, let editor, editor.document.id == id {
                    guard await editor.finishPendingWork() else {
                        importError = editor.saveError ?? String(localized: "Das Projekt konnte vor dem Verschieben nicht gesichert werden.")
                        return false
                    }
                }
                switch action {
                case .trash:
                    try await store.moveToTrash(id)
                    if editor?.document.id == id { editor = nil; section = .library }
                case .restore: try await store.restore(id)
                case .delete: try await store.permanentlyDelete(id)
                }
                await refreshLibrary(); return true
            } catch { importError = String(localized: "Die Papierkorb-Aktion konnte nicht abgeschlossen werden: \(error.localizedDescription)"); await refreshLibrary(); return false }
        }
        metadataTask = task
        return await task.value
    }
    func flushBeforeQuitting() async -> Bool {
        guides.isSuspended = true
        defer { guides.isSuspended = false }
        search.cancel()
        if let panel = storagePanel { storagePanel = nil; isChoosingStorageFolder = false; panel.cancel(nil) }
        let pendingOCR = directOCRTask
        pendingOCR?.cancel(); await pendingOCR?.value
        await screenshot.finishBeforeQuitting()
        guard await videos.finishPendingWork() else { return false }
        if let librarySwitchTask { _ = await librarySwitchTask.value }
        if let transferTask { _ = await transferTask.value }
        if let metadataTask, !(await metadataTask.value) { return false }
        if let openingTask { await openingTask.value }
        guard await guides.finishPendingWork() else { return false }
        guard await finishAllQuickCapturePendingWork() else { return false }
        return await editor?.finishPendingWork() ?? true
    }

    /// A dismissed thumbnail remains owned by this model until its export/save task is done.
    /// This keeps a started PNG write alive without keeping the thumbnail visible.
    private func retainQuickCapturePendingWork(_ model: EditorModel) {
        let id = model.document.id
        guard quickCaptureInFlight[id] == nil else { return }
        let task = Task { @MainActor [weak self, model] in
            let succeeded = await model.finishPendingWork()
            if !succeeded {
                let message = model.error ?? model.saveError
                    ?? String(localized: "Die Aufnahme konnte nicht vollständig gespeichert werden.")
                self?.quickCaptureFailure = message
                self?.quickCaptureFailurePresented = true
                self?.quickCaptureFailureAcknowledged = false
                self?.importError = message
                self?.showWorkspaceWindow?()
            }
            self?.quickCaptureInFlight.removeValue(forKey: id)
            return succeeded
        }
        quickCaptureInFlight[id] = task
    }

    @discardableResult
    private func finishQuickCapturePendingWork() async -> Bool {
        var succeeded = true
        // A dismissal can happen while an earlier task is being awaited. Drain
        // until no task was added during the previous await.
        while !quickCaptureInFlight.isEmpty {
            let tasks = Array(quickCaptureInFlight.values)
            for task in tasks where !(await task.value) { succeeded = false }
        }
        if let failure = quickCaptureFailure {
            if !quickCaptureFailurePresented {
                importError = failure
                quickCaptureFailurePresented = true
                return false
            }
            if !quickCaptureFailureAcknowledged {
                importError = failure
                // The alert is still visible. Keep the boundary blocked until
                // the user acknowledges the output failure.
                return false
            }
            // The alert was acknowledged; consume the failure exactly once.
            quickCaptureFailure = nil
            quickCaptureFailurePresented = false
            quickCaptureFailureAcknowledged = false
            succeeded = true
        }
        return succeeded
    }

    private func finishAllQuickCapturePendingWork() async -> Bool {
        if let editorImagesCopyTask { _ = await editorImagesCopyTask.value }
        guard await finishQuickCapturePendingWork() else { return false }
        for capture in quickCaptures {
            guard await capture.finishPendingWork() else {
                importError = capture.error ?? capture.saveError
                    ?? String(localized: "Die Aufnahme konnte nicht vollständig gespeichert werden.")
                return false
            }
        }
        // A close can arrive while a visible capture is being flushed. Drain
        // once more so that newly dismissed work cannot cross the boundary.
        return await finishQuickCapturePendingWork()
    }

    /// Called by the shared error alert. Clearing the published text alone must
    /// not make a failed dismissed export look acknowledged.
    func acknowledgeImportError() {
        if quickCaptureFailurePresented, importError == quickCaptureFailure { quickCaptureFailureAcknowledged = true }
        importError = nil
    }
    func addGuideProjects(_ ids: [UUID], replacing: UUID? = nil, at position: GuideInsertion = .end) {
        guard requirePro(.guides) else { return }
        guard !isLoading, storage.libraryError == nil else { return }
        guides.addProjects(ids, from: store, replacing: replacing, at: position) { [weak self] in
            guard let self else { return false }
            return await self.editor?.finishPendingWork() != false
        }
    }
    func guideSource(for step: GuideStep) -> ProjectLibraryItem? {
        guard step.sourceLibrary == GuideModel.libraryKey(store), let id = step.sourceProjectID else { return nil }
        return items.first { $0.id == id }
    }
    func editGuideImage(_ stepID: UUID) async {
        guard requirePro(.guides), !isLoading, !guides.isBusy, !guides.isSuspended, videos.preview == nil,
              let guide = guides.document, let step = guide.steps.first(where: { $0.id == stepID }),
              let source = guideSource(for: step) else { return }
        guides.isSuspended = true
        let saved = await guides.flush()
        guides.isSuspended = false
        guard saved, guides.document?.id == guide.id else { return }
        openProject(source.id)
        if let openingTask { await openingTask.value }
        guard editor?.document.id == source.id, section == .editor else { return }
        guideImageReturn = GuideImageReturn(guide: guide.id, step: stepID, project: source.id)
    }
    func returnToGuide(applyingChanges: Bool) async {
        guard !isLoading, !guides.isBusy, let target = guideImageReturn,
              guides.document?.id == target.guide, editor?.document.id == target.project,
              let step = guides.document?.steps.first(where: { $0.id == target.step }),
              guideSource(for: step)?.id == target.project else { return }
        guard await editor?.finishPendingWork() != false else { return }
        if applyingChanges {
            guard requirePro(.guides) else { return }
            addGuideProjects([target.project], replacing: target.step)
            guard await guides.finishPendingWork(), guides.error == nil else { section = .guides; return }
        }
        guideImageReturn = nil; guides.selectedStep = target.step; guides.stepToReveal = target.step; section = .guides
    }
}

enum WorkspaceSection: Hashable { case library, editor, guides }

extension WorkspaceModel {
    var canChangeStorage: Bool {
        storage.isReady && !isLoading && !videos.isBusy && videos.preview == nil && !isUpdatingMetadata && !isChoosingStorageFolder && !screenshot.isBusy && !guides.isBusy && !guides.isSuspended
            && editor?.isCanvasGestureActive != true && editor?.isExporting != true
    }
    func chooseStorageFolder(_ kind: StorageLocations.Kind) {
        guard canChangeStorage else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = kind == .png ? String(localized: "PNG-Standardordner wählen") : String(localized: "Ordner für die Projektbibliothek wählen")
        panel.prompt = String(localized: "Ordner verwenden")
        panel.message = kind == .png ? String(localized: "PNG speichern öffnet künftig diesen Ordner. Du kannst den Zielort beim Speichern weiter ändern.")
            : String(localized: "Im gewählten Ordner wird Snaprivo-Bibliothek angelegt. Vorhandene Projekte und Papierkorb werden übernommen; der bisherige Ordner bleibt erhalten.")
        panel.directoryURL = kind == .png ? storage.pngFolder : storage.libraryFolder
        storagePanel = panel; isChoosingStorageFolder = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, self.storagePanel === panel else { return }
            self.storagePanel = nil; self.isChoosingStorageFolder = false
            guard response == .OK, let folder = panel.url else { return }
            if kind == .png { Task { _ = await self.setPNGFolderAsync(folder) } }
            else { Task { await self.changeLibraryFolder(folder) } }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    @discardableResult func setPNGFolder(_ folder: URL) -> Bool {
        do {
            let prepared = try storage.prepare(folder)
            storage.commit(prepared, for: .png); storageError = nil
            storageNotice = String(localized: "PNG-Standardordner gespeichert.")
            return true
        } catch { storageError = String(localized: "Der PNG-Ordner konnte nicht festgelegt werden: \(error.localizedDescription)"); return false }
    }
    @discardableResult func setPNGFolderAsync(_ folder: URL) async -> Bool {
        do {
            let prepared = try await storage.prepareAsync(folder)
            storage.commit(prepared, for: .png); storageError = nil
            storageNotice = String(localized: "PNG-Standardordner gespeichert.")
            return true
        } catch {
            storageError = String(localized: "Der PNG-Ordner konnte nicht festgelegt werden: \(error.localizedDescription)")
            return false
        }
    }
    @discardableResult func changeLibraryFolder(_ folder: URL) async -> Bool {
        guard canChangeStorage else { return false }
        isLoading = true; isChangingLibrary = true; storageNotice = nil; storageError = nil
        let task = Task { [self] in
            defer { isLoading = false; isChangingLibrary = false; librarySwitchTask = nil }
            var prepared: StorageLocations.Prepared?
            var published: URL?
            var committed = false
            defer { if let prepared, !committed { storage.discard(prepared) } }
            do {
                guard await finishAllQuickCapturePendingWork() else { return false }
                let grant = try await storage.prepareAsync(folder); prepared = grant
                let target = StorageLocations.libraryURL(in: grant.url)
                let canonical = target.standardizedFileURL.resolvingSymlinksInPath()
                if storage.libraryError != nil {
                    guard canonical == storage.storedLibraryURL?.standardizedFileURL.resolvingSymlinksInPath() else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    let replacement = ProjectStore(root: target)
                    guard try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadNoSuchFile) }
                    let active = try await replacement.list(), trash = try await replacement.listTrash()
                    guard active.issues.isEmpty, trash.issues.isEmpty else { throw ProjectError.invalidDocument }
                    storage.commit(grant, for: .library); committed = true; store = replacement; guideImageReturn = nil
                    await refreshLibrary(); storageNotice = String(localized: "Bibliotheksordner erneut freigegeben.")
                    return true
                }
                guard await editor?.finishPendingWork() != false else {
                    storageError = String(localized: "Sichere zuerst die offenen Änderungen im bisherigen Ordner."); return false
                }
                if canonical == store.root.standardizedFileURL.resolvingSymlinksInPath() {
                    storage.commit(grant, for: .library); committed = true
                    storageNotice = String(localized: "Bibliotheksordner bestätigt.")
                    return true
                }
                if storage.libraryFolder != nil || !items.isEmpty || !trashItems.isEmpty {
                    guard try store.root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadNoSuchFile) }
                }
                let count = try await store.copyLibrary(to: target); published = target
                let replacement = ProjectStore(root: target)
                if let editor {
                    let copied = try await replacement.load(editor.document.id)
                    guard !editor.isDirty, copied.generation == editor.savedRevision,
                          copied.document.objects == editor.history.objects else { throw ProjectError.staleRevision }
                }
                storage.commit(grant, for: .library); committed = true
                store = replacement; guideImageReturn = nil; editor?.useProjectStore(replacement)
                quickCaptures.forEach { $0.useProjectStore(replacement) }
                await refreshLibrary()
                storageNotice = String(localized: "\(count) Projekte einschließlich Papierkorb übernommen. Der bisherige Ordner bleibt erhalten.")
                return true
            } catch {
                if let published, !committed {
                    _ = await Task.detached { try? FileManager.default.removeItem(at: published) }.value
                }
                if (error as? CocoaError)?.code == .fileWriteFileExists {
                    storageError = String(localized: "Im gewählten Ordner existiert bereits eine Snaprivo-Bibliothek. Wähle einen anderen Ordner; vorhandene Daten werden nicht überschrieben.")
                } else { storageError = String(localized: "Der Bibliotheksordner konnte nicht geändert werden. Der bisherige Speicherort bleibt aktiv. \(error.localizedDescription)") }
                return false
            }
        }
        librarySwitchTask = task
        return await task.value
    }
}

extension WorkspaceModel {
    enum TransferAction { case importProject, exportProject(UUID), backup, restoreBackup, completeBackup, restoreComplete, importLegacy }

    func chooseTransfer(_ action: TransferAction) {
        guard !isLoading, !isUpdatingMetadata, !screenshot.isBusy, storage.libraryError == nil else { return }
        let panel: NSSavePanel
        switch action {
        case .importProject, .restoreBackup, .restoreComplete, .importLegacy:
            let open = NSOpenPanel()
            open.allowsMultipleSelection = false; open.canChooseDirectories = false
            if case .importLegacy = action { open.canChooseDirectories = true; open.canChooseFiles = false }
            open.treatsFilePackagesAsDirectories = false
            panel = open
        default: panel = NSSavePanel() }
        switch action {
        case .importProject:
            panel.title = String(localized: "Bearbeitbares Projekt importieren"); panel.allowedContentTypes = [Self.projectType]
            panel.message = String(localized: "Das Projekt wird als eigene Kopie in die Bibliothek aufgenommen.")
        case .exportProject(let id):
            panel.title = String(localized: "Bearbeitbares Projekt exportieren"); panel.allowedContentTypes = [Self.projectType]
            let title = items.first { $0.id == id }?.document.title ?? editor?.name ?? String(localized: "Projekt")
            panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".snaprivo"
            panel.message = String(localized: "Enthält das unveränderte Original – auch zugeschnittene oder abgedeckte Inhalte. Zum Weitergeben nur sichtbarer Pixel PNG exportieren.")
        case .importLegacy:
            panel.title = String(localized: "Bisherige Snaprivo-Daten übernehmen")
            panel.message = String(localized: "Beende die bisherige App. Wähle ihren App-Container oder dessen Ordner „Library/Application Support“. Inhalte werden geprüft und als Kopien übernommen.")
        case .completeBackup:
            panel.title = String(localized: "Alles sichern")
            panel.allowedContentTypes = [Self.completeBackupType]
            panel.nameFieldStringValue = "Snaprivo-\(UUID().uuidString.prefix(8)).snaprivoall"
            panel.message = String(localized: "Enthält Bilder, Videos, Papierkörbe und bearbeitbare Anleitungen einschließlich Originalen.")
        case .restoreComplete:
            panel.title = String(localized: "Alles wiederherstellen")
            panel.allowedContentTypes = [Self.completeBackupType]
            panel.message = String(localized: "Alle Inhalte werden geprüft und als neue Kopien ergänzt. Vorhandene Arbeit bleibt erhalten.")
        case .backup:
            panel.title = String(localized: "Bibliothek sichern"); panel.allowedContentTypes = [Self.backupType]
            let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = "Snaprivo-Backup-\(stamp).snaprivobackup"
            panel.message = String(localized: "Sichert Bildprojekte einschließlich Papierkorb und Originalbildern. Anleitungen bitte separat als bearbeitbare Anleitung exportieren.")
        case .restoreBackup:
            panel.title = String(localized: "Bibliothek aus Sicherung ergänzen"); panel.allowedContentTypes = [Self.backupType]
            panel.message = String(localized: "Bestehende Projekte bleiben erhalten. Bei gleicher Projekt-ID wird eine zusätzliche Kopie angelegt; der Papierkorbstatus wird übernommen.")
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.transfer(action, at: url) }
        }
    }
    static var completeBackupType: UTType { UTType(exportedAs: "com.snaprivo.complete-backup", conformingTo: .package) }
    static var projectType: UTType { UTType(exportedAs: "com.snaprivo.project", conformingTo: .data) }
    static var backupType: UTType { UTType(exportedAs: "com.snaprivo.backup", conformingTo: .package) }

    @discardableResult func transfer(_ action: TransferAction, at url: URL) async -> Bool {
        guard !isLoading, !isUpdatingMetadata, !screenshot.isBusy, !videos.isBusy, !guides.isBusy, videos.preview == nil, storage.libraryError == nil else { return false }
        isLoading = true; isTransferring = true; importError = nil; transferNotice = nil
        let task = Task { [self] in
            guides.isSuspended = true; videos.isSuspended = true
            defer { isLoading = false; isTransferring = false; transferTask = nil; guides.isSuspended = false; videos.isSuspended = false }
            guard await guides.finishPendingWork(), await videos.finishPendingWork() else { return false }
            guard await finishAllQuickCapturePendingWork() else { return false }
            guard await editor?.finishPendingWork() != false else { importError = String(localized: "Sichere zuerst die offenen Änderungen."); return false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                switch action {
                case .exportProject(let id):
                    try await store.exportProject(id, to: url)
                    transferNotice = String(localized: "Bearbeitbares Projekt exportiert. Die Datei enthält das Originalbild.")
                case .importProject:
                    let (archive, image, thumbnail) = try await Task.detached(priority: .userInitiated) {
                        let archive = try ProjectArchive.read(from: url)
                        let image = try Self.archiveImage(archive)
                        return (archive, image, try Self.archiveThumbnail(archive))
                    }.value
                    let id = try await store.importProject(archive, thumbnail: thumbnail)
                    let loaded = try await store.load(id)
                    editor = makeEditor(image: image, document: loaded.document, generation: loaded.generation)
                    section = .editor
                    transferNotice = String(localized: "Projekt als bearbeitbare Kopie importiert.")
                case .completeBackup, .restoreComplete, .importLegacy:
                    let service = CompleteBackup(images: store, videos: videos.files, guides: guides.store)
                    let count: CompleteBackup.Counts
                    if case .completeBackup = action { count = try await service.backup(to: url) }
                    else if case .importLegacy = action { count = try await service.importLegacy(from: url) }
                    else { count = try await service.restore(from: url) }
                    transferNotice = String(localized: "\(count.images) Bilder, \(count.videos) Videos und \(count.guides) Anleitungen verarbeitet.")
                    await guides.refresh()
                case .backup:
                    let count = try await store.backup(to: url)
                    transferNotice = String(localized: "\(count) Projekte einschließlich Papierkorb gesichert.")
                case .restoreBackup:
                    let count = try await store.restoreBackup(from: url, thumbnail: Self.archiveThumbnail)
                    section = .library
                    transferNotice = String(localized: "\(count) Projekte wiederhergestellt. Vorhandene Projekte wurden beibehalten.")
                }
                await refreshLibrary(); return true
            } catch {
                importError = String(localized: "Die Dateiaktion konnte nicht abgeschlossen werden: \(error.localizedDescription)")
                await refreshLibrary(); return false
            }
        }
        transferTask = task
        return await task.value
    }
    nonisolated static func archiveImage(_ archive: ProjectArchive) throws -> CGImage {
        let document = try archive.validatedDocument()
        try EditorRenderer.validateAssets(document.objects)
        guard let source = CGImageSourceCreateWithData(archive.original as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              image.width == document.pixelSize.width, image.height == document.pixelSize.height else { throw ProjectError.invalidDocument }
        return image
    }
    nonisolated static func archiveThumbnail(_ archive: ProjectArchive) throws -> Data {
        let document = try archive.validatedDocument()
        return try EditorRenderer.thumbnail(image: archiveImage(archive), objects: document.objects, crop: document.crop, resizedSize: document.resizedSize, canvasRect: document.canvasRect, transform: document.transform, presentation: document.presentation)
    }
}

extension WorkspaceModel {
    func openExternalFile(_ url: URL) async {
        hasOpenedExternalFile = true; showsOnboarding = false
        if let metadataTask { _ = await metadataTask.value }
        if let librarySwitchTask { _ = await librarySwitchTask.value }
        if let openingTask { await openingTask.value }
        if let transferTask { _ = await transferTask.value }
        switch url.pathExtension.lowercased() {
        case "snaprivo": _ = await transfer(.importProject, at: url)
        case "snaprivobackup": _ = await transfer(.restoreBackup, at: url)
        case "snaprivoall": _ = await transfer(.restoreComplete, at: url)
        case "snaprivoguide":
            guard !isLoading else { return }
            await guides.importExternalCopy(url); section = .guides
        case "png", "jpg", "jpeg", "tif", "tiff", "heic":
            openImage(at: url)
            if let openingTask { await openingTask.value }
        default: importError = String(localized: "Dieser Dateityp wird nicht unterstützt.")
        }
    }
    func createGuide(from ids: [UUID]) {
        guard requirePro(.guides) else { return }
        guard !isLoading, !ids.isEmpty else { return }
        guides.createFromProjects(ids, from: store) { [weak self] in
            await self?.editor?.finishPendingWork() != false
        }
        section = .guides
    }
    func dismissQuickCapture(_ model: EditorModel) {
        guard let index = quickCaptures.firstIndex(where: { $0.document.id == model.document.id }) else { return }
        retainQuickCapturePendingWork(model)
        quickCaptures.remove(at: index)
        if selectedQuickCaptureID == model.document.id {
            selectedQuickCaptureID = quickCaptures.isEmpty ? nil : quickCaptures[min(index, quickCaptures.count - 1)].document.id
        }
        onQuickCaptureDismissed?()
    }
    func editQuickCapture(_ model: EditorModel? = nil) {
        guard !isLoading, let value = model ?? quickCapture else { return }
        isLoading = true
        openingTask = Task {
            defer { isLoading = false; openingTask = nil }
            guard await editor?.finishPendingWork() != false else { return }
            editor = value; dismissQuickCapture(value); section = .editor
            if let showWorkspaceWindow { showWorkspaceWindow() }
            else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" }) {
                NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
            }
        }
    }
    func discardQuickCapture(_ model: EditorModel? = nil) async {
        guard let value = model ?? quickCapture else { return }
        do {
            guard await value.finishPendingWork() else { return }
            try await store.moveToTrash(value.document.id)
            dismissQuickCapture(value); await refreshLibrary()
        } catch { importError = error.localizedDescription }
    }

}
