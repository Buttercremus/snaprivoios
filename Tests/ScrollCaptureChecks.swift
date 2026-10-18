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
        try await checkSessionControls(first: a, next: b)
        try await checkEditableProject(second)
        print("Scroll capture checks passed: exact vertical seams/orientation across three frames, stable-frame check, section limit, editor autosave/restart/edit/undo/export.")
    }
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

@MainActor private func checkSessionControls(first: CGImage, next: CGImage) async throws {
    _ = NSApplication.shared
    let selection = ScreenshotSelection(displayID: 1, rect: CGRect(x: 0, y: 0, width: 180, height: 300), screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    let session = ManualScrollSession(selection: selection, first: first, captureFrame: { next })
    let running = Task { await session.run() }
    try await Task.sleep(for: .milliseconds(100))
    guard let panel = NSApp.windows.first(where: { $0 is ScrollCapturePanel && $0.isVisible }), let content = panel.contentView else { preconditionFailure("Scroll panel missing") }
    let auto = content.subviews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("toggleAutomatic") }!
    let undo = content.subviews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("undoLastSection") }!
    auto.performClick(nil)
    for _ in 0..<400 {
        if session.count == 2 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    precondition(session.count == 2, "Automatic stable section was not appended")
    auto.performClick(nil)
    // Let any in-flight unchanged-frame request finish before using Undo.
    try await Task.sleep(for: .milliseconds(500))
    undo.performClick(nil)
    precondition(session.count == 1, "Undo did not restore the previous section")
    let popups = content.subviews.compactMap { $0 as? NSPopUpButton }
    precondition(popups.count == 2 && popups.allSatisfy(\.isEnabled))
    popups[0].selectItem(at: 2); _ = NSApp.sendAction(popups[0].action!, to: popups[0].target, from: popups[0])
    session.cancel()
    let result = await running.value; precondition(result == nil)
    try await Task.sleep(for: .milliseconds(1000)); precondition(session.count == 1, "A cancelled auto session kept appending")
    print("Scroll controls passed: automatic stable capture, undo, inset controls and cancellation; no real capture requested.")
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
