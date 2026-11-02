import AppKit
import AVFoundation
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import SnagForgeDomain

struct VideoAudioOptions: Equatable, Sendable {
    var systemAudio = false
    var microphone = false
    var requiresAudio: Bool { systemAudio || microphone }

    var summary: String {
        switch (systemAudio, microphone) {
        case (false, false): String(localized: "ohne Ton")
        case (true, false): String(localized: "Systemton · Mikrofon aus")
        case (false, true): String(localized: "Mikrofon · Systemton aus")
        case (true, true): String(localized: "Systemton und Mikrofon")
        }
    }
}

enum VideoMicrophoneError: LocalizedError {
    case denied, restricted, unavailable
    var errorDescription: String? {
        switch self {
        case .denied: String(localized: "Mikrofonzugriff fehlt. Erlaube Snaprivo unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon oder schalte das Mikrofon aus.")
        case .restricted: String(localized: "Der Mikrofonzugriff ist auf diesem Mac eingeschränkt. Schalte das Mikrofon aus, um ohne Mikrofon aufzunehmen.")
        case .unavailable: String(localized: "Kein Mikrofon verfügbar. Verbinde ein Mikrofon oder schalte die Mikrofonaufnahme aus.")
        }
    }
}

/// Checking a checkbox never requests permission. Called only by explicit Start.
@MainActor
struct VideoMicrophoneAccess {
    var status: @MainActor () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) }
    var request: @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    var hasInput: @MainActor () -> Bool = { AVCaptureDevice.default(for: .audio) != nil }

    func authorize(ifNeeded needed: Bool) async throws {
        try Task.checkCancellation()
        guard needed else { return }
        switch status() {
        case .authorized: break
        case .notDetermined:
            let granted = await request()
            try Task.checkCancellation()
            guard granted else { throw VideoMicrophoneError.denied }
        case .denied: throw VideoMicrophoneError.denied
        case .restricted: throw VideoMicrophoneError.restricted
        @unknown default: throw VideoMicrophoneError.denied
        }
        guard hasInput() else { throw VideoMicrophoneError.unavailable }
    }
}

enum VideoRecordingEvent {
    case started, finished
    case recordingFailed(any Error), streamFailed(any Error)
    case audioLevel(VideoAudioSource, AudioSignalLevel)
}

/// Only the public SCK boundary is replaced by synthetic transports in tests.
@MainActor
protocol VideoRecordingTransport: AnyObject {
    var onEvent: (@MainActor (VideoRecordingEvent) -> Void)? { get set }
    func start(completion: @escaping @MainActor (Result<Void, any Error>) -> Void)
    func stop(completion: @escaping @MainActor (Result<Void, any Error>) -> Void)
    func detachOutput() throws
}

@MainActor
struct PreparedVideoRecording {
    let transport: any VideoRecordingTransport
    let pixelSize: PixelSize
}

/// A one-shot recording. Callback operations are bounded even when the platform
/// never acknowledges start/stop. Late callbacks cannot revive a terminal result.
@MainActor
final class VideoRecordingEngine {
    typealias Prepare = @MainActor (ScreenshotSelection, Bool, VideoAudioOptions, URL) async throws -> PreparedVideoRecording
    typealias PrepareWithClicks = @MainActor (ScreenshotSelection, Bool, VideoAudioOptions, URL, Bool) async throws -> PreparedVideoRecording
    // SCK imports backgroundColor as unowned(unsafe), so keep the color alive.
    private static let windowBackgroundColor = CGColor(gray: 0, alpha: 1)
    private enum Phase { case idle, starting, recording, stopping, terminal }
    private var phase: Phase = .idle
    private let prepare: Prepare
    private let prepareWithClicks: PrepareWithClicks?
    private let timeout: Duration
    private var transport: (any VideoRecordingTransport)?
    private var preparation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var unexpectedFinishTask: Task<Void, Never>?
    private var resolvingUnexpectedFinish = false
    private var notifyUnexpectedFinish = false
    private var failure: (any Error)?
    private var size: PixelSize?
    private var streamStarted = false
    private var outputStarted = false
    private var outputFinished = false
    private var stopReturned = false
    private var detached = false
    private var startWaiter: CheckedContinuation<PixelSize, any Error>?
    private var stopWaiters: [CheckedContinuation<Void, any Error>] = []
    private(set) var canDiscardPartial = true
    var onFailure: (@MainActor (any Error) -> Void)?
    var onAudioLevel: (@MainActor (VideoAudioSource, AudioSignalLevel) -> Void)?

    init(timeout: Duration = .seconds(15), prepare: Prepare? = nil) {
        self.timeout = timeout
        if let prepare { self.prepare = prepare; prepareWithClicks = nil }
        else {
            self.prepare = ScreenCaptureVideoTransport.prepare
            self.prepareWithClicks = ScreenCaptureVideoTransport.prepareWithClicks
        }
    }

