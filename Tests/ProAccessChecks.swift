import AppKit
import SnagForgeDomain

enum ProAccessChecks {
    @MainActor static func run(image: CGImage) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProAccess-\(UUID())")
        let suite = "ProAccess-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let client = FakeProStore(), purchase = ProPurchaseModel(client: client)
        let workspace = WorkspaceModel(root: root, defaults: defaults, purchases: purchase)
        await purchase.start()
        defer { purchase.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func verify(_ value: Bool) { ReleaseWorkflowChecks.verify(value) }
        verify(!purchase.hasPro)
        verify(workspace.authorizeCapture(scrolling: false, video: false))
        verify(!workspace.authorizeCapture(scrolling: true, video: false))
        verify(workspace.requestedProFeature == .scrolling)
        verify(!workspace.authorizeCapture(scrolling: false, video: true))
        verify(!workspace.screenshot.isBusy)
        var videoCapture = workspace.captureConfiguration; videoCapture.media = .video
        workspace.screenshot.start(configuration: videoCapture, requestPermission: true) { _ in preconditionFailure("Free started a video") }
        verify(!workspace.screenshot.permissionWasRequested && !workspace.screenshot.isBusy)
        workspace.openScreenshot(image)
        try await ReleaseWorkflowChecks.wait { !workspace.isLoading }
        let editor = workspace.editor!, id = editor.document.id
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 80, y: 80))
        editor.commit([arrow]); verify(editor.history.objects == [arrow])
        editor.beginTextRecognition(); verify(!editor.isShowingTextRecognition)
        editor.tool = .callout; verify(editor.tool == .selection)
        editor.updateStyle(drawingStyle: .handDrawn)
        verify(editor.defaultArrowDrawingStyle == .precise)
        let callout = EditorObject(kind: .callout, start: CGPoint(x: 20, y: 20), text: "Paid explanation")
        editor.commit([arrow, callout]); verify(editor.history.objects == [arrow])
        verify(!editor.updateMetadata(tags: ["Paid"]))
        verify(!(await workspace.updateProjectMetadata(id, collections: ["Paid"])))
        verify(await workspace.updateProjectMetadata(id, title: "Free title", favorite: true))
        workspace.setOCRIndexing(true); verify(!defaults.bool(forKey: "library.ocrIndexingEnabled.v1"))
        workspace.guides.create(); workspace.createGuide(from: [id])
        verify(workspace.guides.document == nil && !workspace.guides.isBusy)
        // Cancellation and pending approval never grant access.
        await purchase.buy(); verify(!purchase.hasPro)
        client.outcome = .pending; await purchase.buy(); verify(!purchase.hasPro)
        client.outcome = .purchased; await purchase.buy(); verify(purchase.hasPro)
        verify(workspace.authorizeCapture(scrolling: true, video: false))
        verify(workspace.authorizeCapture(scrolling: false, video: true))
        editor.tool = .callout; verify(editor.tool == .callout)
        editor.commit([arrow, callout]); verify(editor.history.objects.count == 2)
        editor.beginTextRecognition(); verify(editor.isShowingTextRecognition)
        editor.isShowingTextRecognition = false
        verify(await workspace.updateProjectMetadata(id, tags: ["Keep me"], collections: ["Preserved collection"]))
        workspace.createGuide(from: [id])
        try await ReleaseWorkflowChecks.wait { !workspace.guides.isBusy }
        verify(workspace.guides.document?.steps.count == 1)
        // A guide capture becomes a library project and the final step without replacing the editor.
        let guideID = workspace.guides.document!.id, itemsBeforeGuideCapture = workspace.items.count
        workspace.addCaptureToGuide(image, guide: guideID)
        try await ReleaseWorkflowChecks.wait { !workspace.isLoading && !workspace.guides.isBusy && workspace.guides.document?.steps.count == 2 }
        let capturedStep = workspace.guides.document!.steps[1]
        verify(workspace.editor === editor && workspace.section == .guides && workspace.items.count == itemsBeforeGuideCapture + 1)
        verify(capturedStep.sourceProjectID != nil && workspace.guideSource(for: capturedStep) != nil)
        // A capture for a guide that is no longer open stays in the library only.
        workspace.addCaptureToGuide(image, guide: UUID())
        try await ReleaseWorkflowChecks.wait { !workspace.isLoading && workspace.items.count == itemsBeforeGuideCapture + 2 }
        verify(workspace.guides.document?.steps.count == 2 && workspace.guides.notice != nil)
        let guide = workspace.guides.document!
        let partial = try await workspace.videos.files.prepare(availableBytes: 1_000_000_000)
        try await ReleaseWorkflowChecks.movie(at: partial)
        let video = try await workspace.videos.files.finalize(partial)
        await workspace.videos.showPreview(recording: video)
        let preview = workspace.videos.preview!
        preview.end = preview.duration / 2
        verify(await preview.apply())
        let savedTrim = preview.document.trim
        let existingObjects = editor.history.objects
        client.owns = false; client.continuation?.yield(())
        try await ReleaseWorkflowChecks.wait { !purchase.hasPro }
        verify(editor.history.objects == existingObjects)
        verify(editor.document.tags == ["Keep me"])
        verify(workspace.guides.document == guide)
        workspace.guides.edit { $0.title = "Must not change" }
        verify(workspace.guides.document == guide)
        let oldEnd = preview.end
        preview.end = preview.duration
        verify(preview.end == oldEnd && preview.document.trim == savedTrim)
        verify(await preview.export(to: root.appendingPathComponent("Free-export.mp4")))
        preview.stopPreview(); workspace.videos.preview = nil
        workspace.guides.export(.pdf, to: root.appendingPathComponent("Free-guide.pdf"))
        try await ReleaseWorkflowChecks.wait { !workspace.guides.isBusy }
        verify(FileManager.default.fileExists(atPath: root.appendingPathComponent("Free-guide.pdf").path))
        verify(editor.exportPNG(to: root.appendingPathComponent("Free-image.png")))
        verify(await workspace.transfer(.completeBackup, at: root.appendingPathComponent("Free-backup.snaprivoall")))
        verify(await workspace.changeTrash(id, action: .trash))
        verify(await workspace.changeTrash(id, action: .restore))
        client.offered = nil; await purchase.reload()
        let before = client.purchases; await purchase.buy()
        verify(purchase.offer == nil && client.purchases == before && !purchase.hasPro)
        let euro = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))
        verify(ProOffer.laterPrice(displayPrice: ProOffer.launchPrice.formatted(euro), style: euro) != nil)
        verify(ProOffer.laterPrice(displayPrice: ProOffer.regularPrice.formatted(euro), style: euro) == nil)
        verify(ProOffer.laterPrice(displayPrice: Decimal(1.23).formatted(euro), style: euro) == nil)
        let dollar = Decimal.FormatStyle.Currency(code: "USD")
        verify(ProOffer.laterPrice(displayPrice: ProOffer.launchPrice.formatted(dollar), style: dollar) == nil)
        var output = ImageOutputOptions(); output.padding = 64; output.shadow = true; output.cornerRadius = 20
        let freeOutput = output.withoutPresentation
        verify(!freeOutput.hasPresentation && freeOutput.format == output.format && freeOutput.quality == output.quality)
        print("PASS: Free/Pro guards, paid workflows, purchase cancellation/pending/refund, existing data/export/backup/trash, Store-price launch/regular/unavailable/currency handling")
    }
}
