import Foundation
import Observation
import SnagForgeDomain

struct GuideAssistantRequest: Identifiable {
    let id = UUID()
    let source: GuideDocument
    let scope: GuideTextScope
}

@MainActor @Observable final class GuideAssistantModel {
    let request: GuideAssistantRequest
    let guide: GuideModel
    var goal = "" { didSet { if goal != oldValue { invalidateDraft() } } }
    var mode: GuideAssistantMode = .suggest { didSet { if mode != oldValue { invalidateDraft() } } }
    var language: GuideAssistantLanguage = .current { didSet { if language != oldValue { invalidateDraft() } } }
    private(set) var availability: GuideAssistantAvailability = .checking
    private(set) var isGenerating = false
    private(set) var draft: GuideTextDraft?
    private(set) var progress: GuideAssistantProgress?
    private(set) var error: String?
    @ObservationIgnored private let service: any GuideTextGenerating
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generationID = UUID()

    init(request: GuideAssistantRequest, guide: GuideModel, service: any GuideTextGenerating = AppleGuideTextService.shared) {
        self.request = request; self.guide = guide; self.service = service
    }
    deinit { task?.cancel() }
    var canGenerate: Bool {
        availability.isAvailable && !isGenerating && goal.count <= 2_000
            && (!request.source.steps.isEmpty || !request.source.introduction.isEmpty
                || !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var canApply: Bool { draft != nil && !isGenerating }
    func refreshAvailability() async {
        let requestedLanguage = language
        availability = .checking
        let result = await service.availability(for: requestedLanguage)
        guard !Task.isCancelled, requestedLanguage == language else { return }
        availability = result
    }
    func generate() {
        guard canGenerate else { return }
        guard guide.document?.id == request.source.id else {
            error = GuideAssistantError.staleSource.localizedDescription; return
        }
        guard !guide.isBusy, !guide.isSuspended, !guide.showsTrash, guide.selectedDocumentIDs.count <= 1,
              guide.requestFeature(.guides) else {
            error = GuideAssistantError.editingUnavailable.localizedDescription; return
        }
        let input = GuideAssistantInput(source: request.source, scope: request.scope, mode: mode, language: language, goal: goal)
        generationID = UUID(); let id = generationID
        draft = nil; error = nil; progress = nil; isGenerating = true
        task = Task { [weak self, service] in
            do {
                let result = try await service.generate(input) { [weak self] progress in
                    await self?.receive(progress, for: id)
                }
                guard !Task.isCancelled, let self, generationID == id else { return }
                _ = try result.applying(to: input.source, basedOn: input.source)
                draft = result; isGenerating = false; task = nil
            } catch {
                guard !Task.isCancelled, let self, generationID == id else { return }
                isGenerating = false; task = nil; progress = nil
                if error is CancellationError { return }
                if let known = error as? GuideAssistantError { self.error = known.localizedDescription }
                else { self.error = GuideAssistantError.generationFailed.localizedDescription }
            }
        }
    }
    private func receive(_ progress: GuideAssistantProgress, for id: UUID) {
        guard generationID == id, isGenerating else { return }
        self.progress = progress
    }
    func cancel() {
        generationID = UUID(); task?.cancel(); task = nil; isGenerating = false; progress = nil
    }
    private func invalidateDraft() {
        cancel(); draft = nil; error = nil
    }
    func editDraft(_ mutation: (inout GuideTextDraft) -> Void) {
        guard !isGenerating, var value = draft else { return }
        mutation(&value); draft = value; error = nil
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let draft else { return false }
        do {
            guard try guide.applyTextDraft(draft, basedOn: request.source) else {
                error = GuideAssistantError.editingUnavailable.localizedDescription; return false
            }
            return true
        } catch GuideTextDraftError.staleSource {
            error = GuideAssistantError.staleSource.localizedDescription
        } catch {
            self.error = GuideAssistantError.invalidResult.localizedDescription
        }
        return false
    }
}
