import AppKit
import AVFoundation
import SwiftUI
import SnagForgeDomain

@MainActor final class FakeProStore: ProStoreClient {
    var owns = false
    var offered: ProOffer? = ProOffer(name: "Synthetic Pro", price: "EUR29.99", laterPrice: "EUR39.99")
    var outcome = ProPurchaseOutcome.cancelled
    var fails = false
    var purchases = 0
    var continuation: AsyncStream<Void>.Continuation?
    func offer() async throws -> ProOffer? {
        if fails { throw CocoaError(.fileReadUnknown) }
        return offered
    }
    func entitled() async throws -> Bool { if fails { throw CocoaError(.fileReadUnknown) }; return owns }
    func purchase() async throws -> ProPurchaseOutcome {
        purchases += 1
        if fails { throw CocoaError(.fileReadUnknown) }
        if case .purchased = outcome { owns = true }
        return outcome
    }
    func restore() async throws { if fails { throw CocoaError(.fileReadUnknown) } }
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}

@main struct ReleaseWorkflowChecks {
    static func verify(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Workflow assertion", file: file, line: line) }
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        preconditionFailure("Operation did not finish")
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Workflows-\(UUID())")
        let suite = "Snaprivo-Workflows-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let owned = FakeProStore(); owned.owns = true
        let entitlement = ProPurchaseModel(client: owned)
        await entitlement.start()
        defer { entitlement.stop() }
        let workspace = WorkspaceModel(root: root.appendingPathComponent("source"), defaults: defaults, purchases: entitlement)
        let context = CGContext(data: nil, width: 480, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
        let image = context.makeImage()!
        workspace.openScreenshot(image); try await wait { !workspace.isLoading }
        let model = workspace.editor!, originalID = model.document.id
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 40), end: CGPoint(x: 200, y: 200))
        arrow.name = "Pointer"
        model.commit([arrow])
        verify(model.renameObject(arrow.id, name: "Named arrow"))
        model.undo(); verify(model.history.objects.first?.name == "Pointer")
        model.redo(); verify(model.history.objects.first?.name == "Named arrow")
        let saved = await model.flush(); verify(saved)
        let reopened = try await workspace.store.load(originalID); verify(reopened.document.objects.first?.name == "Named arrow")
        workspace.openScreenshot(image); try await wait { !workspace.isLoading }
        let secondID = workspace.editor!.document.id
        workspace.createGuide(from: [secondID, originalID]); try await wait { !workspace.guides.isBusy }
        verify(workspace.guides.document?.steps.count == 2)
        workspace.guides.edit { $0.style = .compact }; let guideSaved = await workspace.guides.flush(); verify(guideSaved)
        workspace.createGuide(from: [originalID]); try await wait { !workspace.guides.isBusy }
        verify(workspace.guides.document?.style == .compact)
        _ = await workspace.changeTrash(secondID, action: .trash)
        let partial = try await workspace.videos.files.prepare(availableBytes: 1_000_000_000)
        try await movie(at: partial)
        _ = try await workspace.videos.files.finalize(partial)
        await workspace.videos.refresh()
        let videoID = workspace.videos.items[0].id, movieURL = try await workspace.videos.files.movieURL(videoID)
        let videoBytes = try Data(contentsOf: movieURL)
        verify(workspace.videos.items[0].bytes > 0)
        verify(await workspace.videos.changeTrash(videoID, action: .trash))
        verify(try await workspace.videos.files.document(videoID).trashedAt != nil)
        verify(try Data(contentsOf: movieURL) == videoBytes)
        // Interrupted media is backed up as opaque bytes, never promoted to a playable video.
        let failed = try await workspace.videos.files.prepare(availableBytes: 1_000_000_000)
        try Data("unfinished".utf8).write(to: failed)
        try await workspace.videos.files.markFailed(failed, message: "Synthetic interruption")
        let backup = root.appendingPathComponent("Everything.snaprivoall")
        verify(await workspace.transfer(.completeBackup, at: backup))
        let target = WorkspaceModel(root: root.appendingPathComponent("target"), defaults: defaults)
        let restored = await target.transfer(.restoreComplete, at: backup)
        if !restored { FileHandle.standardError.write(Data((target.importError ?? "No error").utf8)) }
        verify(restored)
        verify(target.items.count == 1 && target.trashItems.count == 1)
        verify(target.guides.documents.count == 2 && target.videos.items.count == 2)
        let restoredGuide = try await target.guides.store.load(target.guides.documents.first { $0.stepCount == 2 }!.id).document
        let allIDs = Set((target.items + target.trashItems).map(\.id))
        verify(restoredGuide.steps.allSatisfy { $0.sourceProjectID.map(allIDs.contains) == true })
        let restoredVideo = target.videos.items.first { $0.document.state == .finished }!
        verify(restoredVideo.document.trashedAt != nil)
        verify(await target.videos.changeTrash(restoredVideo.id, action: .restore))
        verify(try Data(contentsOf: await target.videos.files.movieURL(restoredVideo.id)) == videoBytes)
        verify(await target.videos.changeTrash(restoredVideo.id, action: .trash))
        verify(await target.videos.changeTrash(restoredVideo.id, action: .delete))
        verify(!FileManager.default.fileExists(atPath: target.videos.files.root.appendingPathComponent(restoredVideo.document.fileName).path))
        // Repeated restore appends fresh identities and retains existing contents.
        verify(await target.transfer(.restoreComplete, at: backup))
        verify(target.items.count == 2 && target.trashItems.count == 2 && target.guides.documents.count == 4)
        // Tampering must reject the whole backup before touching any destination store.
        let guideFolder = backup.appendingPathComponent("guides")
        let guideFile = try FileManager.default.contentsOfDirectory(at: guideFolder, includingPropertiesForKeys: nil)[0]
        let original = try Data(contentsOf: guideFile)
        try Data("corrupt".utf8).write(to: guideFile)
        verify(!(await target.transfer(.restoreComplete, at: backup)))
        verify(target.items.count == 2 && target.guides.documents.count == 4)
        try original.write(to: guideFile)
        // A failure publishing the final component rolls back only this operation.
        let blockedRoot = root.appendingPathComponent("blocked-guides")
        try FileManager.default.createDirectory(at: blockedRoot.appendingPathComponent(".guide-lock"), withIntermediateDirectories: true)
        let beforeImages = target.items.count, beforeVideos = target.videos.items.count
        do {
            _ = try await CompleteBackup(images: target.store, videos: target.videos.files, guides: GuideStore(root: blockedRoot)).restore(from: backup)
            preconditionFailure("Final-component write failure accepted")
        } catch { }
        await target.refreshLibrary()
        verify(target.items.count == beforeImages && target.videos.items.count == beforeVideos)
        // Native opening uses the same validated additive import path.
        let portable = root.appendingPathComponent("Open.snaprivo")
        try await workspace.store.exportProject(originalID, to: portable)
        await target.openExternalFile(portable); verify(target.items.count == 3 && target.editor != nil)
        await target.openExternalFile(guideFile); verify(target.guides.documents.count == 5)
        let coldDelegate = SnagForgeDelegate()
        let beforeFinder = target.items.count
        await coldDelegate.openFiles([portable, portable])
        coldDelegate.workspace = target
        try await wait { target.items.count == beforeFinder + 2 }
        // A user-selected previous container is copied through the same validation path.
        let legacy = root.appendingPathComponent("legacy/Data/Library/Application Support")
        let oldImages = ProjectStore(root: legacy.appendingPathComponent("SnagForge/Projects"))
        let archive = try ProjectArchive.read(from: portable)
        _ = try await oldImages.importProject(archive, thumbnail: nil)
        let imageCountBeforeMigration = target.items.count
        verify(await target.transfer(.importLegacy, at: root.appendingPathComponent("legacy")))
        verify(target.items.count == imageCountBeforeMigration + 1)
        verify(try await oldImages.list().items.count == 1)
        // Optional preview preserves an existing editor until the explicit edit action.
        workspace.preferences.quickPreviewAfterCapture = true
        let previousID = workspace.editor?.document.id
        workspace.openScreenshot(image); try await wait { !workspace.isLoading }
        verify(workspace.quickCapture != nil && workspace.editor?.document.id == previousID)
        let discardedID = workspace.quickCapture!.document.id
        await workspace.discardQuickCapture()
        verify(workspace.quickCapture == nil && workspace.trashItems.contains { $0.id == discardedID })
        workspace.openScreenshot(image); try await wait { !workspace.isLoading }
        let quickID = workspace.quickCapture!.document.id
        workspace.editQuickCapture(); verify(workspace.editor?.document.id == quickID && workspace.quickCapture == nil)
        try await purchases()
        try await ProAccessChecks.run(image: image)
        print("PASS: complete backup/restore, trash, bytes, interrupted media, corruption rejection, Finder routing, guides, object names/undo, quick preview, purchase states")
    }
    @MainActor static func purchases() async throws {
        let fake = FakeProStore(), blocked = FakeProStore()
        blocked.outcome = .purchased
        let model = ProPurchaseModel(client: blocked, purchasesEnabled: false)
        await model.start(); await model.buy(); verify(!model.hasPro && blocked.purchases == 0); model.stop()
        let store = ProPurchaseModel(client: fake, purchasesEnabled: true)
        await store.start(); verify(store.offer?.price == "EUR29.99")
        await store.buy(); verify(!store.hasPro && store.message == nil)
        fake.outcome = .pending; await store.buy(); verify(!store.hasPro && store.message != nil)
        fake.offered = ProOffer(name: "Synthetic Pro", price: "EUR39.99")
        let purchasesBeforePriceChange = fake.purchases
        await store.buy()
        verify(fake.purchases == purchasesBeforePriceChange && !store.hasPro && store.offer?.price == "EUR39.99" && store.message != nil)
        fake.outcome = .purchased; await store.buy(); verify(store.hasPro)
        let restarted = ProPurchaseModel(client: fake, purchasesEnabled: true)
        await restarted.start(); verify(restarted.hasPro)
        fake.owns = false; fake.continuation?.yield(())
        try await wait { !restarted.hasPro }
        fake.fails = true; await store.restore(); verify(store.error != nil)
        fake.fails = false; await store.restore(); verify(!store.hasPro)
        store.stop(); restarted.stop()
    }
    static func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input); verify(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var pixel: CVPixelBuffer?; verify(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel) == kCVReturnSuccess)
            let buffer = pixel!; CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 7), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            verify(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished(); await writer.finishWriting(); verify(writer.status == .completed)
    }
}
