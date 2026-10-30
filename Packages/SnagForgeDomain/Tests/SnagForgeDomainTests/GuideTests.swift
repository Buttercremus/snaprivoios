import Foundation
import Testing
import Darwin
@testable import SnagForgeDomain

private let guidePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")!
private func guideFixture() -> GuideDocument {
    GuideDocument(title: "Synthetic guide", introduction: "Introduction", steps: [
        GuideStep(title: "First", caption: "Caption", png: guidePNG, sourceProjectID: UUID(), sourceLibrary: String(repeating: "a", count: 64)),
        GuideStep(title: "Second", png: guidePNG)
    ])
}

@Test func guidePersistenceRoundTripRecoveryAndConcurrentWriters() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Guide-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let a = GuideStore(root: root), b = GuideStore(root: root), value = guideFixture()
    try await a.create(value)
    #expect(try await b.load(value.id).document == value)
    var changed = value; changed.title = "Changed"; changed.moveStep(changed.steps[1].id, by: -1); changed.style = .compact
    let saved = try await a.save(changed, expectedRevision: 0)
    #expect(saved.revision == 1 && saved.steps[0].title == "Second")
    await #expect(throws: ProjectError.self) { try await b.save(value, expectedRevision: 0) }
    #expect(try await b.load(value.id).document == saved)
    try Data("interrupted or damaged save".utf8).write(to: root.appendingPathComponent("\(value.id).snaprivoguide"))
    let recovered = try await b.load(value.id)
    #expect(recovered.recovered && recovered.document == value)
    #expect(try await b.save(recovered.document, expectedRevision: 0).revision == 1)
}

@Test func guideFutureVersionsNeverFallBackOrOverwrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideFuture-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root), value = guideFixture()
    try await store.create(value)
    _ = try await store.save(value, expectedRevision: 0)
    var future = value; future.version = 3
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    let data = try encoder.encode(future), url = root.appendingPathComponent("\(value.id).snaprivoguide")
    try data.write(to: url)
    await #expect(throws: ProjectError.unsupportedVersion) { try await store.load(value.id) }
    await #expect(throws: ProjectError.self) { try await store.save(value, expectedRevision: 0) }
    #expect(try Data(contentsOf: url) == data)
    #expect(try await store.list().issues.count == 1)
}

