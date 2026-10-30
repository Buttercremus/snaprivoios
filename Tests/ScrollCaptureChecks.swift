import AppKit
import SnagForgeDomain

struct ScrollCaptureChecks {
    @MainActor static func run() async throws {
        let width = 180, height = 800
        var pixels = [UInt8]()
        for y in 0..<height { for x in 0..<width {
            let v = UInt8(truncatingIfNeeded: (y * 7919 + x * 104729) ^ (y * x * 313))
            pixels.append(contentsOf: [v, v, v, 255])
        } }
        let source = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        func slice(_ y: Int) -> CGImage { source.cropping(to: CGRect(x: 0, y: y, width: width, height: 300))! }
        let a = slice(0), b = slice(110), c = slice(245)
        let first = try ScrollCaptureProcessor.append(previous: a, next: b, stable: b, accumulated: a, count: 1)
        let second = try ScrollCaptureProcessor.append(previous: b, next: c, stable: c, accumulated: first, count: 2)
        precondition(first.height == 410 && second.height == 545 && second.width == width)
        let actual = NSBitmapImageRep(cgImage: second), expected = NSBitmapImageRep(cgImage: source)
        for y in 0..<545 { for x in stride(from: 0, to: width, by: 7) {
            let lhs = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let rhs = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            precondition(abs(lhs.redComponent - rhs.redComponent) < 0.01, "Seam/orientation mismatch at \(x),\(y)")
        } }
        do { _ = try ScrollCaptureProcessor.append(previous: a, next: b, stable: c, accumulated: a, count: 1); preconditionFailure("Moving content accepted") }
        catch ScrollStitchError.moving { }
        do { _ = try ScrollCaptureProcessor.append(previous: a, next: b, stable: b, accumulated: a, count: 50); preconditionFailure("Section limit ignored") }
        catch ScrollStitchError.limit { }
        let rolling = try ScrollCaptureProcessor.append(previous: a, next: b, stable: c, accumulated: a, count: 80, allowsScrolling: true)
        let rollingPNG = try EditorRenderer.png(image: rolling, objects: []), firstPNG = try EditorRenderer.png(image: first, objects: [])
        precondition(rolling.height == first.height && rollingPNG == firstPNG, "Rolling frames changed output pixels")
        do {
            _ = try ScrollCaptureProcessor.append(previous: a, next: c, stable: b, accumulated: a, count: 1, allowsScrolling: true)
            preconditionFailure("Reverse motion accepted during continuous capture")
        } catch ScrollStitchError.uncertain { }
        try await checkOverlayHandoff()
        try await checkVideoOverlayHandoff()
        try await checkFullScreenChoices()
        try await checkRetinaTextScrolling()
        try await checkSessionControls(first: a, next: b)
        try await checkFinalFrameSettling(first: a, next: b, last: c)
        try await checkEditableProject(second)
        print("Scroll capture checks passed: exact vertical seams/orientation across three frames, stable-frame check, section limit, editor autosave/restart/edit/undo/export.")
    }
}

