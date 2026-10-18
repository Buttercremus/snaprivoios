import Foundation
import Testing
@testable import SnagForgeDomain

private func projectFixture() -> ProjectDocument {
    var objects = [EditorObject.Kind.arrow, .text, .rectangle, .ellipse, .callout, .blur, .triangle, .diamond, .star].map {
        EditorObject(kind: $0, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 70, y: 90), text: "Zeile 1\nÜberschrift →", fontSize: 38, lineWidth: 7)
    }
    objects[0].color = EditorColor(red: 0.1, green: 0.7, blue: 0.4)
    objects[5].blurRadius = 24
    objects[2].fill = EditorFill(isEnabled: true, color: EditorColor(red: 0.2, green: 0.6, blue: 0.9), opacity: 0.45)
    objects[2].cornerRadius = 18
    objects[3].fill = EditorFill(isEnabled: false, opacity: 0.7)
    objects[4].fill = EditorFill(isEnabled: true, color: EditorColor(red: 1, green: 0.8, blue: 0.2), opacity: 0.85)
    objects[4].textWidth = 140; objects[4].textHeight = 100
    objects[6].stroke = EditorStroke(style: .dashed)
    objects[7].stroke = EditorStroke(style: .dotted)
    objects[8].stroke = EditorStroke(isEnabled: false)
    objects[8].fill = EditorFill(isEnabled: true, color: objects[0].color)
    return ProjectDocument(title: "Synthetisches Projekt", pixelSize: PixelSize(width: 240, height: 160)!, objects: objects)
}
private func temporaryLibrary() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("SnagForge-tests-\(UUID().uuidString)")
}
private func package(_ root: URL, _ id: UUID) -> URL {
    root.appendingPathComponent("\(id.uuidString).snagforge")
}

@Test func projectRoundTripPreservesEveryEditableProperty() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), original = Data("immutable source".utf8)
    let initial = projectFixture()
    try await store.create(initial, original: original, thumbnail: Data("thumb".utf8))
    var next = initial; next.revision = 1; next.objects[1].text = "Bearbeitet"; next.modifiedAt = .now
    try await store.save(next, expectedGeneration: 0, thumbnail: nil)
    let afterRestart = try await ProjectStore(root: root).load(initial.id)
    #expect(afterRestart.document == next)
    #expect(afterRestart.original == original)
    #expect(!afterRestart.recovered)
    let listing = try await ProjectStore(root: root).list()
    #expect(listing.items.count == 1 && listing.issues.isEmpty)
    #expect(listing.items.first?.document.objects == next.objects)
}

@Test func corruptLastRevisionRecoversAndCanBeSavedAgain() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    var document = projectFixture()
    try await store.create(document, original: Data([1]), thumbnail: nil)
    document.revision = 1; document.objects.removeLast()
    try await store.save(document, expectedGeneration: document.revision - 1, thumbnail: nil)
    let previous = document
    document.revision = 2; document.objects.removeLast()
    try await store.save(document, expectedGeneration: document.revision - 1, thumbnail: nil)
    let folder = package(root, document.id)
    try Data("interrupted/corrupt".utf8).write(to: folder.appendingPathComponent("Revisions/2.json"))
    let recovered = try await ProjectStore(root: root).load(document.id)
    #expect(recovered.recovered)
    #expect(recovered.document == previous)
    #expect(recovered.generation == 2)
    var repaired = recovered.document; repaired.revision = recovered.generation + 1
    try await store.save(repaired, expectedGeneration: 2, thumbnail: nil)
    let loaded = try await store.load(document.id)
    #expect(!loaded.recovered && loaded.document == repaired)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Revisions/1.json").path))
}

@Test func failedWriteKeepsLastCompleteProject() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), initial = projectFixture()
    try await store.create(initial, original: Data([1,2,3]), thumbnail: nil)
    var next = initial; next.revision = 1; next.objects = []
    let blocked = package(root, initial.id).appendingPathComponent("Revisions/1.json")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) { try await store.save(next, expectedGeneration: 0, thumbnail: nil) }
    #expect(try await store.load(initial.id).document == initial)
    try FileManager.default.removeItem(at: blocked)
    try await store.save(next, expectedGeneration: 0, thumbnail: nil)
    #expect(try await store.load(initial.id).document == next)
}

@Test func futureVersionAndStaleWritersNeverOverwrite() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), initial = projectFixture()
    try await store.create(initial, original: Data([1]), thumbnail: nil)
    var next = initial; next.revision = 1
    try await store.save(next, expectedGeneration: 0, thumbnail: nil)
    await #expect(throws: ProjectError.staleRevision) { try await store.save(next, expectedGeneration: 0, thumbnail: nil) }
    let url = package(root, initial.id).appendingPathComponent("Revisions/1.json")
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    json["schemaVersion"] = 99
    let future = try JSONSerialization.data(withJSONObject: json)
    try future.write(to: url)
    await #expect(throws: ProjectError.unsupportedVersion) { try await store.load(initial.id) }
    next.revision = 2
    await #expect(throws: ProjectError.unsupportedVersion) { try await store.save(next, expectedGeneration: 1, thumbnail: nil) }
    #expect(try Data(contentsOf: url) == future)
}

@Test func invalidProjectsAreReportedWithoutHidingHealthyOnes() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), good = projectFixture(), bad = projectFixture()
    try await store.create(good, original: Data([1]), thumbnail: nil)
    try await store.create(bad, original: Data([2]), thumbnail: nil)
    try FileManager.default.removeItem(at: package(root, bad.id).appendingPathComponent("original.png"))
    let listing = try await store.list()
    #expect(listing.items.map(\.id) == [good.id])
    #expect(listing.issues.count == 1)
    var invalid = good; invalid.objects[0].lineWidth = -1
    #expect(throws: ProjectError.invalidDocument) { try invalid.validated() }
}

@Test func competingStoresRejectStaleBaseEvenWithHigherRevision() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let first = ProjectStore(root: root), second = ProjectStore(root: root), initial = projectFixture()
    try await first.create(initial, original: Data([1]), thumbnail: nil)
    var one = initial; one.revision = 1
    try await first.save(one, expectedGeneration: 0, thumbnail: nil)
    var stale = initial; stale.revision = 5; stale.objects = []
    await #expect(throws: ProjectError.staleRevision) { try await second.save(stale, expectedGeneration: 0, thumbnail: nil) }
    #expect(try await first.load(initial.id).document == one)
}

@Test func oversizedRevisionCannotCommitAnUnreadableProject() async throws {
    let root = temporaryLibrary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), initial = projectFixture()
    try await store.create(initial, original: Data([1]), thumbnail: nil)
    var huge = initial; huge.revision = 1
    huge.objects = (0..<33).map { _ in
        EditorObject(kind: .text, start: .zero, text: String(repeating: "a", count: 1_000_000))
    }
    await #expect(throws: ProjectError.documentTooLarge) { try await store.save(huge, expectedGeneration: 0, thumbnail: nil) }
    #expect(try await store.load(initial.id).document == initial)
    var new = huge; new.revision = 0
    await #expect(throws: ProjectError.documentTooLarge) { try await store.create(new, original: Data([1]), thumbnail: nil) }
}
