import Foundation
import Testing
@testable import SnagForgeDomain

@Test func trashRestoreAndDeletePersistAcrossStoreInstances() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    let object = EditorObject(kind: .text, start: .zero, text: "Keep")
    let doc = ProjectDocument(title: "Trash", pixelSize: PixelSize(width: 100, height: 100)!, objects: [object], isFavorite: true)
    let original = Data([1,2,3]), thumb = Data([4,5])
    try await store.create(doc, original: original, thumbnail: thumb)
    await #expect(throws: (any Error).self) { try await store.permanentlyDelete(doc.id) }
    #expect(try await store.load(doc.id).document == doc)
    try await store.moveToTrash(doc.id)
    #expect(try await store.list().items.isEmpty)
    let fresh = ProjectStore(root: root), trash = try await fresh.listTrash()
    #expect(trash.items.count == 1 && trash.items[0].document == doc && trash.items[0].thumbnail == thumb)
    var stale = doc; stale.revision = 1
    await #expect(throws: (any Error).self) { try await store.save(stale, expectedGeneration: 0, thumbnail: nil) }
    try await fresh.restore(doc.id)
    #expect(try await fresh.load(doc.id).original == original)
    #expect(try await fresh.load(doc.id).document == doc)
    #expect(try await fresh.listTrash().items.isEmpty)
    try await fresh.moveToTrash(doc.id)
    // A collision must preserve both packages rather than overwrite either one.
    try await fresh.create(doc, original: original, thumbnail: thumb)
    await #expect(throws: (any Error).self) { try await fresh.restore(doc.id) }
    #expect(try await fresh.listTrash().items.count == 1)
    try await fresh.permanentlyDelete(doc.id)
    #expect(try await ProjectStore(root: root).listTrash().items.isEmpty)
    #expect(try await fresh.load(doc.id).original == original)
}

@Test func interruptedDeletionIntentIsResumed() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    let doc = ProjectDocument(title: "Delete intent", pixelSize: PixelSize(width: 10, height: 10)!)
    try await store.create(doc, original: Data([1]), thumbnail: nil)
    try await store.moveToTrash(doc.id)
    let trash = root.appendingPathComponent(".Trash")
    let pending = trash.appendingPathComponent(doc.id.uuidString + ".deleting")
    try FileManager.default.moveItem(at: trash.appendingPathComponent(doc.id.uuidString + ".snagforge"), to: pending)
    let listing = try await ProjectStore(root: root).listTrash()
    #expect(listing.items.isEmpty && listing.issues.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: pending.path))
}