@MainActor private func checkFullScreenChoices() async throws {
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    let desktop = FrozenDesktop(displays: NSScreen.screens.map {
        FrozenDisplay(displayID: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32,
            screenFrame: $0.frame, image: context.makeImage()!)
    })
    for (media, scrolling) in [(CaptureMedia.image, false), (.video, false), (.image, true)] {
        let selector = ScreenshotSelector()
        var finished = false
        let pending = Task {
            let result = try await selector.select(source: .region, windows: [], desktop: desktop, media: media, scrolling: scrolling)
            finished = true; return result
        }
        for _ in 0..<200 where !NSApp.windows.contains(where: { $0.isVisible && $0.contentView is SelectionView }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        var active = NSApp.windows.first { $0.isVisible && $0.contentView is SelectionView }!.contentView as! SelectionView
        active.onPropose?(active.screenFrame.insetBy(dx: 100, dy: 100))
        func chooseSource(_ source: CaptureSource) {
            let toolbar = active.subviews.compactMap { $0 as? CaptureReviewToolbar }.first!
            let item = toolbar.sourceChoicesMenu().items.first { ($0.representedObject as? String) == source.rawValue }!
            _ = NSApp.sendAction(item.action!, to: item.target, from: item)
        }
        let draft = active.reviewDraft!
        chooseSource(.automatic)
        precondition(active.mode == .automatic && active.reviewDraft == draft && !finished)
        chooseSource(.window)
        precondition(active.mode == .window && active.reviewDraft == nil && !finished,
            "Window source must return to window selection without taking a capture")
        active.onPropose?(draft.rect)
        active.reviewDraft = CaptureSelectionDraft(rect: draft.rect, windowID: 42)
        chooseSource(.region)
        precondition(active.mode == .region && active.reviewDraft?.rect == draft.rect && active.reviewDraft?.windowID == nil && !finished,
            "Region source must keep the rectangle and remove window tracking")
        precondition(active.isVideo == (media == .video) && active.isScrolling == scrolling,
            "Source selection changed the media/scroll route")
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
            let toolbar = active.subviews.compactMap { $0 as? CaptureReviewToolbar }.first!
            let item = toolbar.screenChoicesMenu().items.first { ($0.representedObject as? NSNumber)?.uint32Value == id }!
            _ = NSApp.sendAction(item.action!, to: item.target, from: item)
            active = NSApp.windows.compactMap { $0.contentView as? SelectionView }.first { $0.window?.isVisible == true && $0.reviewDraft != nil }!
            precondition(!finished && active.displayID == id && active.reviewDraft?.rect == screen.frame && active.reviewDraft?.windowID == nil,
                "Entire display was captured immediately or lost its screen geometry")
            precondition(active.isVideo == (media == .video) && active.isScrolling == scrolling,
                "Display switching lost the selected media/scroll route")
        }
        active.confirm()
        let selection = try await pending.value
        precondition(selection?.rect == selection?.screenFrame && selection?.media == media && selection?.isScrolling == scrolling)
        if media == .video { precondition(selection?.videoSource == .display) }
        selector.cancel()
    }
    print("Capture source/display menus passed: automatic selection preserves draft, window selection restarts, region retains rectangle without window tracking; screen menu changes full-screen frame before confirmation, actual display IDs/bounds, image/video/scroll route preserved, video display source and cleanup.")
}

