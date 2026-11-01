import AppKit
import SnagForgeDomain

private actor FakeGuideTextService: GuideTextGenerating {
    var state: GuideAssistantAvailability = .available(images: false)
    var inputs: [GuideAssistantInput] = []
    var holds = false
    var fails = false
    var pending: [(GuideAssistantInput, CheckedContinuation<GuideTextDraft, Error>)] = []
    func availability(for language: GuideAssistantLanguage) -> GuideAssistantAvailability { state }
    func configure(state: GuideAssistantAvailability? = nil, holds: Bool = false, fails: Bool = false) {
        if let state { self.state = state }; self.holds = holds; self.fails = fails
    }
    func count() -> Int { inputs.count }
    func generate(_ input: GuideAssistantInput,
                  progress: @escaping @Sendable (GuideAssistantProgress) async -> Void) async throws -> GuideTextDraft {
        inputs.append(input); await progress(.init(completed: 0, total: 2))
        if fails { throw GuideAssistantError.generationFailed }
        if holds { return try await withCheckedThrowingContinuation { pending.append((input, $0)) } }
        await progress(.init(completed: 2, total: 2))
        return Self.result(input)
    }
    func release() {
        let callbacks = pending; pending.removeAll()
        for (input, continuation) in callbacks { continuation.resume(returning: Self.result(input)) }
    }
    nonisolated private static func result(_ input: GuideAssistantInput) -> GuideTextDraft {
        let steps = input.source.steps.filter { input.scope == .document || input.scope == .step($0.id) }
        return GuideTextDraft(documentID: input.source.id, scope: input.scope,
            title: input.scope == .document ? "Proposed title" : nil,
            introduction: input.scope == .document ? "Proposed introduction" : nil,
            steps: steps.map { .init(id: $0.id, title: "Proposed " + $0.title, caption: "Proposed description") })
    }
}

