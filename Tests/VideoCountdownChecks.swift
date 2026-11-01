import AppKit
import AVFoundation
import QuartzCore
import SwiftUI
import SnagForgeDomain

/// Exercises the production panel/start task with a clock advanced by the test.
/// No screen stream or microphone input is opened.
@MainActor enum VideoCountdownChecks {
    static func sessions() async throws {
        try await outlines()
        badgeFrames()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Countdown-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Fixture.mp4")
        try await VideoRecordingChecks.movie(at: fixture, includesAudio: true)

        for seconds in [0, 3, 5] {
            let folder = root.appendingPathComponent("Complete-\(seconds)")
            let clock = CountdownTestClock(), source = SyntheticVideoTransport()
            var prepared = 0
            let inherited = NSPanel(contentRect: VideoLifecycleChecks.selection.screenFrame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            inherited.isReleasedWhenClosed = false; inherited.orderFrontRegardless()
            let overlay = CaptureSelectionOverlay(panels: [inherited])
            let session = VideoRecordingSession(selection: VideoLifecycleChecks.selection, includesCursor: false,
                selectionOverlay: overlay,
                delaySeconds: seconds, audio: .init(systemAudio: true, microphone: false), files: VideoRecordingFiles(root: folder), makeEngine: {
                    prepared += 1
                    return VideoRecordingEngine { _, _, audio, url in
                        require(audio.systemAudio && !audio.microphone, "Saved audio options did not reach the engine")
                        try FileManager.default.copyItem(at: fixture, to: url)
                        return .init(transport: source, pixelSize: VideoLifecycleChecks.size)
                    }
                }, waitCountdownSecond: { try await clock.wait() })
            session.onState = { _, recording in
                if [.starting, .countingDown, .recording].contains(session.phase) {
                    require(inherited.isVisible && inherited.alphaValue == 1, "Video startup hid/faded its inherited frame")
                }
                if session.phase == .countingDown { require(!recording, "Countdown reported an active recording") }
            }
            overlay.close()
            require(inherited.isVisible, "Session did not take ownership of the visible selection")
            let run = Task { await session.run(startImmediately: true) }
            let controls = try await controls(for: session)
            require(controls.delay.selectedTag() == seconds && !controls.delay.isEnabled)
            for tick in 0..<seconds {
                try await VideoLifecycleChecks.waitUntil { clock.waits == tick + 1 && clock.pending != nil }
                require(session.phase == .countingDown && prepared == 0 && source.startCalls == 0)
                require(!FileManager.default.fileExists(atPath: folder.path), "Countdown created a working recording")
                require(!controls.primary.isEnabled && !controls.delay.isEnabled && !controls.microphone.isEnabled && !controls.system.isEnabled)
                require(controls.close.isEnabled && controls.close.keyEquivalent == "\u{1b}")
                require(controls.status.stringValue.contains(String(localized: "Video startet in \(seconds - tick) …")))
                let badge = NSApp.windows.first { $0.identifier?.rawValue == "video.countdownBadge" && $0.isVisible }
                require(badge != nil && badge!.ignoresMouseEvents && !badge!.isKeyWindow, "Countdown lost its click-through badge")
                require((badge?.contentView as? NSHostingView<VideoCountdownNumber>)?.rootView.seconds == seconds - tick, "Countdown badge showed another second")
                require(abs(badge!.frame.midX - VideoLifecycleChecks.selection.rect.midX) < 0.5
                    && abs(badge!.frame.midY - VideoLifecycleChecks.selection.rect.midY) < 0.5, "Countdown badge left the source center")
                clock.tick()
            }
            try await VideoLifecycleChecks.waitUntil { session.phase == .recording }
            require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.countdownBadge" && $0.isVisible }, "Countdown badge remained during recording")
            require(prepared == 1 && source.startCalls == 1 && clock.waits == seconds)
            require(inherited.isVisible && inherited.identifier?.rawValue == "video.recordingRegion")
            require(session.hasLibraryChanges)
            require(NSApp.windows.contains { $0.identifier?.rawValue == "video.recordingRegion" && $0.isVisible }, "Recording lost its visible region")
            let toolbar = NSApp.windows.first { $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible }!
            require(!controls.panel.isVisible && toolbar.frame.height == CaptureToolbarSurface.barHeight, "Recording retained the large setup window")
            let stop = (toolbar.contentView as! CaptureToolbarSurface).controls.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "video.recordingStop" }!
            require(stop.isEnabled && stop.title == String(localized: "Stop"))
            require(controls.status.stringValue.contains("00:00"), "Countdown was counted as recording duration")
            stop.performClick(nil)
            try await VideoLifecycleChecks.waitUntil { session.phase == .finished }
            require(session.phase == .finished && source.stopCalls == 1)
            require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.recordingRegion" && $0.isVisible }, "Finished capture retained its frame")
            require(!toolbar.isVisible, "Finished capture retained its recording toolbar")
            await session.closeSafely(); await run.value
            require(!inherited.isVisible, "Completed session retained its inherited selection")
            session.onState = nil
        }

        // Cancel at the first and final second, including an uncooperative clock
        // that resumes after cancellation. Neither path may create a recording.
        for tickToCancel in [1, 3] {
            let folder = root.appendingPathComponent("Cancel-\(tickToCancel)")
            let clock = CountdownTestClock()
            var prepared = 0
            let session = VideoRecordingSession(selection: VideoLifecycleChecks.selection, includesCursor: false,
                delaySeconds: 3, files: VideoRecordingFiles(root: folder), makeEngine: {
                    prepared += 1; return VideoRecordingEngine { _, _, _, _ in throw VideoRecordingError.windowUnavailable }
                }, waitCountdownSecond: { try await clock.wait() })
            let run = Task { await session.run() }
            let controls = try await controls(for: session)
            controls.primary.performClick(nil)
            for tick in 1...tickToCancel {
                try await VideoLifecycleChecks.waitUntil { clock.waits == tick && clock.pending != nil }
                if tick < tickToCancel { clock.tick() }
            }
            if tickToCancel == 1 {
                let toolbar = NSApp.windows.first { $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible }!
                let cancel = (toolbar.contentView as! CaptureToolbarSurface).controls.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "video.recordingStop" }!
                require(cancel.isEnabled && cancel.keyEquivalent == "\u{1b}")
                cancel.performClick(nil)
            }
            else { controls.panel.performClose(nil) }
            try await VideoLifecycleChecks.waitUntil { clock.cancelled }
            clock.tick()
            await run.value
            require(prepared == 0 && session.phase == .ready && !controls.panel.isVisible)
            require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.countdownBadge" && $0.isVisible }, "Cancelled countdown kept its badge")
            require(!session.hasLibraryChanges, "Cancelled countdown changed the library selection")
            require(!FileManager.default.fileExists(atPath: folder.path), "Cancelled countdown left files behind")
        }

