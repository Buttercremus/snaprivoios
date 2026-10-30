import AppKit
import SnagForgeDomain

private actor PNGWriteGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; started = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor func checkEditorExportLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Export-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "Snaprivo-Export-\(UUID())", defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let workspace = WorkspaceModel(root: root.appendingPathComponent("library"), defaults: defaults)
    let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
    let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
    func makeEditor(objects: [EditorObject] = [], write: @escaping EditorModel.PNGWriter = EditorModel.writePNGData) async throws -> EditorModel {
        let document = ProjectDocument(title: "Synthetic export", pixelSize: PixelSize(width: 120, height: 80)!, objects: objects)
        try await workspace.store.create(document, original: original, thumbnail: nil)
        return EditorModel(image: image, document: document, generation: 0, store: workspace.store, writePNG: write, onSaved: {})
    }
    func assertCovered(_ data: Data) {
        let pixels = NSBitmapImageRep(data: data)!, color = pixels.colorAt(x: 60, y: 40)!.usingColorSpace(.sRGB)!
        precondition(color.redComponent < 0.01 && color.greenComponent < 0.01 && color.blueComponent < 0.01,
                     "PNG leaked original pixels under a confirmed redaction")
    }
    func waitForWriter(_ gate: PNGWriteGate) async throws {
        for _ in 0..<500 {
            if await gate.started { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("PNG writer did not start")
    }
    var small = EditorObject(kind: .redact, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 25, y: 25))
    small.color = EditorColor(red: 0, green: 0, blue: 0)
    var large = small; large.end = CGPoint(x: 110, y: 70)
    let moved = small.translated(by: CGSize(width: 50, height: 20))
    // All live previews cover the sample pixel; their committed state still exposes it.
    for (label, committed, preview) in [("draw", [], [large]), ("move", [small], [moved]), ("resize", [small], [large])] {
        let model = try await makeEditor(objects: committed)
        let target = root.appendingPathComponent("\(label).png"), sentinel = Data("existing destination".utf8)
        try sentinel.write(to: target)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("existing clipboard", forType: .string)
        model.preview = preview; model.isCanvasGestureActive = true
        assertCovered(try EditorRenderer.png(image: image, objects: model.objects))
        precondition(!model.hasExportableImage)
        precondition(model.pngShareItem == nil, "An active canvas preview was offered for sharing")
        precondition(!model.openPNG(with: root.appendingPathComponent("Fake.app")), "Active canvas preview was opened externally")
        model.copyPNG(to: pasteboard)
        model.exportPNG() // Must not open a panel either, including menu/keyboard callers.
        precondition(!model.exportPNG(to: target) && !model.isExportingPNG && model.copyState == .idle)
        precondition(pasteboard.string(forType: .string) == "existing clipboard" && pasteboard.data(forType: .png) == nil)
        let unchangedTarget = try Data(contentsOf: target)
        precondition(unchangedTarget == sentinel, "Active gesture replaced an export destination")
        model.isCanvasGestureActive = false
        precondition(!model.hasExportableImage, "An unfinished preview must also block export")
        model.commit(preview)
        precondition(model.hasExportableImage)
        model.copyPNG(to: pasteboard)
        for _ in 0..<500 where model.copyState == .copying { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.copyState == .copied)
        assertCovered(pasteboard.data(forType: .png)!)
        precondition(model.exportPNG(to: target))
        let finished = await model.finishPendingWork()
        precondition(finished && !model.isExportingPNG)
        assertCovered(try Data(contentsOf: target))
        let reopened = try await workspace.store.load(model.document.id)
        precondition(reopened.document.objects == preview)
    }
    // Quit must wait for a started write, reject new exports, then save the latest project state.
    let gate = PNGWriteGate()
    let slow = try await makeEditor(objects: [large]) { data, url in
        await gate.pause(); try await EditorModel.writePNGData(data, to: url)
    }
    workspace.editor = slow
    let target = root.appendingPathComponent("quit.png")
    precondition(slow.exportPNG(to: target)); try await waitForWriter(gate)
    precondition(slow.pngShareItem == nil, "An active PNG export allowed another sharing operation")
    slow.commit([large, EditorObject(kind: .arrow, start: CGPoint(x: 10, y: 75), end: CGPoint(x: 100, y: 75))])
    var quitFinished = false
    let quit = Task { let result = await workspace.flushBeforeQuitting(); quitFinished = true; return result }
    try await Task.sleep(for: .milliseconds(100))
    precondition(!quitFinished && !FileManager.default.fileExists(atPath: target.path))
    precondition(!slow.hasExportableImage && !slow.exportPNG(to: root.appendingPathComponent("second.png")))
    await gate.release()
    let quitResult = await quit.value
    precondition(quitResult && quitFinished && !slow.isDirty && !slow.isExportingPNG)
    assertCovered(try Data(contentsOf: target))
    let saved = try await workspace.store.load(slow.document.id)
    precondition(saved.document.objects == slow.history.objects, "Quit lost edits made during export")

    // A write failure during quit cancels termination, preserves the target and still autosaves.
    let failureGate = PNGWriteGate()
    let failing = try await makeEditor { _, _ in
        await failureGate.pause(); throw CocoaError(.fileWriteOutOfSpace)
    }
    workspace.editor = failing; failing.commit([large])
    let failureTarget = root.appendingPathComponent("failed.png"), sentinel = Data("previous file".utf8)
    try sentinel.write(to: failureTarget)
    precondition(failing.exportPNG(to: failureTarget)); try await waitForWriter(failureGate)
    var failedQuitFinished = false
    let failedQuit = Task { let result = await workspace.flushBeforeQuitting(); failedQuitFinished = true; return result }
    try await Task.sleep(for: .milliseconds(100)); precondition(!failedQuitFinished)
    await failureGate.release()
    let failedQuitResult = await failedQuit.value
    precondition(!failedQuitResult && failing.error != nil && failing.notice == nil && !failing.isExportingPNG && !failing.isDirty)
    let unchangedFailureTarget = try Data(contentsOf: failureTarget)
    precondition(unchangedFailureTarget == sentinel)
    // A project switch/second quit must not swallow an unacknowledged error from a completed task.
    let unacknowledgedQuit = await workspace.flushBeforeQuitting(); precondition(!unacknowledgedQuit)
    workspace.openProject(slow.document.id)
    for _ in 0..<500 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    precondition(workspace.editor === failing)
    failing.error = nil // The error alert's OK action.
    let retryQuit = await workspace.flushBeforeQuitting(); precondition(retryQuit)

    // Replacing an editor must retain its export until completion, also if Quit arrives meanwhile.
    let switchGate = PNGWriteGate()
    let previous = try await makeEditor(objects: [large]) { data, url in
        await switchGate.pause(); try await EditorModel.writePNGData(data, to: url)
    }
    let next = try await makeEditor()
    workspace.editor = previous
    let switchTarget = root.appendingPathComponent("switch.png")
    precondition(previous.exportPNG(to: switchTarget)); try await waitForWriter(switchGate)
    workspace.openProject(next.document.id)
    try await Task.sleep(for: .milliseconds(100))
    precondition(workspace.isLoading && workspace.editor === previous)
    var switchQuitFinished = false
    let switchQuit = Task { let result = await workspace.flushBeforeQuitting(); switchQuitFinished = true; return result }
    try await Task.sleep(for: .milliseconds(100)); precondition(!switchQuitFinished)
    await switchGate.release()
    let switchQuitResult = await switchQuit.value
    precondition(switchQuitResult && workspace.editor?.document.id == next.document.id)
    assertCovered(try Data(contentsOf: switchTarget))
    // A screenshot can be persisted while the outgoing editor still owns a
    // running export. Replacement and Quit must wait for that owner to finish.
    let captureGate = PNGWriteGate()
    let capturePrevious = try await makeEditor { data, url in
        await captureGate.pause(); try await EditorModel.writePNGData(data, to: url)
    }
    workspace.editor = capturePrevious
    await workspace.refreshLibrary()
    let knownIDs = Set(workspace.items.map(\.id)), captureTarget = root.appendingPathComponent("capture-switch.png")
    precondition(capturePrevious.exportPNG(to: captureTarget)); try await waitForWriter(captureGate)
    capturePrevious.commit([large])
    workspace.openScreenshot(image)
    for _ in 0..<500 where Set(workspace.items.map(\.id)) == knownIDs { try await Task.sleep(for: .milliseconds(10)) }
    let pendingCapture = workspace.items.first { !knownIDs.contains($0.id) }
    precondition(pendingCapture != nil && workspace.isLoading && workspace.editor === capturePrevious,
                 "Capture lost its persisted image or replaced an editor with an active export")
    let persistedCapture = try await workspace.store.load(pendingCapture!.id)
    precondition(persistedCapture.original == original)
    let captureQuit = Task { await workspace.flushBeforeQuitting() }
    await captureGate.release()
    let captureQuitResult = await captureQuit.value
    precondition(captureQuitResult && workspace.editor?.document.id == pendingCapture!.id && !capturePrevious.isDirty)
    let outgoing = try await workspace.store.load(capturePrevious.document.id)
    precondition(outgoing.document.objects == [large] && FileManager.default.fileExists(atPath: captureTarget.path))
    // Inject the application boundary: verify files and lifetime without launching another app.
    let application = root.appendingPathComponent("Synthetic.app")
    let openRoot = root.appendingPathComponent("open-with")
    func makeOpeningEditor(_ open: @escaping EditorModel.PNGApplicationOpener) async throws -> EditorModel {
        let document = ProjectDocument(title: "Synthetic open-with", pixelSize: PixelSize(width: 120, height: 80)!, objects: [large])
        try await workspace.store.create(document, original: original, thumbnail: nil)
        return EditorModel(image: image, document: document, generation: 0, store: workspace.store,
                           openPNGApplication: open, externalOpenRoot: openRoot, onSaved: {})
    }
    var openedFiles: [URL] = []
    let external = try await makeOpeningEditor { file, app in
        precondition(app == application && file.pathExtension == "png")
        openedFiles.append(file)
    }
    external.beginCrop(); external.cropDraft = CGRect(x: 10, y: 10, width: 100, height: 60); external.applyCrop()
    precondition(external.applyImageSize(PixelSize(width: 50, height: 30)!))
    let expected = try EditorRenderer.png(image: image, objects: external.history.objects,
                                         crop: external.document.crop, resizedSize: external.document.resizedSize)
    precondition(external.openPNG(with: application) && external.isOpeningExternally && external.pngShareItem == nil)
    precondition(!external.openPNG(with: application), "Two external opens started together")
    let opened = await external.finishPendingWork()
    precondition(opened && !external.isOpeningExternally && external.error == nil && openedFiles.count == 1)
    let firstFile = openedFiles[0], firstData = try Data(contentsOf: firstFile)
    let firstPixels = NSBitmapImageRep(data: firstData)!
    precondition(firstData == expected && firstPixels.pixelsWide == 50 && firstPixels.pixelsHigh == 30)
    let covered = firstPixels.colorAt(x: 25, y: 15)!.usingColorSpace(.deviceRGB)!
    precondition(covered.redComponent == 0 && covered.greenComponent == 0 && covered.blueComponent == 0 && covered.alphaComponent == 1)
    external.commit([])
    precondition(external.openPNG(with: application))
    let reopened = await external.finishPendingWork()
    let unchangedFirstFile = try Data(contentsOf: firstFile)
    precondition(reopened && openedFiles.count == 2 && openedFiles[1] != firstFile && unchangedFirstFile == firstData,
                 "A new external edit overwrote or deleted a previous app's working copy")

    let openGate = PNGWriteGate()
    var delayedData: Data?
    let delayed = try await makeOpeningEditor { file, _ in
        delayedData = try Data(contentsOf: file); await openGate.pause()
    }
    precondition(delayed.openPNG(with: application)); try await waitForWriter(openGate)
    delayed.commit([])
    var openFinished = false
    let finishOpen = Task { let result = await delayed.finishPendingWork(); openFinished = true; return result }
    try await Task.sleep(for: .milliseconds(100))
    precondition(!openFinished && delayed.isOpeningExternally && !delayed.hasExportableImage)
    await openGate.release()
    let finishedOpen = await finishOpen.value
    precondition(finishedOpen && !delayed.isDirty)
    assertCovered(delayedData!)

    var failedFile: URL?
    let cannotOpen = try await makeOpeningEditor { file, _ in failedFile = file; throw CocoaError(.fileReadNoSuchFile) }
    precondition(cannotOpen.openPNG(with: application))
    let failedOpen = await cannotOpen.finishPendingWork()
    precondition(!failedOpen && cannotOpen.error != nil && !cannotOpen.isOpeningExternally
                 && !FileManager.default.fileExists(atPath: failedFile!.deletingLastPathComponent().path), "Failed external open lost its error or retained its unused copy")
    let failedAgain = await cannotOpen.finishPendingWork(); precondition(!failedAgain)
    cannotOpen.error = nil
    let acknowledged = await cannotOpen.finishPendingWork(); precondition(acknowledged)
    let applications = EditorPNGApplication.available()
    precondition(Set(applications.map(\.url)).count == applications.count && applications.allSatisfy { !$0.name.isEmpty })
    if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
        precondition(applications.first?.url == preview.standardizedFileURL)
    }
    precondition(NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) != nil)
    print("Open-with checks passed: confirmed-state guards, cropped/resized/opaque PNG, selected application, separate retained working copies, pending-open lifetime, failure cleanup/acknowledgement and installed PNG app discovery. No application was launched.")
    print("Editor export checks passed: live draw/move/resize blocked; clipboard and file pixels; quit waits for PNG; failure preserves target and saves project; editor replacement during quit.")
}
