import Foundation
import Testing
@testable import SnagForgeDomain

private func textSource() -> GuideDocument {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")!
    return GuideDocument(title: "Original", introduction: "Before", style: .compact, steps: [
        GuideStep(title: "First", caption: "One", png: png, sourceProjectID: UUID(),
                  sourceLibrary: String(repeating: "a", count: 64), sourceRevision: 4),
        GuideStep(title: "Second", caption: "Two", png: png)
    ], includesCover: false)
}
private func wholeDraft(_ source: GuideDocument) -> GuideTextDraft {
    GuideTextDraft(documentID: source.id, scope: .document, title: "Proposed", introduction: "After",
        steps: source.steps.map { .init(id: $0.id, title: "New " + $0.title, caption: "New " + $0.caption) })
}

@Test func guideTextDraftPreservesAssetsReferencesAndLatestRevision() throws {
    let source = textSource(), draft = wholeDraft(source)
    var current = source; current.revision = 7; current.modifiedAt = Date(timeIntervalSince1970: 1234)
    let result = try draft.applying(to: current, basedOn: source)
    #expect(result.title == "Proposed" && result.introduction == "After")
    #expect(result.revision == 7 && result.modifiedAt == current.modifiedAt)
    #expect(result.style == .compact && !result.includesCover && result.id == source.id)
    for (before, after) in zip(source.steps, result.steps) {
        #expect(before.id == after.id && before.png == after.png)
        #expect(before.sourceProjectID == after.sourceProjectID && before.sourceLibrary == after.sourceLibrary)
        #expect(before.sourceRevision == after.sourceRevision)
        #expect(after.title == "New " + before.title && after.caption == "New " + before.caption)
    }
}

@Test func guideSingleStepDraftPreservesUnrelatedConcurrentEdits() throws {
    let source = textSource(), id = source.steps[1].id
    let draft = GuideTextDraft(documentID: source.id, scope: .step(id),
        steps: [.init(id: id, title: "Revised", caption: "Rewritten")])
    var current = source; current.title = "Renamed"; current.steps[0].caption = "Edited elsewhere"
    current.steps.reverse()
    let result = try draft.applying(to: current, basedOn: source)
    #expect(result.title == current.title && result.introduction == current.introduction)
    #expect(result.steps.map(\.id) == current.steps.map(\.id))
    #expect(result.steps[0].title == "Revised" && result.steps[1].caption == "Edited elsewhere")
}

@Test func guideTextDraftRejectsStaleOrReplacedSourcesWithoutMutation() throws {
    let source = textSource(), draft = wholeDraft(source)
    var variants: [GuideDocument] = []
    var value = source; value.id = UUID(); variants.append(value)
    value = source; value.title = "Changed"; variants.append(value)
    value = source; value.steps.reverse(); variants.append(value)
    value = source; value.steps[0].caption = "Changed"; variants.append(value)
    value = source; value.steps[0].png.append(1); variants.append(value)
    value = source; value.steps.removeLast(); variants.append(value)
    for current in variants {
        #expect(throws: GuideTextDraftError.staleSource) { try draft.applying(to: current, basedOn: source) }
    }
    #expect(source.title == "Original" && source.steps[0].caption == "One")
}

@Test func guideTextDraftRejectsMissingDuplicateExtraAndInvalidText() throws {
    let source = textSource(), valid = wholeDraft(source)
    var variants: [GuideTextDraft] = []
    var value = valid; value.steps.removeLast(); variants.append(value)
    value = valid; value.steps.append(value.steps[0]); variants.append(value)
    value = valid; value.steps[0] = .init(id: UUID(), title: "Unknown", caption: ""); variants.append(value)
    value = valid; value.title = " "; variants.append(value)
    value = valid; value.title = String(repeating: "x", count: 257); variants.append(value)
    value = valid; value.steps[0].caption = String(repeating: "x", count: 8001); variants.append(value)
    value = valid; value.introduction = "Bad\u{0}"; variants.append(value)
    for draft in variants {
        #expect(throws: GuideTextDraftError.invalidDraft) { try draft.applying(to: source, basedOn: source) }
    }
}

@Test func guideTextDraftSupportsEmptyGuideAndRejectsHeaderInStepScope() throws {
    let source = GuideDocument(title: "")
    let draft = GuideTextDraft(documentID: source.id, scope: .document, title: "Goal", introduction: "Introduction")
    #expect(try draft.applying(to: source, basedOn: source).steps.isEmpty)
    let populated = textSource(), id = populated.steps[0].id
    let invalid = GuideTextDraft(documentID: populated.id, scope: .step(id), title: "Unrequested header",
        steps: [.init(id: id, title: "Title", caption: "Caption")])
    #expect(throws: GuideTextDraftError.invalidDraft) { try invalid.applying(to: populated, basedOn: populated) }
}