    static func configuration(geometry: VideoGeometry, includesCursor: Bool, audio: VideoAudioOptions, windowCapture: Bool = false,
                              showsMouseClicks: Bool = false) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        // Leave sourceRect unset for independent windows so resizing keeps the entire window.
        if !windowCapture { config.sourceRect = geometry.sourceRect }
        config.scalesToFit = windowCapture
        config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        if windowCapture { config.backgroundColor = windowBackgroundColor }
        config.captureDynamicRange = .SDR
        config.width = geometry.pixelSize.width; config.height = geometry.pixelSize.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        // Three surfaces stall the tested H.264 recording pipeline after four
        // frames. Eight is Apple's supported upper bound and gives the encoder
        // sufficient headroom; real A/V tests cover sustained frame delivery.
        config.queueDepth = 8; config.showsCursor = includesCursor
        // ScreenCaptureKit's click indicator requires BGRA pixel buffers. Keep
        // the default off and let the recording preference opt in explicitly.
        config.showMouseClicks = showsMouseClicks
        if showsMouseClicks { config.pixelFormat = kCVPixelFormatType_32BGRA }
        config.capturesAudio = audio.systemAudio
        config.sampleRate = 48_000; config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = audio.microphone
        config.captureResolution = .best
        config.ignoreShadowsDisplay = true
        return config
    }

    func start(selection: ScreenshotSelection, includesCursor: Bool, audio: VideoAudioOptions, url: URL,
               showsMouseClicks: Bool = false) async throws -> PixelSize {
        guard phase == .idle else { throw VideoRecordingError.alreadyStarted }
        try Task.checkCancellation()
        phase = .starting
        let result: PixelSize = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                armDeadline()
                let prepareWithClicks = self.prepareWithClicks
                preparation = Task { [weak self, prepare, prepareWithClicks, showsMouseClicks] in
                    do {
                        let prepared: PreparedVideoRecording
                        if let prepareWithClicks {
                            prepared = try await prepareWithClicks(selection, includesCursor, audio, url, showsMouseClicks)
                        } else {
                            prepared = try await prepare(selection, includesCursor, audio, url)
                        }
                        guard let self, phase == .starting, !Task.isCancelled else {
                            // Preparation may finish after cancellation or its deadline.
                            // No stream was started; detach the unused output only.
                            try? prepared.transport.detachOutput()
                            return
                        }
                        transport = prepared.transport; size = prepared.pixelSize
                        canDiscardPartial = false
                        prepared.transport.onEvent = { [weak self] event in self?.receive(event) }
                        prepared.transport.start { [weak self] result in
                            guard let self, phase == .starting else { return }
                            switch result {
                            case .success: streamStarted = true; completeStartIfReady()
                            case .failure(let error):
                                if !outputStarted { outputFinished = true }
                                fail(error)
                            }
                        }
                    } catch { self?.fail(error) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(CancellationError()) }
        }
        // A delegate failure may arrive after the start waiter was resumed but
        // before its caller gets actor time. Do not return a stale start success.
        if let failure { throw failure }
        return result
    }

    func stop() async throws {
        guard phase != .idle else { throw VideoRecordingError.notStarted }
        if phase == .terminal {
            if let failure { throw failure }
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            stopWaiters.append(continuation)
            if phase == .starting { fail(CancellationError()) }
            else { beginStop() }
        }
    }

    private func completeStartIfReady() {
        guard phase == .starting, streamStarted, outputStarted, let size else { return }
        deadline?.cancel(); deadline = nil
        phase = .recording
        startWaiter?.resume(returning: size); startWaiter = nil
    }

    private func receive(_ event: VideoRecordingEvent) {
        guard phase != .terminal else { return }
        switch event {
        case .started:
            guard phase == .starting else { return }
            outputStarted = true; completeStartIfReady()
        case .finished:
            outputFinished = true
            if phase == .starting || phase == .recording { unexpectedFinish() }
            else { completeStopIfReady() }
        case .recordingFailed(let error):
            outputFinished = true; fail(error)
        case .streamFailed(let error):
            fail(error)
        case .audioLevel(let source, let level):
            if phase == .recording { onAudioLevel?(source, level) }
        }
    }

    private func unexpectedFinish() {
        // macOS can report file finish just before the concrete stream error
        // (observed for insufficient storage). Keep publication blocked while
        // giving that error at most 50 ms to arrive; a generic finish is fallback.
        notifyUnexpectedFinish = phase == .recording
        resolvingUnexpectedFinish = true
        unexpectedFinishTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: min(timeout, .milliseconds(100)) / 2) } catch { return }
            guard let self, phase != .terminal else { return }
            unexpectedFinishTask = nil; resolveUnexpectedFinish()
            completeStopIfReady()
        }
        beginStop()
    }
    private func resolveUnexpectedFinish() {
        guard resolvingUnexpectedFinish else { return }
        if failure == nil { failure = VideoRecordingError.interrupted }
        resolvingUnexpectedFinish = false
        startWaiter?.resume(throwing: failure!); startWaiter = nil
        if notifyUnexpectedFinish { notifyUnexpectedFinish = false; onFailure?(failure!) }
    }

    private func fail(_ error: any Error) {
        guard phase != .terminal else { return }
        let wasRecording = phase == .recording
        if failure == nil { failure = error }
        startWaiter?.resume(throwing: failure!); startWaiter = nil
        if phase != .stopping { beginStop() }
        else { detachOutput(); completeStopIfReady() }
        // Start/stop callers already receive their errors. Only an interruption
        // of an active recording needs an unsolicited notification to the UI.
        if wasRecording { onFailure?(failure!) }
    }

    private func beginStop() {
        guard phase != .stopping && phase != .terminal else { return }
        phase = .stopping
        deadline?.cancel(); preparation?.cancel()
        guard let transport else { finishStop(); return }
        armDeadline()
        if failure != nil { detachOutput() }
        transport.stop { [weak self] result in
            guard let self, phase == .stopping, !stopReturned else { return }
            stopReturned = true
            if case .failure(let error) = result {
                if failure == nil { failure = error }
                detachOutput()
            }
            completeStopIfReady()
        }
    }

    private func detachOutput() {
        guard !detached, let transport else { return }
        detached = true
        do { try transport.detachOutput() }
        catch { if failure == nil { failure = error } }
    }

    private func completeStopIfReady() {
        guard phase == .stopping, stopReturned, outputFinished, !resolvingUnexpectedFinish else { return }
        finishStop()
    }

    private func finishStop() {
        resolveUnexpectedFinish()
        canDiscardPartial = transport == nil || outputFinished
        phase = .terminal
        unexpectedFinishTask?.cancel(); unexpectedFinishTask = nil; resolvingUnexpectedFinish = false
        deadline?.cancel(); deadline = nil
        preparation?.cancel(); preparation = nil
        transport?.onEvent = nil; transport = nil
        let waiters = stopWaiters; stopWaiters.removeAll()
        for waiter in waiters {
            if let failure { waiter.resume(throwing: failure) }
            else { waiter.resume() }
        }
    }

    private func armDeadline() {
        deadline?.cancel()
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled, let self else { return }
            if phase == .starting { fail(VideoRecordingError.timeout) }
            else if phase == .stopping {
                if failure == nil { failure = VideoRecordingError.timeout }
                detachOutput()
                // Keep an unconfirmed working file hidden: the writer might
                // still own it. A timeout must never publish it as finished.
                finishStop()
            }
        }
    }
}

