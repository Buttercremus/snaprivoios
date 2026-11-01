import Foundation

public enum GuideTextScope: Equatable, Sendable {
    case document
    case step(UUID)
}

public enum GuideTextDraftError: Error, Equatable { case staleSource, invalidDraft }

/// A reviewable text proposal. It can never add, remove or replace image steps.
public struct GuideTextDraft: Equatable, Sendable {
    public struct Step: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var caption: String
        public init(id: UUID, title: String, caption: String) {
            self.id = id; self.title = title; self.caption = caption
        }
    }
    public let documentID: UUID
    public let scope: GuideTextScope
    public var title: String?
    public var introduction: String?
    public var steps: [Step]
    public init(documentID: UUID, scope: GuideTextScope, title: String? = nil,
                introduction: String? = nil, steps: [Step] = []) {
        self.documentID = documentID; self.scope = scope; self.title = title
        self.introduction = introduction; self.steps = steps
    }

    /// Autosave revision changes are allowed; changes to the source text or pixels are not.
    /// Unrelated current metadata and, for a single step, other edits remain intact.
    public func applying(to current: GuideDocument, basedOn source: GuideDocument) throws -> GuideDocument {
        guard current.id == documentID, source.id == documentID else { throw GuideTextDraftError.staleSource }
        let targets: [GuideStep]
        switch scope {
        case .document:
            guard title != nil, introduction != nil else { throw GuideTextDraftError.invalidDraft }
            guard current.title == source.title, current.introduction == source.introduction,
                  current.steps.map(\.id) == source.steps.map(\.id) else { throw GuideTextDraftError.staleSource }
            targets = source.steps
        case .step(let id):
            guard title == nil, introduction == nil else { throw GuideTextDraftError.invalidDraft }
            guard let step = source.steps.first(where: { $0.id == id }) else { throw GuideTextDraftError.staleSource }
            targets = [step]
        }
        guard steps.map(\.id) == targets.map(\.id) else { throw GuideTextDraftError.invalidDraft }
        var result = current
        for (target, proposed) in zip(targets, steps) {
            guard let index = result.steps.firstIndex(where: { $0.id == target.id }),
                  result.steps[index].title == target.title, result.steps[index].caption == target.caption,
                  result.steps[index].png == target.png else { throw GuideTextDraftError.staleSource }
            result.steps[index].title = proposed.title; result.steps[index].caption = proposed.caption
        }
        if let title, let introduction { result.title = title; result.introduction = introduction }
        do { return try result.validated() }
        catch { throw GuideTextDraftError.invalidDraft }
    }
}
