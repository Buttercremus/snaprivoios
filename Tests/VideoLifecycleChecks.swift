import AppKit
import ScreenCaptureKit
import SnagForgeDomain

@MainActor
enum VideoLifecycleChecks {
    static let selection = ScreenshotSelection(displayID: 0, rect: CGRect(x: 40, y: 50, width: 320, height: 180),
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    static let size = PixelSize(width: 320, height: 180)!
    static let url = URL(fileURLWithPath: "/tmp/synthetic-video-lifecycle.mp4")
    static func error(_ code: Int) -> NSError {
        NSError(domain: "Snaprivo.SyntheticVideo", code: code,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic video failure \(code)"])
    }
    static func engine(_ transport: SyntheticVideoTransport, timeout: Duration = .seconds(1)) -> VideoRecordingEngine {
        VideoRecordingEngine(timeout: timeout) { _, _, _, _ in .init(transport: transport, pixelSize: size) }
    }
    static func start(_ engine: VideoRecordingEngine) async throws {
        let result = try await engine.start(selection: selection, includesCursor: false, audio: .init(), url: url)
        require(result == size)
    }
    static func expectError(_ expected: NSError, _ operation: () async throws -> Void) async {
        do { try await operation(); preconditionFailure("Failure was reported as success") }
        catch { require((error as NSError).domain == expected.domain && (error as NSError).code == expected.code, "First failure was replaced") }
    }
    static func expectRecordingError(_ expected: VideoRecordingError, _ operation: () async throws -> Void) async {
        await expectError(expected as NSError, operation)
    }
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Synthetic lifecycle did not reach its expected state")
    }

    static func engines() async throws {
        // Both start acknowledgments are necessary; finish alone is insufficient
        // until Stop returns. Repeated stop callers share one platform operation.
        let transport = SyntheticVideoTransport()
        transport.startAction = { source, _ in source.onEvent?(.started) }
        transport.stopAction = { _, _ in }
        let recording = engine(transport)
        await expectRecordingError(.notStarted) { try await recording.stop() }
        let state = SyntheticCompletion()
        let starting = Task { try await start(recording); state.started = true }
        try await waitUntil { transport.startCalls == 1 }
        require(!state.started)
        transport.startCompletion?(.success(()))
        try await starting.value
        let lateEvent = transport.onEvent
        let firstStop = Task { try await recording.stop(); state.stops += 1 }
        let secondStop = Task { try await recording.stop(); state.stops += 1 }
        try await waitUntil { transport.stopCalls == 1 }
        lateEvent?(.finished)
        require(state.stops == 0, "File finish bypassed the stream Stop result")
        transport.stopCompletion?(.success(()))
        try await firstStop.value; try await secondStop.value
        require(state.stops == 2 && recording.canDiscardPartial)
        lateEvent?(.streamFailed(error(99))); lateEvent?(.started); lateEvent?(.finished)
        try await recording.stop()
        await expectRecordingError(.alreadyStarted) { try await start(recording) }

        let preparationError = VideoRecordingEngine { _, _, _, _ in throw error(10) }
        await expectError(error(10)) { try await start(preparationError) }
        await expectError(error(10)) { try await preparationError.stop() }
        require(preparationError.canDiscardPartial)

        for event in [VideoRecordingEvent.recordingFailed(error(11)), .streamFailed(error(11))] {
            let source = SyntheticVideoTransport()
            source.startAction = { source, _ in source.onEvent?(event) }
            let recording = engine(source)
            var notifications = 0
            recording.onFailure = { _ in notifications += 1 }
            await expectError(error(11)) { try await start(recording) }
            await expectError(error(11)) { try await recording.stop() }
            require(source.stopCalls == 1 && source.detachCalls == 1 && notifications == 0 && recording.canDiscardPartial)
        }
        let refused = SyntheticVideoTransport()
        refused.startAction = { _, completion in completion(.failure(error(12))) }
        refused.stopAction = { _, completion in completion(.failure(error(13))) }
        let refusedEngine = engine(refused)
        await expectError(error(12)) { try await start(refusedEngine) }
        await expectError(error(12)) { try await refusedEngine.stop() }
        require(refused.stopCalls == 1 && refused.detachCalls == 1 && refusedEngine.canDiscardPartial)

        let immediatelyFailed = SyntheticVideoTransport()
        immediatelyFailed.startAction = { source, completion in
            source.onEvent?(.started); completion(.success(()))
            source.onEvent?(.recordingFailed(error(14)))
        }
        let immediateEngine = engine(immediatelyFailed)
        await expectError(error(14)) { try await start(immediateEngine) }
        await expectError(error(14)) { try await immediateEngine.stop() }

        for event in [VideoRecordingEvent.recordingFailed(error(20)), .streamFailed(error(20)), .finished] {
            let source = SyntheticVideoTransport(), recording = engine(source)
            var notifications = 0
            recording.onFailure = { _ in notifications += 1 }
            try await start(recording)
            let send = source.onEvent
            send?(event); send?(.recordingFailed(error(21))); send?(.streamFailed(error(22)))
            if case .finished = event {
                await expectError(error(21)) { try await recording.stop() }
            } else { await expectError(error(20)) { try await recording.stop() } }
            if case .finished = event { try await Task.sleep(for: .milliseconds(60)) }
            require(notifications == 1 && source.stopCalls == 1 && source.detachCalls == 1)
        }

        let ended = SyntheticVideoTransport(), endedEngine = engine(ended)
        try await start(endedEngine); ended.onEvent?(.finished)
        await expectRecordingError(.interrupted) { try await endedEngine.stop() }
        let storage = NSError(domain: SCStreamErrorDomain, code: -3822)
        let storageSource = SyntheticVideoTransport(), storageEngine = engine(storageSource)
        var storageNotifications = 0
        storageEngine.onFailure = { error in require((error as NSError).code == -3822); storageNotifications += 1 }
        try await start(storageEngine); storageSource.onEvent?(.finished)
        try await Task.sleep(for: .milliseconds(15))
        storageSource.onEvent?(.streamFailed(storage)); storageSource.onEvent?(.recordingFailed(error(88)))
        await expectError(storage) { try await storageEngine.stop() }
        require(storageNotifications == 1 && storageSource.stopCalls == 1 && storageEngine.canDiscardPartial)

        for finishFirst in [false, true] {
            let source = SyntheticVideoTransport()
            source.detachError = error(32)
            source.stopAction = { source, completion in
                if finishFirst { source.onEvent?(.finished) }
                completion(.failure(error(30)))
                source.onEvent?(.recordingFailed(error(31)))
            }
            let recording = engine(source)
            try await start(recording)
            await expectError(error(30)) { try await recording.stop() }
            require(recording.canDiscardPartial && source.detachCalls == 1)
        }
        let earlyFinish = SyntheticVideoTransport()
        earlyFinish.startAction = { source, completion in source.onEvent?(.finished); completion(.success(())) }
        let earlyEngine = engine(earlyFinish)
        await expectRecordingError(.interrupted) { try await start(earlyEngine) }
        await expectRecordingError(.interrupted) { try await earlyEngine.stop() }

        // Deadline covers discovery/preparation, start callback, recording-start
        // delegate, stop callback, and file-finish delegate independently.
        var pending: CheckedContinuation<PreparedVideoRecording, Never>?
        let delayed = SyntheticVideoTransport()
        let delayedEngine = VideoRecordingEngine(timeout: .milliseconds(40)) { _, _, _, _ in
            await withCheckedContinuation { pending = $0 }
        }
        await expectRecordingError(.timeout) { try await start(delayedEngine) }
        await expectRecordingError(.timeout) { try await delayedEngine.stop() }
        require(delayedEngine.canDiscardPartial && pending != nil)
        pending?.resume(returning: .init(transport: delayed, pixelSize: size))
        try await waitUntil { delayed.detachCalls == 1 }
        require(delayed.startCalls == 0, "Late preparation started a timed-out capture")

        for missingStartCallback in [false, true] {
            let source = SyntheticVideoTransport()
            source.startAction = { source, completion in
                if missingStartCallback { source.onEvent?(.started) }
                else { completion(.success(())) }
            }
            let recording = engine(source, timeout: .milliseconds(40))
            await expectRecordingError(.timeout) { try await start(recording) }
            await expectRecordingError(.timeout) { try await recording.stop() }
            require(source.stopCalls == 1 && source.detachCalls == 1 && recording.canDiscardPartial)
        }
        for missingFinish in [false, true] {
            let source = SyntheticVideoTransport()
            source.stopAction = { source, completion in
                if missingFinish { completion(.success(())) }
                else { source.onEvent?(.finished) }
            }
            let recording = engine(source, timeout: .milliseconds(40))
            try await start(recording)
            let late = source.onEvent
            await expectRecordingError(.timeout) { try await recording.stop() }
            require(recording.canDiscardPartial == !missingFinish && source.detachCalls == 1)
            late?(.finished); source.stopCompletion?(.success(()))
            await expectRecordingError(.timeout) { try await recording.stop() }
        }
        let cancelled = SyntheticVideoTransport()
        cancelled.startAction = { _, _ in }
        let cancelledEngine = engine(cancelled)
        let cancelledStart = Task { try await start(cancelledEngine) }
        try await waitUntil { cancelled.startCalls == 1 }
        cancelledStart.cancel()
        do { try await cancelledStart.value; preconditionFailure("Cancelled start succeeded") }
        catch is CancellationError { }
        do { try await cancelledEngine.stop(); preconditionFailure("Cancellation was lost") }
        catch is CancellationError { }
        require(cancelled.stopCalls == 1 && cancelled.detachCalls == 1 && cancelledEngine.canDiscardPartial)
        print("Video engine lifecycle passed: preparation/start/delegate errors, dual acknowledgments, shared Stop, first-error preservation, duplicate/late callbacks, independent deadlines, cancellation and safe partial-file disposition.")
    }

    static func sessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Video-Lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Synthetic.mp4")
        try await VideoRecordingChecks.movie(at: fixture)
        let permissionError = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let diskFull = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        for scenario in ["prepare", "source", "start", "startThenFail", "stop", "recording", "permission", "diskFull", "invalid", "timeout", "success", "doubleStop", "quit", "quitTimeout", "cancelStartTimeout"] {
            let folder = root.appendingPathComponent(scenario), files = VideoRecordingFiles(root: folder)
            if scenario == "prepare" { try Data("synthetic blocked directory".utf8).write(to: folder) }
            let previous = folder.appendingPathComponent("Previous.mp4")
            if scenario == "recording" {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: fixture, to: previous)
            }
            let source = SyntheticVideoTransport()
            if scenario == "start" { source.startAction = { _, completion in completion(.failure(error(40))) } }
            if scenario == "startThenFail" {
                source.startAction = { source, completion in
                    source.onEvent?(.started); completion(.success(())); source.onEvent?(.streamFailed(error(45)))
                }
            }
            if scenario == "stop" { source.stopAction = { source, completion in source.onEvent?(.finished); completion(.failure(error(41))) } }
            if ["timeout", "quitTimeout", "cancelStartTimeout"].contains(scenario) {
                source.stopAction = { _, completion in completion(.success(())) }
            }
            if scenario == "cancelStartTimeout" { source.startAction = { _, _ in } }
            let recording = VideoRecordingEngine(timeout: .milliseconds(80)) { _, _, _, url in
                if scenario == "source" { throw error(44) }
                if scenario == "invalid" { try Data("synthetic invalid movie".utf8).write(to: url) }
                else { try FileManager.default.copyItem(at: fixture, to: url) }
                return .init(transport: source, pixelSize: size)
            }
            let session = VideoRecordingSession(selection: selection, includesCursor: false, files: files, makeEngine: { recording })
            var reported: [NSError] = []
            var editorRecordings: [URL] = []
            session.onFinished = { editorRecordings.append($0) }
            session.onPermissionFailure = { reported.append($0 as NSError) }
            let run = Task { await session.run() }
            try await waitUntil { NSApp.windows.contains { $0.isVisible && $0.title == String(localized: "Videoaufnahme") } }
            let panel = NSApp.windows.first { $0.isVisible && $0.title == String(localized: "Videoaufnahme") }!
            let view = (panel.contentView as! CaptureToolbarSurface).controls
            let buttons = view.subviews.compactMap { $0 as? NSButton }
            let primary = buttons.first { $0.accessibilityIdentifier() == "video.primary" }!
            let preview = buttons.first { $0.accessibilityIdentifier() == "video.preview" }!
            let close = buttons.first { $0.accessibilityIdentifier() == "video.close" }!
            primary.performClick(nil)
            if scenario == "prepare" {
                try await waitUntil { session.phase == .failed }
                require(source.startCalls == 0 && source.stopCalls == 0 && reported.count == 1)
                require(!primary.isEnabled && preview.isHidden && close.isEnabled)
                require(try Data(contentsOf: folder) == Data("synthetic blocked directory".utf8))
                await session.closeSafely(); await run.value
                continue
            }
            if scenario == "cancelStartTimeout" { try await waitUntil { source.startCalls == 1 } }
            else if !["start", "startThenFail", "source"].contains(scenario) { try await waitUntil { session.phase == .recording } }
            let late = source.onEvent
            switch scenario {
            case "recording": late?(.recordingFailed(error(42))); late?(.streamFailed(error(43)))
            case "permission": late?(.streamFailed(permissionError))
            case "diskFull": late?(.recordingFailed(diskFull))
            case "quit", "quitTimeout", "cancelStartTimeout": await session.closeSafely()
            case "doubleStop":
                let first = Task { await session.stop() }, second = Task { await session.stop() }
                await first.value; await second.value
            case "start", "startThenFail", "source": break
            default: await session.stop()
            }
            let successful = ["success", "doubleStop", "quit"].contains(scenario)
            let cancelled = scenario == "cancelStartTimeout"
            try await waitUntil { session.phase == (cancelled ? .ready : successful ? .finished : .failed) }
            let completed = try await files.completed()
            require(completed.count == (successful || scenario == "recording" ? 1 : 0), "Failed recording was published")
            require(source.stopCalls == (scenario == "source" ? 0 : 1) && reported.count == (successful || cancelled ? 0 : 1), "Duplicate stop or error reporting")
            require(preview.isHidden == !successful && primary.isEnabled == (successful || cancelled) && close.isEnabled)
            require(editorRecordings.count == (["success", "doubleStop"].contains(scenario) ? 1 : 0), "Editor opened for failed/closing capture, or finalization routed twice")
            if let routed = editorRecordings.first {
                require(completed == [routed] && !panel.isVisible, "Editor handoff preceded durable finalization or left capture controls open")
            }
            require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.recordingRegion" && $0.isVisible }, "Terminal recording retained its outline")
            require(!NSApp.windows.contains { $0.identifier?.rawValue == "video.recordingToolbar" && $0.isVisible }, "Terminal recording retained its toolbar")
            if scenario == "permission" { require(reported.first?.domain == permissionError.domain && reported.first?.code == permissionError.code) }
            if scenario == "diskFull" { require(reported.first?.domain == NSPOSIXErrorDomain && reported.first?.code == Int(ENOSPC)) }
            let working = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent != ".library" }
            let keptPartial = ["timeout", "quitTimeout", "cancelStartTimeout"].contains(scenario)
            require(working.count == ((successful || keptPartial || scenario == "recording") ? 1 : 0), "Working file removed before confirmed finish or not cleaned up")
            if keptPartial { require(working.allSatisfy { $0.lastPathComponent.hasPrefix(".") }, "Unconfirmed output became visible") }
            if scenario == "recording" {
                require(try Data(contentsOf: previous) == Data(contentsOf: fixture), "Failure cleanup removed or changed an older video")
                let status = view.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "video.status" }!
                require(reported.first?.code == 42 && status.stringValue.contains("Synthetic video failure 42"))
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let result = root.appendingPathComponent("VideoFailureControls.png")
                try bitmap.representation(using: .png, properties: [:])!.write(to: result)
            }
            late?(.recordingFailed(error(90))); late?(.finished)
            await session.closeSafely(); await run.value
            require(reported.count == (successful || cancelled ? 0 : 1), "Late event changed terminal UI state")
        }
        print("Native video failure sessions passed: start/stop/writer/permission/disk-full/invalid-file errors, one visible failure, disabled exports, confirmed cleanup, hidden timeout partial, successful finalization and quit.")
    }
}

@MainActor
final class SyntheticVideoTransport: VideoRecordingTransport {
    typealias Completion = @MainActor (Result<Void, any Error>) -> Void
    var onEvent: (@MainActor (VideoRecordingEvent) -> Void)?
    var startAction: (@MainActor (SyntheticVideoTransport, Completion) -> Void)?
    var stopAction: (@MainActor (SyntheticVideoTransport, Completion) -> Void)?
    var startCompletion: Completion?
    var stopCompletion: Completion?
    var detachError: (any Error)?
    var startCalls = 0, stopCalls = 0, detachCalls = 0
    func start(completion: @escaping Completion) {
        startCalls += 1; startCompletion = completion
        if let startAction { startAction(self, completion) }
        else { onEvent?(.started); completion(.success(())) }
    }
    func stop(completion: @escaping Completion) {
        stopCalls += 1; stopCompletion = completion
        if let stopAction { stopAction(self, completion) }
        else { onEvent?(.finished); completion(.success(())) }
    }
    func detachOutput() throws {
        detachCalls += 1
        if let detachError { throw detachError }
    }
}

@MainActor private final class SyntheticCompletion {
    var started = false
    var stops = 0
}

private func require(_ value: Bool, _ message: String = "Video lifecycle check failed", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}
