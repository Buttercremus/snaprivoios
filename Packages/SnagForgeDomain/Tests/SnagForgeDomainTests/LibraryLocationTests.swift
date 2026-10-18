import Foundation
import Testing
@testable import SnagForgeDomain

private func locationFixture() -> (URL, ProjectStore, ProjectDocument) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-location-\(UUID())")
    return (root, ProjectStore(root: root.appendingPathComponent("source")),
            ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 100, height: 80)!))
}

@Test func libraryCopyPreservesOriginalRevisionsThumbnailAndTrash() async throws {
    let (root, source, initial) = locationFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let original = Data([1, 2, 3]), thumbnail = Data([4, 5])
    try await source.create(initial, original: original, thumbnail: thumbnail)
    var edited = initial; edited.revision = 1
    edited.objects = [EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 40, y: 30))]
    try await source.save(edited, expectedGeneration: 0, thumbnail: thumbnail)
    let deleted = ProjectDocument(title: "Trash", pixelSize: initial.pixelSize)
    try await source.create(deleted, original: Data([6]), thumbnail: nil)
    try await source.moveToTrash(deleted.id)
    let destination = root.appendingPathComponent("destination")
    #expect(try await source.copyLibrary(to: destination) == 2)
    let copy = ProjectStore(root: destination)
    #expect(try await copy.load(initial.id).document == edited)
    #expect(try await copy.load(initial.id).original == original)
    #expect(try await copy.list().items.first?.thumbnail == thumbnail)
    #expect(try await copy.listTrash().items.map(\.id) == [deleted.id])
    let relative = "\(initial.id.uuidString).snagforge/Revisions/0.json"
    #expect(try Data(contentsOf: source.root.appendingPathComponent(relative)) == Data(contentsOf: destination.appendingPathComponent(relative)))
    try await copy.restore(deleted.id)
    #expect(try await source.listTrash().items.map(\.id) == [deleted.id])
    edited.revision = 2; edited.objects = []
    try await copy.save(edited, expectedGeneration: 1, thumbnail: nil)
    #expect(try await source.load(initial.id).generation == 1)
    #expect(try await copy.load(initial.id).generation == 2)
}

@Test func libraryCopyRefusesExistingAndNestedDestinations() async throws {
    let (root, source, document) = locationFixture(); defer { try? FileManager.default.removeItem(at: root) }
    try await source.create(document, original: Data([1]), thumbnail: nil)
    let existing = root.appendingPathComponent("existing")
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
    let sentinel = existing.appendingPathComponent("keep"); try Data([9]).write(to: sentinel)
    await #expect(throws: (any Error).self) { try await source.copyLibrary(to: existing) }
    #expect(try Data(contentsOf: sentinel) == Data([9]))
    for destination in [source.root, source.root.appendingPathComponent("nested"), root] {
        await #expect(throws: ProjectError.invalidDocument) { try await source.copyLibrary(to: destination) }
    }
    #expect(try await source.load(document.id).original == Data([1]))
}

@Test func libraryCopyFailureKeepsSourceAndRemovesStaging() async throws {
    let (root, source, document) = locationFixture(); defer { try? FileManager.default.removeItem(at: root) }
    try await source.create(document, original: Data([1]), thumbnail: nil)
    let project = source.root.appendingPathComponent("\(document.id.uuidString).snagforge")
    let outside = root.appendingPathComponent("outside"); try Data([7]).write(to: outside)
    try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("extra-link"), withDestinationURL: outside)
    let destination = root.appendingPathComponent("destination")
    await #expect(throws: ProjectError.invalidDocument) { try await source.copyLibrary(to: destination) }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".snaprivo-library-") })
    #expect(try await source.load(document.id).original == Data([1]))
    #expect(try Data(contentsOf: outside) == Data([7]))
}

@Test func libraryCopyRefusesIncompleteProjectWithoutPublishing() async throws {
    let (root, source, document) = locationFixture(); defer { try? FileManager.default.removeItem(at: root) }
    try await source.create(document, original: Data([1]), thumbnail: nil)
    try FileManager.default.removeItem(at: source.root.appendingPathComponent("\(document.id.uuidString).snagforge/original.png"))
    let destination = root.appendingPathComponent("destination")
    await #expect(throws: ProjectError.invalidDocument) { try await source.copyLibrary(to: destination) }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(try await source.list().issues.count == 1)
}

@Test func emptyLibraryCanMoveBeforeFirstCapture() async throws {
    let (root, source, _) = locationFixture(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let destination = root.appendingPathComponent("destination")
    #expect(try await source.copyLibrary(to: destination) == 0)
    #expect(try await ProjectStore(root: destination).list().items.isEmpty)
}
