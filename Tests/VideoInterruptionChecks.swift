import AppKit
import ScreenCaptureKit
import SnagForgeDomain

/// Only local NotificationCenters and silent file fixtures; no system changes.
@MainActor enum VideoInterruptionChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoInterruption-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Silent.mp4"); try await VideoRecordingChecks.movie(at: fixture)
        for cause in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSApplication.didChangeScreenParametersNotification] {
            for stage in ["ready", "countdown", "starting", "recording", "storage", "stopFailure", "stopTimeout", "closeRace"] {
                let center = NotificationCenter(), source = SyntheticVideoTransport()
                let files = VideoRecordingFiles(root: root.appendingPathComponent("\(cause.rawValue)-\(stage)"))
                let clock = InterruptionClock()
                if stage == "starting" { source.startAction = { _, _ in } }
                if stage == "stopFailure" { source.stopAction = { source, completion in source.onEvent?(.finished); completion(.failure(VideoLifecycleChecks.error(71))) } }
                if stage == "stopTimeout" { source.stopAction = { _, completion in completion(.success(())) } }
                var preparations = 0, errors: [String] = []
                let display = InterruptionDisplayState()
                let session = VideoRecordingSession(selection: VideoLifecycleChecks.selection, includesCursor: false,
                    delaySeconds: stage == "countdown" ? 3 : 0, files: files, makeEngine: {
                        preparations += 1
                        return VideoRecordingEngine(timeout: .milliseconds(100)) { _, _, audio, url in
                            require(!audio.requiresAudio)
                            try FileManager.default.copyItem(at: fixture, to: url)
                            return .init(transport: source, pixelSize: VideoLifecycleChecks.size)
                        }
                    }, waitCountdownSecond: { await clock.wait() }, workspaceNotifications: center, displayNotifications: center,
                    displayState: { [.init(id: 1, frame: CGRect(x: 0, y: 0, width: 1920 + display.version, height: 1080), scale: 2)] })
                session.onPermissionFailure = { errors.append($0.localizedDescription) }
                let run = Task { await session.run() }
                try await VideoLifecycleChecks.waitUntil { NSApp.windows.contains { $0.isVisible && $0.title == String(localized: "Videoaufnahme") } }
                let panel = NSApp.windows.first { $0.isVisible && $0.title == String(localized: "Videoaufnahme") }!
                let views = panel.contentView!.subviews
                let primary = views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "video.primary" }!
                let status = views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "video.status" }!
                if stage != "ready" { primary.performClick(nil) }
                if stage == "countdown" { try await VideoLifecycleChecks.waitUntil { clock.pending != nil } }
                else if stage == "starting" { try await VideoLifecycleChecks.waitUntil { source.startCalls == 1 } }
                else if stage != "ready" { try await VideoLifecycleChecks.waitUntil { session.phase == .recording } }
                let before = session.phase
                center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await Task.sleep(for: .milliseconds(10))
                let visibleControls = stage == "ready" ? panel.isVisible : NSApp.windows.contains {
                    $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible
                }
                require(session.phase == before && visibleControls, "Unchanged display configuration interrupted the session")
                if stage == "storage" {
                    source.onEvent?(.finished)
                    try await Task.sleep(for: .milliseconds(15))
                    source.onEvent?(.streamFailed(NSError(domain: SCStreamErrorDomain, code: -3822)))
                    try await VideoLifecycleChecks.waitUntil { session.phase == .failed }
                    if #available(macOS 27, *) { require(status.stringValue.contains("Speicherplatz")) }
                    require(try await files.completed().isEmpty)
                    require(errors.count == 1)
                    await session.closeSafely(); await run.value
                    continue
                }
                display.version = 1
                center.post(name: cause, object: nil); center.post(name: cause, object: nil)
                if stage == "countdown" { clock.resume() }
                if stage == "closeRace" { await session.closeSafely() }
                if ["ready", "countdown", "starting"].contains(stage) {
                    await run.value
                    require(!panel.isVisible && session.phase == .ready)
                    require(preparations == (stage == "starting" ? 1 : 0))
                    require(try await files.completed().isEmpty, "System change published an unstarted recording")
                } else if ["stopFailure", "stopTimeout"].contains(stage) {
                    try await VideoLifecycleChecks.waitUntil { session.phase == .failed }
                    require(errors.count == 1 && !status.stringValue.contains("lokale MP4 bleibt erhalten"), "System notice hid a recording failure")
                    require(try await files.completed().isEmpty)
                    let listing = try await files.list()
                    require(listing.items.count == 1 && listing.items[0].document.state == .failed)
                    await session.closeSafely(); await run.value
                } else {
                    try await VideoLifecycleChecks.waitUntil { session.phase == .finished }
                    require(errors.isEmpty && source.stopCalls == 1)
                    let completed = try await files.completed()
                    require(completed.count == 1)
                    require(try Data(contentsOf: completed[0]) == Data(contentsOf: fixture))
                    if stage != "closeRace" {
                        try await VideoLifecycleChecks.waitUntil { status.stringValue.contains("lokale MP4 bleibt erhalten") }
                        require(primary.isEnabled)
                    }
                    await session.closeSafely(); await run.value
                }
                let stops = source.stopCalls
                center.post(name: cause, object: nil)
                try await Task.sleep(for: .milliseconds(10))
                require(source.stopCalls == stops && !panel.isVisible, "Closed session retained a live system observer")
                require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible }, "Closed session retained its toolbar")
            }
        }
        print("Silent interruption checks passed: sleep/display-sleep/display-configuration notifications, ready/countdown/start cancellation, no late start, one finalized silent original, repeated notifications, close race, first failure/timeout preserved and observer removal.")
    }
}
@MainActor private final class InterruptionClock {
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { pending = $0 } }
    func resume() { pending?.resume(); pending = nil }
}
@MainActor private final class InterruptionDisplayState { var version = 0 }

@main struct VideoValidationRunner {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await VideoLifecycleChecks.engines()
                try await VideoLifecycleChecks.sessions()
                try await VideoInterruptionChecks.run()
            } catch { preconditionFailure("Silent video validation failed: \(error)") }
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
    }
}
private func require(_ value: Bool, _ message: String = "Video interruption check failed", file: StaticString = #fileID, line: UInt = #line) { precondition(value, message, file: file, line: line) }
