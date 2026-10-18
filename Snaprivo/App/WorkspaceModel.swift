import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers
import SnagForgeDomain

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
    var requestedProFeature: ProFeature?
    @ObservationIgnored var showPaywallWindow: (@MainActor () -> Void)?
    var showsPaywall = false
    var quickCapture: EditorModel?
    private(set) var hasOpenedExternalFile = false
    var showsOnboarding = false
    var libraryShowsVideos = false
    let storage: StorageLocations
    var captureConfiguration: CaptureConfiguration
    var pendingCapture: UUID?
    var isScrollCapture = false
    private(set) var store: ProjectStore
    private(set) var isChangingLibrary = false
    private(set) var isChoosingStorageFolder = false
    var storageError: String?
    var storageNotice: String?
    @ObservationIgnored private var storagePanel: NSOpenPanel?
    @ObservationIgnored private var librarySwitchTask: Task<Bool, Never>?
    var editor: EditorModel?
    private(set) var isChangingTrash = false
    private(set) var isUpdatingMetadata = false
    @ObservationIgnored private var metadataTask: Task<Bool, Never>?
    private(set) var isTransferring = false
    var transferNotice: String?
    @ObservationIgnored private var transferTask: Task<Bool, Never>?
    var isImporting = false
    var importError: String?
    var section: WorkspaceSection? = .library
    private(set) var items: [ProjectLibraryItem] = []
    private(set) var trashItems: [ProjectLibraryItem] = []
    private(set) var trashIssues: [String] = []
    private(set) var libraryIssues: [String] = []
    private(set) var isLoading = false
    private(set) var didLoadLibrary = false
    @ObservationIgnored private var openingTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
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
                self.quickCapture?.proAccessDidChange()
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
        await videos.refresh()
        guard storage.libraryError == nil else {
            libraryIssues = [storage.libraryError!]; didLoadLibrary = true; synchronizeSearch(); return
        }
        let currentStore = store
        do {
            let listing = try await currentStore.list()
            guard currentStore === store else { return }
            items = listing.items; libraryIssues = listing.issues
            let trash = try await currentStore.listTrash()
            guard currentStore === store else { return }
            trashItems = trash.items; trashIssues = trash.issues
        } catch {
            guard currentStore === store else { return }
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
    private func didSave() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshLibrary() }
    }
    func openScreenshot(_ captured: CGImage) {
        if let openingTask {
            Task { await openingTask.value; openScreenshot(captured) }
            return
        }
        openNew(title: String(localized: "Screenshot – ") + Date.now.formatted(date: .abbreviated, time: .standard), copyAfterOpen: preferences.copyAfterCapture, isScreenshot: true) { captured }
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
                let (image, document) = try await Task.detached(priority: .userInitiated) {
                    let image = try decode()
                    guard let size = PixelSize(width: image.width, height: image.height) else { throw ProjectError.invalidDocument }
                    let document = ProjectDocument(title: title, pixelSize: size)
                    let original = try EditorRenderer.png(image: image, objects: [])
                    let thumbnail = try? EditorRenderer.thumbnail(image: image, objects: [])
                    try await store.create(document, original: original, thumbnail: thumbnail)
                    return (image, document)
                }.value
                let newEditor = makeEditor(image: image, document: document, generation: 0)
                // Copy the new screenshot even if unsaved work prevents replacing the editor.
                if copyAfterOpen { copyCapture(newEditor) }
                // Keep a new capture even if the previous editor cannot currently be saved.
                let previousSaved = await previous?.finishPendingWork() != false
                if previousSaved && isScreenshot && preferences.quickPreviewAfterCapture {
                    quickCapture = newEditor
                } else if previousSaved {
                    editor = newEditor
                } else {
                    editor?.notice = String(localized: "Das neue Bild ist in der Bibliothek gesichert. Sichere zuerst die bisherigen Änderungen.")
                }
                if isScreenshot && !preferences.completedFirstCapture {
                    preferences.completedFirstCapture = true
                    if previousSaved { editor?.notice = String(localized: "Erste Aufnahme gesichert. Werkzeuge oben wählen, anschließend PNG speichern oder kopieren.") }
                }
                if quickCapture == nil { section = .editor }
                await refreshLibrary()
            } catch { importError = String(localized: "Das Projekt konnte nicht angelegt werden: \(error.localizedDescription)") }
        }
    }
    private func makeEditor(image: CGImage, document: ProjectDocument, generation: Int) -> EditorModel {
        let next = EditorModel(image: image, document: document, generation: generation, store: store,
                    automaticallyFitsImage: preferences.automaticallyFitsImage,
                    pngDirectory: { [storage] in storage.pngFolder }) { [weak self] in self?.didSave() }
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
    /// Creation order stays stable while an open image is edited or renamed.
    var editorQuickSwitchItems: [ProjectLibraryItem] {
        items.sorted {
            if $0.document.createdAt != $1.document.createdAt { return $0.document.createdAt > $1.document.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var canSwitchEditorImage: Bool {
        !isLoading && canSwitchEditorImageForToolbar
    }
    /// Loading blocks actions without dimming navigation that remains valid for the current image.
    var canSwitchEditorImageForToolbar: Bool {
        (!isLoading || editor?.isSwitchingImage == true)
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
        guard canSwitchEditorImage, items.contains(where: { $0.id == id }) else { return }
        openProject(id)
    }
    func switchEditorImage(by distance: Int) {
        guard let id = adjacentEditorImage(distance) else { return }
        switchEditorImage(to: id)
    }
    func openProject(_ id: UUID) {
        guard storage.libraryError == nil else { importError = storage.libraryError; return }
        guard !isLoading, !isUpdatingMetadata else { return }
        if editor?.document.id == id { section = .editor; return }
        let previous = suspendEditorForImageSwitch()
        isLoading = true
        openingTask = Task {
            defer { resumeEditorAfterImageSwitch(previous); isLoading = false; openingTask = nil }
            guard await previous?.finishPendingWork() != false else { return }
            do {
                let loaded = try await store.load(id)
                let image = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(loaded.original as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                          CGImageSourceGetStatus(source) == .statusComplete,
                          image.width == loaded.document.pixelSize.width, image.height == loaded.document.pixelSize.height else {
                        throw ProjectError.invalidDocument
                    }
                    return image
                }.value
                editor = makeEditor(image: image, document: loaded.document, generation: loaded.generation)
                if loaded.recovered { editor?.notice = String(localized: "Vorheriger Speicherstand wiederhergestellt") }
                section = .editor
            } catch { importError = error.localizedDescription }
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
        await screenshot.finishBeforeQuitting()
        guard await videos.finishPendingWork() else { return false }
        if let librarySwitchTask { _ = await librarySwitchTask.value }
        if let transferTask { _ = await transferTask.value }
        if let metadataTask, !(await metadataTask.value) { return false }
        if let openingTask { await openingTask.value }
        guard await guides.finishPendingWork() else { return false }
        return await editor?.finishPendingWork() ?? true
    }
    func addGuideProjects(_ ids: [UUID], replacing: UUID? = nil) {
        guard requirePro(.guides) else { return }
        guard !isLoading, storage.libraryError == nil else { return }
        guides.addProjects(ids, from: store, replacing: replacing) { [weak self] in
            guard let self else { return false }
            return await self.editor?.finishPendingWork() != false
        }
    }
}

enum WorkspaceSection: Hashable { case library, editor, guides }

extension WorkspaceModel {
    var canChangeStorage: Bool {
        !isLoading && !videos.isBusy && videos.preview == nil && !isUpdatingMetadata && !isChoosingStorageFolder && !screenshot.isBusy && !guides.isBusy && !guides.isSuspended
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
            if kind == .png { self.setPNGFolder(folder) }
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
                let grant = try storage.prepare(folder); prepared = grant
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
                    storage.commit(grant, for: .library); committed = true; store = replacement
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
                store = replacement; editor?.useProjectStore(replacement)
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
        return try EditorRenderer.thumbnail(image: archiveImage(archive), objects: document.objects, crop: document.crop, resizedSize: document.resizedSize)
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
    func editQuickCapture() {
        guard let value = quickCapture else { return }
        editor = value; quickCapture = nil; section = .editor
    }
    func discardQuickCapture() async {
        guard let value = quickCapture else { return }
        do { try await store.moveToTrash(value.document.id); quickCapture = nil; await refreshLibrary() }
        catch { importError = error.localizedDescription }
    }
}
