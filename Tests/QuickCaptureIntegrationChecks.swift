import AppKit
import SnagForgeDomain
import Vision

@MainActor private final class QuickClipboardVersion { var value = 0 }

private actor QuickCaptureExportGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func isStarted() -> Bool { started }
    func pause() async { await withCheckedContinuation { continuation = $0; started = true } }
    func release() { continuation?.resume(); continuation = nil }
}
private actor QuickCaptureResultBox {
    private(set) var result: Bool?
    func set(_ value: Bool) { result = value }
    func read() -> Bool? { result }
}

@main struct QuickCaptureIntegrationChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-QuickCapture-\(UUID())")
        let suite = "Snaprivo-QuickCapture-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        workspace.preferences.quickPreviewAfterCapture = true
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let image = context.makeImage()!
        let editorHost = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        editorHost.identifier = .init("workspace"); editorHost.isReleasedWhenClosed = false
        let setupHost = NSWindow(contentRect: editorHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
        setupHost.identifier = .init("capture"); setupHost.isReleasedWhenClosed = false
        let anonymousHost = NSWindow(contentRect: editorHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
        anonymousHost.isReleasedWhenClosed = false; anonymousHost.orderFront(nil)
        let generatedHost = NSWindow(contentRect: editorHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
        generatedHost.identifier = .init("SwiftUI.Generated.Workspace.1"); generatedHost.isReleasedWhenClosed = false; generatedHost.orderFront(nil)
        let previewHost = NSPanel(contentRect: editorHost.frame, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        previewHost.isReleasedWhenClosed = false
        defer { editorHost.close(); setupHost.close(); anonymousHost.close(); generatedHost.close(); previewHost.close() }
        ScreenshotCoordinator.restoreAfterImageCapture([editorHost, setupHost, anonymousHost, generatedHost, previewHost], opensEditor: false)
        precondition(!anonymousHost.isVisible && !generatedHost.isVisible, "Capture routing depended on exact SwiftUI window IDs")
        precondition(!editorHost.isVisible && !setupHost.isVisible && previewHost.isVisible, "Quick capture brought the editor/setup back on screen")
        ScreenshotCoordinator.restoreAfterImageCapture([editorHost, setupHost], opensEditor: true)
        precondition(editorHost.isVisible && setupHost.isVisible, "Normal capture did not restore its host windows")
        editorHost.orderOut(nil); setupHost.orderOut(nil); previewHost.orderOut(nil)
        var editorOpenRequests = 0
        workspace.showWorkspaceWindow = { editorOpenRequests += 1; editorHost.makeKeyAndOrderFront(nil) }
        var previewReadyRequests = 0
        workspace.onQuickCaptureReady = { model in
            previewReadyRequests += 1
            QuickCapturePanelController.shared.present(workspace: workspace, model: model)
        }
        let initialSection = workspace.section
        workspace.openScreenshot(image)
        for _ in 0..<300 { if !workspace.isLoading { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard let first = workspace.quickCapture else { preconditionFailure("quick capture was not retained") }
        precondition(workspace.editor == nil && workspace.section == initialSection && editorOpenRequests == 0 && !editorHost.isVisible,
                     "A preview capture opened the editor before a thumbnail was clicked")
        precondition(previewReadyRequests == 1 && QuickCapturePanelController.shared.isVisible,
                     "Preview depended on a visible workspace to appear")
        QuickCapturePanelController.shared.present(workspace: workspace, model: first)
        precondition(QuickCapturePanelController.shared.isVisible, "preview panel did not open")
        QuickCapturePanelController.shared.hide()
        precondition(!QuickCapturePanelController.shared.isVisible, "preview panel did not hide")
        QuickCapturePanelController.shared.restore()
        precondition(QuickCapturePanelController.shared.isVisible, "preview panel did not restore")
        QuickCapturePanelController.shared.present(workspace: workspace, model: first)
        precondition(QuickCapturePanelController.shared.isVisible && workspace.quickCapture === first, "panel replacement lost capture ownership")
        func waitForCapture() async throws {
            for _ in 0..<300 { if !workspace.isLoading { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Capture did not finish")
        }
        for _ in 0..<5 { workspace.openScreenshot(image); try await waitForCapture() }
        precondition(workspace.quickCaptures.count == 5 && !workspace.quickCaptures.contains { $0 === first }, "Stack did not retain the five latest captures")
        let listing = try await workspace.store.list()
        precondition(listing.items.count == 6, "Evicting a thumbnail deleted a project")
        let dismissed = workspace.quickCaptures[1]
        workspace.dismissQuickCapture(dismissed)
        precondition(workspace.quickCaptures.count == 4 && !workspace.quickCaptures.contains { $0 === dismissed })
        precondition(QuickCapturePanelController.shared.isVisible, "Closing one thumbnail hid the remaining stack")
        workspace.selectedQuickCaptureID = workspace.quickCaptures.first!.document.id
        workspace.moveQuickCaptureSelection(by: -1)
        precondition(workspace.selectedQuickCaptureID == workspace.quickCaptures.first!.document.id)
        workspace.moveQuickCaptureSelection(by: 1)
        let next = workspace.quickCaptures[1]
        precondition(workspace.selectedQuickCaptureID == next.document.id)
        workspace.dismissQuickCapture(next)
        precondition(workspace.selectedQuickCaptureID == workspace.quickCaptures[1].document.id)
        precondition(workspace.quickCaptures.count == 3)
        let afterDismiss = try await workspace.store.list()
        precondition(afterDismiss.items.count == 6, "Closing a thumbnail deleted its saved image")
        QuickCapturePanelController.shared.refreshLayout()
        if let frame = QuickCapturePanelController.shared.frame,
           let visible = NSScreen.screens.first(where: { $0.visibleFrame.contains(frame.origin) })?.visibleFrame {
            precondition(frame.minX == visible.minX + 16 && frame.minY == visible.minY + 16 && frame.maxY <= visible.maxY)
        } else { preconditionFailure("Stack was not positioned on a visible screen") }
        let selected = workspace.quickCaptures.last!
        workspace.editQuickCapture(selected); try await waitForCapture()
        precondition(workspace.editor === selected && !workspace.quickCaptures.contains { $0 === selected }, "Wrong thumbnail opened in the editor")
        precondition(editorOpenRequests == 1 && editorHost.isVisible && workspace.section == .editor,
                     "Explicit thumbnail click did not open the editor exactly once")
        editorHost.orderOut(nil)
        workspace.openScreenshot(image); try await waitForCapture()
        precondition(workspace.editor === selected && editorOpenRequests == 1 && !editorHost.isVisible,
                     "A later capture reopened or replaced the existing editor")
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 10,y:20),end: CGPoint(x:30,y:35)); mask.color = EditorColor(red:0,green:0,blue:0)
        first.commit([mask]); first.beginCrop(); first.cropDraft = CGRect(x:5,y:5,width:100,height:60); first.applyCrop()
        precondition(first.applyImageSize(PixelSize(width:200,height:120)!)); first.transformImage(.clockwise90)
        let share = EditorPNGShare(image: first.image, objects: first.history.objects, crop: first.history.crop,
                                   resizedSize: first.history.resizedSize, title: first.name,
                                   canvasRect: first.history.canvasRect, transform: first.history.transform)
        let payload = try await QuickCapturePayload.prepare(share, in: root)
        let exported = payload.file
        let source = CGImageSourceCreateWithURL(exported as CFURL, nil)!
        let flattened = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(flattened.width == 120 && flattened.height == 200, "transfer PNG changed synthetic dimensions")
        let black = EditorRenderer.pixelColor(flattened,x:80,y:30)!
        precondition(black.redComponent < 0.01 && black.greenComponent < 0.01 && black.blueComponent < 0.01, "Drag file exposed redacted content")
        let provider = NSItemProvider(contentsOf: exported)!
        precondition(provider.hasItemConformingToTypeIdentifier("public.file-url"), "Finder drag lacks a file representation")
        let pins = PinnedImageController.shared
        pins.show(flattened, title:"Synthetic")
        precondition(pins.panelCount == 1); pins.toggleClickThrough(); precondition(pins.allPinsIgnoreMouseEvents)
        pins.unlockAll(); precondition(!pins.allPinsIgnoreMouseEvents); pins.closeAll(); precondition(pins.panelCount == 0)
        let storedBeforeClosing = try await workspace.store.list().items.count
        for preview in workspace.quickCaptures { workspace.dismissQuickCapture(preview) }
        precondition(workspace.quickCaptures.isEmpty && workspace.selectedQuickCaptureID == nil)
        precondition(!QuickCapturePanelController.shared.isVisible, "Closing the last thumbnail left a floating panel")
        QuickCapturePanelController.shared.restore()
        precondition(!QuickCapturePanelController.shared.isVisible, "Restore reopened an empty preview panel")
        QuickCapturePanelController.shared.present(workspace: workspace)
        precondition(!QuickCapturePanelController.shared.isVisible, "Present reopened an empty preview panel")
        let storedAfterClosing = try await workspace.store.list().items.count
        precondition(storedAfterClosing == storedBeforeClosing, "Closing the stack deleted saved projects")
        let textContext = CGContext(data: nil, width: 800, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        textContext.setFillColor(NSColor.white.cgColor); textContext.fill(CGRect(x: 0, y: 0, width: 800, height: 160))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: textContext, flipped: false)
        NSString(string: "SYNTHETIC COPY TEST").draw(at: CGPoint(x: 30, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let textShare = EditorPNGShare(image: textContext.makeImage()!, objects: [], crop: nil, resizedSize: nil, title: "Synthetic text")
        // Exercise clipboard/result state against real Vision's deterministic
        // fast engine; accurate model startup is covered separately and can
        // exceed this integration suite's deadline on the macOS 27 test host.
        let recognition = QuickImageRecognitionModel(service: TextRecognitionService(perform: { request, image in
            var fast = request; fast.recognitionLevel = .fast
            fast.recognitionLanguages = fast.supportedRecognitionLanguages
            return try await fast.perform(on: image, orientation: .up)
        }))
        func waitForRecognition() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while recognition.isBusy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!recognition.isBusy, "Thumbnail OCR did not finish")
        }
        recognition.recognize(textShare, codesOnly: false, canUse: { true }, copy: { _ in false })
        try await waitForRecognition()
        precondition(recognition.text.contains("SYNTHETIC") && recognition.error != nil && !recognition.didCopyText,
                     "Thumbnail OCR lost its result after a clipboard failure")
        let board = NSPasteboard(name: .init("Snaprivo-Thumbnail-OCR-\(UUID())"))
        defer { board.releaseGlobally() }
        precondition(recognition.copyText(canUse: { true }, copy: { value in board.clearContents(); return board.setString(value, forType: .string) }))
        precondition(recognition.didCopyText && board.string(forType: .string) == recognition.text)
        let revision = QuickClipboardVersion()
        var clipboardWrites = 0
        recognition.recognize(textShare, codesOnly: false, canUse: { true }, copy: { _ in clipboardWrites += 1; return true }, clipboardRevision: { revision.value })
        revision.value = 1
        try await waitForRecognition()
        precondition(!recognition.text.isEmpty && !recognition.didCopyText && clipboardWrites == 0,
                     "Late thumbnail OCR overwrote a changed clipboard")
        precondition(!recognition.copyText(canUse: { false }, copy: { _ in clipboardWrites += 1; return true }) && clipboardWrites == 0)
        recognition.cancel(); precondition(recognition.text.isEmpty && !recognition.isBusy)

        // Regression: a dismissed thumbnail must keep a started PNG write alive
        // until quit, and a second dismissal during that wait must be drained too.
        let quitRoot = root.appendingPathComponent("quit-regression", isDirectory: true)
        let quitWorkspace = WorkspaceModel(root: quitRoot, defaults: defaults)
        func syntheticImage() -> CGImage {
            let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            return context.makeImage()!
        }
        func gatedModel(_ workspace: WorkspaceModel, gate: QuickCaptureExportGate) async throws -> EditorModel {
            let image = syntheticImage()
            let document = ProjectDocument(title: "gated", pixelSize: PixelSize(width: 40, height: 30)!)
            let original = try EditorRenderer.png(image: image, objects: [])
            try await workspace.store.create(document, original: original, thumbnail: nil)
            return EditorModel(image: image, document: document, generation: 0, store: workspace.store,
                               writePNG: { data, url in await gate.pause(); try await EditorModel.writePNGData(data, to: url) }, onSaved: {})
        }
        let firstGate = QuickCaptureExportGate()
        let gatedFirst = try await gatedModel(quitWorkspace, gate: firstGate)
        quitWorkspace.quickCapture = gatedFirst
        let firstTarget = quitRoot.appendingPathComponent("first.png")
        precondition(gatedFirst.exportPNG(to: firstTarget))
        for _ in 0..<100 where !(await firstGate.isStarted()) { try await Task.sleep(for: .milliseconds(10)) }
        let firstStarted = await firstGate.isStarted()
        precondition(firstStarted && gatedFirst.isExportingPNG)
        quitWorkspace.dismissQuickCapture(gatedFirst)
        precondition(quitWorkspace.quickCaptures.isEmpty, "Dismissal did not remove the miniature immediately")
        let quitResult = QuickCaptureResultBox()
        Task { await quitResult.set(await quitWorkspace.flushBeforeQuitting()) }
        try await Task.sleep(for: .milliseconds(100))
        let initialQuitResult = await quitResult.read()
        precondition(initialQuitResult == nil && !FileManager.default.fileExists(atPath: firstTarget.path), "Quit did not wait for dismissed PNG export")
        let secondGate = QuickCaptureExportGate()
        let second = try await gatedModel(quitWorkspace, gate: secondGate)
        quitWorkspace.quickCapture = second
        let secondTarget = quitRoot.appendingPathComponent("second.png")
        precondition(second.exportPNG(to: secondTarget))
        for _ in 0..<100 where !(await secondGate.isStarted()) { try await Task.sleep(for: .milliseconds(10)) }
        quitWorkspace.dismissQuickCapture(second)
        await firstGate.release()
        try await Task.sleep(for: .milliseconds(100))
        let midQuitResult = await quitResult.read()
        precondition(midQuitResult == nil, "Quit completed before the second dismissed export was released")
        await secondGate.release()
        for _ in 0..<100 {
            if await quitResult.read() != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let finalQuitResult = await quitResult.read()
        precondition(finalQuitResult == true && FileManager.default.fileExists(atPath: firstTarget.path)
                     && FileManager.default.fileExists(atPath: secondTarget.path), "Released exports did not complete before quit")

        let failureGate = QuickCaptureExportGate()
        let failing = try await gatedModel(quitWorkspace, gate: failureGate)
        quitWorkspace.quickCapture = failing
        let failureTarget = quitRoot.appendingPathComponent("failure.png")
        // The writer starts and then fails, exercising the visible workspace error.
        let failingWriter: EditorModel.PNGWriter = { _, _ in await failureGate.pause(); throw CocoaError(.fileWriteUnknown) }
        let failingModel = EditorModel(image: failing.image, document: failing.document, generation: 0, store: quitWorkspace.store,
                                       writePNG: failingWriter, onSaved: {})
        quitWorkspace.quickCapture = failingModel
        precondition(failingModel.exportPNG(to: failureTarget))
        for _ in 0..<100 where !(await failureGate.started) { try await Task.sleep(for: .milliseconds(10)) }
        quitWorkspace.dismissQuickCapture(failingModel); await failureGate.release()
        for _ in 0..<100 where quitWorkspace.importError == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(quitWorkspace.importError != nil, "Dismissed export failure was not surfaced")
        let blockedFailureQuit = await quitWorkspace.flushBeforeQuitting()
        precondition(!blockedFailureQuit, "Unacknowledged dismissed export failure did not block quit")
        quitWorkspace.importError = nil
        let stillBlockedWithoutAck = await quitWorkspace.flushBeforeQuitting()
        precondition(!stillBlockedWithoutAck && quitWorkspace.importError != nil, "Clearing the error text alone acknowledged the dismissed export failure")
        quitWorkspace.acknowledgeImportError()
        let failureQuitSucceeded = await quitWorkspace.flushBeforeQuitting()
        precondition(failureQuitSucceeded, "Acknowledged dismissed export failure blocked quit")

        let libraryParent = root.appendingPathComponent("library-switch", isDirectory: true)
        let destination = libraryParent.appendingPathComponent("chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bookmarks = FolderBookmarkClient(create: { Data($0.path.utf8) }, resolve: { data in
            guard let path = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            return .init(url: URL(fileURLWithPath: path), stale: false)
        }, start: { _ in true }, stop: { _ in })
        let libraryWorkspace = WorkspaceModel(root: libraryParent.appendingPathComponent("old"), defaults: defaults, bookmarkClient: bookmarks)
        defer { libraryWorkspace.storage.endAccess() }
        let libraryGate = QuickCaptureExportGate()
        let exporting = try await gatedModel(libraryWorkspace, gate: libraryGate)
        let libraryExport = libraryParent.appendingPathComponent("before-switch.png")
        libraryWorkspace.quickCapture = exporting
        precondition(exporting.exportPNG(to: libraryExport))
        for _ in 0..<100 where !(await libraryGate.isStarted()) { try await Task.sleep(for: .milliseconds(10)) }
        let libraryWriterStarted = await libraryGate.isStarted()
        precondition(libraryWriterStarted)
        libraryWorkspace.dismissQuickCapture(exporting)
        let oldLibrary = libraryWorkspace.store.root
        let libraryResult = QuickCaptureResultBox()
        Task { await libraryResult.set(await libraryWorkspace.changeLibraryFolder(destination)) }
        try await Task.sleep(for: .milliseconds(100))
        let blockedLibraryResult = await libraryResult.read()
        precondition(blockedLibraryResult == nil && libraryWorkspace.store.root == oldLibrary,
                     "Library replacement did not wait for the dismissed export")
        await libraryGate.release()
        for _ in 0..<100 {
            if await libraryResult.read() != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let switchedLibraryResult = await libraryResult.read()
        precondition(switchedLibraryResult == true && libraryWorkspace.store.root != oldLibrary
                     && FileManager.default.fileExists(atPath: libraryExport.path), "Export or library replacement did not finish")
        let transferred = try await libraryWorkspace.store.load(exporting.document.id)
        precondition(transferred.document.pixelSize == exporting.document.pixelSize)
        print("Quick capture integration checks passed: window routing, stack/transfer/OCR; dismissed export ownership, successive quit gates, failure/explicit acknowledgment and gated library replacement")
    }
}
