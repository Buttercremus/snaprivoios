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

private actor FilmstripOneShotGate {
    private var consumed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func pauseOnce() async {
        guard !consumed else { return }
        consumed = true
        await withCheckedContinuation { continuation = $0; started = true }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor FilmstripCopyFinishBox {
    private var result: Bool?
    func set(_ result: Bool) { self.result = result }
    func read() -> Bool? { result }
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
        let now = Date.now
        let older = ProjectDocument(title: "Older image", pixelSize: PixelSize(width: 32, height: 24)!, createdAt: now.addingTimeInterval(-60))
        let newer = ProjectDocument(title: "Newer image", pixelSize: older.pixelSize, createdAt: now)
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
        let reselected = workspace.editor!, focusBeforeReselect = reselected.focusRequest
        workspace.switchEditorImage(to: newer.id)
        precondition(workspace.editor === reselected && !workspace.isLoading && reselected.focusRequest > focusBeforeReselect,
                     "Clicking the active thumbnail did not return focus to the editor")
        precondition(reselected.editingTextObject == nil && reselected.history.objects.last?.text == "Pending filmstrip text",
                     "Reselecting the current image left its inline text session open")
        reselected.editText(at: CGPoint(x: 4, y: 4), object: reselected.history.objects.last)
        reselected.updateText("Pending text after reselect")
        workspace.switchEditorImage(by: 1); try await waitForOpen()
        precondition(workspace.editor!.document.id == older.id)
        precondition(workspace.editor!.tool == .arrow && workspace.editor!.defaultArrowLineWidth == 23 && workspace.editor!.defaultColor == EditorColor(red: 0.2, green: 0.4, blue: 0.8))
        let saved = try await workspace.store.load(newer.id)
        precondition(saved.document.objects.last?.text == "Pending text after reselect")
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 138),
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
            let header = bitmap.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: Int(32 * scale)))!
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
        workspace.section = .library
        workspace.preferences.completedOnboarding = true
        let workspaceHost = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        let workspaceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.borderless], backing: .buffered, defer: false)
        workspaceWindow.isReleasedWhenClosed = false; workspaceWindow.contentView = workspaceHost
        defer { workspaceWindow.close() }
        func sidebarPixels() -> Data {
            workspaceHost.layoutSubtreeIfNeeded()
            let bitmap = workspaceHost.bitmapImageRepForCachingDisplay(in: workspaceHost.bounds)!
            workspaceHost.cacheDisplay(in: workspaceHost.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / workspaceHost.bounds.width
            let sidebar = bitmap.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: Int(180 * scale), height: Int(600 * scale)))!
            return NSBitmapImageRep(cgImage: sidebar).representation(using: .png, properties: [:])!
        }
        try await Task.sleep(for: .milliseconds(200))
        let enabledSidebar = sidebarPixels()
        workspace.switchEditorImage(to: newer.id)
        try await Task.sleep(for: .milliseconds(50))
        precondition(workspace.isLoading && workspace.editor === exporting)
        precondition(workspace.openingProjectID == newer.id && workspace.section == .library,
                     "Library was replaced before the target and outgoing export were ready")
        precondition(thumbnailPixels() == enabledPixels, "Disabling navigation changed every thumbnail's brightness")
        precondition(navigationPixels() == enabledNavigation, "Loading dimmed the previous/next buttons")
        precondition(sidebarPixels() == enabledSidebar, "Switching images flashed the sidebar quick-action labels")
        precondition(workspace.canSwitchEditorImageForToolbar && !workspace.canSwitchEditorImage)
        precondition(exporting.isSwitchingImage && exporting.hasConfirmedImageForToolbar && !exporting.hasExportableImage)
        let waitingRevision = exporting.document.revision
        exporting.commit([EditorObject(kind: .text, start: .zero, text: "Late input must not change the outgoing image")])
        exporting.beginCrop(); exporting.editText(at: .zero); exporting.undo()
        precondition(exporting.document.revision == waitingRevision && exporting.cropDraft == nil && exporting.editingTextObject == nil)
        workspace.switchEditorImage(to: older.id) // Duplicate clicks while loading are ignored.
        workspace.switchEditorImage(by: -1) // Keyboard/accessibility actions are guarded as well.
        await workspace.trashEditorImage(older.id)
        precondition(workspace.trashItems.isEmpty, "Removing an image bypassed the loading guard")
        await gate.release(); try await waitForOpen()
        precondition(workspace.editor!.document.id == newer.id && FileManager.default.fileExists(atPath: output.path))
        precondition(!exporting.isSwitchingImage && !workspace.editor!.isSwitchingImage)
        precondition(workspace.openingProjectID == nil && workspace.section == .editor, "Completed open retained its loading target")
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
        precondition(!conflicted.isSwitchingImage && workspace.openingProjectID == nil, "A failed switch left the old image frozen or busy")
        precondition(conflicted.document.objects.last?.text == "My local edit")
        await workspace.trashEditorImage(newer.id)
        precondition(workspace.editor === conflicted && !workspace.trashItems.contains { $0.id == newer.id }, "Direct trash discarded changes after a save conflict")
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
        let retained = workspace.editor
        workspace.section = .library
        workspace.openProject(UUID()); try await waitForOpen()
        precondition(workspace.editor === retained && workspace.section == .library && workspace.openingProjectID == nil && workspace.importError != nil,
                     "A missing project replaced the library/editor or left loading active")
        workspace.importError = nil
        try await checkRecentImagesAndTrash(png: png, image: image)
        try await checkMultiSelectionAndNativeCopy(png: png)
        print("Editor filmstrip checks passed: seven-day boundary, stable creation order and scrolling, filter independence, pending text/autosave/export, unchanged rendered thumbnail pixels during/after loading, outgoing-input freeze with visible canvas, retained tool settings, bounds, draft guards, competing-writer recovery, saved copies, direct recoverable trash, native multi-selection and multi-file clipboard export.")
    }

    private static func checkStableSelectionLayout(workspace: WorkspaceModel) async throws {
        let strip = NSHostingView(rootView: EditorFilmstripView(workspace: workspace))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 138), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = strip
        defer { window.close() }
        func thumbnailBand() -> [Int] {
            strip.layoutSubtreeIfNeeded()
            let bitmap = strip.bitmapImageRepForCachingDisplay(in: strip.bounds)!
            strip.cacheDisplay(in: strip.bounds, to: bitmap)
            let x = Int(70 * CGFloat(bitmap.pixelsWide) / strip.bounds.width)
            return (0..<bitmap.pixelsHigh).filter { y in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.blueComponent > 0.7 && color.redComponent < 0.4
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        let single = thumbnailBand(), height = strip.fittingSize.height
        precondition(!single.isEmpty, "No synthetic thumbnail pixels were rendered for layout comparison")
        let second = workspace.editorQuickSwitchItems[1].id
        workspace.selectEditorFilmstripImage(second, extending: true)
        try await Task.sleep(for: .milliseconds(100))
        precondition(thumbnailBand() == single && strip.fittingSize.height == height,
                     "Multi-selection moved/resized the thumbnail row or the entire strip")
        workspace.preferences.dismissedEditorHints.insert("filmstripMultiCopy")
        try await Task.sleep(for: .milliseconds(100))
        precondition(thumbnailBand() == single && strip.fittingSize.height == height,
                     "Dismissing the hint moved/resized the filmstrip")
        window.setContentSize(NSSize(width: 420, height: 138))
        try await Task.sleep(for: .milliseconds(100))
        precondition(thumbnailBand() == single && strip.fittingSize.height == height,
                     "Compact width or selection actions changed the thumbnail row height")
        workspace.preferences.dismissedEditorHints.remove("filmstripMultiCopy")
        workspace.selectEditorFilmstripImage(second, extending: true)
        print("Filmstrip layout passed: actual thumbnail pixels and fitting height remain stable for single/multiple selection, hint dismissal and compact width")
    }

    private static func checkMultiSelectionAndNativeCopy(png: Data) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FilmstripMultiCopy-\(UUID())")
        let suite = "FilmstripMultiCopy-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        let now = Date.now
        let crop = CGRect(x: 4, y: 3, width: 20, height: 16)
        var redaction = EditorObject(kind: .redact, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 14, y: 14))
        redaction.color = EditorColor(red: 0, green: 0, blue: 0)
        let documents = (0..<3).map { index in
            ProjectDocument(title: "Multi \(index)", pixelSize: PixelSize(width: 32, height: 24)!,
                objects: index == 0 ? [redaction] : [], createdAt: now.addingTimeInterval(Double(index)), crop: index == 0 ? crop : nil)
        }
        for document in documents { try await workspace.store.create(document, original: png, thumbnail: png) }
        await workspace.refreshLibrary()
        func waitForOpen() async throws {
            for _ in 0..<500 { if !workspace.isLoading { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Multi-copy image switch timed out")
        }
        let ordered = workspace.editorQuickSwitchItems.map(\.id)
        let activeID = ordered[0]
        workspace.switchEditorImage(to: activeID); try await waitForOpen()
        precondition(workspace.editorFilmstripSelectedIDs == [activeID], "Selection did not default to the active image")
        try await checkStableSelectionLayout(workspace: workspace)
        let second = ordered[1]
        workspace.selectEditorFilmstripImage(second, extending: true)
        precondition(workspace.editor?.document.id == activeID && workspace.editorFilmstripSelectedIDs == [activeID, second],
                     "Extending selection opened another image")
        workspace.selectEditorFilmstripImage(second, extending: true)
        precondition(workspace.editorFilmstripSelectedIDs == [activeID], "Extending selection did not toggle off")
        workspace.selectEditorFilmstripImage(second)
        try await waitForOpen()
        precondition(workspace.editor?.document.id == second && workspace.editorFilmstripSelectedIDs == [second],
                     "Normal selection did not open and reset the selection")
        workspace.selectEditorFilmstripImage(activeID, extending: true)
        workspace.selectEditorFilmstripImage(ordered[2], extending: true)
        precondition(workspace.editorFilmstripSelectedIDs == Set(ordered), "Could not select all filmstrip images")

        // The active image has an unsaved redaction; the older image has saved crop/redaction data.
        var unsavedRedaction = EditorObject(kind: .redact, start: CGPoint(x: 8, y: 4), end: CGPoint(x: 18, y: 12))
        unsavedRedaction.color = EditorColor(red: 0, green: 0, blue: 0)
        workspace.editor?.commit([unsavedRedaction])
        let board = NSPasteboard(name: NSPasteboard.Name("FilmstripMultiCopy-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("old clipboard", forType: .string)
        let outputRoot = root.appendingPathComponent("exports", isDirectory: true)
        let copy = workspace.copySelectedEditorImages(to: board, in: outputRoot)
        precondition(copy != nil, "A valid multi-selection was not copyable")
        let copySucceeded = await copy!.value
        precondition(copySucceeded, "Multi-selection copy failed")
        precondition(!workspace.preferences.dismissedEditorHints.contains("filmstripMultiCopy"), "Copying hid the persistent multi-selection hint")
        let urls = (board.readObjects(forClasses: [NSURL.self]) as? [NSURL])?.compactMap { $0.isFileURL ? ($0 as URL) : nil } ?? []
        precondition(urls.count == ordered.count && urls.allSatisfy { $0.path.hasPrefix(outputRoot.path) && FileManager.default.fileExists(atPath: $0.path) },
                     "Copy did not publish separate temporary PNG URLs")
        precondition(urls.map { $0.lastPathComponent } == documents.reversed().map { $0.title + ".png" },
                     "Copied files did not preserve filmstrip order")
        for (id, url) in zip(ordered, urls) {
            let bytes = try Data(contentsOf: url)
            precondition(bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]), "Copied output is not a flattened PNG")
            let bitmap = NSBitmapImageRep(data: bytes)!
            if id == documents[0].id {
                precondition(bitmap.pixelsWide == 20 && bitmap.pixelsHigh == 16, "Saved crop was not applied")
                let covered = bitmap.colorAt(x: 3, y: 4)!.usingColorSpace(.deviceRGB)!
                precondition(covered.redComponent < 0.02 && covered.greenComponent < 0.02 && covered.blueComponent < 0.02,
                             "Saved redaction exposed original pixels in the multi-copy")
            } else if id == workspace.editor?.document.id {
                let covered = bitmap.colorAt(x: 10, y: 8)!.usingColorSpace(.deviceRGB)!
                precondition(covered.redComponent < 0.02 && covered.greenComponent < 0.02 && covered.blueComponent < 0.02,
                             "Multi-copy ignored the active editor's unsaved redaction")
            }
        }
        let committedBatches = try FileManager.default.contentsOfDirectory(at: outputRoot, includingPropertiesForKeys: nil).count

        // A prepare failure must not destroy the previous clipboard contents.
        board.clearContents(); board.setString("keep this", forType: .string)
        let failing = workspace.copySelectedEditorImages(to: board, in: outputRoot, prepare: { _, _ in
            throw CocoaError(.fileWriteUnknown)
        })
        precondition(failing != nil)
        let failed = await failing!.value
        precondition(!failed)
        precondition(board.string(forType: .string) == "keep this", "Failed preparation replaced the clipboard")
        let batchesAfterFailure = try FileManager.default.contentsOfDirectory(at: outputRoot, includingPropertiesForKeys: nil).count
        precondition(batchesAfterFailure == committedBatches)
        workspace.acknowledgeImportError()

        let original = root.appendingPathComponent("\(documents[0].id).snagforge/original.png")
        try Data("invalid PNG".utf8).write(to: original)
        let corruptCopy = workspace.copySelectedEditorImages(to: board, in: outputRoot)!
        let corruptCopied = await corruptCopy.value
        precondition(!corruptCopied && board.string(forType: .string) == "keep this", "A corrupt source partially replaced the clipboard")
        let batchesAfterCorruption = try FileManager.default.contentsOfDirectory(at: outputRoot, includingPropertiesForKeys: nil).count
        precondition(batchesAfterCorruption == committedBatches,
                     "Failed multi-copy left prepared image batches behind")
        try png.write(to: original)
        workspace.acknowledgeImportError()

        // External clipboard changes while preparation is held win and are never overwritten.
        let gate = FilmstripOneShotGate()
        let held = workspace.copySelectedEditorImages(to: board, in: outputRoot, prepare: { snapshot, directory in
            await gate.pauseOnce()
            return try await snapshot.writeTemporaryPNG(in: directory)
        })
        precondition(held != nil)
        for _ in 0..<500 { if await gate.started { break }; try await Task.sleep(for: .milliseconds(5)) }
        board.clearContents(); board.setString("external", forType: .string)
        await gate.release()
        let heldResult = await held!.value
        precondition(!heldResult && board.string(forType: .string) == "external",
                     "Clipboard mutation during preparation was overwritten")

        let quitGate = FilmstripOneShotGate()
        let preparing = workspace.copySelectedEditorImages(to: board, in: outputRoot, prepare: { snapshot, directory in
            await quitGate.pauseOnce()
            return try await snapshot.writeTemporaryPNG(in: directory)
        })!
        for _ in 0..<500 { if await quitGate.started { break }; try await Task.sleep(for: .milliseconds(5)) }
        let preparationStarted = await quitGate.started
        precondition(preparationStarted && workspace.isCopyingSelectedEditorImages && !workspace.canSwitchEditorImage)
        let quitResult = FilmstripCopyFinishBox()
        let quitting = Task { await quitResult.set(await workspace.flushBeforeQuitting()) }
        try await Task.sleep(for: .milliseconds(75))
        let waiting = await quitResult.read()
        precondition(waiting == nil, "Quit completed before the selected images were copied")
        await quitGate.release()
        let prepared = await preparing.value
        await quitting.value
        let quitSucceeded = await quitResult.read()
        precondition(prepared && quitSucceeded == true, "Copy did not finish before quitting")

        // Native events: modifier clicks are intercepted, trash bounds are excluded, and
        // Cmd+C only works while this view owns first responder and has no extra modifier.
        let native = FilmstripModifierClickView(frame: NSRect(x: 0, y: 0, width: 112, height: 102))
        var toggles = 0, copies = 0
        native.isEnabled = { true }; native.canCopySelection = { true }
        native.onToggleSelection = { toggles += 1 }; native.onCopySelection = { copies += 1; return true }
        let control = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 40), modifierFlags: [.control], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        precondition(native.shouldIntercept(event: control, at: NSPoint(x: 20, y: 40)))
        native.mouseDown(with: control); precondition(toggles == 1)
        precondition(!native.shouldIntercept(event: control, at: NSPoint(x: 100, y: 96)), "Trash bounds were treated as selection")
        native.rightMouseDown(with: control); precondition(toggles == 2, "Ctrl-right fallback did not toggle")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        precondition(!native.performKeyEquivalent(with: key), "Cmd+C was handled without first responder")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 112, height: 102), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = native; window.makeFirstResponder(native)
        let copyItem = NSMenuItem(); copyItem.action = #selector(FilmstripModifierClickView.copy(_:))
        precondition(native.validateUserInterfaceItem(copyItem))
        precondition(native.performKeyEquivalent(with: key) && copies == 1)
        let extra = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "C", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        precondition(!native.performKeyEquivalent(with: extra) && copies == 1)
        window.close()
    }

    private static func checkRecentImagesAndTrash(png: Data, image: CGImage) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecentFilmstrip-\(UUID())")
        let suite = "RecentFilmstrip-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        // A fixed clock covers the inclusive boundary independently of test duration.
        let now = Date(timeIntervalSince1970: 1_792_368_000)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let expired = ProjectDocument(title: "Expired", pixelSize: PixelSize(width: 32, height: 24)!, createdAt: cutoff.addingTimeInterval(-1))
        let boundary = ProjectDocument(title: "Exactly seven days", pixelSize: expired.pixelSize, createdAt: cutoff)
        let recent = ProjectDocument(title: "Recent", pixelSize: expired.pixelSize, createdAt: now)
        for document in [expired, boundary, recent] { try await workspace.store.create(document, original: png, thumbnail: png) }
        await workspace.refreshLibrary()
        precondition(workspace.editorQuickSwitchItems(asOf: now).map(\.id) == [recent.id, boundary.id])
        precondition(workspace.editorQuickSwitchItems(asOf: now.addingTimeInterval(1)).map(\.id) == [recent.id])
        try await workspace.store.updateMetadata(expired.id, title: "Edited today")
        await workspace.refreshLibrary()
        precondition(!workspace.editorQuickSwitchItems(asOf: now).contains { $0.id == expired.id }, "Editing revived an expired thumbnail")
        precondition(workspace.items.count == 3, "Preview filtering removed older library projects")

        // Use dates relative to the live clock for the production navigation and trash actions.
        let live = Date.now
        var documents: [ProjectDocument] = []
        for index in 0..<12 {
            let document = ProjectDocument(title: "Recent \(index)", pixelSize: expired.pixelSize, createdAt: live.addingTimeInterval(Double(index)))
            try await workspace.store.create(document, original: png, thumbnail: png)
            documents.append(document)
        }
        await workspace.refreshLibrary()
        func waitForOpen() async throws {
            for _ in 0..<1000 { if !workspace.isLoading { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Recent image switch timed out")
        }
        workspace.switchEditorImage(to: documents[11].id); try await waitForOpen()
        let strip = NSHostingView(rootView: EditorFilmstripView(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 138), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = strip
        defer { window.close() }
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        strip.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        guard let scroll = scrollView(in: strip) else { preconditionFailure("Missing native filmstrip scroll view") }
        let initialOffset = scroll.contentView.bounds.origin.x
        workspace.switchEditorImage(to: documents[10].id); try await waitForOpen()
        try await Task.sleep(for: .milliseconds(250))
        precondition(abs(scroll.contentView.bounds.origin.x - initialOffset) < 1, "Clicking a thumbnail shifted the strip")
        // Manual scrolling remains possible and later selections preserve that position as well.
        scroll.contentView.scroll(to: NSPoint(x: 256, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(50))
        let manualOffset = scroll.contentView.bounds.origin.x
        precondition(manualOffset > 100)
        workspace.switchEditorImage(by: 1); try await waitForOpen()
        try await Task.sleep(for: .milliseconds(250))
        precondition(abs(scroll.contentView.bounds.origin.x - manualOffset) < 1, "Navigation reset manual scrolling")

        let selected = workspace.editor!.document.id
        let closed = documents[0].id
        await workspace.trashEditorImage(closed)
        precondition(workspace.editor!.document.id == selected && workspace.trashItems.contains { $0.id == closed })
        workspace.editor!.beginCrop()
        await workspace.trashEditorImage(selected)
        precondition(workspace.editor!.document.id == selected && !workspace.trashItems.contains { $0.id == selected }, "Trash discarded a crop draft")
        workspace.editor!.cancelCrop()
        workspace.editor!.editText(at: .zero); workspace.editor!.updateText("Pending text before direct trash")
        let neighbor = workspace.adjacentEditorImage(1) ?? workspace.adjacentEditorImage(-1)
        await workspace.trashEditorImage(selected)
        precondition(workspace.editor?.document.id == neighbor && workspace.section == .editor)
        precondition(workspace.trashItems.contains { $0.id == selected })
        let reopened = WorkspaceModel(root: root, defaults: defaults)
        await reopened.refreshLibrary()
        precondition(reopened.trashItems.first { $0.id == selected }?.document.objects.last?.text == "Pending text before direct trash")
        let restored = await reopened.changeTrash(selected, action: .restore); precondition(restored)
        let recovered = try await reopened.store.load(selected)
        precondition(recovered.original == png && recovered.document.objects.last?.text == "Pending text before direct trash")

        // With no neighbor, removing the last image returns to the library.
        let lastRoot = root.appendingPathComponent("LastImage")
        let last = WorkspaceModel(root: lastRoot, defaults: defaults)
        try await last.store.create(documents[0], original: png, thumbnail: png)
        await last.refreshLibrary()
        last.editor = EditorModel(image: image, document: documents[0], generation: 0, store: last.store, onSaved: {})
        last.section = .editor
        await last.trashEditorImage(documents[0].id)
        precondition(last.editor == nil && last.section == .library && last.editorQuickSwitchItems.isEmpty && last.trashItems.count == 1)
    }
}