@MainActor private func checkFinalFrameSettling(first: CGImage, next: CGImage, last: CGImage) async throws {
    let selection = ScreenshotSelection(displayID: 1, rect: CGRect(x: 100, y: 100, width: 180, height: 300),
        screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), isScrolling: true)
    let context = CGContext(data: nil, width: first.width, height: first.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: first.width, height: first.height))
    let repaint = context.makeImage()!
    // First accept the second viewport. Then imitate a brief blank repaint
    // just as Done is clicked. No warning should be shown
    // if the final viewport subsequently matches (with or without a new strip).
    for (final, expectedHeight) in [(next, 410), (last, 545)] {
        let gate = ScrollFrameGate(repaint)
        var samples = 0
        let session = ScrollCaptureSession(selection: selection, first: first, captureFrame: {
            samples += 1
            if samples == 1 { return next }
            if samples == 2 { return await gate.next() }
            return samples == 3 ? repaint : final
        })
        let running = Task { await session.run() }
        for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
        precondition(gate.started && session.count == 2)
        let panel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
        let done = (panel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
        done.performClick(nil); gate.release()
        for _ in 0..<500 where panel.isVisible && session.isFinishing { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!panel.isVisible && samples == 4, "Transient final mismatch still requires a second click (samples=\(samples), title=\(done.title))")
        let image = await running.value
        precondition(image?.height == expectedHeight, "Retry dropped or duplicated the final strip")
    }

    let gate = ScrollFrameGate(repaint)
    var samples = 0
    let unresolved = ScrollCaptureSession(selection: selection, first: first, captureFrame: {
        samples += 1
        if samples == 1 { return next }
        if samples == 2 { return await gate.next() }
        return repaint // No matching content ever returns.
    })
    let unresolvedRun = Task { await unresolved.run() }
    for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
    precondition(gate.started)
    let panel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
    let done = (panel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
    done.performClick(nil); gate.release()
    for _ in 0..<500 where unresolved.isFinishing { try await Task.sleep(for: .milliseconds(10)) }
    precondition(samples == 6 && done.isEnabled && done.title == String(localized: "Übernehmen"),
        "Final retries were unbounded or silently accepted an unresolved gap")
    done.performClick(nil)
    let partial = await unresolvedRun.value; precondition(partial?.height == 410)

    let cancelGate = ScrollFrameGate(repaint)
    var cancelSamples = 0
    let cancelled = ScrollCaptureSession(selection: selection, first: first, captureFrame: {
        cancelSamples += 1
        if cancelSamples == 1 { return next }
        if cancelSamples == 2 { return await cancelGate.next() }
        return repaint
    })
    let cancelledRun = Task { await cancelled.run() }
    for _ in 0..<500 where !cancelGate.started { try await Task.sleep(for: .milliseconds(10)) }
    precondition(cancelGate.started)
    let cancelPanel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
    let cancelDone = (cancelPanel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
    cancelDone.performClick(nil); cancelGate.release()
    for _ in 0..<500 where cancelSamples < 3 { try await Task.sleep(for: .milliseconds(10)) }
    cancelled.cancel()
    let cancelledImage = await cancelledRun.value; precondition(cancelledImage == nil)
    try await Task.sleep(for: .milliseconds(400))
    precondition(cancelSamples == 3 && !cancelPanel.isVisible, "Cancellation launched another final retry or published a late image")
    print("Final scroll frame passed: transient mismatch retries automatically, unchanged end opens with one click, new final strip included, persistent gap still explicit, bounded attempts and cancellation during retry.")
}

@MainActor private func checkOverlayHandoff() async throws {
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    let white = context.makeImage()!
    let desktop = FrozenDesktop(displays: NSScreen.screens.map {
        FrozenDisplay(displayID: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32, screenFrame: $0.frame, image: white)
    })
    let selector = ScreenshotSelector()
    let pending = Task { try await selector.select(source: .region, windows: [], desktop: desktop) }
    for _ in 0..<200 where !NSApp.windows.contains(where: { $0.isVisible && $0.contentView is SelectionView }) {
        try await Task.sleep(for: .milliseconds(10))
    }
    let panel = NSApp.windows.first { $0.isVisible && $0.contentView is SelectionView }!
    let view = panel.contentView as! SelectionView
    let draft = CaptureSelectionDraft(rect: panel.frame.insetBy(dx: 120, dy: 120))
    view.onPropose?(draft.rect)
    await NSAnimationContext.runAnimationGroup { context in context.duration = 0; view.setChromeVisible(true) }
    try await Task.sleep(for: .milliseconds(200))
    func pixels() -> NSBitmapImageRep {
        return renderSelectionMask(view)
    }
    let before = pixels()
    let beforeShade = before.colorAt(x: before.pixelsWide / 2, y: 50)!.usingColorSpace(.deviceRGB)!.redComponent
    view.isScrolling = true; view.confirm()
    let selected = try await pending.value
    let overlay = selector.takeScrollOverlay()
    precondition(selected?.isScrolling == true && selected?.rect == draft.rect && overlay != nil)
    selector.cancel() // Ownership belongs to the session now, not the selector.
    precondition(panel.isVisible && panel.contentView === view && panel.ignoresMouseEvents && !panel.isOpaque && view.isLiveCapture,
        "Scroll confirmation closed/replaced the existing mask or left it intercepting input")
    precondition(view.reviewDraft == draft && !view.isOpaque && view.frozenImage === white)
    let after = pixels()
    let shade = after.colorAt(x: after.pixelsWide / 2, y: 50)!.usingColorSpace(.deviceRGB)!
    precondition(abs(beforeShade - shade.redComponent) < 0.01 && shade.alphaComponent > 0.99,
        "The live mask changed the frozen surround/shade: before=\(beforeShade), after=\(shade)")
    precondition(after.colorAt(x: after.pixelsWide / 2, y: after.pixelsHigh / 2)!.alphaComponent < 0.01,
        "Frozen desktop still hides the scrolling content")
    overlay?.close(); precondition(!panel.isVisible)
    print("Scroll handoff passed: identical window/view/frame/shade, live transparent hole, click-through, transferred ownership and cleanup.")
}

@MainActor private func checkVideoOverlayHandoff() async throws {
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    let desktop = FrozenDesktop(displays: NSScreen.screens.map {
        FrozenDisplay(displayID: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32,
            screenFrame: $0.frame, image: context.makeImage()!)
    })
    for (wholeDisplay, cancelBeforeTransfer) in [(false, false), (true, false), (false, true)] {
        let selector = ScreenshotSelector()
        let pending = Task { try await selector.select(source: .region, windows: [], desktop: desktop) }
        for _ in 0..<200 where !NSApp.windows.contains(where: { $0.isVisible && $0.contentView is SelectionView }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let original = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible && $0.contentView is SelectionView }
        let panel = original[0], view = panel.contentView as! SelectionView
        let rect = wholeDisplay ? panel.frame : panel.frame.insetBy(dx: 120, dy: 120)
        view.onPropose?(rect)
        await NSAnimationContext.runAnimationGroup { context in context.duration = 0; view.setChromeVisible(true) }
        try await Task.sleep(for: .milliseconds(200))
        func findVideo(_ parent: NSView) -> NSButton? {
            if let button = parent as? NSButton, button.accessibilityIdentifier() == "capture.video" { return button }
            return parent.subviews.lazy.compactMap { findVideo($0) }.first
        }
        findVideo(view)!.performClick(nil) // Switch a photo request to video through the actual action.
        let selected = try await pending.value
        precondition(selected?.media == .video && selected?.rect == rect)
        // Source activation currently takes 350 ms. The blue mask must survive
        // a longer preparation interval without closing, fading or intercepting input.
        try await Task.sleep(for: .milliseconds(400))
        precondition(original.allSatisfy { $0.isVisible && $0.ignoresMouseEvents && !$0.isOpaque })
        precondition(panel.contentView === view && view.isLiveCapture && !view.subviews.contains { $0 is CaptureReviewToolbar })
        if cancelBeforeTransfer {
            selector.cancel()
            precondition(original.allSatisfy { !$0.isVisible }, "Abandoned video selection leaked its mask")
            continue
        }
        let overlay = selector.takeVideoOverlay()!
        selector.cancel()
        let keyWindow = NSApp.keyWindow
        let outline = VideoRecordingOutline(selection: selected!, selectionOverlay: overlay)
        overlay.close() // The outline owns the same windows now.
        precondition(original.allSatisfy { $0.isVisible && $0.identifier?.rawValue == "video.recordingRegion" },
            "Video handoff closed or replaced a selection window")
        precondition(NSApp.keyWindow === keyWindow, "Video handoff stole source focus")
        outline.show(recording: false)
        func edge() -> NSColor {
            let content = panel.contentView!, bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            return bitmap.colorAt(x: Int((rect.minX - panel.frame.minX + 1) * CGFloat(bitmap.pixelsWide) / panel.frame.width),
                y: Int((panel.frame.maxY - rect.midY) * CGFloat(bitmap.pixelsHigh) / panel.frame.height))!.usingColorSpace(.deviceRGB)!
        }
        let blue = edge()
        precondition(blue.alphaComponent > 0.9 && blue.blueComponent > blue.redComponent, "Preparation frame was not blue")
        outline.show(recording: true)
        let red = edge()
        precondition(red.alphaComponent > 0.9 && red.redComponent > red.blueComponent && panel.isVisible,
            "Recording did not recolor the existing visible frame")
        outline.hide()
        precondition(original.allSatisfy { !$0.isVisible }, "Video cleanup retained a mask")
    }
    print("Video selection handoff passed: real Video action, same visible windows during source delay and live outline, blue-to-red recolor, whole display, passthrough/focus, ownership and early cancellation cleanup.")
}

@MainActor private func checkRetinaTextScrolling() async throws {
    let width = 2200, viewport = 1400, pageHeight = 3200
    let context = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let words = ["Aufnahme", "Bereich", "Vorschau", "Fenster", "Darstellung", "Markierung", "Ausschnitt", "Seite", "Beispiel", "Inhalt", "Projekt", "Sammlung", "Bild", "Auswahl", "Export", "Format", "Breite", "Position", "Werkzeug", "Bibliothek"]
    for line in 0..<60 {
        var seed = UInt64(line + 1) * 7919
        let body = (0..<(8 + line % 5)).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return words[Int((seed >> 32) % UInt64(words.count))]
        }.joined(separator: " ")
        let text = "Absatz \(line + 1) – Synthetischer Text \(line * 7919 + 2137). " + body
        (text as NSString).draw(at: CGPoint(x: 80 + line % 3 * 12, y: line * 52), withAttributes:
            [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let source = context.makeImage()!
    func slice(_ offset: Int) -> CGImage { source.cropping(to: CGRect(x: 0, y: offset, width: width, height: viewport))! }
    let first = slice(0)
    let clock = ContinuousClock(), start = clock.now
    // Tiny smooth-scroll increments as well as non-line-aligned larger steps.
    var previous = first, accumulated = first
    for offset in [2, 137, 391, 732] {
        let next = slice(offset), prior = previous, composed = accumulated
        accumulated = try await Task.detached {
            try ScrollCaptureProcessor.append(previous: prior, next: next, accumulated: composed, count: 1, allowsScrolling: true)
        }.value
        previous = next
        precondition(accumulated.height == viewport + offset, "Retina text did not grow at the exact scroll displacement")
    }
    let elapsed = start.duration(to: clock.now)
    let actual = NSBitmapImageRep(cgImage: accumulated), expected = NSBitmapImageRep(cgImage: source)
    for y in stride(from: 0, to: accumulated.height, by: 7) { for x in stride(from: 0, to: width, by: 61) {
        let a = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        let b = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        precondition(abs(a.redComponent - b.redComponent) < 0.01, "Text seam at \(x),\(y)")
    } }
    let selection = ScreenshotSelection(displayID: 1, rect: CGRect(x: 100, y: 100, width: 700, height: 500),
        screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), isScrolling: true)
    var frameIndex = 0
    let scrollingStarted = clock.now
    let session = ScrollCaptureSession(selection: selection, first: first, captureFrame: {
        frameIndex += 1
        let elapsed = scrollingStarted.duration(to: clock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        // Advance independently of analysis: real scrolling keeps moving while
        // the previous frame is being processed. No artificial pause per frame.
        return slice(min(732, Int(seconds * 600)))
    })
    let running = Task { await session.run() }
    try await Task.sleep(for: .milliseconds(20))
    let preview = NSApp.windows.first { $0.isVisible && $0.accessibilityIdentifier() == "scroll.preview" }!
        .contentView!.subviews.compactMap { $0 as? NSImageView }.first!
    for _ in 0..<1500 where preview.image?.size.height != CGFloat(viewport + 732) {
        try await Task.sleep(for: .milliseconds(10))
    }
    precondition(session.count >= 3, "Continuously moving Retina frames were not appended automatically")
    precondition(preview.image?.size.height == CGFloat(viewport + 732), "The corner preview did not grow with the composed image")
    session.cancel(); _ = await running.value
    print("Retina text: 2200 × 1400 input, four exact seamless increments in \(elapsed), timed continuous 600 px/s scrolling across \(frameIndex) samples, corner preview 2200 × \(viewport + 732).")
}


@MainActor private func checkEditableProject(_ stitched: CGImage) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Scroll-\(UUID())")
    let suite = "Snaprivo-Scroll-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
    let workspace = WorkspaceModel(root: root, defaults: defaults)
    workspace.openScreenshot(stitched)
    for _ in 0..<500 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    guard let editor = workspace.editor else { preconditionFailure("Scroll result did not open as an editor project") }
    let original = try EditorRenderer.png(image: stitched, objects: [])
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 150, y: 190), lineWidth: 8)
    let text = EditorObject(kind: .text, start: CGPoint(x: 25, y: 220), text: "Scroll-Test", fontSize: 18)
    let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 20, y: 350), end: CGPoint(x: 160, y: 410), lineWidth: 4)
    editor.commit([arrow, text, shape])
    // Exercise debounce itself, without forcing a save before the simulated restart.
    try await Task.sleep(for: .milliseconds(1000))
    for _ in 0..<500 where editor.isSaving { try await Task.sleep(for: .milliseconds(10)) }
    precondition(!editor.isDirty && editor.saveError == nil, "Scroll annotations were not autosaved")
    let saved = try await ProjectStore(root: root).load(editor.document.id)
    precondition(saved.original == original && saved.document.objects == [arrow, text, shape])
    let restarted = WorkspaceModel(root: root, defaults: defaults)
    await restarted.refreshLibrary()
    precondition(restarted.items.contains { $0.document.id == editor.document.id }, "Scroll project missing after restart")
    restarted.openProject(editor.document.id)
    for _ in 0..<500 where restarted.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    guard let restored = restarted.editor else { preconditionFailure("Saved scroll project cannot be reopened") }
    precondition(restored.image.width == stitched.width && restored.image.height == stitched.height)
    precondition(restored.history.objects == [arrow, text, shape], "Restart flattened or lost scroll annotations")
    var moved = arrow; moved.end.y += 20
    restored.commit([moved, text, shape]); restored.undo()
    precondition(restored.history.objects == [arrow, text, shape], "Reopened scroll object cannot be undone")
    restored.redo()
    let flushed = await restored.flush(); precondition(flushed)
    let exported = try EditorRenderer.png(image: restored.image, objects: restored.history.objects)
    let bitmap = NSBitmapImageRep(data: exported)!
    precondition(bitmap.pixelsWide == stitched.width && bitmap.pixelsHigh == stitched.height)
    let reloaded = try await ProjectStore(root: root).load(editor.document.id)
    precondition(reloaded.document.objects == [moved, text, shape], "Edits after restart were lost")
}

