import Foundation
import Testing
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
    var future = value; future.version = 2
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
