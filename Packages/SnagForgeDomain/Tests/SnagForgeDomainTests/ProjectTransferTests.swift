import Foundation
import Testing
@testable import SnagForgeDomain

private let transferPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")!

@Test func portableProjectPreservesOperationsAndNeverOverwrites() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    var mask = EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 1, y: 1))
    mask.color = EditorColor(red: 0, green: 0, blue: 0)
    let doc = ProjectDocument(title: "Roundtrip", pixelSize: PixelSize(width: 1, height: 1)!, objects: [mask],
                              crop: CGRect(x: 0, y: 0, width: 1, height: 1), resizedSize: PixelSize(width: 3, height: 2), isFavorite: true)
    try await store.create(doc, original: transferPNG, thumbnail: nil)
    let url = root.appendingPathComponent("export.snaprivo")
    try await store.exportProject(doc.id, to: url)
    let archive = try ProjectArchive.read(from: url)
    #expect(try archive.validatedDocument() == doc)
    let imported = try await store.importProject(archive, thumbnail: nil)
    let copy = try await store.load(imported)
    #expect(imported != doc.id && copy.original == transferPNG)
    #expect(copy.document == ProjectArchive.copy(doc, id: imported))
    #expect(try await store.load(doc.id).document == doc)
}

@Test func libraryBackupRestoresActiveTrashAndConflicts() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let store = ProjectStore(root: base.appendingPathComponent("source"))
    let doc = ProjectDocument(title: "Same name", pixelSize: PixelSize(width: 1, height: 1)!, isFavorite: true)
    let trash = ProjectDocument(title: "Same name", pixelSize: doc.pixelSize)
    try await store.create(doc, original: transferPNG, thumbnail: nil)
    try await store.create(trash, original: transferPNG, thumbnail: nil)
    try await store.moveToTrash(trash.id)
    let backup = base.appendingPathComponent("test.snaprivobackup")
    #expect(try await store.backup(to: backup) == 2)
    let restored = ProjectStore(root: base.appendingPathComponent("restored"))
    #expect(try await restored.restoreBackup(from: backup, thumbnail: { _ in transferPNG }) == 2)
    #expect(try await restored.load(doc.id).document == doc)
    #expect(try await restored.listTrash().items.map(\.id) == [trash.id])
    #expect(try await restored.restoreBackup(from: backup, thumbnail: { _ in transferPNG }) == 2)
    #expect(try await restored.list().items.count == 2)
    #expect(try await restored.listTrash().items.count == 2)
    let restart = ProjectStore(root: base.appendingPathComponent("restored"))
    #expect(try await restart.load(doc.id).original == transferPNG)
}

@Test func rejectsBrokenArchiveLinksAndBackupBeforePublishing() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let store = ProjectStore(root: base.appendingPathComponent("source"))
    let doc = ProjectDocument(title: "Valid", pixelSize: PixelSize(width: 1, height: 1)!)
    try await store.create(doc, original: transferPNG, thumbnail: nil)
    let second = ProjectDocument(title: "Second", pixelSize: doc.pixelSize)
    try await store.create(second, original: transferPNG, thumbnail: nil)
    let backup = base.appendingPathComponent("test.snaprivobackup")
    _ = try await store.backup(to: backup)
    let index = try LibraryBackupIndex.read(from: backup)
    // Fail only after another complete project has already been staged.
    let entry = backup.appendingPathComponent(index.entries[1].file)
    let external = base.appendingPathComponent("other")
    try FileManager.default.moveItem(at: entry, to: external)
    try FileManager.default.createSymbolicLink(at: entry, withDestinationURL: external)
    #expect(throws: ProjectError.invalidDocument) { try ProjectArchive.read(from: entry) }
    let restored = ProjectStore(root: base.appendingPathComponent("restored"))
    await #expect(throws: ProjectError.invalidDocument) { try await restored.restoreBackup(from: backup, thumbnail: { _ in transferPNG }) }
    #expect(try await restored.list().items.isEmpty)
    try FileManager.default.removeItem(at: entry)
    try Data("broken".utf8).write(to: entry)
    await #expect(throws: ProjectError.invalidDocument) { try await restored.restoreBackup(from: backup, thumbnail: { _ in transferPNG }) }
    #expect(try await restored.list().items.isEmpty)
    var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: external), format: nil) as! [String: Any]
    plist["version"] = 999
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: external)
    #expect(throws: ProjectError.unsupportedVersion) { try ProjectArchive.read(from: external) }
}

@Test func backupErrorsPreserveExistingFilesAndSourceLibrary() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let store = ProjectStore(root: base.appendingPathComponent("source"))
    let doc = ProjectDocument(title: "Keep", pixelSize: PixelSize(width: 1, height: 1)!)
    try await store.create(doc, original: transferPNG, thumbnail: nil)
    let destination = base.appendingPathComponent("existing.snaprivobackup")
    let sentinel = Data("Do not replace this backup".utf8)
    try sentinel.write(to: destination)
    #expect(throws: ProjectError.fileTooLarge) { try ProjectArchive.readRegularFile(destination, limit: 2) }
    await #expect(throws: (any Error).self) { try await store.backup(to: destination) }
    #expect(try Data(contentsOf: destination) == sentinel)
    let missingParent = base.appendingPathComponent("missing/backup.snaprivobackup")
    await #expect(throws: (any Error).self) { try await store.backup(to: missingParent) }
    #expect(try await store.load(doc.id).original == transferPNG)
    #expect(try await store.load(doc.id).document == doc)
}

@Test func redactionsPersistUndoAndStayAboveOtherObjects() throws {
    let mask = EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 10, y: 10))
    let text = EditorObject(kind: .text, start: .zero, text: "secret")
    let blur = EditorObject(kind: .blur, start: .zero, end: mask.end)
    #expect(EditorLayers.paintOrder([mask, text, blur]).map(\.id) == [blur.id, text.id, mask.id])
    #expect(!EditorLayers.canMove(mask.id, in: [mask, text], direction: .back))
    var history = EditorHistory(objects: [text]); history.commit([text, mask]); history.undo()
    #expect(history.objects == [text]); history.redo(); #expect(history.objects == [text, mask])
    let doc = ProjectDocument(title: "Mask", pixelSize: PixelSize(width: 20, height: 20)!, objects: history.objects)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(doc)) == doc)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProjectDocument(title: "Legacy", pixelSize: doc.pixelSize))) as! [String: Any]
    legacy["schemaVersion"] = 4
    #expect(try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy)).schemaVersion == ProjectDocument.currentVersion)
}
