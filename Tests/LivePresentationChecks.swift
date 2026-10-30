import AppKit
import SnagForgeDomain

@main struct LivePresentationChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-LivePresentation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ctx = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 120, y: 0, width: 120, height: 80))
        let image = ctx.makeImage()!
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 240, height: 160)!, objects: [mask])
        let store = ProjectStore(root: root.appendingPathComponent("Projects"))
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        var style = EditorPresentation(); style.rotationDegrees = 27.5; style.padding = 40; style.cornerRadius = 16
        style.background = .gradient(PresentationBackgroundCatalog.gradients[0]); style.shadowStrength = 0.3; style.aspectRatio = .wide
        model.beginPresentationEditing()
        var intermediate = style; intermediate.rotationDegrees = 10; model.updatePresentation(intermediate)
        model.updatePresentation(style); model.endPresentationEditing()
        precondition(model.history.presentation == style && model.document.presentation == style)
        model.undo(); precondition(model.history.presentation.isIdentity && model.document.presentation == nil)
        model.redo(); precondition(model.history.presentation == style)
        model.isEditingPresentation = true
        model.selectObjectFromList(mask.id)
        precondition(!model.isEditingPresentation && model.selection == mask.id && model.history.presentation == style)
        do {
            _ = try EditorRenderer.render(image: image, objects: [mask], crop: .zero, presentation: style)
            preconditionFailure("Invalid crop accepted")
        } catch { }
        let flattened = try EditorRenderer.render(image: image, objects: [mask], presentation: style)
        let geometry = style.geometry(for: document.pixelSize)!
        precondition(flattened.width == geometry.outputSize.width && flattened.height == geometry.outputSize.height)
        let redacted = CGPoint(x: 50, y: 50).applying(geometry.imageTransform)
        let pixel = EditorRenderer.pixelColor(flattened, x: Int(redacted.x), y: Int(redacted.y))!
        precondition(pixel.redComponent < 0.02 && pixel.blueComponent < 0.02 && pixel.alphaComponent > 0.99, "Rotation exposed masked pixels")
        let corners = [CGPoint(x: 1, y: 1), CGPoint(x: flattened.width - 2, y: flattened.height - 2)]
        for corner in corners { precondition(EditorRenderer.pixelColor(flattened, x: Int(corner.x), y: Int(corner.y))!.alphaComponent > 0.99) }
        let preview = try EditorRenderer.render(image: image, objects: [mask], maxDimension: 200, presentation: style)
        precondition(max(preview.width, preview.height) <= 200)
        precondition(abs(Double(preview.width) / Double(preview.height) - Double(flattened.width) / Double(flattened.height)) < 0.02)
        var transparent = EditorPresentation(); transparent.rotationDegrees = 31
        let transparentPNG = try EditorRenderer.render(image: image, objects: [mask], presentation: transparent)
        precondition(EditorRenderer.pixelColor(transparentPNG, x: 0, y: 0)!.alphaComponent < 0.01, "Rotation unexpectedly added an opaque background")
        let options = ImageOutputOptions(presentation: transparent)
        precondition(options.presentation.background == nil && options.presentation.rotationDegrees == 31)
        let optionsImage = try ImageOutput.compose(image, options: options)
        precondition(EditorRenderer.pixelColor(optionsImage, x: 0, y: 0)!.alphaComponent > 0.99, "JPEG must be opaque")
        let importedFile = root.appendingPathComponent("background.png")
        try EditorRenderer.png(image: image, objects: []).write(to: importedFile)
        let asset = try PresentationBackgroundStorage.importAsset(from: importedFile)
        try FileManager.default.removeItem(at: importedFile)
        style.background = .asset(asset, blur: 4)
        model.updatePresentation(style)
        let flushed = await model.flush(); precondition(flushed)
        let loaded = try await store.load(document.id)
        precondition(loaded.document.presentation == style && loaded.document.objects == [mask])
        let reopened = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        precondition(reopened.history.presentation == style)
        let shareFile = try await reopened.pngShareItemForToolbar!.writeTemporaryPNG(in: root)
        let shareSource = CGImageSourceCreateWithURL(shareFile as CFURL, nil)!
        let shared = CGImageSourceCreateImageAtIndex(shareSource, 0, nil)!
        precondition(shared.width == loaded.document.outputPixelSize.width && shared.height == loaded.document.outputPixelSize.height)
        let archiveFile = root.appendingPathComponent("portable.snaprivo")
        try await store.exportProject(document.id, to: archiveFile)
        let archive = try ProjectArchive.read(from: archiveFile)
        let freshStore = ProjectStore(root: root.appendingPathComponent("OtherMac"))
        let importedID = try await freshStore.importProject(archive, thumbnail: nil)
        let imported = try await freshStore.load(importedID)
        precondition(imported.document.presentation == style)
        let importedImage = try EditorRenderer.render(image: image, objects: imported.document.objects, presentation: imported.document.presentation)
        precondition(importedImage.width == shared.width && importedImage.height == shared.height)
        let backup = root.appendingPathComponent("LibraryBackup")
        let count = try await store.backup(to: backup); precondition(count == 1)
        let backupStore = ProjectStore(root: root.appendingPathComponent("RestoredBackup"))
        let restoredIDs = try await backupStore.restoreBackupIDs(from: backup, thumbnail: { _ in Data() })
        let backupDocument = try await backupStore.readDocument(restoredIDs[0])
        precondition(backupDocument.presentation == style)
        let suite = "Snaprivo-PresentationCheck-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(PresentationPresetStore.save([PresentationPreset(name: "Synthetic", options: ImageOutputOptions(presentation: style))], defaults: defaults))
        precondition(PresentationPresetStore.load(defaults: defaults).first?.options.presentation == style)
        let export = root.appendingPathComponent("export.png")
        precondition(reopened.exportPNG(to: export))
        let finished = await reopened.finishPendingWork(); precondition(finished)
        precondition(CGImageSourceCreateWithURL(export as CFURL, nil) != nil)
        print("Live presentation checks passed: free angles, opaque masks, alpha, bounded preview, grouped undo, own image assets, reopening, portable projects/backups, presets and PNG export/share")
    }
}
