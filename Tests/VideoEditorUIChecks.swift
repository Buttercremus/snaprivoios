import AppKit
import SwiftUI
import SnagForgeDomain

/// Operates the real extended video editor through its own controls in an offscreen window and keeps
/// a screenshot of every state for visual review. Synthetic clip only; no capture, microphone or audio output.
@main struct VideoEditorUIChecks {
    /// A real AppKit run loop serves popovers and SwiftUI's accessibility tree.
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run() }
            catch { preconditionFailure("Video editor UI failed: \(error)") }
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/VideoEditorUI/Screens", isDirectory: true)
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoEditorUI-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Originals"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await SyntheticVideoFixture.write(to: partial, includesAudio: true)
        let original = try await files.finalize(partial, audio: .init(systemAudio: true))
        let originalBytes = try Data(contentsOf: original)
        let document = try await files.list().items.first!.document
        precondition(document.hasAudio, "The synthetic clip lacks the audio track the volume control needs")
        let model = VideoEditorModel(document: document, url: original, files: files)
        model.player.isMuted = true
        defer { model.stopPreview() }

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VideoReviewView(model: model).environment(\.accessibilityEnabled, true))
        // Offscreen: the check never covers the user's own windows.
        window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
        // Not key and not activated: the check never takes focus, and SwiftUI then draws into the window snapshot.
        window.orderFront(nil)
        let host = window.contentView!

        func settle(_ milliseconds: Int = 350) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
        func waitFor(_ what: String, _ condition: () -> Bool) async throws {
            for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
            preconditionFailure("Timed out waiting for \(what)")
        }
        var shots: [(String, CGSize)] = []
        func shoot(_ name: String, _ view: NSView = host) throws {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            shots.append((name, view.bounds.size))
        }
        func element(_ object: Any, id: String? = nil, label: String? = nil, depth: Int = 0) -> AnyObject? {
            guard depth < 60, let node = object as? NSObject else { return nil }
            // SwiftUI's virtual nodes implement the public selectors without adopting the full protocol.
            let value: AnyObject = node
            if let id, value.accessibilityIdentifier?() == id { return value }
            if let label, value.accessibilityLabel?() == label { return value }
            for child in value.accessibilityChildren?() ?? [] {
                if let found = element(child, id: id, label: label, depth: depth + 1) { return found }
            }
            // Scroll views embed their SwiftUI content in a hosting view that is not an accessibility child.
            for subview in (node as? NSView)?.subviews ?? [] {
                if let found = element(subview, id: id, label: label, depth: depth + 1) { return found }
            }
            return nil
        }
        func press(_ object: AnyObject?, _ what: String) {
            precondition(object?.accessibilityPerformPress?() == true, "Could not press \(what)")
        }
        /// Controls are disabled while the preview rebuilds; press once the control is there and enabled.
        func press(id: String? = nil, label: String? = nil, in view: NSView = host, _ what: String) async throws {
            var control: AnyObject?
            for _ in 0..<150 {
                control = element(view, id: id, label: label)
                if control?.isAccessibilityEnabled?() == true { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            precondition(control?.isAccessibilityEnabled?() == true, "\(what) was missing or stayed disabled")
            press(control, what)
        }
        func isEnabled(_ id: String) -> Bool { element(host, id: id)?.isAccessibilityEnabled?() == true }
        func shown(_ id: String) -> String? { (element(host, id: id) as? NSObject)?.value(forKey: "accessibilityValue") as? String }
        /// The scrolling option panel exposes no accessibility children in this offscreen window, but SwiftUI keeps one
        /// keyboard proxy per control at its exact place. Real mouse clicks there operate the controls; each effect is
        /// checked against the model, which also confirms which control was hit.
        func panelControls() -> [NSView] {
            guard let panel = views(NSScrollView.self, in: host).first(where: { $0.frame.width < 300 }) else { preconditionFailure("Missing option panel") }
            return views(NSView.self, in: panel).filter { String(describing: Swift.type(of: $0)).contains("KeyViewProxy") }.sorted { $0.frame.minY < $1.frame.minY }
        }
        func click(_ view: NSView, atFraction fraction: CGFloat = 0.5) {
            let point = view.convert(CGPoint(x: view.bounds.minX + view.bounds.width * fraction, y: view.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            }
        }
        func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            view.subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + views(type, in: $0) }
        }
        /// SwiftUI pickers are virtual accessibility nodes. Open the menu like VoiceOver or with a click, then choose
        /// with the arrow keys and Return, as a person would. The starting highlight depends on how the menu opened,
        /// so Up first reaches the top item in every case.
        func choose(item index: Int, of count: Int, inPicker id: String, opening proxy: NSView? = nil) async throws {
            if let proxy { click(proxy) } else {
                guard let picker = element(host, id: id) else { preconditionFailure("Missing picker \(id)") }
                precondition(picker.isAccessibilityEnabled?() == true, "Picker \(id) is disabled")
                press(picker, "Picker \(id)")
            }
            var menu: NSWindow?
            for _ in 0..<50 where menu == nil {
                try await Task.sleep(for: .milliseconds(20))
                menu = NSApp.windows.first { $0.isVisible && $0 !== window && $0.className.contains("Menu") }
            }
            guard let menu else { preconditionFailure("Picker \(id) opened no menu") }
            func key(_ code: UInt16, _ characters: String) {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    NSApp.postEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: menu.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: code)!, atStart: false)
                }
            }
            for _ in 0...count { key(126, String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)) }
            for _ in 0..<index { key(125, String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)) }
            key(36, "\r")
            for _ in 0..<50 where menu.isVisible { try await Task.sleep(for: .milliseconds(20)) }
            precondition(!menu.isVisible, "The menu of \(id) stayed open")
        }
        /// Sliders take an accessibility value; stepping is the fallback for nodes that only increment.
        func setSlider(_ slider: AnyObject?, to target: Double, _ what: String) {
            guard let slider else { preconditionFailure("Missing slider \(what)") }
            precondition(slider.isAccessibilityEnabled?() == true, "Slider \(what) is disabled")
            slider.setAccessibilityValue?(NSNumber(value: target))
            func current() -> Double {
                let value: Any? = (slider as? NSObject)?.value(forKey: "accessibilityValue")
                return (value as? NSNumber)?.doubleValue ?? .nan
            }
            for _ in 0..<100 where abs(current() - target) > 0.02 {
                if current() > target { slider.accessibilityPerformDecrement?() } else { slider.accessibilityPerformIncrement?() }
            }
        }
        func popover() -> NSWindow? { NSApp.windows.first { $0 !== window && $0.isVisible && $0.className.contains("Popover") } }
        func enter(_ seconds: Double, into id: String, in view: NSView) {
            guard let field = views(NSTextField.self, in: view).first(where: { $0.accessibilityIdentifier() == id })
                ?? (element(view, id: id) as? NSTextField) else { preconditionFailure("Missing field \(id)") }
            precondition(field.window?.makeFirstResponder(field) == true, "Field \(id) took no focus")
            let editor = field.currentEditor()!
            editor.selectAll(nil)
            editor.insertText(seconds.formatted(.number.precision(.fractionLength(1)).grouping(.never)))
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

        // 1. Opened editor with a ready preview, full original and neutral playback.
        try await waitFor("the first preview") { model.isPreviewReady }
        try await settle()
        precondition(model.playback.isIdentity && !model.hasUnappliedChanges && model.start == 0 && near(model.end, model.duration))
        try shoot("01-geoeffnet")
        // Glass buttons look pale in window snapshots; their real state comes from accessibility.
        precondition(isEnabled("video.editor.play") && !isEnabled("video.editor.apply") && !isEnabled("video.editor.reset"),
                     "Initial control states are wrong: play must be on, saving and reset off")

        // 2. Timeline zoom keeps the playhead in view: seek near the end, then 8×.
        model.seek(1.7); try await settle()
        try await choose(item: 3, of: 4, inPicker: "video.editor.timelineZoom")
        try await settle(500)
        precondition(shown("video.editor.timelineZoom") == VideoTimelineZoom.eightTimes.title, "The time view picker did not show 8×")
        try shoot("02-zeitansicht-8x")
        let scroller = views(NSScrollView.self, in: host).first { $0.hasHorizontalScroller && ($0.documentView?.frame.width ?? 0) > $0.frame.width * 7 }
        precondition(scroller != nil, "The 8× timeline did not widen its scrolling content")
        let visible = scroller!.documentVisibleRect, content = scroller!.documentView!.frame.width
        let playheadX = 16 + (content - 32) * 1.7 / model.duration
        precondition(visible.minX <= playheadX && playheadX <= visible.maxX, "Zooming lost the playhead: \(visible) vs. \(playheadX)")
        try await choose(item: 0, of: 4, inPicker: "video.editor.timelineZoom"); try await settle()
        precondition(shown("video.editor.timelineZoom") == VideoTimelineZoom.fit.title, "The time view did not return to the whole clip")

        // 3. Remove an inner section through its popover.
        model.seek(0.6); try await settle()
        let controls = panelControls()
        precondition(controls.count >= 4, "The option panel lacks its tempo, volume, section and zoom controls")
        click(controls[2])
        try await waitFor("the range popover") { popover() != nil }
        try await settle()
        let removePopover = popover()!.contentView!
        enter(0.6, into: "video.range.start", in: removePopover)
        enter(1.0, into: "video.range.end", in: removePopover)
        try await settle()
        try shoot("03-abschnitt-entfernen-popover", removePopover)
        try await press(id: "video.range.apply", in: removePopover, "Übernehmen im Abschnittspopover")
        try await waitFor("the closed popover") { popover() == nil }
        precondition(model.playback.removed.count == 1 && near(model.playback.removed[0].start, 0.6) && near(model.playback.removed[0].end, 1.0)
                     && near(model.outputDuration, model.duration - 0.4) && model.hasUnappliedChanges, "The removed section was not applied: \(model.playback)")
        try await settle()
        precondition(isEnabled("video.editor.apply") && isEnabled("video.editor.reset"), "Saving or reset stayed off with an unsaved cut")
        try shoot("04-abschnitt-entfernt")

        // 4. Tempo and volume through their native controls.
        // Items: 0,25× 0,5× 0,75× 1× 1,25× 1,5× 2× 3× 4×.
        try await choose(item: 6, of: 9, inPicker: "video.playback.speed", opening: panelControls()[0])
        try await settle()
        click(panelControls()[1], atFraction: 0.5)
        try await settle()
        precondition(model.playback.speed == 2 && abs(model.playback.volume - 0.5) < 0.08 && near(model.outputDuration, (model.duration - 0.4) / 2),
                     "Tempo or volume did not reach the edit: \(model.playback)")
        try shoot("05-tempo-lautstaerke")

        // 5. Add a manual zoom section and enlarge it.
        model.seek(0.2); try await settle()
        // Panel order: tempo, volume, remove section, one "reinsert" per removed section, then add zoom.
        let removedBefore = model.playback.removed
        click(panelControls()[3 + removedBefore.count])
        try await waitFor("the zoom popover") { popover() != nil }
        try await settle()
        let zoomPopover = popover()!.contentView!
        precondition(model.playback.removed == removedBefore, "The click hit another panel control")
        enter(0.1, into: "video.range.start", in: zoomPopover)
        enter(0.5, into: "video.range.end", in: zoomPopover)
        setSlider(element(zoomPopover, label: String(localized: "Vergrößerung")), to: 2, "Vergrößerung")
        try await settle()
        try shoot("06-zoom-popover", zoomPopover)
        try await press(id: "video.range.apply", in: zoomPopover, "Übernehmen im Zoompopover")
        try await waitFor("the closed popover") { popover() == nil }
        precondition(model.playback.zooms.count == 1 && near(model.playback.zooms[0].scale, 2)
                     && near(model.playback.zooms[0].range.start, 0.1) && near(model.playback.zooms[0].range.end, 0.5), "The zoom was not applied: \(model.playback)")
        precondition(model.position > 0.1 && model.position < 0.5, "Applying a zoom did not show its middle")
        try await waitFor("the zoomed preview") { model.isPreviewReady }
        try await settle()
        try shoot("07-zoom-hinzugefuegt")

        // 6. Save, then Undo and Redo through the header buttons.
        let edited = model.playback
        try await press(id: "video.editor.apply", "Änderungen sichern")
        try await waitFor("the saved edit") { !model.isBusy && !model.hasUnappliedChanges }
        let saved = try await files.document(document.id)
        precondition(saved.playback == edited && saved.schemaVersion == 5, "The saved file lacks the reviewed edit")
        try await settle()
        try shoot("08-gesichert")
        try await press(label: String(localized: "Rückgängig"), "Rückgängig")
        try await waitFor("Undo") { !model.isBusy && model.playback.isIdentity }
        try await settle()
        try shoot("09-rueckgaengig")
        try await press(label: String(localized: "Wiederholen"), "Wiederholen")
        try await waitFor("Redo") { !model.isBusy && model.playback == edited }
        try await settle()
        try shoot("10-wiederholt")

        let finalBytes = try Data(contentsOf: original)
        precondition(finalBytes == originalBytes, "Editing changed the original video")
        let sizes = Set(shots.filter { !$0.0.contains("popover") }.map { "\(Int($0.1.width))×\(Int($0.1.height))" })
        precondition(sizes.count == 1, "The editor changed its size while editing: \(sizes)")
        window.orderOut(nil)
        print("Video editor UI passed: real controls for 8× zoom with visible playhead, inner cut, tempo, volume, zoom section, save, Undo/Redo; stable \(sizes.first!) window, unchanged original. Screens: \(output.path)")
    }
}
