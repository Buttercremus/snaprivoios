import Foundation
import Observation
import SnagForgeDomain

struct GuideAssistantRequest: Identifiable {
    let id = UUID()
    let source: GuideDocument
    let scope: GuideTextScope
    var mode: GuideAssistantMode = .suggest
    /// One-click entries start writing as soon as the model is available.
    var startsImmediately = false
    /// Source projects that still match their step snapshots, for locating marks.
    var markups: [UUID: ProjectDocument] = [:]
}

/// Suggestions shown directly in step cards. They live outside the view, so switching sections keeps
/// them; each step has at most one, and the service writes them one after another.
@MainActor @Observable final class GuideInlineSuggestions {
    static let shared = GuideInlineSuggestions()
    private(set) var models: [UUID: GuideAssistantModel] = [:]
    /// The dialog's request. It keeps running while the dialog is closed with "Im Hintergrund weiter".
    var assistant: GuideAssistantModel?
    @ObservationIgnored private let service: any GuideTextGenerating
    init(service: any GuideTextGenerating = AppleGuideTextService.shared) { self.service = service }

    func observe(_ guide: GuideModel) {
        guide.onStepMembershipChange = { [weak self] id, steps in self?.keep(only: id, stepIDs: steps) }
        keep(only: guide.document?.id, stepIDs: Set(guide.document?.steps.map(\.id) ?? []))
    }

    /// Empty steps get a suggestion, written steps a revision. A new request replaces the step's previous one.
    func suggest(for stepID: UUID, in document: GuideDocument, guide: GuideModel, markups: [UUID: ProjectDocument]) {
        guard let step = document.steps.first(where: { $0.id == stepID }) else { return }
        observe(guide)
        models.removeValue(forKey: stepID)?.cancel()
        let model = GuideAssistantModel(request: .init(source: document, scope: .step(stepID), mode: step.caption.isEmpty ? .suggest : .revise,
            startsImmediately: true, markups: markups.filter { $0.key == stepID }), guide: guide, service: service)
        models[stepID] = model
        model.prepareWhenGuideIsReady()
    }
    @discardableResult func apply(_ stepID: UUID) -> Bool {
        guard let model = models[stepID], model.apply() else { return false }
        models[stepID] = nil
        return true
    }
    func discard(_ stepID: UUID) { models.removeValue(forKey: stepID)?.cancel() }
    /// Removed steps release their snapshots; Undo restores the step, not its discarded suggestion.
    func keep(only documentID: UUID?, stepIDs: Set<UUID>? = nil) {
        for (id, model) in models where model.request.source.id != documentID || stepIDs?.contains(id) == false { discard(id) }
        if let assistant {
            let removedStep: Bool
            if case .step(let id) = assistant.request.scope { removedStep = stepIDs?.contains(id) == false }
            else { removedStep = false }
            if assistant.request.source.id != documentID || removedStep { assistant.cancel(); self.assistant = nil }
        }
    }
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
    /// Read-only texts streamed while generating; replaced by `draft` when complete.
    private(set) var preview: GuideTextDraft?
    private(set) var progress: GuideAssistantProgress?
    private(set) var activity: GuideAssistantProgress.Activity?
    private(set) var activityStartedAt = Date.now
    private(set) var error: String?
    @ObservationIgnored private let service: any GuideTextGenerating
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var generationID = UUID()
    @ObservationIgnored private var didStartImmediately = false

    init(request: GuideAssistantRequest, guide: GuideModel, service: any GuideTextGenerating = AppleGuideTextService.shared) {
        self.request = request; self.guide = guide; self.service = service; self.mode = request.mode
    }
    deinit { preparationTask?.cancel(); task?.cancel() }
    var canGenerate: Bool {
        availability.isAvailable && !isGenerating && goal.count <= 2_000
            && (!request.source.steps.isEmpty || !request.source.introduction.isEmpty
                || !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var canApply: Bool { draft != nil && !isGenerating }
    var visibleDraft: GuideTextDraft? { draft ?? preview }
    func refreshAvailability() async {
        let requestedLanguage = language
        availability = .checking
        let result = await service.availability(for: requestedLanguage)
        guard !Task.isCancelled, requestedLanguage == language else { return }
        availability = result
    }
    func prepareWhenGuideIsReady() {
        preparationTask?.cancel()
        preparationTask = Task { [weak self, guide] in
            do {
                while guide.isBusy { try await Task.sleep(for: .milliseconds(50)) }
                try Task.checkCancellation()
                await self?.prepare()
            } catch { }
        }
    }
    /// Checks availability, loads the model early and honors a one-click start once.
    func prepare() async {
        let id = generationID
        await refreshAvailability()
        guard !Task.isCancelled, generationID == id, availability.isAvailable else { return }
        if request.startsImmediately, !didStartImmediately, canGenerate {
            didStartImmediately = true; generate()
        } else {
            await service.prewarm(for: language)
        }
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
        let input = GuideAssistantInput(source: request.source, scope: request.scope, mode: mode, language: language, goal: goal, markups: request.markups)
        generationID = UUID(); let id = generationID
        draft = nil; preview = nil; error = nil; progress = nil; activity = nil; activityStartedAt = .now; isGenerating = true
        task = Task { [weak self, service] in
            do {
                let result = try await service.generate(input) { [weak self] progress in
                    await self?.receive(progress, for: id)
                }
                guard !Task.isCancelled, let self, generationID == id else { return }
                _ = try result.applying(to: input.source, basedOn: input.source)
                draft = result; preview = nil; activity = nil; isGenerating = false; task = nil
            } catch {
                guard !Task.isCancelled, let self, generationID == id else { return }
                isGenerating = false; task = nil; progress = nil; preview = nil; activity = nil
                if error is CancellationError { return }
                if let known = error as? GuideAssistantError { self.error = known.localizedDescription }
                else { self.error = GuideAssistantError.generationFailed.localizedDescription }
            }
        }
    }
    private func receive(_ progress: GuideAssistantProgress, for id: UUID) {
        guard generationID == id, isGenerating else { return }
        if progress.total > 0 { self.progress = progress }
        if let draft = progress.draft { preview = draft }
        if let activity = progress.activity, activity != self.activity { self.activity = activity; activityStartedAt = .now }
    }
    /// Plain description of the current phase; before the first report the local model is starting.
    var activityText: String {
        switch activity {
        case nil: String(localized: "Apple Intelligence wird vorbereitet …")
        case .waiting: String(localized: "Wartet auf andere Vorschläge …")
        case .reading(let step): String(localized: "Schritt \(step): Bild wird gelesen …")
        case .writing(let step): String(localized: "Schritt \(step) wird geschrieben …")
        case .introduction: String(localized: "Titel und Einleitung werden geschrieben …")
        }
    }
    func cancel() {
        generationID = UUID(); preparationTask?.cancel(); preparationTask = nil
        task?.cancel(); task = nil; isGenerating = false; progress = nil; preview = nil; activity = nil
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
