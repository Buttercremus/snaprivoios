import AppKit
import SnagForgeDomain

private actor FakeGuideTextService: GuideTextGenerating {
    var state: GuideAssistantAvailability = .available(images: false)
    var inputs: [GuideAssistantInput] = []
    var holds = false
    var fails = false
    var pending: [(GuideAssistantInput, CheckedContinuation<GuideTextDraft, Error>)] = []
    var prewarms = 0
    var holdsAvailability = false
    var availabilityWaiters: [CheckedContinuation<Void, Never>] = []
    func availability(for language: GuideAssistantLanguage) async -> GuideAssistantAvailability {
        if holdsAvailability { await withCheckedContinuation { availabilityWaiters.append($0) } }
        return state
    }
    func holdAvailability() { holdsAvailability = true }
    func waitingAvailabilityCount() -> Int { availabilityWaiters.count }
    func releaseAvailability() {
        holdsAvailability = false
        let pending = availabilityWaiters; availabilityWaiters = []
        pending.forEach { $0.resume() }
    }
    func prewarm(for language: GuideAssistantLanguage) { prewarms += 1 }
    func prewarmCount() -> Int { prewarms }
    func configure(state: GuideAssistantAvailability? = nil, holds: Bool = false, fails: Bool = false) {
        if let state { self.state = state }; self.holds = holds; self.fails = fails
    }
    func count() -> Int { inputs.count }
    func generate(_ input: GuideAssistantInput,
                  progress: @escaping @Sendable (GuideAssistantProgress) async -> Void) async throws -> GuideTextDraft {
        inputs.append(input); await progress(.init(completed: 0, total: 2))
        if fails { throw GuideAssistantError.generationFailed }
        if holds {
            // A held request has streamed part of its first step.
            var partial = GuideTextDraft(documentID: input.source.id, scope: input.scope)
            if let first = input.source.steps.first { partial.steps = [.init(id: first.id, title: "Streaming", caption: "")] }
            await progress(.init(completed: 0, total: 0, activity: .waiting))
            await progress(.init(completed: 0, total: 2, draft: partial, activity: .writing(step: 1)))
            return try await withCheckedThrowingContinuation { pending.append((input, $0)) }
        }
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

@MainActor private func markupChecks() throws {
    // Probe outlines and anti-aliasing at the 640-pixel probe size add a few pixels.
    func near(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 0.015) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }
    var document = ProjectDocument(title: "Marks", pixelSize: PixelSize(width: 900, height: 500)!)
    let frame = EditorObject(kind: .rectangle, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 400, y: 200))
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 700, y: 400), end: CGPoint(x: 500, y: 300))
    var first = EditorObject(kind: .step, start: CGPoint(x: 120, y: 330), end: CGPoint(x: 150, y: 360)); first.stepStyle = EditorStepStyle(index: 1)
    let note = EditorObject(kind: .text, start: CGPoint(x: 600, y: 120), text: "Click here", fontSize: 30)
    let blur = EditorObject(kind: .blur, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 50))
    document.objects = [blur, frame, arrow, first, note]
    document.crop = CGRect(x: 100, y: 50, width: 700, height: 400)
    let cropped = try GuideStepMarkup.marks(in: document, matching: PixelSize(width: 1400, height: 800)!)
    precondition(cropped.count == 4 && cropped.map(\.role) == [.region, .target, .marker, .note], "Marks lost or kept a blur")
    precondition(near(cropped[0].rect, CGRect(x: 100.0 / 700, y: 50.0 / 400, width: 200.0 / 700, height: 100.0 / 400)),
                 "A frame did not land on its cropped snapshot position: \(cropped[0].rect)")
    precondition(cropped[2].number == 1 && cropped[2].label == "1")
    let otherShape = try GuideStepMarkup.marks(in: document, matching: PixelSize(width: 900, height: 900)!)
    precondition(otherShape.isEmpty, "Geometry was used for a snapshot of another shape")
    // A presentation background moves the image inward; marks must follow the composed snapshot.
    var presented = document; var style = EditorPresentation(); style.padding = 120
    style.background = .solid(EditorColor(red: 0.2, green: 0.4, blue: 0.9)); presented.presentation = style
    let blank = CGContext(data: nil, width: 900, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    let snapshot = try EditorRenderer.render(image: blank, objects: [], crop: presented.crop, maxDimension: 2560, presentation: presented.presentation)
    let inset = try GuideStepMarkup.marks(in: presented, matching: PixelSize(width: snapshot.width, height: snapshot.height)!)
    precondition(inset.count == 4 && inset[0].rect.minX > cropped[0].rect.minX && inset[0].rect.width < cropped[0].rect.width,
                 "Marks ignored the presentation padding")
    // Text is matched by position: inside frames, nearest to arrow tips and markers, notes kept apart.
    func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> RecognizedTextLine {
        RecognizedTextLine(text: text, confidence: 1, bounds: CGRect(x: x, y: y, width: 0.12, height: 0.04))
    }
    let marks = cropped
    let lines = [line("Notifications", 0.17, 0.25), line("Sound: Off", 0.58, 0.6), line("Safari", 0.12, 0.72),
                 line("Click here", marks[3].rect.minX + 0.005, marks[3].rect.minY + 0.005), line("Unrelated", 0.8, 0.95)]
    let hints = GuideStepMarkup.describe(marks, lines: lines, aspect: 1.75)
    precondition(hints.elements == ["Safari", "Notifications", "Sound: Off"] && hints.notes == ["Click here"],
                 "Marked text was not matched in order: \(hints)")
    precondition(GuideStepMarkup.unreadAreas(marks, lines: []).count == 2, "Empty frames and notes were not read again")
    // A small model can keep writing past its field; the review never shows that tail.
    precondition(AppleGuideTextService.clean("„Safari“ auswählen.“} ```json {") == "„Safari“ auswählen.")
    precondition(AppleGuideTextService.clean("Choose “Sound”.”}") == "Choose “Sound”.")
    precondition(AppleGuideTextService.clean("  Plain text. ") == "Plain text.")
    for text in ["Gib {Vorname} ein und bestätige mit OK.", "Füge {\"name\": \"Simon\"} ein.",
                 "Schreibe das Zeichen \"}\".", "Schreibe „{“ und danach „}“.",
                 "Code: ```json\n{\"name\": \"Simon\"}\n```", "Wähle „Erledigt.“}"] {
        precondition(AppleGuideTextService.clean(text) == text, "Valid braces, quotes or code were truncated: \(text)")
    }
    print("PASS: marks follow crop and presentation, skip blurs and stale shapes, match framed/pointed/numbered text in order, keep notes apart, re-read empty frames and drop runaway tails")
    fflush(nil)
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

        // Streamed text is visible at once, but only a complete draft can be applied.
        await fake.configure(state: .available(images: false), holds: true)
        let streaming = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        await streaming.refreshAvailability(); streaming.generate()
        precondition(streaming.activityText == String(localized: "Apple Intelligence wird vorbereitet …"), "A starting request showed no activity")
        for _ in 0..<100 { if streaming.preview != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(streaming.preview?.steps.first?.title == "Streaming" && streaming.visibleDraft != nil
                     && streaming.draft == nil && !streaming.canApply, "Streamed text was hidden or applicable early")
        precondition(!streaming.apply() && guide.document == beforeCancel, "A partial draft changed the guide")
        precondition(streaming.activity == .writing(step: 1) && streaming.activityText == String(localized: "Schritt \(1) wird geschrieben …")
                     && streaming.progress?.total == 2, "The current phase was not shown, or a queue report replaced the progress")
        await fake.release(); try await waitForAssistant(streaming)
        precondition(streaming.preview == nil && streaming.draft?.title == "Proposed title" && streaming.canApply && streaming.activity == nil,
                     "The complete draft did not replace the live preview")

        // One-click entries start exactly once with their mode; a plain open only loads the model.
        await fake.configure(state: .available(images: false))
        let startsBefore = await fake.count(), prewarmsBefore = await fake.prewarmCount()
        let oneClick = GuideAssistantModel(request: .init(source: guide.document!, scope: .step(source.steps[0].id), mode: .revise,
                                                          startsImmediately: true), guide: guide, service: fake)
        precondition(oneClick.mode == .revise, "A step entry lost its requested mode")
        await oneClick.prepare(); try await waitForAssistant(oneClick)
        await oneClick.prepare()
        let plain = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        await plain.prepare()
        let startsAfter = await fake.count(), prewarmsAfter = await fake.prewarmCount()
        let lastMode = await fake.inputs.last?.mode
        precondition(startsAfter == startsBefore + 1 && lastMode == .revise && oneClick.draft != nil && !plain.isGenerating,
                     "One-click entry did not start exactly once")
        precondition(prewarmsAfter == prewarmsBefore + 2, "Opening without a start did not load the model early")
        precondition(guide.document == beforeCancel, "Automatic generation changed the guide before acceptance")

        await fake.configure(state: .available(images: false), fails: true)
        await denied.refreshAvailability(); denied.generate(); try await waitForAssistant(denied)
        precondition(denied.draft == nil && denied.error != nil && guide.document == beforeCancel)
        await fake.configure(state: .available(images: false))
        denied.generate(); try await waitForAssistant(denied); precondition(denied.draft != nil)
        denied.goal = "Changed configuration"; precondition(denied.draft == nil && !denied.canApply)

        // Inline suggestions: written in place, applied as one undo step, discarded or dropped with their guide.
        let inline = GuideInlineSuggestions(service: fake)
        let current = guide.document!, target = current.steps[0], other = current.steps[1]
        inline.suggest(for: target.id, in: current, guide: guide, markups: [:])
        inline.suggest(for: other.id, in: current, guide: guide, markups: [:])
        for _ in 0..<200 { if inline.models.values.allSatisfy({ $0.canApply }) { break }; try await Task.sleep(for: .milliseconds(10)) }
        let inlineMode = inline.models[target.id]?.mode
        precondition(inline.models.count == 2 && inlineMode == (target.caption.isEmpty ? .suggest : .revise), "Inline suggestions did not start per step")
        precondition(guide.document == current, "An inline suggestion changed the guide before acceptance")
        precondition(inline.apply(target.id) && inline.models[target.id] == nil && inline.models[other.id] != nil)
        precondition(guide.document?.steps[0].title == "Proposed " + target.title && guide.document?.steps[1] == other,
                     "Applying one inline suggestion changed another step")
        precondition(inline.apply(other.id), "A second inline suggestion was stale after the first was applied")
        guide.undo(); precondition(guide.document?.steps[1] == other && guide.document?.steps[0].title == "Proposed " + target.title)
        guide.undo(); precondition(guide.document?.steps == current.steps, "Inline acceptance was not one undo step each")
        inline.suggest(for: target.id, in: guide.document!, guide: guide, markups: [:])
        inline.discard(target.id); precondition(inline.models.isEmpty && guide.document?.steps == current.steps)
        inline.suggest(for: target.id, in: guide.document!, guide: guide, markups: [:])
        inline.assistant = GuideAssistantModel(request: .init(source: guide.document!, scope: .document), guide: guide, service: fake)
        inline.keep(only: guide.document!.id); precondition(inline.assistant != nil, "A background request of the open guide was dropped")
        inline.keep(only: UUID()); precondition(inline.models.isEmpty && inline.assistant == nil, "Switching guides kept suggestions of another guide")
        try await checkInlineSuggestionLifetimes(guide)
        guide.create(); try await waitForGuide()
        guide.edit { $0.title = "" }
        let emptySource = guide.document!
        let empty = GuideAssistantModel(request: .init(source: emptySource, scope: .document), guide: guide, service: fake)
        await empty.refreshAvailability(); precondition(!empty.canGenerate)
        empty.goal = "Explain the notification settings"; precondition(empty.canGenerate)
        empty.generate(); try await waitForAssistant(empty)
        precondition(empty.draft?.steps.isEmpty == true && guide.document == emptySource)
        precondition(empty.apply() && guide.document?.steps.isEmpty == true)
        print("PASS: review-before-apply, edited proposals, one undo/redo, persistence, stale-source protection, single-step scope, entitlement checks, all unavailable states, cancellation/lifetime/late result, read-only live preview, one-click start and prewarm, phase display, inline step suggestions and background requests, retry and configuration invalidation")
        fflush(nil)

        try markupChecks()

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
            // Requests from several steps wait for each other instead of failing.
            let shortenInput = GuideAssistantInput(source: textSource, scope: .step(textSource.steps[0].id), mode: .shorten, language: .english, goal: "")
            let reviseInput = GuideAssistantInput(source: textSource, scope: .step(textSource.steps[0].id), mode: .revise, language: .english, goal: "")
            async let firstQueued = AppleGuideTextService.shared.generate(shortenInput) { _ in }
            async let secondQueued = AppleGuideTextService.shared.generate(reviseInput) { _ in }
            let queued = try await [firstQueued, secondQueued]
            precondition(queued.allSatisfy { !$0.steps[0].caption.isEmpty }, "A concurrent request failed instead of waiting")
            print("PASS: live concurrent requests are served one after another"); fflush(nil)
            let unfinished = GuideDocument(title: "")
            let header = try await AppleGuideTextService.shared.generate(.init(source: unfinished, scope: .document,
                mode: .suggest, language: .german, goal: "Benachrichtigungston in den Einstellungen ausschalten")) { _ in }
            let completed = try header.applying(to: unfinished, basedOn: unfinished)
            precondition(!completed.title.isEmpty && completed.steps.isEmpty)
            print("PASS: live header generation fills an unfinished empty title without creating image steps")
        }
    }
}