// SCK encodes media. The sample queue meters audio; MainActor receives numbers and lifecycle events.
@MainActor
private final class ScreenCaptureVideoTransport: NSObject, VideoRecordingTransport, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    private var stream: SCStream!
    private var output: SCRecordingOutput!
    private let sampleQueue = DispatchQueue(label: "com.snaprivo.video.samples", qos: .userInitiated)
    nonisolated private let meter = VideoAudioMeter()
    private var attached = false
    var onEvent: (@MainActor (VideoRecordingEvent) -> Void)?

    static func prepare(selection: ScreenshotSelection, includesCursor: Bool, audio: VideoAudioOptions, url: URL) async throws -> PreparedVideoRecording {
        try await prepareWithClicks(selection: selection, includesCursor: includesCursor, audio: audio, url: url, showsMouseClicks: false)
    }
    static func prepareWithClicks(selection: ScreenshotSelection, includesCursor: Bool, audio: VideoAudioOptions, url: URL,
                                  showsMouseClicks: Bool) async throws -> PreparedVideoRecording {
        let content = try await ScreenshotService().content()
        try Task.checkCancellation()
        let filter: SCContentFilter
        let geometry: VideoGeometry
        if let windowID = selection.windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }), window.isOnScreen,
                  let owner = window.owningApplication, owner.processID != ProcessInfo.processInfo.processIdentifier else {
                throw VideoRecordingError.windowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            geometry = try VideoGeometry(contentSize: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        } else {
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == selection.displayID }),
                  screen.frame == selection.screenFrame,
                  let display = content.displays.first(where: { $0.displayID == selection.displayID }) else { throw ScreenshotError.invalidRegion }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            geometry = try VideoGeometry(selection: selection.rect, screen: screen.frame, scale: CGFloat(filter.pointPixelScale))
        }
        let config = VideoRecordingEngine.configuration(geometry: geometry, includesCursor: includesCursor, audio: audio,
            windowCapture: selection.windowID != nil, showsMouseClicks: showsMouseClicks)
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url; recording.videoCodecType = .h264; recording.outputFileType = .mp4
        let transport = ScreenCaptureVideoTransport()
        transport.stream = SCStream(filter: filter, configuration: config, delegate: transport)
        // Drain live samples even though SCRecordingOutput owns encoding, avoiding
        // missing-consumer errors from SCK. Never retain buffers or forward them
        // onto the MainActor. The surface queue also needs encoder headroom above.
        try transport.stream.addStreamOutput(transport, type: .screen, sampleHandlerQueue: transport.sampleQueue)
        if audio.systemAudio {
            try transport.stream.addStreamOutput(transport, type: .audio, sampleHandlerQueue: transport.sampleQueue)
        }
        if audio.microphone {
            try transport.stream.addStreamOutput(transport, type: .microphone, sampleHandlerQueue: transport.sampleQueue)
        }
        transport.output = SCRecordingOutput(configuration: recording, delegate: transport)
        try transport.stream.addRecordingOutput(transport.output)
        transport.attached = true
        return PreparedVideoRecording(transport: transport, pixelSize: geometry.pixelSize)
    }
    func start(completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        stream.startCapture { error in
            Task { @MainActor in completion(error.map { .failure($0) } ?? .success(())) }
        }
    }
    func stop(completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        stream.stopCapture { error in
            Task { @MainActor in completion(error.map { .failure($0) } ?? .success(())) }
        }
    }
    func detachOutput() throws {
        guard attached else { return }
        try stream.removeRecordingOutput(output)
        attached = false
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let source: VideoAudioSource
        switch type { case .audio: source = .system; case .microphone: source = .microphone; default: return }
        guard let level = meter.read(sampleBuffer, source: source) else { return }
        Task { @MainActor [weak self] in self?.onEvent?(.audioLevel(source, level)) }
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.onEvent?(.started) }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.onEvent?(.finished) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.onEvent?(.recordingFailed(error)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in self?.onEvent?(.streamFailed(error)) }
    }
}

enum VideoRecordingError: LocalizedError {
    case notStarted, alreadyStarted, interrupted, timeout, lowSpace, invalidMovie, missingAudio, windowUnavailable, invalidGIFOptions, gifDurationExceeded
    var errorDescription: String? {
        switch self {
        case .notStarted: String(localized: "Die Videoaufnahme wurde noch nicht gestartet.")
        case .alreadyStarted: String(localized: "Diese Videositzung wurde bereits gestartet. Bitte eine neue Aufnahme beginnen.")
        case .interrupted: String(localized: "Die Videoaufnahme wurde unerwartet beendet. Bitte erneut aufnehmen.")
        case .timeout: String(localized: "Die Aufnahme hat nicht rechtzeitig geantwortet. Bitte erneut versuchen.")
        case .lowSpace: String(localized: "Zu wenig Speicherplatz. Für den Start werden mindestens 128 MB freier Platz benötigt.")
        case .invalidMovie: String(localized: "Die Aufnahme enthält noch kein abspielbares Video. Bitte etwas länger aufnehmen und erneut versuchen.")
        case .missingAudio: String(localized: "Die Aufnahme enthält keine lesbare Tonspur, obwohl Ton gewählt war. Bitte erneut aufnehmen oder die Tonaufnahme ausschalten.")
        case .windowUnavailable: String(localized: "Das gewählte Fenster ist nicht mehr verfügbar. Wähle es erneut aus.")
        case .invalidGIFOptions: String(localized: "Die GIF-Einstellungen sind ungültig.")
        case .gifDurationExceeded: String(localized: "Die ausgewählte GIF-Dauer überschreitet das Exportlimit. Kürze die Auswahl vor dem Export.")
        }
    }
}


@MainActor
struct VideoDisplaySnapshot: Equatable {
    let id: UInt32
    let frame: CGRect
    let scale: CGFloat
    static func current() -> [Self] {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32).map {
                Self(id: $0, frame: screen.frame, scale: screen.backingScaleFactor)
            }
        }.sorted { $0.id < $1.id }
    }
}

