import AppKit
import SnagForgeDomain

@main struct TrashChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Library-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceModel(root: root)
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!, png = try EditorRenderer.png(image: image, objects: [])
        let doc = ProjectDocument(title: "Trash fixture", pixelSize: PixelSize(width: 20, height: 20)!, isFavorite: true)
        try await workspace.store.create(doc, original: png, thumbnail: png)
        workspace.openProject(doc.id)
        for _ in 0..<500 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let editor = workspace.editor!
        editor.editText(at: .zero); editor.updateText("Pending text")
        let moved = await workspace.changeTrash(doc.id, action: .trash)
        precondition(moved && workspace.editor == nil && workspace.items.isEmpty && workspace.trashItems.count == 1)
        let fresh = WorkspaceModel(root: root); await fresh.refreshLibrary()
        precondition(fresh.trashItems[0].document.objects[0].text == "Pending text")
        let restored = await fresh.changeTrash(doc.id, action: .restore); precondition(restored)
        let loaded = try await fresh.store.load(doc.id)
        precondition(loaded.original == png && loaded.document.isFavorite && loaded.document.objects[0].text == "Pending text")
        let movedAgain = await fresh.changeTrash(doc.id, action: .trash); precondition(movedAgain)
        let deleted = await fresh.changeTrash(doc.id, action: .delete); precondition(deleted)
        let final = WorkspaceModel(root: root); await final.refreshLibrary()
        precondition(final.items.isEmpty && final.trashItems.isEmpty)
        print("Trash checks passed: open editor pending text flush, close after trash, restart, restore original/favorite/objects and permanent deletion of synthetic fixture.")
    }
}