@MainActor private func checkInlineSuggestionLifetimes(_ guide: GuideModel) async throws {
    let service = FakeGuideTextService()
    let source = guide.document!, target = source.steps[0]
    func waitForAvailability(_ count: Int, in service: FakeGuideTextService) async throws {
        for _ in 0..<300 {
            if await service.waitingAvailabilityCount() == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Availability checkpoint was not reached")
    }
    // Explicit cancellation also invalidates prepare() calls owned by a view task.
    await service.holdAvailability()
    let direct = GuideAssistantModel(request: .init(source: source, scope: .step(target.id), startsImmediately: true), guide: guide, service: service)
    let preparing = Task { await direct.prepare() }
    try await waitForAvailability(1, in: service)
    direct.cancel(); await service.releaseAvailability(); await preparing.value
    let cancelledCalls = await service.count()
    precondition(cancelledCalls == 0 && !direct.isGenerating, "Cancelled preparation still invoked inference")
    await direct.refreshAvailability(); direct.generate()
    for _ in 0..<300 where direct.isGenerating { try await Task.sleep(for: .milliseconds(10)) }
    precondition(direct.draft != nil, "Explicit retry after cancellation was blocked")

    await service.holdAvailability()
    let edited = GuideAssistantModel(request: .init(source: source, scope: .step(target.id), startsImmediately: true), guide: guide, service: service)
    let checking = Task { await edited.prepare() }
    try await waitForAvailability(1, in: service)
    let beforeEdit = await service.count()
    edited.goal = "Updated while availability is being checked"
    await service.releaseAvailability(); await checking.value
    let afterEdit = await service.count()
    precondition(edited.canGenerate && !edited.isGenerating && afterEdit == beforeEdit,
                 "Editing during preparation started a stale request or left availability stuck")

    let held = FakeGuideTextService()
    // A non-cooperative availability provider may finish after discard or replacement.
    let suggestions = GuideInlineSuggestions(service: held)
    await held.holdAvailability()
    suggestions.suggest(for: target.id, in: source, guide: guide, markups: [:])
    try await waitForAvailability(1, in: held)
    weak let discarded = suggestions.models[target.id]
    suggestions.discard(target.id)
    await held.releaseAvailability()
    for _ in 0..<300 where discarded != nil { try await Task.sleep(for: .milliseconds(10)) }
    let discardedCalls = await held.count()
    precondition(discarded == nil && discardedCalls == 0 && suggestions.models.isEmpty,
                 "Discard kept the preparation or started an invisible generation")

    await held.holdAvailability()
    suggestions.suggest(for: target.id, in: source, guide: guide, markups: [:])
    try await waitForAvailability(1, in: held)
    weak let replaced = suggestions.models[target.id]
    suggestions.suggest(for: target.id, in: source, guide: guide, markups: [:])
    try await waitForAvailability(2, in: held)
    await held.releaseAvailability()
    for _ in 0..<300 { if suggestions.models[target.id]?.canApply == true && replaced == nil { break }; try await Task.sleep(for: .milliseconds(10)) }
    let replacementCalls = await held.count()
    precondition(replaced == nil && replacementCalls == 1 && suggestions.models[target.id]?.canApply == true,
                 "Replacing a preparation started both requests")
    weak let removed = suggestions.models[target.id]
    suggestions.assistant = GuideAssistantModel(request: .init(source: source, scope: .step(target.id)), guide: guide, service: held)
    guide.removeStep(target.id)
    precondition(removed == nil && suggestions.models.isEmpty && suggestions.assistant == nil,
                 "Removing a step kept its finished suggestion, dialog or screenshot snapshot")
    guide.undo()
    precondition(guide.document?.steps == source.steps && suggestions.models.isEmpty,
                 "Undo did not restore the step or resurrected a discarded suggestion")

    await held.configure(holds: true)
    suggestions.suggest(for: target.id, in: guide.document!, guide: guide, markups: [:])
    for _ in 0..<300 { if await held.pending.count == 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
    precondition(suggestions.models[target.id]?.isGenerating == true)
    weak let running = suggestions.models[target.id]
    guide.removeStep(target.id)
    await held.release()
    for _ in 0..<300 where running != nil { try await Task.sleep(for: .milliseconds(10)) }
    precondition(running == nil && suggestions.models.isEmpty && guide.document?.steps.contains(where: { $0.id == target.id }) == false,
                 "Removing a step kept running work or published a late result")
    guide.undo()
    print("PASS: cancelled/discarded/replaced preparation, explicit retry, removed-step snapshots and jobs released, Undo without resurrected suggestions")
}