@MainActor
final class VideoRecordingSession: NSObject, NSWindowDelegate {
    enum Phase { case ready, countingDown, starting, recording, stopping, finished, failed }
    private(set) var phase: Phase = .ready
    private(set) var hasLibraryChanges = false
    private let selection: ScreenshotSelection
    private let outline: VideoRecordingOutline
    private let recordingToolbar = VideoRecordingToolbar()
    private let countdownBadge = VideoCountdownBadge()
    private let includesCursor: Bool
    private let showsMouseClicks: Bool
    private let microphoneAccess: VideoMicrophoneAccess
    private let files: VideoRecordingFiles
    private let makeEngine: @MainActor () -> VideoRecordingEngine
    private let waitCountdownSecond: @MainActor () async throws -> Void
    private let workspaceNotifications: NotificationCenter
    private let displayNotifications: NotificationCenter
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var interruptionTask: Task<Void, Never>?
    private let displayState: @MainActor () -> [VideoDisplaySnapshot]
    private var originalDisplays: [VideoDisplaySnapshot] = []
    private var countdownRemaining = 0
    private var engine: VideoRecordingEngine?
    private var partial: URL?
    private var finished: URL?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    private var timer: Timer?
    private var startedAt: Date?
    private var outputSize: PixelSize?
    private var recordingAudio = VideoAudioOptions()
    private var pendingCaptureFailure: (any Error)?
    private var showsMicrophoneSettings = false
    private var isClosing = false
    private let panel = VideoControlPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 380), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let systemAudio = NSButton(checkboxWithTitle: String(localized: "Systemton aufnehmen"), target: nil, action: nil)
    private let microphone = NSButton(checkboxWithTitle: String(localized: "Mikrofon aufnehmen"), target: nil, action: nil)
    private let microphoneSettings = NSButton(title: String(localized: "Mikrofoneinstellungen öffnen"), target: nil, action: nil)
    private let delay = NSPopUpButton(frame: .zero, pullsDown: false)
    private let primary = NSButton(title: String(localized: "Video starten"), target: nil, action: nil)
    private let preview = NSButton(title: String(localized: "Video ansehen"), target: nil, action: nil)
    private let close = NSButton(title: String(localized: "Abbrechen"), target: nil, action: nil)
    var onState: (@MainActor (String, Bool) -> Void)?
    var onPermissionFailure: (@MainActor (any Error) -> Void)?
    /// The application routes this validated local original into its own video editor.
    var onFinished: (@MainActor (URL) -> Void)?

    init(selection: ScreenshotSelection, includesCursor: Bool, showsMouseClicks: Bool = false, selectionOverlay: CaptureSelectionOverlay? = nil,
         delaySeconds: Int = 0, audio: VideoAudioOptions = .init(), microphoneAccess: VideoMicrophoneAccess = .init(),
         files: VideoRecordingFiles = .init(), makeEngine: @escaping @MainActor () -> VideoRecordingEngine = { .init() },
         waitCountdownSecond: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(1)) },
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter, displayNotifications: NotificationCenter = .default,
         displayState: @escaping @MainActor () -> [VideoDisplaySnapshot] = VideoDisplaySnapshot.current) {
        self.selection = selection; self.includesCursor = includesCursor; self.showsMouseClicks = showsMouseClicks
        outline = VideoRecordingOutline(selection: selection, selectionOverlay: selectionOverlay)
        self.microphoneAccess = microphoneAccess
        self.files = files; self.makeEngine = makeEngine
        self.waitCountdownSecond = waitCountdownSecond
        self.workspaceNotifications = workspaceNotifications; self.displayNotifications = displayNotifications
        self.displayState = displayState
        super.init()
        recordingToolbar.onStop = { [weak self] in Task { await self?.stop() } }
        recordingToolbar.onCancel = { [weak self] in Task { await self?.closeSafely() } }
        outline.onRegionChange = { [weak self] rect in
            guard let self, usesRecordingToolbar else { return }
            if phase == .countingDown {
                if let rect { countdownBadge.show(countdownRemaining, region: rect) } else { countdownBadge.hide() }
            }
            recordingToolbar.show(region: rect ?? selection.rect, screen: selection.screenFrame)
        }
        for (seconds, title) in [(0, String(localized: "Keine")), (3, String(localized: "3 Sekunden")), (5, String(localized: "5 Sekunden"))] {
            delay.addItem(withTitle: title); delay.lastItem?.tag = seconds
        }
        systemAudio.state = audio.systemAudio ? .on : .off
        microphone.state = audio.microphone ? .on : .off
        delay.selectItem(withTag: [0, 3, 5].contains(delaySeconds) ? delaySeconds : 0)
    }
    func run(startImmediately: Bool = false) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            originalDisplays = displayState()
            observeSystemChanges()
            panel.title = String(localized: "Videoaufnahme"); panel.level = .floating; panel.hidesOnDeactivate = false
            panel.identifier = NSUserInterfaceItemIdentifier("video.controls")
            panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let surface = CaptureToolbarSurface(frame: CGRect(x: 0, y: 0, width: 360, height: 380))
            panel.contentView = surface
            let body = surface.controls
            status.frame = CGRect(x: 20, y: 276, width: 320, height: 84)
            status.font = .systemFont(ofSize: 13); status.setAccessibilityIdentifier("video.status"); body.addSubview(status)
            systemAudio.frame = CGRect(x: 20, y: 236, width: 320, height: 28)
            systemAudio.target = self; systemAudio.action = #selector(audioChanged)
            systemAudio.setAccessibilityIdentifier("video.systemAudio")
            systemAudio.toolTip = String(localized: "Nimmt auch Ton von Apps außerhalb des Bildausschnitts auf.")
            body.addSubview(systemAudio)
            microphone.frame = CGRect(x: 20, y: 200, width: 320, height: 28)
            microphone.target = self; microphone.action = #selector(audioChanged)
            microphone.setAccessibilityIdentifier("video.microphone")
            microphone.toolTip = String(localized: "Nimmt das Standardmikrofon von macOS auf. Zugriff wird erst beim Start angefragt.")
            body.addSubview(microphone)
            let delayLabel = NSTextField(labelWithString: String(localized: "Vorlauf"))
            delayLabel.frame = CGRect(x: 20, y: 164, width: 88, height: 24)
            body.addSubview(delayLabel)
            delay.frame = CGRect(x: 116, y: 160, width: 224, height: 28)
            delay.setAccessibilityLabel(String(localized: "Vorlauf vor Video")); delay.setAccessibilityIdentifier("video.delay")
            delay.toolTip = String(localized: "Wartezeit nach „Video starten“. Während des Countdowns kannst du abbrechen.")
            body.addSubview(delay)
            primary.frame = CGRect(x: 20, y: 108, width: 320, height: 40); CaptureToolbarSurface.style(primary, prominent: true)
            primary.target = self; primary.action = #selector(primaryPressed); primary.keyEquivalent = "\r"
            primary.setAccessibilityIdentifier("video.primary"); body.addSubview(primary)
            preview.frame = CGRect(x: 20, y: 60, width: 320, height: 40); CaptureToolbarSurface.style(preview)
            preview.target = self; preview.action = #selector(previewPressed); preview.setAccessibilityIdentifier("video.preview"); body.addSubview(preview)
            microphoneSettings.frame = preview.frame; CaptureToolbarSurface.style(microphoneSettings)
            microphoneSettings.target = self; microphoneSettings.action = #selector(openMicrophoneSettings)
            microphoneSettings.setAccessibilityIdentifier("video.microphoneSettings"); body.addSubview(microphoneSettings)
            close.frame = CGRect(x: 20, y: 12, width: 320, height: 40); CaptureToolbarSurface.style(close)
            close.target = self; close.action = #selector(closePressed); close.keyEquivalent = "\u{1b}"
            close.setAccessibilityIdentifier("video.close"); body.addSubview(close)
            let screen = selection.screenFrame
            let x = selection.rect.maxX + 380 < screen.maxX ? selection.rect.maxX + 12 : max(screen.minX + 12, selection.rect.minX - 372)
            let height = panel.frame.height
            panel.setFrameOrigin(CGPoint(x: x, y: min(max(screen.minY + 12, selection.rect.maxY - height), screen.maxY - height - 12)))
            if startImmediately { start() } else { update() }
            show()
        }
    }
    private var usesRecordingToolbar: Bool { [.countingDown, .starting, .recording, .stopping].contains(phase) }
    func show() {
        if usesRecordingToolbar {
            recordingToolbar.show(region: outline.visibleRect ?? selection.rect, screen: selection.screenFrame)
        } else { panel.makeKeyAndOrderFront(nil); panel.makeMain(); panel.orderFrontRegardless() }
    }
    private var audioOptions: VideoAudioOptions { .init(systemAudio: systemAudio.state == .on, microphone: microphone.state == .on) }
    @objc private func audioChanged() { showsMicrophoneSettings = false; update() }
    @objc private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
    private func update(_ message: String? = nil) {
        if [.ready, .countingDown, .starting, .recording, .stopping].contains(phase) {
            outline.show(recording: phase == .recording || phase == .stopping)
        } else { outline.hide() }
        if phase == .countingDown, let region = outline.visibleRect { countdownBadge.show(countdownRemaining, region: region) }
        else { countdownBadge.hide() }
        let text: String
        let audioDescription = (phase == .ready ? audioOptions : recordingAudio).summary
        switch phase {
        case .ready:
            let source = switch selection.videoSource {
            case .window: String(localized: "Fenster ausgewählt. Die Aufnahme folgt dem ganzen Fenster beim Verschieben.\nMP4 · H.264 · bis 1080p/30 fps")
            case .display: String(localized: "Bildschirm ausgewählt. Video starten, sobald du bereit bist.\nMP4 · H.264 · bis 1080p/30 fps")
            default: String(localized: "Bereich ausgewählt. Video starten, sobald du bereit bist.\nMP4 · H.264 · bis 1080p/30 fps")
            }
            text = source + "\n" + audioDescription
        case .countingDown:
            text = String(localized: "Video startet in \(countdownRemaining) …") + "\n" + audioDescription + "\n" + String(localized: "Abbrechen oder Esc beendet den Vorlauf.")
        case .starting: text = String(localized: "Video wird gestartet …")
        case .recording:
            let seconds = Int(Date.now.timeIntervalSince(startedAt ?? .now))
            text = String(format: String(localized: "● Aufnahme läuft · %02d:%02d"), seconds / 60, seconds % 60) + String(localized: "\n\(outputSize?.width ?? 0) × \(outputSize?.height ?? 0) Pixel · \(audioDescription)\nMit Stop beenden und die Aufnahme ansehen.")
        case .stopping: text = String(localized: "Video wird beendet und MP4 fertiggestellt …")
        case .finished: text = String(localized: "Video fertig. Jetzt als MP4 speichern.\nEine lokale Kopie bleibt in Snaprivo erhalten.")
        case .failed: text = String(localized: "Video konnte nicht aufgenommen werden. Bitte schließen und erneut versuchen.")
        }
        status.stringValue = message ?? text
        systemAudio.isEnabled = phase == .ready
        microphone.isEnabled = phase == .ready
        delay.isEnabled = phase == .ready
        microphoneSettings.isHidden = !(phase == .ready && showsMicrophoneSettings)
        primary.title = phase == .recording ? String(localized: "Stop") : phase == .finished ? String(localized: "MP4 speichern …") : String(localized: "Video starten")
        primary.isEnabled = [.ready, .recording, .finished].contains(phase) && exportTask == nil
        preview.isHidden = phase != .finished
        close.title = phase == .recording ? String(localized: "Stop und schließen") : (phase == .ready || phase == .countingDown) ? String(localized: "Abbrechen") : String(localized: "Schließen")
        close.isEnabled = phase != .starting && phase != .stopping && exportTask == nil
        if usesRecordingToolbar {
            panel.orderOut(nil)
            let seconds = max(0, Int(Date.now.timeIntervalSince(startedAt ?? .now)))
            recordingToolbar.update(recording: phase == .recording, status: status.stringValue,
                duration: String(format: "%02d:%02d", seconds / 60, seconds % 60),
                dimensions: "\(outputSize?.width ?? 0) × \(outputSize?.height ?? 0) px",
                canCancel: phase == .countingDown)
            recordingToolbar.configureAudio(recordingAudio)
            show()
        } else {
            let wasVisible = recordingToolbar.isVisible
            recordingToolbar.hide()
            if wasVisible && !isClosing && !(phase == .finished && onFinished != nil) { show() }
        }
        onState?(status.stringValue.components(separatedBy: "\n")[0], phase == .recording)
        if phase == .countingDown {
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: String(localized: "Video startet in \(countdownRemaining) …"),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
        }
    }
    @objc private func primaryPressed() {
        switch phase {
        case .ready: start()
        case .recording: Task { await stop() }
        case .finished: save()
        default: break
        }
    }
    private func start() {
        guard phase == .ready, interruptionTask == nil else { return }
        let delaySeconds = delay.selectedTag()
        recordingAudio = audioOptions; showsMicrophoneSettings = false; pendingCaptureFailure = nil
        phase = .starting; update()
        startTask = Task { [self] in
            defer { startTask = nil }
            do {
                if recordingAudio.microphone { update(String(localized: "Mikrofonzugriff prüfen …")) }
                try await microphoneAccess.authorize(ifNeeded: recordingAudio.microphone)
                for seconds in stride(from: delaySeconds, to: 0, by: -1) {
                    try Task.checkCancellation()
                    countdownRemaining = seconds; phase = .countingDown; update()
                    try await waitCountdownSecond()
                }
                try Task.checkCancellation()
                phase = .starting; update()
                let url = try await files.prepare(); partial = url; hasLibraryChanges = true
                try Task.checkCancellation()
                let engine = makeEngine(); self.engine = engine
                engine.onFailure = { [weak self] error in self?.unexpectedFailure(error) }
                engine.onAudioLevel = { [weak self] source, level in
                    guard let self, phase == .recording else { return }
                    recordingToolbar.updateAudioLevel(source, level: level)
                }
                outputSize = try await engine.start(selection: selection, includesCursor: includesCursor, audio: recordingAudio, url: url,
                    showsMouseClicks: showsMouseClicks)
                try Task.checkCancellation()
                if let pendingCaptureFailure { throw pendingCaptureFailure }
                phase = .recording; startedAt = .now
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.update()
                    }
                }
                update()
            } catch is CancellationError {
                await releaseWorkingRecording()
                phase = .ready; update()
            } catch let error as VideoMicrophoneError {
                // No stream or working file exists yet. Keep the source selection
                // available for retrying without microphone or after Settings.
                if case .denied = error { showsMicrophoneSettings = true }
                phase = .ready; update(error.localizedDescription)
            } catch { await fail(error) }
        }
    }
    func stop() async {
        if let startTask { await startTask.value }
        if let stopTask { await stopTask.value; return }
        guard phase == .recording else { return }
        phase = .stopping; timer?.invalidate(); timer = nil; update()
        let task = Task { [self] in
            defer { stopTask = nil; engine = nil }
            do {
                guard let engine else { throw VideoRecordingError.notStarted }
                try await engine.stop()
                guard let partial else { throw VideoRecordingError.invalidMovie }
                finished = try await files.finalize(partial, audio: recordingAudio); self.partial = nil
                phase = .finished; update()
                if let finished, let onFinished, !isClosing {
                    onFinished(finished)
                    finishPanel()
                }
            } catch { await fail(error) }
        }
        stopTask = task; await task.value
    }
    private func unexpectedFailure(_ error: any Error) {
        guard phase == .starting || phase == .recording else { return }
        if pendingCaptureFailure == nil { pendingCaptureFailure = error }
        if phase == .recording { Task { await stop() } }
    }
    private func fail(_ error: any Error) async {
        guard phase != .failed else { return }
        timer?.invalidate(); timer = nil
        let message = captureFailureMessage(error)
        await releaseWorkingRecording(failureMessage: message)
        phase = .failed; update(String(localized: "Aufnahme fehlgeschlagen: \(message)"))
        onPermissionFailure?(error)
    }
    private func captureFailureMessage(_ error: any Error) -> String {
        let ns = error as NSError
        var full = ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC)
            || ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue
        if #available(macOS 27, *) {
            // Public SDK-27 SCStreamError.Code.insufficientStorage value. Match
            // its raw code to keep compilation with the macOS-26 SDK possible.
            full = full || ns.domain == SCStreamErrorDomain && ns.code == -3822
        }
        return full ? String(localized: "Die Aufnahme wurde wegen zu wenig freiem Speicherplatz beendet. Schaffe Platz und starte sie erneut.") : error.localizedDescription
    }
    private func releaseWorkingRecording(failureMessage: String? = nil) async {
        // Wait for bounded transport cleanup before touching its working file.
        if let engine { try? await engine.stop() }
        if let partial {
            try? await files.markFailed(partial, message: failureMessage)
            if engine?.canDiscardPartial != false { await files.discardPartial(partial) }
            self.partial = nil
        }
        engine = nil
    }
    private func save() {
        guard let finished, exportTask == nil else { return }
        let save = NSSavePanel(); save.allowedContentTypes = [.mpeg4Movie]
        save.nameFieldStringValue = "Snaprivo-Video-" + Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + ".mp4"
        save.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        save.begin { [weak self] response in
            guard let self, response == .OK, let target = save.url else { return }
            exportTask = Task { [self] in
                defer { exportTask = nil; update(status.stringValue) }
                let access = target.startAccessingSecurityScopedResource()
                defer { if access { target.stopAccessingSecurityScopedResource() } }
                do { try await files.export(finished, to: target); status.stringValue = String(localized: "Gespeichert: \(target.lastPathComponent)") }
                catch { status.stringValue = String(localized: "Speichern fehlgeschlagen: \(error.localizedDescription)\nDie lokale Aufnahme bleibt erhalten. Erneut speichern versuchen.") }
                update(status.stringValue)
            }
            update(String(localized: "MP4 wird gespeichert …"))
        }
    }
    @objc private func previewPressed() { if let finished { NSWorkspace.shared.open(finished) } }
    @objc private func closePressed() { Task { await closeSafely() } }
    func closeSafely() async {
        isClosing = true
        removeSystemObservers()
        startTask?.cancel()
        if let interruptionTask { await interruptionTask.value }
        await stop()
        if let exportTask { await exportTask.value }
        guard phase != .starting && phase != .stopping else { return }
        finishPanel()
    }
    private func observeSystemChanges() {
        for (center, name, sleep) in [
            (workspaceNotifications, NSWorkspace.willSleepNotification, true),
            (workspaceNotifications, NSWorkspace.screensDidSleepNotification, true),
            (displayNotifications, NSApplication.didChangeScreenParametersNotification, false)
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.systemChanged(sleep: sleep) }
            }
            systemObservers.append((center, token))
        }
    }
    private func removeSystemObservers() {
        for (center, token) in systemObservers { center.removeObserver(token) }
        systemObservers.removeAll()
    }
    private func systemChanged(sleep: Bool) {
        // AppKit may also post for benign changes such as minimizing a window.
        // Stop only for actual display identity, geometry or pixel-scale changes.
        guard sleep || displayState() != originalDisplays else { return }
        guard interruptionTask == nil, continuation != nil, [.ready, .countingDown, .starting, .recording].contains(phase) else { return }
        let wasRecording = phase == .recording
        if !wasRecording { startTask?.cancel() }
        interruptionTask = Task { [self] in
            defer { interruptionTask = nil }
            await stop()
            if wasRecording {
                if phase == .finished, continuation != nil {
                    update(sleep ? String(localized: "Aufnahme vor dem Ruhezustand beendet. Die lokale MP4 bleibt erhalten.")
                        : String(localized: "Aufnahme wegen geänderter Bildschirmkonfiguration beendet. Die lokale MP4 bleibt erhalten."))
                }
            } else { finishPanel() }
        }
    }
    private func finishPanel() {
        removeSystemObservers(); timer?.invalidate(); timer = nil
        outline.hide()
        countdownBadge.hide()
        recordingToolbar.hide()
        panel.orderOut(nil); panel.close()
        continuation?.resume(); continuation = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closePressed(); return false }
}

