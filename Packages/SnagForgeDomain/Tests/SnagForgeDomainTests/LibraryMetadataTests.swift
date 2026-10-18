import Foundation
import Testing
@testable import SnagForgeDomain

@Test func libraryMetadataPersistsWithoutChangingImageOrAnnotations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    let object = EditorObject(kind: .arrow, start: .zero, end: CGPoint(x: 50, y: 50))
    let doc = ProjectDocument(title: "Before", pixelSize: PixelSize(width: 100, height: 100)!, objects: [object])
    let original = Data([1, 2, 3]), thumb = Data([4, 5])
    try await store.create(doc, original: original, thumbnail: thumb)
    try await store.updateMetadata(doc.id, title: "  After  ", favorite: true)
    let loaded = try await ProjectStore(root: root).load(doc.id)
    #expect(loaded.document.title == "After" && loaded.document.isFavorite)
    #expect(loaded.document.objects == [object] && loaded.original == original)
    #expect(loaded.document.id == doc.id && loaded.document.createdAt == doc.createdAt)
    let listing = try await store.list()
    #expect(listing.items[0].thumbnail == thumb)
    try await store.updateMetadata(doc.id, title: "After", favorite: true)
    #expect(try await store.load(doc.id).generation == loaded.generation)
    try await store.updateMetadata(doc.id, favorite: false)
    #expect(try await store.load(doc.id).document.isFavorite == false)
    await #expect(throws: ProjectError.invalidDocument) { try await store.updateMetadata(doc.id, title: " \n ") }
    await #expect(throws: ProjectError.invalidDocument) { try await store.updateMetadata(doc.id, title: String(repeating: "x", count: 1025)) }
    var stale = doc; stale.revision = 99
    await #expect(throws: ProjectError.staleRevision) { try await store.save(stale, expectedGeneration: 0, thumbnail: nil) }
}

@Test func oldProjectsDefaultToNotFavorite() throws {
    let doc = ProjectDocument(title: "Old", pixelSize: PixelSize(width: 10, height: 10)!)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
    json.removeValue(forKey: "favorite"); json["schemaVersion"] = 3
    #expect(try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)).isFavorite == false)
}
