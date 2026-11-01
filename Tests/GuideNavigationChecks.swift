import AppKit
import SwiftUI
import Darwin
import SnagForgeDomain

@MainActor private final class NavigationProStore: ProStoreClient {
    func offer() async throws -> ProOffer? { nil }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .cancelled }
    func restore() async throws { }
    func updates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@MainActor private final class GuideFirstFrameRecorder {
    weak var host: NSView?
    var imagePixels: [Int] = []
    func capture() {
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var red = 0
        // Ignore list selection and count only the synthetic red step image in the detail.
        let start = Int(260 * CGFloat(bitmap.pixelsWide) / host.bounds.width)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: start, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   color.redComponent > 0.6 && color.redComponent > color.greenComponent * 2
                    && color.redComponent > color.blueComponent * 2 { red += 1 }
            }
        }
        imagePixels.append(red)
        if red == 0 {
            try? bitmap.representation(using: .png, properties: [:])!.write(to:
                URL(fileURLWithPath: "build/GuideNavigationTests/guide-switch-frame.png"))
        }
    }
}

private struct GuideNavigationTestRoot: View {
    let workspace: WorkspaceModel
    @Bindable var model: GuideModel
    let frames: GuideFirstFrameRecorder
    var body: some View {
        GuideView(workspace: workspace, model: model)
            .onChange(of: model.document?.id) { _, id in if id != nil { frames.capture() } }
    }
}

