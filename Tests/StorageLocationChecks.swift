import AppKit
import SnagForgeDomain

@MainActor private final class TestFolderBookmarks {
    var accesses: [URL: Int] = [:]
    var denied = false
    var stale = false
    var creationFails = false
    var creations = 0
    var client: FolderBookmarkClient {
        FolderBookmarkClient(create: { [self] url in
            creations += 1
            if creationFails { throw CocoaError(.fileWriteNoPermission) }
            return Data(url.path.utf8)
        }, resolve: { [self] data in
            guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/") else { throw CocoaError(.fileReadCorruptFile) }
            return .init(url: URL(fileURLWithPath: path, isDirectory: true), stale: stale)
        }, start: { [self] url in
            guard !denied else { return false }
            accesses[url, default: 0] += 1; return true
        }, stop: { [self] url in
            precondition(accesses[url, default: 0] > 0, "Unbalanced security-scoped access")
            accesses[url, default: 0] -= 1
        })
    }
    func assertReleased() { precondition(accesses.values.allSatisfy { $0 == 0 }) }
}

@MainActor enum StorageLocationChecks {
    static func run() async throws {
        try checkAppearance()
        try checkBookmarkLifecycle()
        try await checkLibrarySwitchAndRestart()
        print("Storage checks passed: System/Hell/Dunkel and restart, PNG save-panel directory, balanced/stale/denied bookmarks, transactional library copy with trash, open-editor Undo after relocation, restart and unavailable-folder recovery.")
    }
    private static func checkAppearance() throws {
        let suite = "Snaprivo-Appearance-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let original = NSApp.appearance
        defer { defaults.removePersistentDomain(forName: suite); NSApp.appearance = original }
        let preferences = AppPreferences(defaults: defaults)
        precondition(preferences.appearance == .system)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 80), styleMask: .titled, backing: .buffered, defer: false)
        for mode in AppAppearance.allCases {
            preferences.appearance = mode
            let restored = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
            precondition(restored.appearance == mode)
            restored.applyAppearance()
            if mode == .system { precondition(NSApp.appearance == nil) }
            else { precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (mode == .light ? .aqua : .darkAqua)) }
        }
        defaults.set("unknown", forKey: "app.appearance")
        precondition(AppPreferences(defaults: defaults).appearance == .system)
    }
    private static func checkBookmarkLifecycle() throws {
        let suite = "Snaprivo-Bookmarks-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Bookmarks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let probe = TestFolderBookmarks(), locations = StorageLocations(defaults: defaults, client: probe.client)
        locations.commit(try locations.prepare(root), for: .png)
        precondition(locations.pngFolder == root && probe.accesses[root] == 1)
        locations.endAccess(); probe.assertReleased()
        probe.stale = true
        let count = probe.creations
        let restored = StorageLocations(defaults: defaults, client: probe.client)
        precondition(restored.pngFolder == root && probe.creations == count + 1)
        restored.clearPNGFolder(); probe.assertReleased()
        precondition(defaults.data(forKey: "storage.png.bookmark") == nil && defaults.string(forKey: "storage.png.path") == nil)
        defaults.set(Data(root.path.utf8), forKey: "storage.png.bookmark")
        probe.creationFails = true
        let failedRenewal = StorageLocations(defaults: defaults, client: probe.client)
        precondition(failedRenewal.pngFolder == nil && failedRenewal.errors[.png] != nil)
        probe.assertReleased()
        probe.creationFails = false; probe.denied = true
        let denied = StorageLocations(defaults: defaults, client: probe.client)
        precondition(denied.pngFolder == nil && denied.errors[.png] != nil)
        do { _ = try denied.prepare(root); preconditionFailure("Denied bookmark accepted") } catch { }
        probe.assertReleased()
        probe.denied = false
        defaults.set(Data("invalid".utf8), forKey: "storage.png.bookmark")
        let invalid = StorageLocations(defaults: defaults, client: probe.client)
        precondition(invalid.pngFolder == nil && invalid.errors[.png] != nil)
        precondition(defaults.data(forKey: "storage.png.bookmark") == Data("invalid".utf8))
        invalid.endAccess(); failedRenewal.endAccess(); denied.endAccess(); probe.assertReleased()
        defaults.set(root.path, forKey: "storage.library.path")
        defaults.set("wrong stored type", forKey: "storage.library.bookmark")
        let brokenLibrary = StorageLocations(defaults: defaults, client: probe.client)
        precondition(brokenLibrary.libraryError != nil && brokenLibrary.libraryURL == nil)
        precondition(!FileManager.default.fileExists(atPath: StorageLocations.libraryURL(in: root).path))
        brokenLibrary.endAccess(); probe.assertReleased()
    }
    private static func checkLibrarySwitchAndRestart() async throws {
        let suite = "Snaprivo-Locations-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Locations-\(UUID())", isDirectory: true)
        let oldRoot = base.appendingPathComponent("old"), chosen = base.appendingPathComponent("chosen", isDirectory: true)
        let pngFolder = base.appendingPathComponent("png", isDirectory: true)
        for folder in [chosen, pngFolder] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: base) }
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.orange.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        let source = ProjectStore(root: oldRoot)
        var initial = ProjectDocument(title: "Synthetic active", pixelSize: PixelSize(width: 100, height: 80)!)
        initial.isFavorite = true
        initial.crop = CGRect(x: 10, y: 10, width: 80, height: 60)
        initial.resizedSize = PixelSize(width: 160, height: 120)!
        try await source.create(initial, original: original, thumbnail: nil)
        let deleted = ProjectDocument(title: "Synthetic trash", pixelSize: initial.pixelSize)
        try await source.create(deleted, original: original, thumbnail: nil)
        try await source.moveToTrash(deleted.id)
        let probe = TestFolderBookmarks()
        let workspace = WorkspaceModel(root: oldRoot, defaults: defaults, bookmarkClient: probe.client)
        defer { workspace.storage.endAccess() }
        await workspace.refreshLibrary()
        workspace.openProject(initial.id); try await waitForOpening(workspace)
        let editor = workspace.editor!
        let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40))
        editor.commit([shape]); editor.selection = shape.id
        editor.viewportBounds = CGRect(x: 0, y: 0, width: 800, height: 600); editor.setZoom(2)
        precondition(workspace.setPNGFolder(pngFolder))
        precondition(editor.makePNGExportPanel().directoryURL?.standardizedFileURL == pngFolder.standardizedFileURL)
        let pngBookmark = defaults.data(forKey: "storage.png.bookmark")
        precondition(!workspace.setPNGFolder(base.appendingPathComponent("missing")))
        precondition(workspace.storage.pngFolder == pngFolder && defaults.data(forKey: "storage.png.bookmark") == pngBookmark)
        workspace.storageError = nil
        editor.isCanvasGestureActive = true
        let refusedDuringGesture = await workspace.changeLibraryFolder(chosen)
        precondition(!refusedDuringGesture && workspace.store.root == oldRoot)
        editor.isCanvasGestureActive = false
        let switched = await workspace.changeLibraryFolder(chosen)
        precondition(switched && workspace.storageError == nil && workspace.editor === editor)
        let target = StorageLocations.libraryURL(in: chosen)
        precondition(workspace.store.root == target && editor.selection == shape.id && editor.viewport.zoom == 2)
        precondition(workspace.items.count == 1 && workspace.trashItems.map(\.id) == [deleted.id])
        let oldSaved = try await source.load(initial.id)
        let copied = try await workspace.store.load(initial.id)
        precondition(copied.document == oldSaved.document && copied.original == original && copied.document.isFavorite)
        precondition(FileManager.default.fileExists(atPath: oldRoot.appendingPathComponent("\(initial.id.uuidString).snagforge/Revisions/0.json").path))
        editor.undo(); let undoSaved = await editor.finishPendingWork(); precondition(undoSaved)
        let newAfterUndo = try await workspace.store.load(initial.id), oldAfterUndo = try await source.load(initial.id)
        precondition(newAfterUndo.document.objects.isEmpty && oldAfterUndo.document.objects == [shape])
        // Existing destination is rejected without changing preferences, data or the live editor.
        let occupied = base.appendingPathComponent("occupied", isDirectory: true)
        try FileManager.default.createDirectory(at: StorageLocations.libraryURL(in: occupied), withIntermediateDirectories: true)
        let priorBookmark = defaults.data(forKey: "storage.library.bookmark")
        let rejected = await workspace.changeLibraryFolder(occupied)
        precondition(!rejected && workspace.storageError != nil && workspace.store.root == target && workspace.editor === editor)
        precondition(defaults.data(forKey: "storage.library.bookmark") == priorBookmark)
        workspace.storageError = nil
        let flushed = await workspace.flushBeforeQuitting(); precondition(flushed)
        workspace.storage.endAccess(); probe.assertReleased()
        let restart = WorkspaceModel(root: base.appendingPathComponent("unused-fallback"), defaults: defaults, bookmarkClient: probe.client)
        defer { restart.storage.endAccess() }
        await restart.refreshLibrary()
        precondition(restart.store.root == target && restart.items.count == 1 && restart.trashItems.count == 1)
        precondition(restart.storage.pngFolder == pngFolder)
        restart.openScreenshot(image); try await waitForOpening(restart)
        precondition(restart.items.count == 2 && restart.importError == nil)
        let restartSaved = await restart.flushBeforeQuitting(); precondition(restartSaved)
        restart.storage.endAccess(); probe.assertReleased()
        // A revoked saved library never creates projects in an invisible default library.
        probe.denied = true
        let fallback = base.appendingPathComponent("never-created")
        let unavailable = WorkspaceModel(root: fallback, defaults: defaults, bookmarkClient: probe.client)
        defer { unavailable.storage.endAccess() }
        await unavailable.refreshLibrary()
        unavailable.openScreenshot(image)
        precondition(unavailable.storage.libraryError != nil && unavailable.importError != nil && unavailable.editor == nil)
        precondition(!FileManager.default.fileExists(atPath: fallback.path))
        probe.denied = false
        let wrong = await unavailable.changeLibraryFolder(pngFolder)
        precondition(!wrong && unavailable.storage.libraryError != nil)
        let reauthorized = await unavailable.changeLibraryFolder(chosen)
        precondition(reauthorized && unavailable.storage.libraryError == nil && unavailable.store.root == target && unavailable.items.count == 2)
        unavailable.storage.endAccess(); probe.assertReleased()
    }
    private static func waitForOpening(_ workspace: WorkspaceModel) async throws {
        for _ in 0..<1000 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!workspace.isLoading && workspace.importError == nil)
    }
}