        // The session popup overrides the inherited default only for this capture.
        // An optional permission answer precedes the complete countdown.
        let clock = CountdownTestClock()
        var permission: CheckedContinuation<Bool, Never>?
        var permissionReads = 0, prepared = 0
        let access = VideoMicrophoneAccess(status: { permissionReads += 1; return .notDetermined },
            request: { await withCheckedContinuation { permission = $0 } }, hasInput: { true })
        let session = VideoRecordingSession(selection: VideoLifecycleChecks.selection, includesCursor: false,
            delaySeconds: 3, microphoneAccess: access, files: VideoRecordingFiles(root: root.appendingPathComponent("Permission")),
            makeEngine: { prepared += 1; return .init() }, waitCountdownSecond: { try await clock.wait() })
        let run = Task { await session.run() }
        let controls = try await controls(for: session)
        controls.delay.selectItem(withTag: 5); controls.microphone.performClick(nil)
        require(clock.waits == 0 && permissionReads == 0, "Changing options started countdown or permissions")
        controls.primary.performClick(nil)
        try await VideoLifecycleChecks.waitUntil { permission != nil }
        require(clock.waits == 0 && session.phase == .starting && prepared == 0)
        permission?.resume(returning: true)
        try await VideoLifecycleChecks.waitUntil { clock.pending != nil }
        require(controls.status.stringValue.contains(String(localized: "Video startet in \(5) …")), "Permission wait consumed countdown time")
        let closing = Task { await session.closeSafely() }
        try await VideoLifecycleChecks.waitUntil { clock.cancelled }
        clock.tick(); await closing.value; await run.value
        require(prepared == 0)
        require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.countdownBadge" && $0.isVisible }, "Closed session kept its countdown badge")