/// Matches the selection shade over the live desktop, with a clear, usable source.
/// SCK excludes our process, including these panels and the separate recording toolbar.
@MainActor
final class VideoRecordingOutline {
    private let selection: ScreenshotSelection
    private let windowFrame: @MainActor (CGWindowID) -> CGRect?
    private let panels: [NSPanel]
    private var timer: Timer?
    private(set) var visibleRect: CGRect?
    var onRegionChange: (@MainActor (CGRect?) -> Void)?

    init(selection: ScreenshotSelection, selectionOverlay: CaptureSelectionOverlay? = nil,
         screens: [CGRect] = NSScreen.screens.map(\.frame),
         windowFrame: @escaping @MainActor (CGWindowID) -> CGRect? = VideoRecordingOutline.currentWindowFrame) {
        self.selection = selection; self.windowFrame = windowFrame
        let inheritedPanels = selectionOverlay?.takePanels() ?? []
        let frames = screens.contains(selection.screenFrame) ? screens : screens + [selection.screenFrame]
        panels = frames.map { frame in
            // Keep the same visible window throughout selection, source focus,
            // countdown and stream startup. Replace only its drawing, never its visibility.
            let panel = inheritedPanels.first { $0.frame == frame }
                ?? NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.identifier = NSUserInterfaceItemIdentifier("video.recordingRegion")
            panel.setAccessibilityIdentifier("video.recordingRegion")
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = VideoRecordingOutlineView()
            view.selectionRect = selection.rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
            view.setAccessibilityElement(false)
            panel.contentView = view
            panel.displayIfNeeded()
            return panel
        }
        // A display may have disappeared while the source app was activated.
        inheritedPanels.filter { !frames.contains($0.frame) }.forEach { $0.orderOut(nil); $0.close() }
    }
    func show(recording: Bool) {
        for panel in panels {
            (panel.contentView as? VideoRecordingOutlineView)?.color = recording ? .systemRed : .controlAccentColor
        }
        updateFrame()
        if selection.windowID != nil && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFrame() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func hide() {
        timer?.invalidate(); timer = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        visibleRect = nil
    }
    private func updateFrame() {
        let rect: CGRect?
        if let id = selection.windowID { rect = windowFrame(id) }
        else { rect = selection.rect }
        guard let rect, !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0,
              panels.contains(where: { $0.frame.intersects(rect) }) else {
            for panel in panels { panel.orderOut(nil) }
            if visibleRect != nil { visibleRect = nil; onRegionChange?(nil) }
            return
        }
        for panel in panels {
            (panel.contentView as? VideoRecordingOutlineView)?.selectionRect = rect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        if visibleRect != rect { visibleRect = rect; onRegionChange?(rect) }
    }
    static func currentWindowFrame(_ id: CGWindowID) -> CGRect? {
        guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
              entry[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return CaptureGeometry.appKitRect(fromQuartz: rect, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }
}

@MainActor private final class VideoRecordingOutlineView: NSView {
    var color: NSColor = .controlAccentColor { didSet { if color != oldValue { needsDisplay = true } } }
    var selectionRect = CGRect.zero { didSet { if selectionRect != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        let hole = selectionRect.intersection(bounds)
        if !hole.isNull { shade.append(NSBezierPath(rect: hole)); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.42).setFill()
        shade.fill()
        color.setStroke()
        let path = NSBezierPath(rect: selectionRect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3; path.stroke()
    }
}

/// Only this small panel accepts input; the desktop shade remains click-through.
@MainActor
final class VideoRecordingToolbar: NSObject {
    private let panel = VideoToolbarPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: CaptureToolbarSurface.barHeight),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let dot = NSView(frame: CGRect(x: 14, y: 24, width: 8, height: 8))
    private let rec = NSTextField(labelWithString: "REC")
    private let time = NSTextField(labelWithString: "00:00")
    private let dimensions = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let stop = CaptureFlatButton(frame: .zero)
    private let audioMeters = NSStackView()
    private var meterGroups: [VideoAudioSource: NSView] = [:]
    private var indicators: [VideoAudioSource: NSLevelIndicator] = [:]
    private var audio = VideoAudioOptions()
    private var lastAudioUpdate: [VideoAudioSource: UInt64] = [:]
    private let reduceMotion: @MainActor () -> Bool
    private var isRecording = false
    private var cancelsCountdown = false
    private var accessibilityObserver: NSObjectProtocol?
    var onStop: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var isVisible: Bool { panel.isVisible }

    init(reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
        super.init()
        panel.identifier = NSUserInterfaceItemIdentifier("video.recordingToolbar")
        panel.title = String(localized: "Videoaufnahme")
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let surface = CaptureToolbarSurface(frame: CGRect(x: 0, y: 0, width: 360, height: CaptureToolbarSurface.barHeight), subdued: true)
        panel.contentView = surface
        let body = surface.controls
        dot.wantsLayer = true; dot.layer?.backgroundColor = NSColor.systemRed.cgColor; dot.layer?.cornerRadius = 4
        dot.setAccessibilityElement(false); dot.setAccessibilityIdentifier("video.recordingDot")
        body.addSubview(dot)
        for (label, frame, font) in [
            (rec, CGRect(x: 28, y: 20, width: 28, height: 16), NSFont.systemFont(ofSize: 11, weight: .bold)),
            (time, CGRect(x: 64, y: 19, width: 56, height: 18), NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)),
            (dimensions, CGRect(x: 128, y: 20, width: 108, height: 16), NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        ] {
            label.frame = frame; label.font = font; label.textColor = .white
            body.addSubview(label)
        }
        rec.textColor = .systemRed
        rec.setAccessibilityElement(false)
        time.setAccessibilityIdentifier("video.recordingTime")
        dimensions.setAccessibilityLabel(String(localized: "Auswahlgröße"))
        dimensions.textColor = NSColor.white.withAlphaComponent(0.68)
        audioMeters.frame = CGRect(x: 128, y: 31, width: 108, height: 12)
        audioMeters.orientation = .horizontal; audioMeters.spacing = 8; audioMeters.distribution = .fillEqually
        audioMeters.isHidden = true; body.addSubview(audioMeters)
        for source in [VideoAudioSource.system, .microphone] {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: source == .system ? "speaker.wave.2.fill" : "mic.fill", accessibilityDescription: nil)
            icon.contentTintColor = NSColor.white.withAlphaComponent(0.85); icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            icon.widthAnchor.constraint(equalToConstant: 10).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 10).isActive = true
            let indicator = NSLevelIndicator()
            indicator.levelIndicatorStyle = .continuousCapacity; indicator.minValue = 0; indicator.maxValue = 100
            indicator.warningValue = 85; indicator.criticalValue = 98; indicator.isEditable = false
            indicator.fillColor = .systemGreen; indicator.warningFillColor = .systemOrange; indicator.criticalFillColor = .systemRed
            indicator.numberOfTickMarks = 0
            indicator.setAccessibilityLabel(source == .system ? String(localized: "Systemtonpegel") : String(localized: "Mikrofonpegel"))
            indicator.setAccessibilityIdentifier(source == .system ? "video.audio.system" : "video.audio.microphone")
            let group = NSStackView(views: [icon, indicator]); group.orientation = .horizontal; group.spacing = 3
            group.alignment = .centerY; group.isHidden = true
            audioMeters.addArrangedSubview(group); indicators[source] = indicator; meterGroups[source] = group
        }
        message.frame = CGRect(x: 12, y: 10, width: 224, height: 36)
        message.font = .systemFont(ofSize: 12, weight: .medium); message.textColor = .white
        message.setAccessibilityIdentifier("video.recordingMessage"); body.addSubview(message)
        body.addSubview(CaptureToolbarSurface.divider(frame: CGRect(x: 248, y: 12, width: 1, height: 32)))
        stop.frame = CGRect(x: 260, y: 10, width: 88, height: CaptureToolbarSurface.controlHeight)
        CaptureToolbarSurface.styleFlat(stop, prominent: true); stop.flatCell.fill = .systemRed
        stop.target = self; stop.action = #selector(stopPressed)
        stop.setAccessibilityIdentifier("video.recordingStop"); body.addSubview(stop)
    }

    func update(recording: Bool, status: String, duration: String, dimensions: String, canCancel: Bool) {
        // Keep Escape local to the countdown, then return keyboard focus to the source app.
        if cancelsCountdown && !canCancel && panel.isKeyWindow { panel.orderOut(nil) }
        isRecording = recording; cancelsCountdown = canCancel
        updateAudioLayout()
        if !recording { lastAudioUpdate.removeAll(); indicators.values.forEach { $0.doubleValue = 0 } }
        expireAudioLevels()
        for view in [dot, rec, time, self.dimensions] { view.isHidden = !recording }
        message.isHidden = recording
        message.stringValue = status.components(separatedBy: "\n").prefix(2).joined(separator: "\n")
        message.toolTip = status
        time.stringValue = duration; time.setAccessibilityLabel(status.components(separatedBy: "\n")[0])
        self.dimensions.stringValue = dimensions; self.dimensions.toolTip = status
        stop.title = canCancel ? String(localized: "Abbrechen") : String(localized: "Stop")
        stop.image = canCancel ? nil : NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
        stop.flatCell.iconSize = 12
        stop.isEnabled = recording || canCancel
        stop.keyEquivalent = canCancel ? "\u{1b}" : ""
        if accessibilityObserver == nil {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.updatePulse() } }
        }
        updatePulse()
    }
    func configureAudio(_ value: VideoAudioOptions) {
        if audio != value { lastAudioUpdate.removeAll(); indicators.values.forEach { $0.doubleValue = 0 } }
        audio = value; updateAudioLayout()
    }
    func updateAudioLevel(_ source: VideoAudioSource, level: AudioSignalLevel, at time: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard isRecording, source == .system ? audio.systemAudio : audio.microphone else { return }
        lastAudioUpdate[source] = time
        indicators[source]?.doubleValue = level.fraction * 100
        indicators[source]?.toolTip = source == .system ? String(localized: "Systemtonpegel") : String(localized: "Mikrofonpegel")
        indicators[source]?.setAccessibilityHelp(nil)
    }
    func expireAudioLevels(at time: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        for (source, indicator) in indicators {
            guard let last = lastAudioUpdate[source], time >= last, time - last < 600_000_000 else {
                indicator.doubleValue = 0; indicator.toolTip = String(localized: "Wartet auf Audiodaten")
                indicator.setAccessibilityHelp(String(localized: "Wartet auf Audiodaten")); continue
            }
        }
    }
    private func updateAudioLayout() {
        let visible = isRecording && audio.requiresAudio
        audioMeters.isHidden = !visible
        meterGroups[.system]?.isHidden = !audio.systemAudio
        meterGroups[.microphone]?.isHidden = !audio.microphone
        dimensions.frame.origin.y = visible ? 10 : 20
        dimensions.font = .monospacedDigitSystemFont(ofSize: visible ? 9 : 11, weight: .medium)
    }

    private func updatePulse() {
        guard isRecording && !reduceMotion() else { dot.layer?.removeAnimation(forKey: "recordingPulse"); return }
        guard dot.layer?.animation(forKey: "recordingPulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1; pulse.toValue = 0.2; pulse.duration = 0.65
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "recordingPulse")
    }

    func show(region: CGRect, screen fallback: CGRect) {
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = lhs.frame.intersection(region), b = rhs.frame.intersection(region)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }?.visibleFrame ?? fallback
        let width = panel.frame.width, height = panel.frame.height, margin: CGFloat = 12
        let x = min(max(region.midX - width / 2, screen.minX + margin), screen.maxX - width - margin)
        let below = region.minY - height - 8, above = region.maxY + 8
        let y = below >= screen.minY + margin ? below : above + height <= screen.maxY - margin ? above : screen.minY + margin
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        if cancelsCountdown && !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
        else if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() {
        dot.layer?.removeAnimation(forKey: "recordingPulse")
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        panel.orderOut(nil); panel.close()
    }
    @objc private func stopPressed() { if cancelsCountdown { onCancel?() } else { onStop?() } }
}

/// Large countdown in the middle of the source. It never takes input; SCK excludes
/// it like every own window, and it hides before the stream starts.
@MainActor
final class VideoCountdownBadge {
    static let maximumSide: CGFloat = 112
    private let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: maximumSide, height: maximumSide),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let host = NSHostingView(rootView: VideoCountdownNumber(seconds: 0, side: maximumSide, animates: false))