@MainActor private final class ScrollFrameGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
    func next() async -> CGImage {
        if !started {
            started = true
            await withCheckedContinuation { continuation = $0 }
        }
        return image
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private func checkSessionControls(first: CGImage, next: CGImage) async throws {
    _ = NSApplication.shared
    let selection = ScreenshotSelection(displayID: 1, rect: CGRect(x: 0, y: 100, width: 180, height: 300), screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), isScrolling: true)
    let gate = ScrollFrameGate(next)
    let session = ScrollCaptureSession(selection: selection, first: first, captureFrame: { await gate.next() })
    var finished = false
    let running = Task { let image = await session.run(); finished = true; return image }
    for _ in 0..<400 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
    precondition(gate.started, "Automatic capture did not start by itself")
    guard let panel = NSApp.windows.first(where: { $0 is ScrollCapturePanel && $0.isVisible }), let content = (panel.contentView as? CaptureToolbarSurface)?.controls else { preconditionFailure("Scroll controls missing") }
    let border = NSApp.windows.first { $0.accessibilityIdentifier() == "scroll.border" && $0.isVisible }!
    precondition(border.ignoresMouseEvents && border.frame == selection.screenFrame &&
        (border.contentView as? SelectionView)?.reviewDraft?.rect == selection.rect,
        "Live mask blocks the underlying app or changed capture geometry")
    precondition(panel.frame.height < 100, "Manual assembly panel still present")
    precondition(!content.subviews.contains { ($0 as? NSButton)?.action == NSSelectorFromString("addSection") })
    let done = content.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
    precondition(NSApp.mainWindow === panel && panel.firstResponder === done, "Scroll controls have no native keyboard/accessibility focus")
    precondition(done.isEnabled && done.title == String(localized: "Fertig"), "Done is unavailable during capture")
    done.performClick(nil)
    precondition(session.isFinishing && !finished, "Done did not await its in-flight frame")
    gate.release()
    let image = await running.value
    precondition(image?.height == 410 && session.count == 2 && finished)
    precondition(!panel.isVisible && !NSApp.windows.contains { $0.accessibilityIdentifier() == "scroll.preview" && $0.isVisible })

    let automatic = ScrollCaptureSession(selection: selection, first: first, captureFrame: { next })
    let automaticRun = Task { await automatic.run() }
    for _ in 0..<400 where automatic.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
    precondition(automatic.count == 2, "The user still has to add individual sections")
    let automaticPanel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
    let body = (automaticPanel.contentView as! CaptureToolbarSurface).controls
    let bitmap = body.bitmapImageRepForCachingDisplay(in: body.bounds)!
    body.cacheDisplay(in: body.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/Snaprivo-ScrollControls.png"))
    automatic.cancel(); let automaticImage = await automaticRun.value; precondition(automaticImage == nil)
    let stoppedCount = automatic.count
    try await Task.sleep(for: .milliseconds(300)); precondition(automatic.count == stoppedCount)

    let cancelledGate = ScrollFrameGate(next)
    let cancelled = ScrollCaptureSession(selection: selection, first: first, captureFrame: { await cancelledGate.next() })
    let cancelledRun = Task { await cancelled.run() }
    for _ in 0..<400 where !cancelledGate.started { try await Task.sleep(for: .milliseconds(10)) }
    cancelled.cancel(); cancelledGate.release()
    let cancelledImage = await cancelledRun.value; precondition(cancelledImage == nil)
    try await Task.sleep(for: .milliseconds(300)); precondition(cancelled.count == 1, "Cancelled frame appended late")

    let failed = ScrollCaptureSession(selection: selection, first: first, captureFrame: { throw ScreenshotError.invalidRegion })
    let failedRun = Task { await failed.run() }
    try await Task.sleep(for: .milliseconds(100))
    let failedPanel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
    let failedDone = (failedPanel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
    failedDone.performClick(nil)
    for _ in 0..<400 where failed.isFinishing { try await Task.sleep(for: .milliseconds(10)) }
    precondition(failedDone.isEnabled && failedDone.title == String(localized: "Übernehmen"), "Failed final frame silently published a complete capture")
    failedDone.performClick(nil)
    let failedImage = await failedRun.value; precondition(failedImage?.height == first.height, "Explicit partial-image confirmation was ignored")

    let trimmed = ScrollCaptureSession(selection: selection, first: first, captureFrame: { first })
    let trimmedRun = Task { await trimmed.run() }
    try await Task.sleep(for: .milliseconds(50))
    let trimmedPanel = NSApp.windows.first { $0 is ScrollCapturePanel && $0.isVisible }!
    let trimmedDone = (trimmedPanel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.finish" } as! NSButton
    let options = (trimmedPanel.contentView as! CaptureToolbarSurface).controls.subviews.first { $0.accessibilityIdentifier() == "scroll.options" } as! NSButton
    let menu = options.menu!
    for (title, percent) in [(String(localized: "Oben auslassen"), 10), (String(localized: "Unten auslassen"), 20)] {
        trimmed.menuNeedsUpdate(menu)
        let item = menu.items.first { $0.title == title }!.submenu!.items.first { $0.tag == percent }!
        precondition(item.isEnabled)
        _ = NSApp.sendAction(item.action!, to: item.target, from: item)
        for _ in 0..<400 where !trimmedDone.isEnabled { try await Task.sleep(for: .milliseconds(10)) }
    }
    trimmedDone.performClick(nil)
    let trimmedImage = await trimmedRun.value
    precondition(trimmedImage?.height == 210 && trimmedImage?.width == first.width, "Inset menus did not exclude fixed header/footer")
    print("Scroll controls passed: compact Done/preview, automatic capture without Add, finishing waits for pending frame, final viewport, partial-result confirmation, cancellation and no late append. Synthetic frames only.")
}

@main struct ScrollValidationRunner {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await ScrollCaptureChecks.run() }
            catch { preconditionFailure("Scroll validation failed: \(error)") }
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
    }
}
