import AppKit
import SnagForgeDomain

@main struct LibraryChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--opening-benchmark") {
            try await ScreenshotOpeningBenchmark.run(); return
        }
        if CommandLine.arguments.contains("--incremental-only") {
            try await IncrementalLibraryChecks.run(); return
        }
        if CommandLine.arguments.contains("--search-only") {
            try await LibrarySearchChecks.run(); return
        }
        if CommandLine.arguments.contains("--filmstrip-only") {
            try await EditorFilmstripChecks.run(); return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Library-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Library-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!, png = try EditorRenderer.png(image: image, objects: [])
        let a = ProjectDocument(title: "Image 10", pixelSize: PixelSize(width: 20, height: 20)!, modifiedAt: Date(timeIntervalSince1970: 20))
        let b = ProjectDocument(title: "Image 2", pixelSize: a.pixelSize, modifiedAt: Date(timeIntervalSince1970: 10))
        try await workspace.store.create(a, original: png, thumbnail: png)
        try await workspace.store.create(b, original: png, thumbnail: png)
        await workspace.refreshLibrary()
        precondition(LibrarySort.nameAscending.ordered(workspace.items).map(\.id) == [b.id, a.id])
        precondition(LibrarySort.nameDescending.ordered(workspace.items).map(\.id) == [a.id, b.id])
        precondition(LibrarySort.modifiedNewest.ordered(workspace.items).map(\.id) == [a.id, b.id])
        precondition(LibrarySort.modifiedOldest.ordered(workspace.items).map(\.id) == [b.id, a.id])
        workspace.preferences.librarySort = .nameDescending; workspace.preferences.favoritesOnly = true
        let renamed = await workspace.updateProjectMetadata(b.id, title: "Renamed", favorite: true); precondition(renamed)
        workspace.openProject(a.id)
        for _ in 0..<500 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let editor = workspace.editor!
        var object = EditorObject(kind: .text, start: .zero, text: "Autosave")
        editor.commit([object])
        let updated = await workspace.updateProjectMetadata(a.id, title: "Open editor", favorite: true); precondition(updated)
        object.text = "After rename"; editor.commit([object])
        let flushed = await workspace.flushBeforeQuitting(); precondition(flushed)
        let fresh = WorkspaceModel(root: root, defaults: UserDefaults(suiteName: suite)!)
        await fresh.refreshLibrary()
        precondition(fresh.preferences.librarySort == .nameDescending && fresh.preferences.favoritesOnly)
        precondition(fresh.items.count == 2 && fresh.items.allSatisfy { $0.document.isFavorite })
        let restored = try await fresh.store.load(a.id)
        precondition(restored.document.title == "Open editor" && restored.document.objects == [object] && restored.original == png)
        editor.undo(); precondition(editor.name == "Open editor" && editor.document.isFavorite)
        let saved = await editor.flush(); precondition(saved)
        let removed = await fresh.updateProjectMetadata(b.id, favorite: false); precondition(removed)
        let again = try await fresh.store.load(b.id); precondition(!again.document.isFavorite && again.document.title == "Renamed")
        try await IncrementalLibraryChecks.run()
        try await LibrarySearchChecks.run()
        try await LibraryEntryChecks.run()
        try await EditorFilmstripChecks.run()
        print("Library checks passed: four sorts, natural names, closed/open project metadata, pending autosave, object undo isolation, preferences and projects after fresh workspace/store, favorite removal.")
    }
}