@main struct GuideAssistantChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideAssistant-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 900, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 900, height: 500))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Settings" as NSString).draw(at: CGPoint(x: 60, y: 360), withAttributes: [.font: NSFont.systemFont(ofSize: 50), .foregroundColor: NSColor.black])
        ("Notifications - Sound: Off" as NSString).draw(at: CGPoint(x: 60, y: 240), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let png = try EditorRenderer.png(image: context.makeImage()!, objects: [])
        let source = GuideDocument(title: "Synthetic settings guide", introduction: "Initial introduction", style: .compact,
            steps: [GuideStep(title: "First", caption: "Open the settings.", png: png),
                    GuideStep(title: "Second", caption: "Choose notifications.", png: png)], includesCover: false)
        let guide = GuideModel(root: root); try await guide.store.create(source); await guide.refresh()
        func waitForGuide() async throws {
            for _ in 0..<500 { if !guide.isBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Guide timed out")
        }
        func waitForAssistant(_ model: GuideAssistantModel) async throws {
            for _ in 0..<500 { if !model.isGenerating { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Assistant timed out")
        }
        guide.open(source.id); try await waitForGuide()
        let baseline = guide.document!
        let fake = FakeGuideTextService()
        let model = GuideAssistantModel(request: .init(source: baseline, scope: .document), guide: guide, service: fake)
        await model.refreshAvailability(); precondition(model.canGenerate && !model.canApply)
        model.goal = "Synthetic goal"; model.language = .german; model.mode = .revise
        model.generate(); precondition(model.isGenerating)
        try await waitForAssistant(model)
        precondition(model.draft?.steps.count == 2 && guide.document == baseline && !guide.isDirty && !guide.canUndo,
                     "Generation modified the guide before acceptance")
        model.editDraft { $0.steps[0].caption = "Manually reviewed description" }
        precondition(model.apply() && guide.canUndo && guide.document?.steps[0].caption == "Manually reviewed description")
        precondition(guide.document?.steps.map(\.png) == baseline.steps.map(\.png) && guide.document?.style == .compact)
        guide.undo(); precondition(guide.document?.title == baseline.title && guide.document?.steps == baseline.steps,
                                  "Acceptance was not a single undo edit")
        guide.redo(); let accepted = guide.document!; let saved = await guide.flush(); precondition(saved)
        let reopened = try await guide.store.load(source.id).document
        precondition(reopened.title == accepted.title && reopened.steps == accepted.steps, "Accepted text was not persisted")

        let stale = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        await stale.refreshAvailability(); stale.generate(); try await waitForAssistant(stale)
        guide.edit { $0.introduction = "Newer unsaved text" }
        precondition(!stale.apply() && stale.error != nil && guide.document?.introduction == "Newer unsaved text")

        let stepModel = GuideAssistantModel(request: .init(source: guide.document!, scope: .step(source.steps[1].id)), guide: guide, service: fake)
        await stepModel.refreshAvailability(); stepModel.mode = .shorten; stepModel.generate(); try await waitForAssistant(stepModel)
        let titleBefore = guide.document!.title, otherBefore = guide.document!.steps[0]
        precondition(stepModel.apply() && guide.document?.title == titleBefore && guide.document?.steps[0] == otherBefore)

        let denied = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        await denied.refreshAvailability()
        let countBefore = await fake.count(); guide.requestFeature = { _ in false }
        denied.generate(); precondition(!denied.isGenerating && denied.error != nil)
        let countAfter = await fake.count(); precondition(countAfter == countBefore, "Free editing invoked inference")
        precondition(!stepModel.apply(), "A revoked entitlement accepted a draft")
        guide.requestFeature = { _ in true }

        for state in [GuideAssistantAvailability.deviceNotEligible, .notEnabled, .modelNotReady, .unsupportedLanguage, .unavailable] {
            await fake.configure(state: state)
            await denied.refreshAvailability(); precondition(!denied.canGenerate && denied.availability == state)
        }
        await fake.configure(state: .available(images: false), holds: true)
        var cancellable: GuideAssistantModel? = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        await cancellable!.refreshAvailability(); cancellable!.generate()
        for _ in 0..<100 { if await fake.count() > countAfter { break }; try await Task.sleep(for: .milliseconds(10)) }
        let beforeCancel = guide.document!
        cancellable!.cancel(); precondition(!cancellable!.isGenerating && cancellable!.draft == nil)
        weak let weakModel = cancellable; cancellable = nil
        precondition(weakModel == nil, "A cancelled service retained the dismissed sheet")
        await fake.release(); try await Task.sleep(for: .milliseconds(50))
        precondition(guide.document == beforeCancel, "A late cancelled result changed the guide")

        await fake.configure(state: .available(images: false), fails: true)
        await denied.refreshAvailability(); denied.generate(); try await waitForAssistant(denied)
        precondition(denied.draft == nil && denied.error != nil && guide.document == beforeCancel)
        await fake.configure(state: .available(images: false))
        denied.generate(); try await waitForAssistant(denied); precondition(denied.draft != nil)
        denied.goal = "Changed configuration"; precondition(denied.draft == nil && !denied.canApply)
        guide.create(); try await waitForGuide()
        guide.edit { $0.title = "" }
        let emptySource = guide.document!
        let empty = GuideAssistantModel(request: .init(source: emptySource, scope: .document), guide: guide, service: fake)
        await empty.refreshAvailability(); precondition(!empty.canGenerate)
        empty.goal = "Explain the notification settings"; precondition(empty.canGenerate)
        empty.generate(); try await waitForAssistant(empty)
        precondition(empty.draft?.steps.isEmpty == true && guide.document == emptySource)
        precondition(empty.apply() && guide.document?.steps.isEmpty == true)
        print("PASS: review-before-apply, edited proposals, one undo/redo, persistence, stale-source protection, single-step scope, entitlement checks, all unavailable states, cancellation/lifetime/late result, retry and configuration invalidation")
        fflush(nil)

        if CommandLine.arguments.contains("--live") {
            let recognition = try await TextRecognitionService.shared.recognize(
                TextRecognitionSnapshot(image: GuideExporter.image(png), objects: [], crop: nil, resizedSize: nil),
                selection: .init(x: 0, y: 0, width: 1, height: 1), language: "")
            precondition(recognition.text.localizedCaseInsensitiveContains("Sound"), "Synthetic source did not exercise actual OCR")
            print("PASS: live Vision reads the synthetic sound setting"); fflush(nil)
            let liveSource = GuideDocument(title: "Notifications", steps: [GuideStep(title: "Notification sound", png: png)])
            let input = GuideAssistantInput(source: liveSource, scope: .document, mode: .suggest, language: .german,
                goal: "Zeige die Einstellung des Benachrichtigungstons. Beschreibe nur den sichtbaren Zustand.")
            for images in [true, false] {
                let service = AppleGuideTextService(permitsImages: images)
                let state = await service.availability(for: .german)
                precondition(state.isAvailable, "Live Apple model unavailable: \(state)")
                print("Live local probe starting: \(state)"); fflush(nil)
                let result = try await service.generate(input) { value in
                    print("Live progress: \(value.completed)/\(value.total)"); fflush(nil)
                }
                precondition(result.title?.isEmpty == false && result.steps.count == 1 && !result.steps[0].caption.isEmpty)
                let applied = try result.applying(to: liveSource, basedOn: liveSource)
                precondition(applied.steps[0].png == png)
                print("PASS: live local Apple generation, \(state), German structured header/step, validated output and unchanged image")
                print("Synthetic proposal:", result.title ?? "", result.steps[0].title, result.steps[0].caption); fflush(nil)
            }
            var textSource = liveSource
            textSource.steps[0].caption = "The settings page is currently open and visible on the screen. On this settings page, the notifications section is visible. The notifications section contains a sound setting. That sound setting is currently set to off. This means that the sound setting for notifications is off on the settings page."
            for mode in [GuideAssistantMode.revise, .shorten] {
                let service = AppleGuideTextService.shared
                let result = try await service.generate(.init(source: textSource, scope: .step(textSource.steps[0].id),
                    mode: mode, language: .english, goal: "Preserve the visible state and make the text clear.")) { _ in }
                precondition(result.title == nil && result.introduction == nil && !result.steps[0].caption.isEmpty)
                if mode == .shorten {
                    precondition(result.steps[0].caption.count < textSource.steps[0].caption.count * 3 / 4,
                                 "Shorten did not reduce a deliberately repetitive source")
                }
                _ = try result.applying(to: textSource, basedOn: textSource)
                print("PASS: live English \(mode), single-step scope")
                print("Synthetic proposal:", result.steps[0].caption); fflush(nil)
            }
            let unfinished = GuideDocument(title: "")
            let header = try await AppleGuideTextService.shared.generate(.init(source: unfinished, scope: .document,
                mode: .suggest, language: .german, goal: "Benachrichtigungston in den Einstellungen ausschalten")) { _ in }
            let completed = try header.applying(to: unfinished, basedOn: unfinished)
            precondition(!completed.title.isEmpty && completed.steps.isEmpty)
            print("PASS: live header generation fills an unfinished empty title without creating image steps")
        }
    }
}
