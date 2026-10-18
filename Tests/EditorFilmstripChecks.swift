import AppKit
import Carbon
import SwiftUI
import SnagForgeDomain

private actor FilmstripWriteGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0; started = true } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor enum EditorFilmstripChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Filmstrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Filmstrip-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        precondition(workspace.captureShortcuts.editorNavigationShortcut(-1) != nil)
        let bound = workspace.captureShortcuts.setShortcut(CaptureShortcut(keyCode: 123, modifiers: UInt32(cmdKey | optionKey)), for: .region)
        precondition(bound && workspace.captureShortcuts.editorNavigationShortcut(-1) == nil && workspace.captureShortcuts.editorNavigationShortcut(1) != nil)
        workspace.captureShortcuts.restoreDefaults()
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(srgbRed: 0.1, green: 0.4, blue: 0.8, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = context.makeImage()!, png = try EditorRenderer.png(image: image, objects: [])
        let older = ProjectDocument(title: "Older image", pixelSize: PixelSize(width: 32, height: 24)!, createdAt: Date(timeIntervalSince1970: 10))
        let newer = ProjectDocument(title: "Newer image", pixelSize: older.pixelSize, createdAt: Date(timeIntervalSince1970: 20))
        func waitForOpen() async throws {
            for _ in 0..<1000 { if !workspace.isLoading { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Image switch timed out")
        }
        await workspace.refreshLibrary()
        precondition(workspace.editorQuickSwitchItems.isEmpty && workspace.adjacentEditorImage(1) == nil)
        try await workspace.store.create(older, original: png, thumbnail: png)
        try await workspace.store.create(newer, original: png, thumbnail: png)
        await workspace.refreshLibrary()
        workspace.preferences.favoritesOnly = true; workspace.preferences.librarySort = .nameAscending
        precondition(workspace.editorQuickSwitchItems.map(\.id) == [newer.id, older.id], "Library filters affected editor navigation")
        workspace.switchEditorImage(to: newer.id); try await waitForOpen()
        precondition(workspace.section == .editor && workspace.editor!.document.id == newer.id)
        workspace.editor!.tool = .arrow
        workspace.editor!.defaultColor = EditorColor(red: 0.2, green: 0.4, blue: 0.8)
        workspace.editor!.defaultArrowLineWidth = 23
        precondition(workspace.adjacentEditorImage(-1) == nil && workspace.adjacentEditorImage(1) == older.id)
        // Pending inline text must be committed and saved even before its debounce expires.
        workspace.editor!.editText(at: CGPoint(x: 4, y: 4)); workspace.editor!.updateText("Pending filmstrip text")
        workspace.switchEditorImage(by: 1); try await waitForOpen()
        precondition(workspace.editor!.document.id == older.id)
        precondition(workspace.editor!.tool == .arrow && workspace.editor!.defaultArrowLineWidth == 23 && workspace.editor!.defaultColor == EditorColor(red: 0.2, green: 0.4, blue: 0.8))
        let saved = try await workspace.store.load(newer.id)
        precondition(saved.document.objects.last?.text == "Pending filmstrip text")
        precondition(workspace.adjacentEditorImage(-1) == newer.id && workspace.adjacentEditorImage(1) == nil)
        precondition(workspace.adjacentEditorImage(Int.max) == nil)
        // Live gestures, unconfirmed crop and modal editor tools must retain their draft.
        let editor = workspace.editor!
        editor.isCanvasGestureActive = true; workspace.switchEditorImage(to: newer.id)
        precondition(workspace.editor === editor && !workspace.isLoading)
        precondition(!workspace.canSwitchEditorImageForToolbar)
        editor.isCanvasGestureActive = false; editor.beginCrop()
        let draft = editor.cropDraft
        workspace.switchEditorImage(to: newer.id)
        precondition(editor.cropDraft == draft && workspace.editor === editor && !workspace.isLoading)
        precondition(!workspace.canSwitchEditorImageForToolbar)
        editor.cancelCrop(); editor.isShowingImageSize = true; workspace.switchEditorImage(to: newer.id)
        precondition(!workspace.isLoading); editor.isShowingImageSize = false
        editor.isShowingTextRecognition = true; workspace.switchEditorImage(to: newer.id)
        precondition(!workspace.isLoading); editor.isShowingTextRecognition = false
        workspace.guides.isSuspended = true; workspace.switchEditorImage(to: newer.id)
        precondition(!workspace.isLoading); workspace.guides.isSuspended = false
        workspace.switchEditorImage(to: UUID()); precondition(!workspace.isLoading)

        // A started PNG export keeps its owner until it completes, then switches images.
        let gate = FilmstripWriteGate()
        workspace.editor = EditorModel(image: image, document: older, generation: 0, store: workspace.store,
            writePNG: { data, url in await gate.pause(); try await EditorModel.writePNGData(data, to: url) }, onSaved: {})
        let exporting = workspace.editor!, output = root.appendingPathComponent("Pending.png")
        precondition(exporting.exportPNG(to: output))
        for _ in 0..<500 { if await gate.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        // Render the production strip while a held export makes the loading state observable.
        let strip = NSHostingView(rootView: EditorFilmstripView(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 128),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = strip
        defer { window.close() }
        func renderedStrip() -> NSBitmapImageRep {
            strip.layoutSubtreeIfNeeded()
            let bitmap = strip.bitmapImageRepForCachingDisplay(in: strip.bounds)!
            strip.cacheDisplay(in: strip.bounds, to: bitmap)
            return bitmap
        }
        func navigationPixels() -> Data {
            let bitmap = renderedStrip()
            let scale = CGFloat(bitmap.pixelsWide) / strip.bounds.width
            let header = bitmap.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: Int(24 * scale)))!
            return NSBitmapImageRep(cgImage: header).representation(using: .png, properties: [:])!
        }
        func thumbnailPixels() -> [[CGFloat]] {
            let bitmap = renderedStrip()
            let scale = CGFloat(bitmap.pixelsWide) / strip.bounds.width
            return [72, 200].map { x in
                let color = bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(60 * scale))!.usingColorSpace(.deviceRGB)!
                return [color.redComponent, color.greenComponent, color.blueComponent]
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        let enabledPixels = thumbnailPixels()
        let enabledNavigation = navigationPixels()
        precondition(enabledPixels.allSatisfy { $0[2] > 0.7 && $0[0] < 0.4 }, "Expected decoded synthetic blue thumbnails")
        workspace.switchEditorImage(to: newer.id)
        try await Task.sleep(for: .milliseconds(50))
        precondition(workspace.isLoading && workspace.editor === exporting)
        precondition(thumbnailPixels() == enabledPixels, "Disabling navigation changed every thumbnail's brightness")
        precondition(navigationPixels() == enabledNavigation, "Loading dimmed the previous/next buttons")
        precondition(workspace.canSwitchEditorImageForToolbar && !workspace.canSwitchEditorImage)
        precondition(exporting.isSwitchingImage && exporting.hasConfirmedImageForToolbar && !exporting.hasExportableImage)
        let waitingRevision = exporting.document.revision
        exporting.commit([EditorObject(kind: .text, start: .zero, text: "Late input must not change the outgoing image")])
        exporting.beginCrop(); exporting.editText(at: .zero); exporting.undo()
        precondition(exporting.document.revision == waitingRevision && exporting.cropDraft == nil && exporting.editingTextObject == nil)
        workspace.switchEditorImage(to: older.id) // Duplicate clicks while loading are ignored.
        workspace.switchEditorImage(by: -1) // Keyboard/accessibility actions are guarded as well.
        await gate.release(); try await waitForOpen()
        precondition(workspace.editor!.document.id == newer.id && FileManager.default.fileExists(atPath: output.path))
        precondition(!exporting.isSwitchingImage && !workspace.editor!.isSwitchingImage)
        try await Task.sleep(for: .milliseconds(50))
        precondition(thumbnailPixels() == enabledPixels, "Finishing navigation changed the thumbnail pixels")
        await workspace.refreshLibrary()
        precondition(workspace.editorQuickSwitchItems.map(\.id) == [newer.id, older.id], "Saving moved a thumbnail under the pointer")

        // A competing writer must leave the old editor and local changes selected.
        workspace.editor!.commit([EditorObject(kind: .text, start: .zero, text: "My local edit")])
        try await ProjectStore(root: root).updateMetadata(newer.id, title: "Saved elsewhere")
        let conflicted = workspace.editor!
        workspace.switchEditorImage(to: older.id); try await waitForOpen()
        precondition(workspace.editor === conflicted && conflicted.isDirty && conflicted.saveError != nil)
        precondition(!conflicted.isSwitchingImage, "A failed switch left the old image frozen")
        precondition(conflicted.document.objects.last?.text == "My local edit")
        // Once explicitly saved as a copy, navigation and the new thumbnail are available.
        let copied = await conflicted.saveCopy(); precondition(copied)
        await workspace.refreshLibrary()
        precondition(workspace.editorQuickSwitchItems.contains { $0.id == conflicted.document.id })
        workspace.switchEditorImage(to: older.id); try await waitForOpen()
        precondition(workspace.editor!.document.id == older.id)
        let trashed = await workspace.changeTrash(newer.id, action: .trash); precondition(trashed)
        precondition(!workspace.editorQuickSwitchItems.contains { $0.id == newer.id })
        workspace.switchEditorImage(to: newer.id); precondition(workspace.editor!.document.id == older.id && !workspace.isLoading)
        // Equal creation dates still have a deterministic order after a fresh store listing.
        let twin = ProjectDocument(title: "Equal age", pixelSize: older.pixelSize, createdAt: older.createdAt)
        try await workspace.store.create(twin, original: png, thumbnail: png)
        await workspace.refreshLibrary()
        precondition(workspace.editorQuickSwitchItems.filter { $0.document.createdAt == older.createdAt }.map(\.id) == [older.id, twin.id].sorted { $0.uuidString < $1.uuidString })
        let initialOrder = workspace.editorQuickSwitchItems.map(\.id)
        await workspace.refreshLibrary(); precondition(workspace.editorQuickSwitchItems.map(\.id) == initialOrder)
        print("Editor filmstrip checks passed: stable creation order, filter independence, pending text/autosave/export, unchanged rendered thumbnail pixels during/after loading, outgoing-input freeze with visible canvas, retained tool settings, bounds, draft guards, competing-writer recovery, saved copies and trash exclusion.")
    }
}