        print("Native video countdown passed: 0/3/5 seconds after direct start with saved audio, no file/engine before expiry, single start, option locking, duration excludes countdown, centered click-through badge gone before recording, popup override, permission before countdown, first/final-second cancellation and late clock resumption without capture.")
    }

    private static func badgeFrames() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let large = VideoCountdownBadge.frame(centeredIn: CGRect(x: 100, y: 100, width: 800, height: 600), within: screen)
        require(large == CGRect(x: 444, y: 344, width: 112, height: 112), "Large source did not center the full badge")
        let small = VideoCountdownBadge.frame(centeredIn: CGRect(x: 300, y: 300, width: 90, height: 40), within: screen)
        require(small.size == CGSize(width: 64, height: 64) && small.midX == 345 && small.midY == 320, "Small source lost its minimum centered badge")
        let edge = VideoCountdownBadge.frame(centeredIn: CGRect(x: -200, y: 860, width: 300, height: 200), within: screen)
        require(edge.minX == 0 && edge.maxY == 900 && edge.width == 100, "Badge left the display of a partly offscreen source")
    }

    private static func outlines() async throws {
        let screen = NSScreen.screens.first!.frame
        let rect = CGRect(x: screen.minX + 80, y: screen.minY + 80, width: 320, height: 180)
        let selection = ScreenshotSelection(displayID: 0, rect: rect, screenFrame: screen, media: .video)
        let outline = VideoRecordingOutline(selection: selection)
        let keyWindow = NSApp.keyWindow
        outline.show(recording: true)
        func visibleOutline() -> NSWindow { NSApp.windows.first { $0.identifier?.rawValue == "video.recordingRegion" && $0.isVisible }! }
        let panel = visibleOutline()
        require(panel.frame == screen && outline.visibleRect == rect)
        require(panel.ignoresMouseEvents && !panel.isOpaque && !panel.hasShadow && NSApp.keyWindow === keyWindow,
            "Recording frame intercepted input or activated the app")
        let view = panel.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        func pixel(_ point: CGPoint, in bitmap: NSBitmapImageRep, frame: CGRect) -> NSColor {
            bitmap.colorAt(x: Int((point.x - frame.minX) * CGFloat(bitmap.pixelsWide) / frame.width),
                y: Int((frame.maxY - point.y) * CGFloat(bitmap.pixelsHigh) / frame.height))!.usingColorSpace(.deviceRGB)!
        }
        require(pixel(CGPoint(x: rect.midX, y: rect.midY), in: bitmap, frame: screen).alphaComponent < 0.01,
            "Recording frame covered captured content")
        let shade = pixel(CGPoint(x: rect.maxX + 20, y: rect.midY), in: bitmap, frame: screen)
        require(abs(shade.alphaComponent - 0.42) < 0.02 && shade.redComponent < 0.01,
            "Recording lost the selection background shade")
        let edge = pixel(CGPoint(x: rect.minX + 1, y: rect.midY), in: bitmap, frame: screen)
        require(edge.alphaComponent > 0.9 && edge.redComponent > edge.blueComponent, "Recording stroke was not visible and red")
        outline.hide(); require(!panel.isVisible)

        let displayOutline = VideoRecordingOutline(selection: ScreenshotSelection(displayID: 0, rect: screen, screenFrame: screen, media: .video))
        displayOutline.show(recording: false)
        require(visibleOutline().frame == screen && displayOutline.visibleRect == screen, "Full-display frame fell outside the visible display")
        displayOutline.hide()

        var liveFrame: CGRect? = rect
        let moving = VideoRecordingOutline(selection: ScreenshotSelection(displayID: 0, rect: rect, screenFrame: screen, windowID: 42, media: .video),
            windowFrame: { _ in liveFrame })
        moving.show(recording: true)
        let movingPanel = visibleOutline()
        liveFrame = rect.offsetBy(dx: 60, dy: 40).insetBy(dx: -20, dy: -10)
        try await VideoLifecycleChecks.waitUntil { moving.visibleRect == liveFrame }
        liveFrame = nil
        try await VideoLifecycleChecks.waitUntil { !movingPanel.isVisible }
        liveFrame = rect
        try await VideoLifecycleChecks.waitUntil { movingPanel.isVisible && moving.visibleRect == rect }
        moving.hide()

        // A window straddling two displays keeps both portions clear. All other pixels stay shaded.
        let adjacent = screen.offsetBy(dx: screen.width, dy: 0)
        let across = CGRect(x: screen.maxX - 80, y: screen.minY + 80, width: 160, height: 180)
        let multi = VideoRecordingOutline(selection: ScreenshotSelection(displayID: 0, rect: across, screenFrame: screen, windowID: 42, media: .video),
            screens: [screen, adjacent], windowFrame: { _ in across })
        multi.show(recording: true)
        let visible = NSApp.windows.filter { $0.identifier?.rawValue == "video.recordingRegion" && $0.isVisible }
        require(visible.count == 2)
        for display in visible {
            let view = display.contentView!, bitmap = display.contentView!.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let part = across.intersection(display.frame)
            require(pixel(CGPoint(x: part.midX, y: part.midY), in: bitmap, frame: display.frame).alphaComponent < 0.01)
            require(abs(pixel(CGPoint(x: display.frame.midX, y: display.frame.minY + 30), in: bitmap, frame: display.frame).alphaComponent - 0.42) < 0.02)
        }
        multi.hide()
        try toolbar(region: rect, screen: screen, keyWindow: keyWindow)
        print("Video overlay passed: 42% selection shade, clear live source, red border, passthrough/focus, display edges, moving/resizing/hidden windows, multi-display hole, compact REC/Stop toolbar, pulse/reduced motion and cleanup.")
    }

    private static func toolbar(region: CGRect, screen: CGRect, keyWindow: NSWindow?) throws {
        let motion = RecordingToolbarMotionState()
        var stops = 0, cancels = 0
        let toolbar = VideoRecordingToolbar(reduceMotion: { motion.reduced })
        toolbar.onStop = { stops += 1 }; toolbar.onCancel = { cancels += 1 }
        toolbar.update(recording: true, status: "Recording · 01:02", duration: "01:02", dimensions: "320 × 180 px", canCancel: false)
        toolbar.show(region: region, screen: screen)
        let panel = NSApp.windows.first { $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible }!
        let views = (panel.contentView as! CaptureToolbarSurface).controls.subviews
        let dot = views.first { $0.accessibilityIdentifier() == "video.recordingDot" }!
        let stop = views.compactMap { $0 as? NSButton }.first!
        let pulse = dot.layer!.animation(forKey: "recordingPulse") as! CABasicAnimation
        require(pulse.duration >= 0.5 && pulse.autoreverses && pulse.repeatCount == .infinity)
        require(!panel.ignoresMouseEvents && NSApp.keyWindow === keyWindow && panel.frame.height == CaptureToolbarSurface.barHeight)
        let available = NSScreen.screens.first!.visibleFrame
        require(available.contains(panel.frame) && !panel.frame.intersects(region), "Toolbar covered a source despite free space below/above")
        require(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "REC" && !$0.isHidden })
        require(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "01:02" && !$0.isHidden })
        stop.performClick(nil); require(stops == 1 && cancels == 0)
        motion.reduced = true
        toolbar.update(recording: true, status: "Recording", duration: "01:03", dimensions: "320 × 180 px", canCancel: false)
        require(dot.layer?.animation(forKey: "recordingPulse") == nil && !dot.isHidden, "Reduced motion retained blinking or lost the dot")
        toolbar.update(recording: false, status: "Countdown", duration: "", dimensions: "", canCancel: true)
        require(dot.isHidden && stop.keyEquivalent == "\u{1b}" && stop.isEnabled)
        stop.performClick(nil); require(stops == 1 && cancels == 1)
        toolbar.show(region: screen, screen: screen)
        require(available.contains(panel.frame), "Full-display Stop was unreachable")
        toolbar.update(recording: false, status: "Finishing", duration: "", dimensions: "", canCancel: false)
        require(!stop.isEnabled && dot.layer?.animation(forKey: "recordingPulse") == nil)
        toolbar.hide(); require(!panel.isVisible)
    }

    private struct Controls {
        let panel: NSWindow
        let primary: NSButton, close: NSButton, microphone: NSButton, system: NSButton
        let delay: NSPopUpButton
        let status: NSTextField
    }
    private static func controls(for session: VideoRecordingSession) async throws -> Controls {
        try await VideoLifecycleChecks.waitUntil { NSApp.windows.contains { $0.identifier?.rawValue == "video.controls" && $0.delegate === session } }
        let panel = NSApp.windows.first { $0.identifier?.rawValue == "video.controls" && $0.delegate === session }!
        let views = (panel.contentView as! CaptureToolbarSurface).controls.subviews
        func button(_ id: String) -> NSButton { views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == id }! }
        return Controls(panel: panel, primary: button("video.primary"), close: button("video.close"), microphone: button("video.microphone"), system: button("video.systemAudio"),
            delay: views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityIdentifier() == "video.delay" }!,
            status: views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "video.status" }!)
    }
}

@MainActor private final class RecordingToolbarMotionState { var reduced = false }

@MainActor private final class CountdownTestClock {
    var pending: CheckedContinuation<Void, Never>?
    var waits = 0
    var cancelled = false
    func wait() async throws {
        waits += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { pending = $0 }
        } onCancel: { Task { @MainActor in self.cancelled = true } }
        try Task.checkCancellation()
    }
    func tick() { let waiter = pending; pending = nil; waiter?.resume() }
}

private func require(_ value: Bool, _ message: String = "Video countdown check failed", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}
