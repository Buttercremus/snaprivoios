import Foundation
import Testing
@testable import SnagForgeDomain

private func searchDocument() -> ProjectDocument {
    ProjectDocument(title: "Support München", pixelSize: PixelSize(width: 800, height: 600)!, tags: ["Fehler", "Login"], collections: ["Kundenhilfe"])
}

@Test func organizationNamesNormalizeValidateAndDeduplicate() throws {
    #expect(try ProjectOrganization.normalized(["  München ", "munchen", "", "LOGIN", "login"], limit: 32) == ["München", "LOGIN"])
    for names in [[String(repeating: "a", count: 81)], ["bad\nname"], ["bad\0name"], (0..<33).map(String.init)] {
        #expect(throws: ProjectError.self) { try ProjectOrganization.normalized(names, limit: 32) }
    }
    var document = searchDocument(); document.tags = [" duplicate "]
    #expect(throws: ProjectError.self) { try document.validated() }
    document.tags = ["A", "a"]
    #expect(throws: ProjectError.self) { try document.validated() }
}

@Test func organizationFormatSevenPreservesSixAndRejectsFutureData() throws {
    var step = EditorObject(kind: .step, start: .zero, end: CGPoint(x: 30, y: 30)); step.stepStyle = EditorStepStyle()
    let old = ProjectDocument(title: "Format 6", pixelSize: PixelSize(width: 100, height: 100)!, objects: [step])
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
    json["schemaVersion"] = 6
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated == old && migrated.tags.isEmpty && migrated.collections.isEmpty)
    json["tags"] = ["Not valid in format 6"]
    #expect(throws: ProjectError.self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    let document = searchDocument()
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    #expect(ProjectArchive.copy(document, id: UUID()).tags == document.tags)
    #expect(ProjectArchive.copy(document, id: UUID()).collections == document.collections)
}

@Test func organizationMetadataRoundTripsAndSurvivesBackupAndTrash() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Organization-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")!
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 1, height: 1)!)
    let store = ProjectStore(root: root.appendingPathComponent("source"))
    try await store.create(document, original: png, thumbnail: nil)
    try await store.updateMetadata(document.id, tags: ["  Bug ", "BUG"], collections: ["Support", "Inbox"])
    let saved = try await store.load(document.id)
    #expect(saved.document.tags == ["Bug"] && saved.document.collections == ["Support", "Inbox"] && saved.generation == 1)
    try await store.updateMetadata(document.id, tags: ["bug"], collections: ["Support"])
    let latest = try await store.readDocument(document.id)
    #expect(latest.tags == ["bug"] && latest.collections == ["Support"])
    await #expect(throws: ProjectError.self) { try await store.updateMetadata(document.id, title: "Must not change", tags: [String(repeating: "a", count: 81)]) }
    #expect(try await store.readDocument(document.id) == latest)
    let external = root.appendingPathComponent("test.snaprivo")
    try await store.exportProject(document.id, to: external)
    let imported = try await store.importProject(ProjectArchive.read(from: external), thumbnail: nil)
    #expect(try await store.load(imported).document.tags == latest.tags)
    try await store.moveToTrash(document.id)
    let backup = root.appendingPathComponent("test.snaprivobackup")
    _ = try await store.backup(to: backup)
    let restored = ProjectStore(root: root.appendingPathComponent("restored"))
    _ = try await restored.restoreBackup(from: backup, thumbnail: { _ in png })
    #expect(try await restored.listTrash().items.first?.document.collections == ["Support"])
    try await restored.restore(document.id)
    #expect(try await restored.load(document.id).document.tags == ["bug"])
}