@Test func guideValidationRejectsInvalidTextImagesStepsAndTraversal() throws {
    let good = guideFixture(); _ = try good.validated()
    var values: [GuideDocument] = []
    var bad = good; bad.title = "  "; values.append(bad)
    bad = good; bad.title = "Invalid\0title"; values.append(bad)
    bad = good; bad.steps[0].caption = String(repeating: "a", count: 8_001); values.append(bad)
    bad = good; bad.steps[0].sourceLibrary = "../../outside"; values.append(bad)
    bad = good; bad.steps[0].png = Data("not a PNG".utf8); values.append(bad)
    bad = good; bad.steps[0].png.replaceSubrange(16..<20, with: [0, 0, 10, 1]); values.append(bad)
    bad = good; bad.steps += bad.steps; values.append(bad)
    bad = good; bad.steps = (0..<101).map { GuideStep(title: "\($0)", png: guidePNG) }; values.append(bad)
    for value in values { #expect(throws: ProjectError.self) { try value.encoded() } }
}

@Test func portableGuideContainsOnlyCurrentFlatImagesAndUserText() throws {
    let value = guideFixture(), encoded = try value.encoded(portable: true)
    let portable = try PropertyListDecoder().decode(GuideDocument.self, from: encoded)
    #expect(portable.steps[0].sourceProjectID == nil && portable.steps[0].sourceLibrary == nil)
    #expect(portable.steps[0].png == guidePNG && portable.steps[0].caption == value.steps[0].caption)
    #expect(portable.steps.count == 2 && portable.title == value.title)
}

@Test func guideMarkdownEscapesUserSyntaxAndUsesFixedAssetNames() throws {
    var value = guideFixture(); value.title = "../Title\n<script>"
    value.steps[0].title = "[click](https://example.invalid) ![image](file:///secret)"
    value.steps[0].caption = "<img src='file:///secret'>\n# Heading\n1. List\n`code` & text"
    let markdown = try GuideMarkdown.text(value)
    #expect(!markdown.contains("<script>") && !markdown.contains("<img"))
    #expect(markdown.contains("\\[click\\]\\(https://example\\.invalid\\)"))
    #expect(markdown.contains("\\# Heading") && markdown.contains("1\\. List"))
    #expect(markdown.contains("(images/0001.png)") && markdown.contains("(images/0002.png)"))
}

@Test func guideReorderBoundsAndDuplicateCreationPreserveExistingWork() async throws {
    var value = guideFixture(); let initial = value
    value.moveStep(value.steps[0].id, by: -1); value.moveStep(UUID(), by: 1); value.moveStep(value.steps[0].id, by: Int.max)
    #expect(value == initial)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideCreate-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root)
    try await store.create(value)
    await #expect(throws: ProjectError.self) { try await store.create(value) }
    #expect(try await store.load(value.id).document == value)
}

@Test func guideVersionOneMigrationAndCoverRoundTrip() throws {
    let value = guideFixture()
    var legacy = try PropertyListSerialization.propertyList(from: value.encoded(), format: nil) as! [String: Any]
    legacy["version"] = 1; legacy.removeValue(forKey: "includesCover")
    let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
    let migrated = try PropertyListDecoder().decode(GuideDocument.self, from: data).validated()
    #expect(migrated.version == 2 && migrated.includesCover && migrated.steps == value.steps)
    var changed = migrated; changed.includesCover = false; changed.steps[0].sourceRevision = 7
    let restored = try PropertyListDecoder().decode(GuideDocument.self, from: changed.encoded())
    #expect(!restored.includesCover && restored.steps[0].sourceRevision == 7)
    let portable = try PropertyListDecoder().decode(GuideDocument.self, from: changed.encoded(portable: true))
    #expect(portable.steps[0].sourceRevision == nil)
}

@Test func guideArbitraryReorderPreservesStepIdentityAndRejectsForeignTargets() {
    var value = guideFixture()
    let third = GuideStep(title: "Third", png: guidePNG); value.steps.append(third)
    let first = value.steps[0], second = value.steps[1]
    value.moveStep(third.id, before: first.id)
    #expect(value.steps == [third, first, second])
    value.moveStep(first.id, before: nil)
    #expect(value.steps == [third, second, first])
    let unchanged = value
    value.moveStep(first.id, before: first.id); value.moveStep(first.id, before: UUID()); value.moveStep(UUID(), before: nil)
    #expect(value == unchanged)
}

@Test func guideLocalTextSavesReuseImagesAndMigrateLegacyFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideAssets-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let value = guideFixture(), path = root.appendingPathComponent("\(value.id).snaprivoguide")
    try value.encoded().write(to: path)
    let store = GuideStore(root: root)
    #expect(try await store.load(value.id).document == value)
    var next = value; next.steps[0].caption = "Changed text"; next.includesCover = false
    let saved = try await store.save(next, expectedRevision: 0)
    let assets = root.appendingPathComponent(".assets/\(value.id)")
    let files = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: [.contentModificationDateKey])
    #expect(files.count == 1) // Identical PNGs are stored once per guide.
    let before = try files[0].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    var textOnly = saved; textOnly.title = "Another text change"
    let latest = try await store.save(textOnly, expectedRevision: saved.revision)
    #expect(try files[0].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before)
    #expect(try await GuideStore(root: root).load(value.id).document == latest)
    let manifest = try PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as! [String: Any]
    #expect(manifest["storageVersion"] as? Int == 1)
    #expect(try await store.list().documents.first?.title == "Another text change")
    try Data("damaged manifest".utf8).write(to: path)
    let recovered = try await GuideStore(root: root).load(value.id)
    #expect(recovered.recovered && recovered.document == saved)
}

@Test func guideTrashSurvivesRestartAndConcurrentSavesCannotResurrectIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideTrash-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root), value = guideFixture()
    try await store.create(value)
    await #expect(throws: ProjectError.self) { try await store.permanentlyDelete(value.id) }
    await #expect(throws: ProjectError.staleRevision) { try await store.moveToTrash(value.id, expectedRevision: 8) }
    try await store.moveToTrash(value.id, expectedRevision: 0)
    let reopened = GuideStore(root: root)
    #expect(try await reopened.list().documents.isEmpty)
    #expect(try await reopened.listTrash().documents.first?.id == value.id)
    #expect(try await reopened.load(value.id, includingTrashed: true).document == value)
    await #expect(throws: ProjectError.self) { try await reopened.load(value.id) }
    await #expect(throws: ProjectError.staleRevision) { try await reopened.save(value, expectedRevision: 0) }
    try await reopened.restore(value.id)
    #expect(try await reopened.listTrash().documents.isEmpty)
    #expect(try await reopened.load(value.id).document == value)
    try await reopened.moveToTrash(value.id, expectedRevision: 0)
    try await reopened.permanentlyDelete(value.id)
    #expect(try await reopened.listTrash().documents.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".assets/\(value.id)").path))
}

@Test func guideStoreRejectsUnsafeAssetReferencesAndCorruptPixels() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideAssetValidation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root), value = guideFixture()
    try await store.create(value)
    let path = root.appendingPathComponent("\(value.id).snaprivoguide")
    var manifest = try PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as! [String: Any]
    manifest["digests"] = ["../../outside", "../../outside"]
    try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0).write(to: path)
    await #expect(throws: (any Error).self) { try await GuideStore(root: root).load(value.id) }
    try await store.removeImported([value.id]); try await store.create(value)
    let folder = root.appendingPathComponent(".assets/\(value.id)")
    let asset = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first!
    try Data(repeating: 0, count: guidePNG.count).write(to: asset)
    await #expect(throws: (any Error).self) { try await GuideStore(root: root).load(value.id) }
}

