import Foundation
import AVFoundation
import AppKit

@MainActor enum VideoTimelineChecks {
    static func run(model: VideoEditorModel, original: URL) async throws {
        let de = Locale(identifier: "de_DE"), en = Locale(identifier: "en_US")
        precondition(VideoTimeText.clock(10.782, locale: de) == "0:10,8")
        precondition(VideoTimeText.clock(59.99, locale: en) == "1:00.0")
        precondition(VideoTimeText.clock(3661.25, locale: de) == "1:01:01,3")
        precondition(VideoTimeText.clock(.nan, locale: en) == "0:00.0")
        precondition(VideoTimeText.selection(1.0 / 30) == String(localized: "Auswahl: 1 Videobild"))
        let scale = VideoTimelineScale(duration: 10, width: 200)
        precondition(scale.x(for: 2) == 40 && scale.seconds(at: 100) == 5)
        precondition(scale.seconds(at: -10) == 0 && scale.seconds(at: 300) == 10)
        precondition(scale.x(for: .infinity) == 0 && VideoTimelineScale(duration: 0, width: 0).seconds(at: 50) == 0)
        for zoom in VideoTimelineZoom.allCases {
            let zoomed = VideoTimelineScale(duration: 10, width: zoom.contentWidth(in: 232) - 32)
            precondition(abs(zoomed.seconds(at: zoomed.x(for: 2.345)) - 2.345) < 0.000001)
            precondition(abs(zoomed.seconds(at: zoomed.x(for: 2) + 20) - 2 - 1 / Double(zoom.rawValue)) < 0.000001,
                "Zoom changed pixels without updating the pointer-to-source time scale")
        }
        precondition(VideoTimelineZoom.eightTimes.contentWidth(in: .infinity) == 32)
        try await checkLiveHandles(model: model)

        var preciseValue = 1.876543, fieldEdits = 0
        let coordinator = VideoSecondsField.Coordinator(value: preciseValue) { value in
            preciseValue = value; fieldEdits += 1; return value
        }
        let field = NSTextField()
        let formatter = NumberFormatter(); formatter.locale = de; formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1; formatter.minimumFractionDigits = 1
        field.formatter = formatter; field.doubleValue = preciseValue
        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        coordinator.submit(field)
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        precondition(preciseValue == 1.876543 && fieldEdits == 0, "Return or focus loss rounded an untouched field")
        coordinator.applyInput("1,234567", formatter: formatter)
        coordinator.submit(field)
        precondition(abs(preciseValue - 1.234567) < 0.0000001 && fieldEdits == 1, "Formatting rounded an explicit input")

        model.moveStart(to: 0.234567)
        precondition(abs(model.start - 0.234567) < 0.0000001, "Presentation rounded the underlying trim")
        model.moveStart(to: 100)
        precondition(model.isValid && abs(model.end - model.start - 1.0 / 30) < 0.000001)
        model.moveEnd(to: -100)
        precondition(model.isValid, "Timeline handles crossed")
        let previous = model.draft
        model.moveEnd(to: .nan); model.moveStart(to: .infinity)
        precondition(model.draft == previous)
        model.discardDraft()
        model.moveStart(to: 0.2); model.moveEnd(to: 0.8)
        model.scrub(to: -1); precondition(model.position == model.start)
        model.scrub(to: 100); precondition(model.position == model.end)
        model.stepFrame(-1)
        precondition(abs(model.position - (model.end - 1.0 / 30)) < 0.000001)
        model.togglePlayback(); model.togglePlayback()
        try await Task.sleep(for: .milliseconds(80))
        precondition(!model.isPlaying && model.player.rate == 0, "A completed seek restarted paused playback")
        model.playSelection(); model.moveStart(to: 0.3)
        try await Task.sleep(for: .milliseconds(80))
        precondition(!model.isPlaying && model.player.rate == 0, "Editing resumed stale playback")
        model.moveEnd(to: 0.8)
        model.togglePlayback()
        try await Task.sleep(for: .milliseconds(120))
        precondition(model.position < 0.6, "Play at the last frame did not restart the selection")
        model.pausePlayback()
        model.discardDraft()

        let frames = await VideoTimelineFrames.load(url: original, duration: model.duration)
        precondition(frames.count == 8 && frames.allSatisfy { $0.width <= 160 && $0.height <= 96 })
        precondition(Set(frames.map { $0.dataProvider!.data! as Data }).count >= 6, "Timeline reused a keyframe instead of showing different positions")
        let cancelled = Task { await VideoTimelineFrames.load(url: original, duration: model.duration) }
        cancelled.cancel()
        let cancelledFrames = await cancelled.value
        precondition(cancelledFrames.isEmpty)

        // Use a separate sidecar so the export workflow does not alter revision checks below.
        let files = VideoRecordingFiles(root: original.deletingLastPathComponent().appendingPathComponent("TimelineExport"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try FileManager.default.copyItem(at: original, to: partial)
        let movie = try await files.finalize(partial)
        let document = try await files.list().items.first!.document
        let exportModel = VideoEditorModel(document: document, url: movie, files: files)
        defer { exportModel.stopPreview() }
        exportModel.start = 0.234567; exportModel.end = 0.876543
        let prepared = await exportModel.prepareExport()
        precondition(prepared)
        precondition(!exportModel.hasUnappliedChanges && exportModel.document.revision == 1)
        precondition(abs(exportModel.document.effectiveTrim.start - 0.234567) < 0.0000001)
        let preparedAgain = await exportModel.prepareExport()
        precondition(preparedAgain && exportModel.document.revision == 1, "Unchanged export added a revision")
        exportModel.start = 0.99; exportModel.end = 0.1
        let invalidPrepared = await exportModel.prepareExport()
        precondition(!invalidPrepared && exportModel.document.revision == 1)
        exportModel.discardDraft(); exportModel.hasProAccess = { false }
        let saved = exportModel.draft
        exportModel.moveStart(to: 0); exportModel.moveEnd(to: 1)
        precondition(exportModel.draft == saved, "Timeline bypassed Pro access")
        print("Video timeline passed: localized one-decimal clocks, shared geometry, bounded handles, full internal precision, frame stepping, stale playback cancellation, eight bounded thumbnails/cancellation, save-before-export and Pro protection.")
    }

    private static func checkLiveHandles(model: VideoEditorModel) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); model.hasProAccess = { true }; model.discardDraft() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        window.contentView = root
        model.discardDraft(); model.moveStart(to: 0.2); model.moveEnd(to: 0.8)
        let start = VideoTrimHandleView(model: model, edge: .start)
        let end = VideoTrimHandleView(model: model, edge: .end)
        start.timelineWidth = 400; end.timelineWidth = 400
        root.addSubview(start); root.addSubview(end)
        start.frame = NSRect(x: 80, y: 10, width: 24, height: 64)
        end.frame = NSRect(x: 320, y: 10, width: 24, height: 64)
        func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 42), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.000001 }
        // Assert each sample BEFORE mouse-up. A test of only the final value
        // cannot catch a grip that waits until the gesture ends to update.
        start.mouseDown(with: event(.leftMouseDown, 95))
        precondition(window.firstResponder === start && model.start == 0.2, "Grabbing a handle jumped the boundary or lost focus")
        start.mouseDragged(with: event(.leftMouseDragged, 135))
        precondition(close(model.start, 0.3) && close(model.position, 0.3) && model.end == 0.8, "First held start-handle movement was not live")
        start.frame.origin.x += 40 // SwiftUI repositions the handle during the same drag.
        start.mouseDragged(with: event(.leftMouseDragged, 175))
        precondition(close(model.start, 0.4) && close(model.position, 0.4), "Moving the view corrupted the drag's window coordinates")
        start.mouseDragged(with: event(.leftMouseDragged, 115))
        precondition(close(model.start, 0.25), "Reversing a held drag did not update immediately")
        start.mouseUp(with: event(.leftMouseUp, 115))
        start.mouseDragged(with: event(.leftMouseDragged, 300))
        precondition(close(model.start, 0.25), "Released drag still edited the cut")
        start.mouseDown(with: event(.leftMouseDown, 120)); start.mouseUp(with: event(.leftMouseUp, 120))
        start.mouseDown(with: event(.leftMouseDown, 120))
        start.mouseDragged(with: event(.leftMouseDragged, 140))
        precondition(close(model.start, 0.3), "Clicking and then dragging reused the old anchor")
        start.mouseUp(with: event(.leftMouseUp, 140))

        end.mouseDown(with: event(.leftMouseDown, 330))
        end.mouseDragged(with: event(.leftMouseDragged, 290))
        precondition(close(model.end, 0.7) && close(model.position, 0.7 - 1.0 / 30) && close(model.start, 0.3), "End-handle movement or its last-frame preview was not live")
        // The actual player, rather than just the displayed time, must seek
        // while the mouse is still held. No mouseUp has been delivered yet.
        for _ in 0..<200 {
            if model.player.currentItem?.status == .readyToPlay && abs(model.player.currentTime().seconds - (0.7 - 1.0 / 30)) < 0.001 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(abs(model.player.currentTime().seconds - (0.7 - 1.0 / 30)) < 0.001 && close(model.position, 0.7 - 1.0 / 30), "AVPlayer did not follow the held end handle")
        end.frame.origin.x -= 40
        end.mouseDragged(with: event(.leftMouseDragged, 350))
        precondition(close(model.end, 0.85), "End handle drifted after the view moved")
        end.mouseDragged(with: event(.leftMouseDragged, -100))
        precondition(model.isValid && close(model.end - model.start, 1.0 / 30), "Held handles crossed")
        end.mouseDragged(with: event(.leftMouseDragged, 310))
        precondition(close(model.end, 0.75), "Handle got stuck after reaching a boundary")
        end.mouseUp(with: event(.leftMouseUp, 310))

        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        start.keyDown(with: right)
        precondition(close(model.start, 0.4) && start.accessibilityPerformDecrement() && close(model.start, 0.3))
        precondition(start.accessibilityRole() == .slider && start.accessibilityIdentifier() == "video.editor.handle.start")
        precondition(close((start.accessibilityValue() as! NSNumber).doubleValue, 0.3))
        start.mouseDown(with: event(.leftMouseDown, 120)); start.isEnabled = false
        start.mouseDragged(with: event(.leftMouseDragged, 200)); start.isEnabled = true
        start.mouseDragged(with: event(.leftMouseDragged, 220))
        precondition(close(model.start, 0.3), "Disabled handle retained a pending drag")
        model.hasProAccess = { false }
        end.mouseDown(with: event(.leftMouseDown, 300)); end.mouseDragged(with: event(.leftMouseDragged, 350))
        precondition(close(model.end, 0.75) && !end.accessibilityPerformIncrement(), "Native drag bypassed Pro access")
        model.hasProAccess = { true }
        start.timelineWidth = 3200
        start.mouseDown(with: event(.leftMouseDown, 120)); start.mouseDragged(with: event(.leftMouseDragged, 160))
        precondition(close(model.start, 0.3125), "8× zoom retained the unzoomed drag sensitivity")
        start.frame.origin.x -= 60
        start.mouseDragged(with: event(.leftMouseDragged, 140)); start.mouseUp(with: event(.leftMouseUp, 140))
        precondition(close(model.start, 0.30625), "Scrolled timeline corrupted the held zoomed handle")
        start.keyDown(with: right)
        precondition(close(model.start, 0.40625), "Zoom altered the keyboard's source-time step")
        model.moveStart(to: 0.3)
        start.timelineWidth = 0
        start.mouseDown(with: event(.leftMouseDown, 120)); start.mouseDragged(with: event(.leftMouseDragged, 200))
        precondition(close(model.start, 0.3), "An unavailable timeline scale changed the trim")
        print("Live native trim handles passed: multiple held samples, immediate boundary/preview updates, moving view coordinates, direction reversal, fresh drags, release, bounds, keyboard/accessibility, disabled/cancelled drag and Pro protection.")
    }
}