@Test func searchTermsMatchAcrossMetadataAndContentWithoutQuerySyntax() throws {
    let document = searchDocument()
    #expect(LibrarySearch.matches(document, query: "MUNCHEN login"))
    #expect(LibrarySearch.matches(document, query: "kundenhilfe pixel", content: "Only in PIXELS"))
    #expect(!LibrarySearch.matches(document, query: "missing pixel", content: "Only in PIXELS"))
    #expect(LibrarySearch.matches(document, query: " %_' ", content: "Literal %_' text"))
    var renamed = document; renamed.title = "Changed"; renamed.tags = ["New"]
    #expect(try LibrarySearch.imageKey(renamed) == LibrarySearch.imageKey(document))
    renamed.objects = [EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 30, y: 30))]
    #expect(try LibrarySearch.imageKey(renamed) != LibrarySearch.imageKey(document))
}

@Test func contentIndexPersistsRejectsStaleImagesAndRevokesWriters() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Search-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("index.sqlite"), document = searchDocument()
    var index = LibraryContentIndex(url: url)
    let initialIndex = index
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let cancelled = Task {
        for await _ in stream { }
        return try await initialIndex.configure(library: "Library A", enabled: true, documents: [document])
    }
    cancelled.cancel()
    continuation.finish()
    await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let epoch = try await index.configure(library: "Library A", enabled: true, documents: [document])
    try await index.record("Only visible München pixel text %_'", for: document, epoch: epoch)
    #expect(try await index.search("login munchen pixel", documents: [document], includeOCR: true) == [document.id])
    #expect(try await index.search("pixel", documents: [document], includeOCR: false).isEmpty)
    index = LibraryContentIndex(url: url)
    let restarted = try await index.configure(library: "Library A", enabled: true, documents: [document])
    #expect(try await index.missing([document], epoch: restarted).isEmpty)
    var changed = document; changed.objects = [EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 400, y: 200))]
    #expect(try await index.search("pixel", documents: [changed], includeOCR: true).isEmpty)
    let updated = try await index.configure(library: "Library A", enabled: true, documents: [changed])
    #expect(try await index.missing([changed], epoch: updated).map(\.id) == [document.id])
    await #expect(throws: LibraryIndexError.self) { try await index.record("Late secret", for: document, epoch: restarted) }
    try await index.record("", for: changed, epoch: updated)
    #expect(try await index.missing([changed], epoch: updated).isEmpty, "Blank images must not be reprocessed forever")
    _ = try await index.configure(library: "Library A", enabled: false, documents: [changed])
    #expect(!FileManager.default.fileExists(atPath: url.path))
    await #expect(throws: LibraryIndexError.self) { try await index.record("Late secret", for: document, epoch: updated) }
    #expect(try await index.search("login", documents: [document], includeOCR: true) == [document.id])
}

@Test func contentIndexRebuildsCorruptionPrunesDeletedAndSeparatesLibraries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Search-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("index.sqlite"), document = searchDocument()
    try Data("corrupt cache".utf8).write(to: url)
    let index = LibraryContentIndex(url: url)
    let epoch = try await index.configure(library: "A", enabled: true, documents: [document])
    #expect(await index.recoveredCache)
    try await index.record("Synthetic secret", for: document, epoch: epoch)
    _ = try await index.configure(library: "A", enabled: true, documents: [])
    #expect(try await index.search("secret", documents: [document], includeOCR: true).isEmpty)
    let restored = try await index.configure(library: "A", enabled: true, documents: [document])
    try await index.record("Rebuilt text", for: document, epoch: restored)
    _ = try await index.configure(library: "B", enabled: true, documents: [document])
    #expect(try await index.search("rebuilt", documents: [document], includeOCR: true).isEmpty)
    let rebuilt = try await index.configure(library: "B", enabled: true, documents: [document], rebuild: true)
    try await index.record("New text", for: document, epoch: rebuilt)
    #expect(try await index.search("new", documents: [document], includeOCR: true) == [document.id])
    await #expect(throws: LibraryIndexError.self) { try await index.record(String(repeating: "x", count: 1_000_001), for: document, epoch: rebuilt) }
}