@Test func guideSaveRepairsSameLengthCorruptionAndKeepsPreviousGenerationReadable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideSameLengthRepair-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root), value = guideFixture()
    try await store.create(value)
    let first = try await store.save(value, expectedRevision: 0)
    let folder = root.appendingPathComponent(".assets/\(value.id)")
    let asset = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
    try Data(repeating: 0, count: guidePNG.count).write(to: asset)

    var changed = first
    changed.title = "Repaired"
    let second = try await store.save(changed, expectedRevision: first.revision)
    #expect(second.revision == 2)
    #expect(try await GuideStore(root: root).load(value.id).document == second)

    // The prior manifest still points at the same content-addressed asset. It must
    // remain readable after the repair as well.
    try Data("damaged current manifest".utf8).write(to: root.appendingPathComponent("\(value.id).snaprivoguide"))
    let recovered = try await GuideStore(root: root).load(value.id)
    #expect(recovered.recovered && recovered.document == first)
    #expect(recovered.document.steps.allSatisfy { $0.png == guidePNG })
}

@Test func guideContendedStoreHonorsCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideLock-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root); try await store.create(guideFixture())
    let descriptor = Darwin.open(root.appendingPathComponent(".guide-lock").path, O_RDWR)
    #expect(descriptor >= 0); defer { Darwin.close(descriptor) }
    #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    defer { _ = flock(descriptor, LOCK_UN) }
    let task = Task { try await store.list() }; task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled lock wait unexpectedly succeeded") }
    catch is CancellationError { }
}

@Test func guideContentSearchFindsUnicodeTextAndKeepsStableStepTargets() throws {
    var value = guideFixture()
    value.title = "Router einrichten"; value.introduction = "Für das Büronetz"
    value.steps[0].title = "Änderungen prüfen"
    value.steps[0].caption = String(repeating: "Vorheriger Text. ", count: 50) + "Geheimwort neu setzen."
    value.steps[1].caption = "Telefon verbinden"
    #expect(GuideSearchMatch.matches(in: value, query: "  \n ").isEmpty)
    #expect(GuideSearchMatch.matches(in: value, query: "buronetz").first?.stepID == nil)
    let match = try #require(GuideSearchMatch.matches(in: value, query: "anderungen geheimwort").first)
    #expect(match.stepID == value.steps[0].id && match.stepNumber == 1)
    #expect(match.excerpt.contains("Geheimwort") && match.excerpt.count <= 162)
    #expect(GuideSearchMatch.matches(in: value, query: "no such text").isEmpty)
    #expect(GuideSearchMatch.matches(in: value, query: value.steps[0].sourceProjectID!.uuidString).isEmpty)
    value.moveStep(value.steps[0].id, by: 1)
    let moved = try #require(GuideSearchMatch.matches(in: value, query: "geheimwort").first)
    #expect(moved.stepID == match.stepID && moved.stepNumber == 2)
}

@Test func guideStepInsertionAndDuplicationAreAtomicAndRetainSources() throws {
    var value = guideFixture()
    value.steps[0].sourceRevision = 12
    let original = value.steps[0]
    let id = try value.duplicateStep(original.id)
    #expect(value.steps.map(\.id) == [original.id, id, value.steps[2].id])
    var expected = original; expected.id = id
    #expect(value.steps[1] == expected)
    value.steps[1].title = "Independent title"
    #expect(value.steps[0] == original)
    let additions = [GuideStep(title: "A", png: guidePNG), GuideStep(title: "B", png: guidePNG)]
    try value.insertSteps(additions, at: .before(id))
    #expect(value.steps[1...2].map(\.id) == additions.map(\.id))
    let unchanged = value
    #expect(throws: ProjectError.self) { try value.insertSteps(additions, at: .after(UUID())) }
    #expect(value == unchanged)
    #expect(throws: ProjectError.self) { try value.insertSteps([original]) }
    #expect(value == unchanged)
    value.steps = (0..<100).map { GuideStep(title: "\($0)", png: guidePNG) }
    let full = value
    #expect(throws: ProjectError.documentTooLarge) { try value.duplicateStep(value.steps[0].id) }
    #expect(value == full)
}

@Test func guideStoreSearchDoesNotReadPNGAssetsOrExposeTrash() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideSearch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GuideStore(root: root), value = guideFixture()
    try await store.create(value)
    // The search must still work when image hydration is impossible.
    try FileManager.default.removeItem(at: root.appendingPathComponent(".assets"))
    #expect(try await store.search("caption").first?.stepID == value.steps[0].id)
    try await store.moveToTrash(value.id, expectedRevision: 0)
    #expect(try await store.search("caption").isEmpty)
}
