import Foundation
import Darwin
import Testing
@testable import SnagForgeDomain

private func limitRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileLimits-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func sparseFile(_ url: URL, bytes: Int) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    try file.truncate(atOffset: UInt64(bytes))
}

@Test func boundedFileReaderAcceptsBoundaryAndRejectsOversizeAndSpecialFiles() throws {
    let root = try limitRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("input")
    let data = Data(repeating: 7, count: 1_048_580)
    try data.write(to: file)
    #expect(try ProjectArchive.readRegularFile(file, limit: data.count) == data)
    #expect(throws: ProjectError.fileTooLarge) { try ProjectArchive.readRegularFile(file, limit: data.count - 1) }
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) { try ProjectArchive.readRegularFile(link, limit: data.count) }
    #expect(throws: ProjectError.invalidDocument) { try ProjectArchive.readRegularFile(root, limit: data.count) }
    let pipe = root.appendingPathComponent("pipe")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: ProjectError.invalidDocument) { try ProjectArchive.readRegularFile(pipe, limit: data.count) }
    try Data().write(to: file)
    #expect(try ProjectArchive.readRegularFile(file, limit: 0).isEmpty)
    #expect(throws: ProjectError.invalidDocument) { try ProjectArchive.readRegularFile(file, limit: -1) }
}

@Test func oversizedLocalOriginalIsRejectedByOpenAndBackup() async throws {
    let root = try limitRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 1, height: 1)!)
    try await store.create(document, original: Data([1]), thumbnail: nil)
    let file = root.appendingPathComponent("\(document.id).snagforge/original.png")
    try sparseFile(file, bytes: ProjectArchive.maximumOriginalBytes + 1)
    await #expect(throws: ProjectError.fileTooLarge) { try await store.load(document.id) }
    let target = root.appendingPathComponent("copy.snaprivobackup")
    await #expect(throws: ProjectError.fileTooLarge) { try await store.backup(to: target) }
    #expect(!FileManager.default.fileExists(atPath: target.path))
}

@Test func unsafeThumbnailIsDiscardedWithoutHidingOrDamagingProject() async throws {
    let root = try limitRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 1, height: 1)!)
    try await store.create(document, original: Data([1]), thumbnail: nil)
    let folder = root.appendingPathComponent("\(document.id).snagforge"), thumb = folder.appendingPathComponent("thumbnail.png")
    try sparseFile(thumb, bytes: ProjectArchive.maximumThumbnailBytes + 1)
    var listing = try await store.list()
    #expect(listing.items.count == 1 && listing.items[0].thumbnail == nil && listing.issues.isEmpty)
    try FileManager.default.removeItem(at: thumb)
    try FileManager.default.createSymbolicLink(at: thumb, withDestinationURL: folder.appendingPathComponent("original.png"))
    listing = try await store.list()
    #expect(listing.items.count == 1 && listing.items[0].thumbnail == nil && listing.issues.isEmpty)
    #expect(try await store.load(document.id).document == document)
}

@Test func localManifestAndRevisionAreBoundedAndPreviousRevisionStillRecovers() async throws {
    let root = try limitRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    var document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 1, height: 1)!)
    try await store.create(document, original: Data([1]), thumbnail: nil)
    let folder = root.appendingPathComponent("\(document.id).snagforge")
    document.revision = 1
    try await store.save(document, expectedGeneration: 0, thumbnail: nil)
    try sparseFile(folder.appendingPathComponent("Revisions/1.json"), bytes: 32_000_001)
    #expect(try await store.load(document.id).recovered)
    let manifest = folder.appendingPathComponent("manifest.json"), originalManifest = try Data(contentsOf: manifest)
    try sparseFile(manifest, bytes: 65_537)
    await #expect(throws: ProjectError.fileTooLarge) { try await store.load(document.id) }
    #expect(try await store.list().issues.count == 1)
    try originalManifest.write(to: manifest)
    let current = folder.appendingPathComponent("Revisions/1.json")
    try FileManager.default.removeItem(at: current)
    try FileManager.default.createSymbolicLink(at: current, withDestinationURL: folder.appendingPathComponent("Revisions/0.json"))
    #expect(try await store.load(document.id).recovered)
}

@Test func committedItemUpdatesKeepOtherItemsAndRejectOlderRevisions() {
    let size = PixelSize(width: 1, height: 1)!
    let a = ProjectDocument(title: "A", pixelSize: size, modifiedAt: Date(timeIntervalSince1970: 1))
    let b = ProjectDocument(title: "B", pixelSize: size, modifiedAt: Date(timeIntervalSince1970: 2))
    let other = ProjectLibraryItem(document: b, thumbnail: Data([2]))
    var next = a; next.revision = 1; next.modifiedAt = Date(timeIntervalSince1970: 3)
    let changed = ProjectLibraryItem(document: next, thumbnail: Data([3]))
    let items = changed.updating([other, ProjectLibraryItem(document: a, thumbnail: Data([1]))])
    #expect(items.map(\.id) == [a.id, b.id])
    #expect(items[0].thumbnail == Data([3]) && items[1].document == b && items[1].thumbnail == Data([2]))
    let stale = ProjectLibraryItem(document: a, thumbnail: nil).updating(items)
    #expect(stale[0].document == next && stale[0].thumbnail == Data([3]))
    #expect(changed.updating([other]).count == 2)
}