@main struct GuideNavigationChecks {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run() }
            catch { preconditionFailure("Guide navigation failed: \(error)") }
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
    }
    @MainActor private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideNavigation-\(UUID())")
        let suite = "GuideNavigation-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let purchases = ProPurchaseModel(client: NavigationProStore()); await purchases.start()
        let workspace = WorkspaceModel(root: root, defaults: defaults, purchases: purchases)
        let model = workspace.guides
        let context = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(srgbRed: 0.9, green: 0.05, blue: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        let png = try EditorRenderer.png(image: context.makeImage()!, objects: [])
        let guides = (0..<3).map { GuideDocument(title: "Synthetic guide \($0)", steps: [GuideStep(title: "Step", png: png)]) }
        for guide in guides { try await model.store.create(guide) }
        await model.refresh()
        func wait() async throws {
            for _ in 0..<1000 { if !model.isBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Guide navigation timed out")
        }
        model.open(guides[0].id); try await wait()
        model.edit { $0.title = "Edited before switching" }
        let savedBeforeSwitch = await model.flush(); precondition(savedBeforeSwitch)

        let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: 1000, height: 680),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let frames = GuideFirstFrameRecorder()
        let host = NSHostingView(rootView: GuideNavigationTestRoot(workspace: workspace, model: model, frames: frames)
            .environment(\.accessibilityEnabled, true))
        frames.host = host
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        frames.capture()
        precondition(frames.imagePixels.last! > 1_000, "Initial guide image was not visible to the frame check")
        func footerPixels() -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let rect = CGRect(x: 0, y: Int((host.bounds.height - 120) * scale), width: Int(180 * scale), height: Int(120 * scale))
            return NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: rect)!).representation(using: .png, properties: [:])!
        }
        func detailPixels() -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let left = Int(260 * CGFloat(bitmap.pixelsWide) / host.bounds.width)
            let rect = CGRect(x: left, y: 0, width: bitmap.pixelsWide - left, height: bitmap.pixelsHigh)
            return NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: rect)!).representation(using: .png, properties: [:])!
        }
        let before = footerPixels()
        let detailBefore = detailPixels()
        let lock = Darwin.open(model.store.root.appendingPathComponent(".guide-lock").path, O_RDWR)
        precondition(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0)
        model.open(guides[1].id)
        precondition(model.isBusy && model.isOpeningDocument && !model.isBusyForControls)
        precondition(model.canUndoForControls && !model.canUndo)
        precondition(model.document?.id == guides[0].id)
        model.selectDocuments([guides[2].id]); model.chooseImport()
        precondition(model.selectedDocumentIDs == [guides[1].id])
        try await Task.sleep(for: .milliseconds(70))
        precondition(footerPixels() == before, "Opening a guide flashed Import/Trash controls")
        try await Task.sleep(for: .milliseconds(300))
        precondition(detailPixels() == detailBefore,
                     "A slow guide switch flashed an overlay or rebuilt the existing detail")
        _ = flock(lock, LOCK_UN); Darwin.close(lock)
        try await wait()
        precondition(model.document?.id == guides[1].id && model.openingDocumentID == nil)
        precondition(frames.imagePixels.allSatisfy { $0 > 1_000 },
                     "The guide detail flashed an empty image in its first frame: \(frames.imagePixels)")

        @MainActor func accessibilityElement(_ object: Any, id: String? = nil, placeholder: String? = nil, depth: Int = 0) -> AnyObject? {
            guard depth < 50, let node = object as? NSObject else { return nil }
            // SwiftUI's virtual nodes implement the public selectors without adopting the full protocol.
            let value: AnyObject = node
            if let id, value.accessibilityIdentifier?() == id { return value }
            if let placeholder, value.accessibilityPlaceholderValue?() == placeholder { return value }
            for child in value.accessibilityChildren?() ?? [] {
                if let result = accessibilityElement(child, id: id, placeholder: placeholder, depth: depth + 1) { return result }
            }
            return nil
        }
        let assistantButton = accessibilityElement(host, id: "guide.assistant.open")!
        precondition(assistantButton.accessibilityPerformPress?() == true, "Native assistant action could not be activated")
        for _ in 0..<100 {
            if window.attachedSheet != nil { break }; try await Task.sleep(for: .milliseconds(10))
        }
        let assistantSheet = window.attachedSheet!
        try await Task.sleep(for: .milliseconds(150))
        let assistantRoot = assistantSheet.contentView!
        // The AppKit-backed TextField exposes its placeholder, but not SwiftUI's identifier.
        let goalField = accessibilityElement(assistantRoot, placeholder: String(localized: "Ziel oder ergänzende Hinweise"))!
        precondition((goalField.accessibilityFrame?() ?? .zero).width > 0, "Assistant goal field was not laid out")
        @MainActor func describeAccessibility(_ object: Any, depth: Int = 0) {
            guard depth < 30, let node = object as? NSObject else { return }
            let value: AnyObject = node
            print(depth, value.accessibilityRole?() as Any, value.accessibilityIdentifier?() as Any,
                  value.accessibilityLabel?() as Any, value.accessibilityFrame?() as Any)
            for child in value.accessibilityChildren?() ?? [] { describeAccessibility(child, depth: depth + 1) }
        }
        guard let accept = accessibilityElement(assistantRoot, id: "guide.assistant.apply") else {
            describeAccessibility(assistantRoot); fflush(nil)
            preconditionFailure("Assistant Apply button was absent from the native accessibility tree")
        }
        precondition(accept.isAccessibilityEnabled?() == false, "Assistant accepted before a reviewed proposal existed")
        precondition(accessibilityElement(assistantRoot, id: "guide.assistant.close")!.accessibilityPerformPress?() == true)
        for _ in 0..<100 {
            if window.attachedSheet == nil { break }; try await Task.sleep(for: .milliseconds(10))
        }
        precondition(window.attachedSheet == nil && model.document?.id == guides[1].id && !model.isDirty,
                     "Closing the assistant changed the guide or left its sheet open")

        func table(in view: NSView) -> NSTableView? {
            if let result = view as? NSTableView { return result }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        // Exercise the actual mouse path as well as model.open: List supplies its own transaction.
        for target in [guides[0].id, guides[1].id, guides[0].id] {
            let list = table(in: host)!
            window.makeFirstResponder(list)
            try await Task.sleep(for: .milliseconds(80))
            let footer = footerPixels()
            let row = model.documents.firstIndex(where: { $0.id == target })!
            let point = list.convert(NSPoint(x: list.bounds.midX, y: list.rect(ofRow: row).midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
            }
            var changedFrames = 0
            for _ in 0..<24 {
                try await Task.sleep(for: .milliseconds(16))
                if footerPixels() != footer { changedFrames += 1 }
                frames.capture()
            }
            precondition(model.document?.id == target, "Native guide click did not open its row")
            precondition(changedFrames == 0, "Native guide switch changed Import/Trash pixels in \(changedFrames) frames")
            precondition(frames.imagePixels.allSatisfy { $0 > 1_000 },
                         "A guide switch briefly emptied the step image: \(frames.imagePixels)")
        }
        func sendDelete(_ code: UInt16) async throws {
            // AppKit focus changes reach SwiftUI's command graph on the next run-loop turn.
            try await Task.sleep(for: .milliseconds(50))
            let character = code == 51 ? "\u{7F}" : "\u{F728}"
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
            // SwiftUI's native command routing needs NSApp.currentEvent, populated by the event loop.
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(50))
        }
        func selectPairAndDelete(_ code: UInt16) async throws {
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100))
            let list = table(in: host)!
            let ids: Set<UUID> = [guides[0].id, guides[1].id]
            let rows = IndexSet(model.documents.indices.filter { ids.contains(model.documents[$0].id) })
            list.selectRowIndexes(rows, byExtendingSelection: false)
            try await Task.sleep(for: .milliseconds(30))
            precondition(model.selectedDocumentIDs == ids, "Native guide list did not publish its multiple selection")
            precondition(model.canTrashSelection && list.allowsMultipleSelection)
            precondition(window.isKeyWindow, "Delete must be tested in the active native window")
            window.makeFirstResponder(list)
            try await sendDelete(code); try await wait()
            precondition(Set(model.trash.map(\.id)) == ids && model.documents.map(\.id) == [guides[2].id],
                         "Delete key \(code) did not move selected guides to Trash (active: \(model.documents.map(\.id)), trash: \(model.trash.map(\.id)), selection: \(model.selectedDocumentIDs), busy: \(model.isBusy), key window: \(window.isKeyWindow), responder: \(String(describing: window.firstResponder)), error: \(String(describing: model.error)))")
            precondition(model.document == nil && model.selectedDocumentIDs.isEmpty)
            for id in ids { model.restore(id); try await wait() }
            model.open(guides[1].id); try await wait()
        }
        try await selectPairAndDelete(51)
        try await selectPairAndDelete(117)

        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100))
        func titleField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.stringValue == model.document?.title { return field }
            return view.subviews.lazy.compactMap { titleField(in: $0) }.first
        }
        let title = titleField(in: host)!
        precondition(window.makeFirstResponder(title))
        let text = title.currentEditor() as! NSTextView
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        try await sendDelete(51)
        precondition(model.document?.title == "" && model.trash.isEmpty && model.documents.count == 3,
                     "Delete in a text field did not stay with its native text editor")
        window.makeFirstResponder(nil)
        model.selectDocuments([guides[0].id, guides[1].id]); model.trashSelection(); try await wait()
        precondition(model.trash.isEmpty && model.documents.count == 3 && model.isDirty && model.error != nil,
                     "A failed save discarded or trashed the selection")
        model.edit { $0.title = "Recovered title" }
        let recovered = await model.flush(); precondition(recovered)
        model.searchQuery = "Synthetic"
        precondition(model.selectedDocumentIDs.isEmpty, "Search retained a hidden bulk-delete selection")
        model.open(guides[1].id)
        precondition(!model.canTrashSelection, "Search enabled deletion without a selected list row")
        model.trashSelection(); try await wait()
        precondition(model.trash.isEmpty && model.documents.count == 3)
        print("Guide navigation passed: native assistant open/goal field/disabled Apply/close, unchanged guide on dismissal; slow opening retains all detail pixels, repeated native clicks retain chrome and step images across frames, stable toolbar eligibility, native multi-selection, both Delete keys, text-field isolation, restore, failed-save and hidden-search-selection protection.")
    }
}
