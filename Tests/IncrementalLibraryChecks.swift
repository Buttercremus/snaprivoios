import AppKit
import SnagForgeDomain

@MainActor enum IncrementalLibraryChecks {
    static func run() async throws {
        try await checkNewImages()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IncrementalLibrary-\(UUID())")
        let suite = "IncrementalLibrary-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let png = try EditorRenderer.png(image: context.makeImage()!, objects: [])
        let edited = ProjectDocument(title: "Edited", pixelSize: PixelSize(width: 20, height: 20)!)
        let untouched = ProjectDocument(title: "Untouched", pixelSize: edited.pixelSize)
        let trashed = ProjectDocument(title: "Trash", pixelSize: edited.pixelSize)
        for document in [edited, untouched, trashed] { try await workspace.store.create(document, original: png, thumbnail: png) }
        try await workspace.store.moveToTrash(trashed.id)
        await workspace.refreshLibrary()
        workspace.openProject(edited.id)
        for _ in 0..<500 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let editor = workspace.editor!
        let otherManifest = root.appendingPathComponent("\(untouched.id).snagforge/manifest.json")
        let manifestBytes = try Data(contentsOf: otherManifest)
        try Data("Broken unrelated package".utf8).write(to: otherManifest)
        let videoMetadata = root.appendingPathComponent(".Videos/.library")
        try FileManager.default.createDirectory(at: videoMetadata, withIntermediateDirectories: true)
        let brokenVideo = videoMetadata.appendingPathComponent("\(UUID()).json")
        try Data("Broken unrelated video".utf8).write(to: brokenVideo)
        var object = EditorObject(kind: .text, start: .zero, text: "First saved snapshot")
        editor.commit([object])
        let saved = await editor.flush(); precondition(saved)
        precondition(workspace.items.first { $0.id == edited.id }?.document == editor.document, "Save callback lagged behind flush")
        precondition(workspace.items.first { $0.id == edited.id }?.thumbnail != nil)
        precondition(workspace.items.first { $0.id == untouched.id }?.document == untouched, "Autosave reread an unrelated package")
        precondition(workspace.trashItems.map(\.id) == [trashed.id] && workspace.trashIssues.isEmpty)
        precondition(workspace.videos.issues.isEmpty && workspace.libraryIssues.isEmpty, "Autosave rescanned video/other metadata")
        // An explicit full refresh still discovers external changes and damage.
        await workspace.refreshLibrary()
        precondition(workspace.libraryIssues.count == 1 && workspace.videos.issues.count == 1)
        try manifestBytes.write(to: otherManifest); try FileManager.default.removeItem(at: brokenVideo)
        await workspace.refreshLibrary()
        precondition(workspace.items.count == 2 && workspace.libraryIssues.isEmpty && workspace.videos.issues.isEmpty)

        for index in 0..<8 {
            let scan = Task { await workspace.refreshLibrary() }
            await Task.yield()
            object.text = "Snapshot \(index)"; editor.commit([object])
            let committed = await editor.flush(); precondition(committed)
            await scan.value
            precondition(workspace.items.first { $0.id == edited.id }?.document == editor.document, "Full refresh replaced a newer committed save")
        }
        // A competing writer rejects the local save; a conflict copy gets its own entry.
        try await ProjectStore(root: root).updateMetadata(edited.id, title: "External change")
        let lastCommitted = workspace.items.first { $0.id == edited.id }!.document
        object.text = "Unsaved conflict"; editor.commit([object])
        let rejected = await editor.flush(); precondition(!rejected)
        precondition(workspace.items.first { $0.id == edited.id }?.document == lastCommitted, "Failed save published an unsaved revision")
        let copied = await editor.saveCopy(); precondition(copied)
        precondition(editor.document.id != edited.id)
        precondition(workspace.items.count == 3 && workspace.items.first { $0.id == editor.document.id }?.document == editor.document)
        print("Incremental library checks passed: immediate saved snapshot/thumbnail, untouched projects/trash/videos, explicit damage discovery, concurrent full refresh, failed-save isolation and new conflict-copy identity.")
    }

    private static func checkNewImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NewImages-\(UUID())")
        let suite = "NewImages-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let library = root.appendingPathComponent("library")
        let workspace = WorkspaceModel(root: library, defaults: defaults)
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!, png = try EditorRenderer.png(image: image, objects: [])
        let existing = ProjectDocument(title: "Untouched", pixelSize: PixelSize(width: 32, height: 24)!)
        try await workspace.store.create(existing, original: png, thumbnail: png)
        // A capture before the first listing must still discover existing projects.
        func waitForOpen() async throws {
            for _ in 0..<1000 {
                if !workspace.isLoading { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            preconditionFailure("New image did not finish opening")
        }
        workspace.openScreenshot(image); try await waitForOpen()
        await workspace.refreshLibrary()
        precondition(workspace.items.count == 2 && workspace.importError == nil)
        let previous = workspace.editor!
        previous.editText(at: CGPoint(x: 3, y: 3)); previous.updateText("Pending text")
        let unrelatedManifest = library.appendingPathComponent("\(existing.id).snagforge/manifest.json")
        let manifest = try Data(contentsOf: unrelatedManifest)
        try Data("Unrelated damage".utf8).write(to: unrelatedManifest)
        workspace.openScreenshot(image); try await waitForOpen()
        let captured = workspace.editor!
        precondition(captured !== previous && !previous.isDirty && !previous.isSwitchingImage)
        let savedPrevious = try await workspace.store.load(previous.document.id)
        precondition(savedPrevious.document.objects.last?.text == "Pending text", "Opening lost pending inline text")
        let savedCapture = try await workspace.store.load(captured.document.id)
        precondition(savedCapture.original == png && workspace.items.first { $0.id == captured.document.id }?.thumbnail != nil)
        precondition(workspace.items.count == 3 && workspace.libraryIssues.isEmpty, "Capture rescanned an unrelated project")
        workspace.preferences.quickPreviewAfterCapture = true
        workspace.openScreenshot(image); try await waitForOpen()
        precondition(workspace.quickCapture != nil && workspace.editor === captured && workspace.items.count == 4)
        workspace.quickCapture = nil; workspace.preferences.quickPreviewAfterCapture = false
        let imported = root.appendingPathComponent("synthetic.png"); try png.write(to: imported)
        workspace.openImage(at: imported); try await waitForOpen()
        precondition(workspace.items.count == 5 && workspace.libraryIssues.isEmpty && workspace.importError == nil)
        try manifest.write(to: unrelatedManifest)
        let scan = Task { await workspace.refreshLibrary() }
        workspace.openScreenshot(image); try await waitForOpen(); await scan.value
        precondition(workspace.items.count == 6 && workspace.items.contains { $0.id == workspace.editor?.document.id })
        // An initial write failure must never publish an uncommitted item/editor.
        let retained = workspace.editor!, preserved = root.appendingPathComponent("preserved")
        try FileManager.default.moveItem(at: library, to: preserved)
        try Data("Blocked library".utf8).write(to: library)
        workspace.openScreenshot(image); try await waitForOpen()
        precondition(workspace.importError != nil && workspace.editor === retained && workspace.items.count == 6)
        try FileManager.default.removeItem(at: library)
        try FileManager.default.moveItem(at: preserved, to: library)
        print("New-image checks passed: initial discovery, pending-text save, persisted original/thumbnail, no full capture/import scan, quick preview, concurrent scan and failed-create isolation.")
    }
}
