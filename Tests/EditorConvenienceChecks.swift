import AppKit
import SnagForgeDomain

@main struct EditorConvenienceChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Convenience-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let objects = [EditorObject(kind: .arrow, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 100, y: 100)),
                       EditorObject(kind: .ellipse, start: CGPoint(x: 140, y: 40), end: CGPoint(x: 200, y: 100)),
                       EditorObject(kind: .rectangle, start: CGPoint(x: 240, y: 40), end: CGPoint(x: 300, y: 100))]
        let doc = ProjectDocument(title: "Synthetic groups", pixelSize: PixelSize(width: 800, height: 600)!, objects: objects)
        let store = ProjectStore(root: root)
        try await store.create(doc, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.select(objects[0].id); model.select(objects[1].id, extending: true)
        precondition(model.selectedIDs.count == 2 && model.selectedObject == nil)
        model.groupSelection(); let grouped = model.history.objects
        precondition(grouped[0].groupID != nil && grouped[0].groupID == grouped[1].groupID && grouped[2].groupID == nil)
        model.selection = nil; model.select(objects[1].id)
        precondition(model.selectedIDs.count == 2)
        model.duplicateSelection()
        precondition(model.history.objects.count == 5 && model.selectedIDs.count == 2)
        let copies = model.history.objects.suffix(2)
        precondition(copies.first!.groupID == copies.last!.groupID && copies.first!.groupID != grouped[0].groupID)
        model.groupSelection(ungroup: true)
        precondition(model.history.objects.suffix(2).allSatisfy { $0.groupID == nil })
        model.removeSelection(); precondition(model.history.objects == grouped)
        model.undo(); precondition(model.history.objects.count == 5)
        model.redo(); precondition(model.history.objects == grouped)
        let saved = await model.flush(); precondition(saved)
        let loaded = try await store.load(doc.id); precondition(loaded.document.objects == grouped)
        model.selectAllObjects(); precondition(model.selectedIDs.count == 3)
        model.removeSelection(); precondition(model.history.objects.isEmpty)
        model.undo(); precondition(model.history.objects == grouped)
        _ = await model.flush()
        ctx.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let asset = try EditorImageAsset(png: EditorRenderer.png(image: ctx.makeImage()!, objects: []), size: PixelSize(width: 800, height: 600)!)
        var picture = EditorObject(kind: .image, start: CGPoint(x: 100, y: 200), end: CGPoint(x: 300, y: 350))
        picture.imageAsset = asset
        model.commit(model.history.objects + [picture]); let assetSaved = await model.flush(); precondition(assetSaved)
        let reopened = try await store.load(doc.id)
        precondition(reopened.document.objects.last?.imageAsset == asset)
        let package = root.appendingPathComponent(doc.id.uuidString + ".snagforge")
        precondition(FileManager.default.fileExists(atPath: package.appendingPathComponent("Assets/" + asset.digest + ".png").path))
        let revision = try String(contentsOf: package.appendingPathComponent("Revisions/\(reopened.generation).json"), encoding: .utf8)
        precondition(!revision.contains(asset.png.base64EncodedString()))
        let archive = try ProjectArchive(document: reopened.document, original: reopened.original)
        let imported = try await store.importProject(archive, thumbnail: nil)
        let importedDoc = try await store.load(imported)
        precondition(importedDoc.document.objects.last?.imageAsset == asset)
        let backupURL = root.appendingPathExtension("backup"), restoredRoot = root.appendingPathExtension("restored")
        defer { try? FileManager.default.removeItem(at: backupURL); try? FileManager.default.removeItem(at: restoredRoot) }
        _ = try await store.backup(to: backupURL)
        let recoveredStore = ProjectStore(root: restoredRoot)
        _ = try await recoveredStore.restoreBackup(from: backupURL, thumbnail: { _ in Data() })
        let recoveredDoc = try await recoveredStore.load(doc.id)
        precondition(recoveredDoc.document.objects.last?.imageAsset == asset)
        let output = try EditorRenderer.png(image: image, objects: reopened.document.objects)
        let pixel = NSBitmapImageRep(data: output)!.colorAt(x: 200, y: 250)!.usingColorSpace(.deviceRGB)!
        precondition(pixel.greenComponent > 0.6 && pixel.redComponent < 0.3)
        let preparedURL = root.appendingPathComponent("prepared-output.bin")
        let preparedData = Data("Synthetic flattened export".utf8)
        let pending = Task { await model.exportPreparedOutput(to: preparedURL) {
            try await Task.sleep(for: .milliseconds(150)); return preparedData
        } }
        while !model.isExportingPNG { await Task.yield() }
        let finished = await model.finishPendingWork()
        let exported = await pending.value
        precondition(finished && exported)
        let preparedRead = try Data(contentsOf: preparedURL); precondition(preparedRead == preparedData)
        print("Prepared output checks passed: pending-work completion waits for the exported file.")
        print("Image asset checks passed: separate files, compact revisions, reopen, archive import and rendered pixels.")
        print("Multi-selection checks passed: toggle, group selection, independent duplicate groups, ungroup, delete, undo/redo, select all and persistence.")
    }
}