    init() {
        panel.identifier = NSUserInterfaceItemIdentifier("video.countdownBadge")
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        // The session already announces every second to VoiceOver.
        panel.setAccessibilityElement(false)
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Centered on the source, smaller for small sources, and kept on its display.
    static func frame(centeredIn region: CGRect, within screen: CGRect) -> CGRect {
        let side = min(maximumSide, max(64, min(region.width, region.height) / 2))
        let x = min(max(region.midX - side / 2, screen.minX), screen.maxX - side)
        let y = min(max(region.midY - side / 2, screen.minY), screen.maxY - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    func show(_ seconds: Int, region: CGRect) {
        let screen = NSScreen.screens.map(\.frame).max { lhs, rhs in
            let a = lhs.intersection(region), b = rhs.intersection(region)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? region
        let frame = Self.frame(centeredIn: region, within: screen)
        // The first second appears in place; only later seconds roll.
        host.rootView = VideoCountdownNumber(seconds: seconds, side: frame.width, animates: panel.isVisible)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
}

struct VideoCountdownNumber: View {
    let seconds: Int
    let side: CGFloat
    let animates: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(verbatim: "\(seconds)")
            .font(.system(size: side / 2, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText(countsDown: true))
            .animation(animates && !reduceMotion ? .smooth(duration: 0.3) : nil, value: seconds)
            .frame(width: side, height: side)
            .glassEffect(.regular.tint(.black.opacity(0.25)), in: .circle)
    }
}

@MainActor private final class VideoToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class VideoControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
