import AppKit
import SwiftUI
import Observation
import Synchronization
import SnagForgeDomain

@MainActor private final class WorkflowProStore: ProStoreClient {
    func offer() async throws -> ProOffer? { ProOffer(name: "Synthetic", price: "Synthetic") }
    var access = true
    func entitled() async throws -> Bool { access }
    func purchase() async throws -> ProPurchaseOutcome { .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@main struct WorkflowPolishChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkflowPolish-\(UUID())")
        let suite = "WorkflowPolish-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let client = WorkflowProStore()
        let purchases = ProPurchaseModel(client: client); await purchases.start()
        let workspace = WorkspaceModel(root: root, defaults: defaults, purchases: purchases)
        try await RenderCancellationChecks.run()
        try await RenderingBudgetChecks.run()
        try await checkOnboarding(root: root.appendingPathComponent("Onboarding"))
        func solid(_ color: NSColor) -> CGImage {
            let context = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            return context.makeImage()!
        }
        let red = solid(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let blue = solid(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        try await checkCropToolSwitches(image: red, root: root.appendingPathComponent("CropToolSwitches"))
        try await checkShapeToolSwitches(workspace: workspace, image: red, root: root.appendingPathComponent("ShapeToolSwitches"))
        for language in ["de", "de_DE", "de_AT", "en", "en_GB", "fr_FR"] {
            let path = language.hasPrefix("de") ? "de" : "en"
            precondition(SnaprivoPrivacyPolicy.url(for: [language]).absoluteString == "https://snaprivo.com/\(path)/privacy/")
        }
        var writes: [String] = []
        let clipboard = NSPasteboard(name: .init("Snaprivo-Synthetic-OCR-\(UUID())"))
        defer { clipboard.releaseGlobally() }

        let observed = Mutex(0)
        withObservationTracking { _ = workspace.isDirectOCRBusy } onChange: { observed.withLock { $0 += 1 } }
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in
            try await Task.sleep(for: .milliseconds(30)); return .init(text: "SYNTHETIC TEXT", codes: [])
        }, copy: { writes.append($0); return true })
        precondition(workspace.isDirectOCRBusy && observed.withLock { $0 } == 1, "Recognition did not publish its busy state")
        withObservationTracking { _ = workspace.isDirectOCRBusy } onChange: { observed.withLock { $0 += 1 } }
        await workspace.directOCRTask?.value
        precondition(!workspace.isDirectOCRBusy && observed.withLock { $0 } == 2, "Completion left the sidebar disabled")
        precondition(writes == ["SYNTHETIC TEXT"] && workspace.directCaptureNotice != nil)
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in throw CocoaError(.fileReadCorruptFile) }, copy: { writes.append($0); return true })
        await workspace.directOCRTask?.value
        precondition(!workspace.isDirectOCRBusy && workspace.directCaptureError != nil && workspace.directCaptureNotice == nil)
        workspace.importError = nil
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in
            try? await Task.sleep(for: .milliseconds(80)); return .init(text: "CANCELLED", codes: [])
        }, copy: { writes.append($0); return true })
        let cancelledTask = workspace.directOCRTask
        workspace.cancelDirectTextCapture(); await cancelledTask?.value
        precondition(!workspace.isDirectOCRBusy && writes == ["SYNTHETIC TEXT"] && workspace.directCaptureNotice == nil, "Cancelled recognition copied text or retained busy state")
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in
            try? await Task.sleep(for: .milliseconds(50)); return .init(text: "STALE", codes: [])
        }, copy: { writes.append($0); return true })
        let staleTask = workspace.directOCRTask
        workspace.cancelDirectTextCapture()
        precondition(!workspace.isDirectOCRBusy, "Cancel kept actions disabled while Vision was cancelling")
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in .init(text: "RETAINED", codes: []) }, copy: { _ in false })
        await workspace.directOCRTask?.value
        precondition(workspace.directCaptureText == "RETAINED" && workspace.directCaptureError != nil && workspace.showsDirectCaptureResult)
        precondition(workspace.copyDirectCaptureText(using: { text in
            clipboard.clearContents(); writes.append(text)
            return clipboard.setString(text, forType: .string)
        }) && writes.last == "RETAINED")
        precondition(clipboard.string(forType: .string) == "RETAINED", "Successful copy did not expose plain text for paste")
        await staleTask?.value
        precondition(workspace.directCaptureText == "RETAINED" && writes.last == "RETAINED", "Cancelled OCR replaced a newer result")
        let revision = Mutex(1)
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in
            try await Task.sleep(for: .milliseconds(20)); return .init(text: "LATE RESULT", codes: [])
        }, copy: { writes.append($0); return true }, clipboardRevision: { revision.withLock { $0 } })
        revision.withLock { $0 = 2 }
        await workspace.directOCRTask?.value
        precondition(workspace.directCaptureText == "LATE RESULT" && writes.last == "RETAINED", "Late OCR overwrote a changed clipboard")
        precondition(workspace.copyDirectCaptureText(using: { writes.append($0); return true }) && writes.last == "LATE RESULT")
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in .init(text: "   ", codes: []) })
        await workspace.directOCRTask?.value
        precondition(workspace.directCaptureText.isEmpty && workspace.directCaptureNotice != nil && workspace.showsDirectCaptureResult, "Empty result had no visible feedback")
        workspace.recognizeCapturedText(red, codesOnly: true, recognize: { _, _ in .init(text: "", codes: ["https://example.com/synthetic"]) })
        await workspace.directOCRTask?.value
        precondition(workspace.directCaptureCodes.count == 1 && workspace.showsDirectCaptureResult)
        workspace.recognizeCapturedText(red, codesOnly: false, recognize: { _, _ in
            try? await Task.sleep(for: .milliseconds(40)); return .init(text: "REVOKED", codes: [])
        }, copy: { writes.append($0); return true })
        let revokedTask = workspace.directOCRTask
        client.access = false; await purchases.restore()
        await revokedTask?.value
        precondition(!workspace.isDirectOCRBusy && !workspace.showsDirectCaptureResult && writes.last == "LATE RESULT", "Revoked OCR access retained text or wrote to the clipboard")
        client.access = true; await purchases.restore()
        workspace.dismissDirectCaptureResult()
        precondition(workspace.directCaptureImage == nil && workspace.directCaptureText.isEmpty && workspace.directCaptureCodes.isEmpty)
        QuickCapturePanelController.shared.closeIfCaptureGone()
        print("Direct text lifecycle passed: observed start/completion, success feedback, failure recovery and cancellation without clipboard writes")

        var blur = EditorObject(kind: .blur, start: CGPoint(x: 40, y: 30), end: CGPoint(x: 120, y: 100)); blur.blurRadius = 12
        let first = ProjectDocument(title: "Synthetic red", pixelSize: PixelSize(width: 320, height: 180)!, objects: [blur])
        var second = ProjectDocument(title: "Synthetic blue", pixelSize: first.pixelSize, objects: [blur])
        var frame = EditorPresentation(); frame.padding = 40
        frame.background = .asset(try EditorImageAsset(png: EditorRenderer.png(image: red, objects: []), size: first.pixelSize), blur: 0)
        second.presentation = frame
        try await workspace.store.create(first, original: EditorRenderer.png(image: red, objects: []), thumbnail: nil)
        try await workspace.store.create(second, original: EditorRenderer.png(image: blue, objects: []), thumbnail: nil)
        func waitForOpen() async throws {
            for _ in 0..<1000 { if !workspace.isLoading { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Image switch did not complete")
        }
        workspace.openProject(first.id); try await waitForOpen()
        let container = EditorCanvasContainer(model: workspace.editor!)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = container
        defer { window.close() }
        let parent = ObjectIdentifier(container)
        for id in [second.id, first.id, second.id, first.id] {
            let outgoing = workspace.editor!, previousCanvas = container.canvas
            workspace.openProject(id)
            precondition(workspace.editor === outgoing, "Outgoing image disappeared before preparation")
            try await waitForOpen()
            let next = workspace.editor!
            precondition(next.initialCanvas?.blurPatches.isEmpty == false && (id != second.id || next.initialCanvas?.wallpaper != nil), "Next image published before filters/wallpaper were ready")
            container.updateModel(next); container.synchronizeTransform()
            precondition(ObjectIdentifier(container) == parent && container.canvas !== previousCanvas && container.subviews.count == 1)
            let canvas = container.canvas
            canvas.synchronizeFocus()
            precondition(window.firstResponder === canvas, "Keyboard focus did not follow the replacement image")
            let context = CGContext(data: nil, width: Int(canvas.bounds.width), height: Int(canvas.bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: canvas.bounds.height); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            canvas.draw(canvas.bounds); NSGraphicsContext.restoreGraphicsState()
            let rect = canvas.presentationImageRect ?? next.viewport.imageRect(image: next.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor)
            let point = EditorImageProjection(source: next.sourceRect, destination: rect).viewPoint(CGPoint(x: 80, y: 60))
            let color = EditorRenderer.pixelColor(context.makeImage()!, x: Int(point.x), y: Int(point.y))!
            precondition(id == first.id ? color.redComponent > 0.95 : color.blueComponent > 0.95, "First frame flashed black or showed the previous image")
        }
        let layout = EditorToolOverflowLayout(width: 415, itemWidths: [100, 100, 100, 100, 100], toolCount: 5, moreWidth: 70)
        precondition(layout.hasOverflow && layout.visibleToolCount == 3 && layout.contentWidth == 374)
        let repacked = EditorToolOverflowLayout(width: layout.contentWidth, itemWidths: [100, 100, 100, 100, 100], toolCount: 5, moreWidth: 70)
        precondition(repacked.visibleToolCount == layout.visibleToolCount, "Compact toolbar changed its overflow allocation")
        print("Image switch passed: outgoing frame retained, prepared blur/wallpaper, stable native parent, correct first-frame pixels across repeated switches; compact toolbar allocation")
        try await EditorFilmstripChecks.run()
    }

    @MainActor private static func checkOnboarding(root: URL) async throws {
        let suite = "Onboarding-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let purchases = ProPurchaseModel(client: WorkflowProStore())
        await purchases.start()
        var automaticCopies = 0
        let workspace = WorkspaceModel(root: root, defaults: defaults, purchases: purchases, copyCapture: { _ in automaticCopies += 1 })
        workspace.preferences.copyAfterCapture = true
        workspace.preferences.quickPreviewAfterCapture = true
        workspace.openOnboardingExample()
        for _ in 0..<1000 {
            if !workspace.isLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let model = workspace.editor else { preconditionFailure("Example did not open in the editor: \(workspace.importError ?? "unknown")") }
        precondition(model.image.width == 800 && model.image.height == 500 && model.history.objects.isEmpty)
        precondition(model.name == String(localized: "Beispielbild") && workspace.section == .editor)
        precondition(!workspace.preferences.completedFirstCapture && !workspace.preferences.completedOnboarding,
                     "Practice falsely completed the first capture or the onboarding UI")
        precondition(automaticCopies == 0 && workspace.quickCapture == nil && !workspace.screenshot.isBusy && workspace.pendingCapture == nil,
                     "Practice used capture/preview/automatic clipboard behavior")
        let saved = try await workspace.store.load(model.document.id)
        let original = try EditorRenderer.png(image: model.image, objects: [])
        precondition(saved.original == original && saved.document.objects.isEmpty && saved.document.title == model.name,
                     "Example did not use the normal persisted project format")
        let route = EditorLearningHintRoute.route
        checkOnboardingDemoFrames()
        precondition(route(.crop, true, 0, 0) == .crop)
        precondition(route(.redact, false, 0, 0) == .redaction)
        for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .callout, .pen] {
            precondition(route(tool, false, 0, 0) == .drawing)
            precondition(route(tool, true, 2, 2) == .crop, "A pending crop lost its confirmation hint")
        }
        precondition(route(.selection, false, 0, 0) == .firstAnnotation)
        precondition(route(.selection, false, 2, 2) == .selection)
        precondition(route(.selection, false, 2, 1) == .output)

        let board = NSPasteboard(name: .init("Snaprivo-Synthetic-Onboarding-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("unchanged", forType: .string)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 720), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: EditorView(workspace: workspace))
        window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(120))
        model.beginCrop()
        workspace.openOnboardingExample()
        precondition(workspace.editor === model && !workspace.isLoading && workspace.importError != nil, "Example replaced an unconfirmed crop")
        workspace.importError = nil
        model.copyPNG(to: board)
        try await Task.sleep(for: .milliseconds(40))
        precondition(model.copyState == .idle && board.string(forType: .string) == "unchanged")
        precondition(!workspace.preferences.dismissedEditorHints.contains("output"), "Blocked copy dismissed the output hint")
        model.cancelCrop()
        model.copyPNG(to: board)
        for _ in 0..<1000 {
            if model.copyState == .copied && workspace.preferences.dismissedEditorHints.contains("output") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.copyState == .copied && board.data(forType: .png) != nil, "Practice image could not be copied")
        precondition(workspace.preferences.dismissedEditorHints == ["firstAnnotation", "output"],
                     "Successful practice copy failed to retire basic hints or hid unrelated crop/redaction/group hints")
        let restored = AppPreferences(defaults: defaults)
        precondition(restored.dismissedEditorHints == ["firstAnnotation", "output"] && !restored.completedFirstCapture)
        if let directory = ProcessInfo.processInfo.environment["SNAPRIVO_ONBOARDING_SNAPSHOTS"] {
            let welcome = NSHostingView(rootView: OnboardingView(shortcuts: workspace.captureShortcuts, finish: { _ in })
                .transaction { $0.disablesAnimations = true }.environment(\.colorScheme, .light).background(Color.white))
            welcome.frame = CGRect(x: 0, y: 0, width: 620, height: 600)
            window.contentView = welcome
            welcome.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            guard let bitmap = welcome.bitmapImageRepForCachingDisplay(in: welcome.bounds) else { preconditionFailure("Native welcome did not render") }
            welcome.cacheDisplay(in: welcome.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("native-welcome.png"))
            try original.write(to: URL(fileURLWithPath: directory).appendingPathComponent("practice-image.png"))
            for stage in OnboardingView.Stage.allCases {
                for progress in [0.25, 0.6, 1.0] {
                    let demo = NSHostingView(rootView: OnboardingIllustration(stage: stage, progress: progress)
                        .frame(width: 572, height: 160).environment(\.colorScheme, .light).background(Color.white))
                    window.setContentSize(NSSize(width: 572, height: 160)); window.contentView = demo
                    demo.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(60))
                    let image = demo.bitmapImageRepForCachingDisplay(in: demo.bounds)!
                    demo.cacheDisplay(in: demo.bounds, to: image)
                    let name = "demo-\(stage.rawValue)-\(Int(progress * 100)).png"
                    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                }
            }
        }
        let finished = await model.finishPendingWork()
        precondition(finished)
        print("Onboarding passed: persisted synthetic practice image, no capture/auto-copy/first-capture flag, crop guard, contextual routes, actual copy retires only relevant persistent hints")
    }

    private static func checkOnboardingDemoFrames() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.02) {
            let capture = OnboardingDemoFrame(stage: .capture, progress: progress)
            precondition(capture.cursor == CGPoint(x: capture.selection.maxX, y: capture.selection.maxY), "Capture cursor left the dragged corner")
            precondition(capture.selection.minX >= 0 && capture.selection.maxX <= 360 && capture.selection.maxY <= 138)
        }
        let arrow = OnboardingDemoFrame(stage: .annotate, progress: 0.34)
        precondition(arrow.cursor == OnboardingDemoFrame.arrowEnd && arrow.arrow == 1 && arrow.circle == 0 && arrow.redaction == 0)
        for boundary in [0.34, 0.44, 0.7, 0.78] {
            let before = OnboardingDemoFrame(stage: .annotate, progress: boundary - 0.00001).cursor
            let after = OnboardingDemoFrame(stage: .annotate, progress: boundary + 0.00001).cursor
            precondition(hypot(after.x - before.x, after.y - before.y) < 0.2, "Demo cursor teleported between drawing operations")
        }
        let annotation = OnboardingDemoFrame(stage: .annotate, progress: 1)
        precondition(annotation.arrow == 1 && annotation.circle == 1 && annotation.redaction == 1 && annotation.cursorOpacity == 0)
        precondition(!OnboardingDemoFrame(stage: .copy, progress: 0.6).copied && OnboardingDemoFrame(stage: .copy, progress: 1).copied)
        for progress in [-2.0, 3.0, .nan, .infinity] {
            let frame = OnboardingDemoFrame(stage: .annotate, progress: progress)
            precondition(frame.cursor.x.isFinite && frame.cursor.y.isFinite && (0...1).contains(frame.arrow))
        }
        print("Onboarding demo passed: capture cursor follows dragged bounds, continuous annotation cursor, staged drawing, terminal/static frame and copy feedback")
    }

    @MainActor private static func checkShapeToolSwitches(workspace: WorkspaceModel, image: CGImage, root: URL) async throws {
        let store = ProjectStore(root: root)
        let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 100, y: 90))
        let document = ProjectDocument(title: "Synthetic shape switch", pixelSize: PixelSize(width: image.width, height: image.height)!, objects: [shape])
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        model.tool = .rectangle; model.selection = shape.id
        let previousEditor = workspace.editor
        workspace.editor = model
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: EditorView(workspace: workspace))
        window.contentView = host; window.orderFront(nil)
        defer { window.close(); workspace.editor = previousEditor }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        for kind in [EditorObject.Kind.ellipse, .rectangle, .ellipse] {
            model.selectShape(kind, focusCanvas: false)
            try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
            precondition(model.selection == shape.id && model.selectedObject?.kind == kind && model.selectedObject?.rect == shape.rect,
                         "The view update discarded the converted shape selection or geometry")
        }
        let green = EditorColor(red: 0, green: 1, blue: 0)
        model.updateStyle(color: green)
        precondition(model.history.objects[0].color == green, "Style change after conversion missed the selected shape")
        model.tool = .arrow
        try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        precondition(model.selection == nil, "Switching tool families retained an unrelated shape selection")
        model.tool = .rectangle
        try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        precondition(model.drawingKind == .ellipse && model.defaultShapeKind == .ellipse, "Returning to Shapes forgot the ellipse")
        let replacement = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
        replacement.inheritToolSettings(from: model)
        precondition(replacement.defaultShapeKind == .ellipse && replacement.drawingKind == .ellipse, "Image switching forgot the selected shape variant")
        let saved = await model.flush(); precondition(saved)
        let reopened = try await store.load(document.id)
        precondition(reopened.document.objects[0].kind == .ellipse && reopened.document.objects[0].color == green)
        print("Shape view regressions passed: selection/style/geometry after conversion, clearing on family changes, ellipse reuse and inheritance, persisted edit; localized privacy URLs")
    }

    @MainActor private static func checkCropToolSwitches(image: CGImage, root: URL) async throws {
        let store = ProjectStore(root: root)
        var document = ProjectDocument(title: "Synthetic crop tool switch", pixelSize: PixelSize(width: 320, height: 180)!)
        document.crop = CGRect(x: 20, y: 10, width: 240, height: 140)
        try await store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
        func croppedModel() -> EditorModel {
            let model = EditorModel(image: image, document: document, generation: 0, store: store, onSaved: {})
            model.viewportBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
            model.setZoom(2)
            model.beginCrop()
            model.cropDraft = CGRect(x: 40, y: 30, width: 120, height: 80)
            precondition(model.canSwitchEditingTool && !model.hasExportableImage && model.pngShareItemForToolbar == nil)
            return model
        }
        let picker = ImageColorPickerState()
        let switches: [(String, (EditorModel) -> Void, (EditorModel) -> Bool)] = [
            ("inline text", { $0.beginInlineTextRecognition() }, { $0.isRecognizingTextInPlace }),
            ("presentation", { $0.togglePresentationTool() }, { $0.isEditingPresentation }),
            ("free rotation", { $0.beginFreeRotation() }, { $0.isEditingPresentation }),
            ("resize", { $0.beginImageResize() }, { $0.isShowingImageSize }),
            ("color picker", { if $0.prepareForEditingTool() { picker.activate() } }, { _ in picker.isActive }),
            ("QR / image insertion preparation", { precondition($0.prepareForEditingTool()) }, { $0.pngShareItemForToolbar != nil })
        ]
        for (name, activate, isActive) in switches {
            let model = croppedModel()
            activate(model)
            precondition(model.tool == .selection && model.cropDraft == nil && isActive(model), "Crop blocked \(name)")
            precondition(model.history.crop == document.crop && model.document.revision == 0 && !model.history.canUndo,
                         "Switching to \(name) committed the draft or changed history")
            precondition(model.viewport.zoom == 2, "Switching to \(name) lost the previous zoom")
        }
        let blocked = croppedModel(), draft = blocked.cropDraft
        blocked.isCanvasGestureActive = true
        precondition(!blocked.canSwitchEditingTool && !blocked.prepareForEditingTool() && blocked.cropDraft == draft)
        blocked.beginInlineTextRecognition(); blocked.togglePresentationTool(); blocked.beginFreeRotation(); blocked.beginImageResize()
        precondition(blocked.cropDraft == draft && !blocked.isEditingPresentation && !blocked.isRecognizingTextInPlace && !blocked.isShowingImageSize)
        blocked.isCanvasGestureActive = false
        blocked.isSwitchingImage = true
        precondition(!blocked.canSwitchEditingTool && !blocked.prepareForEditingTool() && blocked.cropDraft == draft)
        blocked.isSwitchingImage = false
        blocked.requestFeature = { _ in false }
        blocked.beginInlineTextRecognition(); blocked.togglePresentationTool()
        precondition(blocked.cropDraft == draft, "Denied Pro access discarded the crop")
        let rotated = croppedModel()
        rotated.transformImage(.clockwise90)
        precondition(rotated.cropDraft == nil && rotated.history.crop == document.crop && rotated.history.transform == .clockwise90)
        rotated.undo()
        precondition(rotated.history.transform == .identity && rotated.history.crop == document.crop, "Rotation undo changed the confirmed crop")
        let saved = await rotated.flush(); precondition(saved)
        print("Crop tool switches passed: OCR, presentation, rotation, resize, picker and QR/insertion preparation; confirmed crop/zoom/history retained, gestures/switching/Pro denial blocked, unconfirmed output unavailable")
    }
}
