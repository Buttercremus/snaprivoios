import AppKit
import Observation
import ScreenCaptureKit
import SnagForgeDomain

@MainActor
@Observable
final class ScreenshotCoordinator {
    private(set) var isBusy = false
    private(set) var status = ""
    var errorMessage: String?
    var needsPermission = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var selector: ScreenshotSelector?
    @ObservationIgnored private var scrollSession: ManualScrollSession?
    @ObservationIgnored private var videoSession: VideoRecordingSession?
    private(set) var isRecordingVideo = false
    var videoFiles = VideoRecordingFiles()
    var onVideoLibraryChange: (@MainActor () async -> Void)?

    @ObservationIgnored private let preflight: @MainActor () -> Bool
    @ObservationIgnored private let requestAccess: @MainActor () -> Bool
    private(set) var permissionWasRequested = false
    private(set) var needsRestart = false

    init(preflight: @escaping @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() },
         requestAccess: @escaping @MainActor () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.preflight = preflight; self.requestAccess = requestAccess
    }
    var hasPermission: Bool { preflight() && !needsRestart }

    @discardableResult func checkPermission(requestIfNeeded: Bool) -> Bool {
        if !preflight(), requestIfNeeded, !permissionWasRequested {
            permissionWasRequested = true
            _ = requestAccess()
        }
        guard hasPermission else {
            needsPermission = true
            errorMessage = needsRestart ? String(localized: "macOS zeigt die Freigabe an, hat den Zugriff für diese App-Sitzung aber abgelehnt. Beende Snaprivo und öffne die App erneut. Deine Projekte werden beim Beenden gesichert.") : ScreenshotError.permission.localizedDescription
            return false
        }
        needsPermission = false; errorMessage = nil
        return true
    }
    func handleCaptureFailure(_ error: Error) {
        let failure = error as NSError
        let declined = failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue
        needsRestart = declined && preflight()
        needsPermission = declined || !preflight()
        if needsPermission { _ = checkPermission(requestIfNeeded: false) }
        else { errorMessage = String(localized: "Aufnahme fehlgeschlagen: \(error.localizedDescription)") }
    }

    func refreshPermission() {
        if needsPermission { _ = checkPermission(requestIfNeeded: false) }
    }

    func start(configuration: CaptureConfiguration, requestPermission: Bool = false, scrolling: Bool = false, videoAudio: VideoAudioOptions = .init(),
               onFailure: @escaping @MainActor () -> Void = {},
               onVideoCapture: @escaping @MainActor (URL) async -> Void = { _ in },
               onCapture: @escaping @MainActor (CGImage) -> Void) {
        guard !isBusy else { return }
        errorMessage = nil
        needsPermission = false
        guard checkPermission(requestIfNeeded: requestPermission) else { onFailure(); return }
        isBusy = true
        status = String(localized: "Aufnahme vorbereiten …")
        task = Task { [weak self] in
            guard let self else { return }
            var hiddenWindows: [NSWindow] = []
            defer {
                selector?.cancel()
                selector = nil
                scrollSession?.cancel(); scrollSession = nil
                hiddenWindows.reversed().forEach { $0.orderFront(nil) }
                hiddenWindows.first?.makeKeyAndOrderFront(nil)
                isBusy = false
                status = ""
                task = nil
            }
            do {
                // Keep the setup visible with an explicit cancel button during pre-roll.
                for seconds in stride(from: configuration.selectionDelaySeconds, to: 0, by: -1) {
                    status = String(localized: "Auswahl startet in \(seconds) …")
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                hiddenWindows = NSApp.windows.filter { $0.isVisible && $0.level.rawValue < NSWindow.Level.statusBar.rawValue }
                hiddenWindows.forEach { $0.orderOut(nil) }
                // Let the window server remove our windows before source enumeration.
                try await Task.sleep(for: .milliseconds(180))
                let service = ScreenshotService()
                let content = try await service.content()
                try Task.checkCancellation()
                guard !content.displays.isEmpty else { throw ScreenshotError.noDisplays }
                let windows = service.windows(in: content)
                status = String(localized: "Bildschirm einfrieren …")
                let desktop = try await service.freeze(content, cursor: scrolling ? false : configuration.includesCursor)
                try Task.checkCancellation()
                let selectionUI = ScreenshotSelector()
                selector = selectionUI
                status = String(localized: "Fenster oder Bereich auswählen …")
                guard let selected = try await selectionUI.select(source: scrolling ? .region : configuration.source, windows: windows, desktop: desktop, media: configuration.media, allowsVideoAction: !scrolling) else { return }
                try Task.checkCancellation()
                status = String(localized: "Auswahl öffnen …")
                if selected.media == .video {
                    let center = CaptureGeometry.quartzPoint(fromAppKit: CGPoint(x: selected.rect.midX, y: selected.rect.midY),
                        primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
                    if let target = (selected.windowID.flatMap { id in windows.first { $0.id == id } }
                        ?? windows.first { $0.frame.contains(center) })?.processID,
                       let app = NSRunningApplication(processIdentifier: target) {
                        app.activate(options: [])
                    }
                    try await Task.sleep(for: .milliseconds(350))
                    try Task.checkCancellation()
                    let session = VideoRecordingSession(selection: selected, includesCursor: configuration.includesCursor,
                                                        delaySeconds: configuration.delaySeconds, audio: videoAudio, files: videoFiles)
                    videoSession = session
                    session.onState = { [weak self] text, recording in self?.status = text; self?.isRecordingVideo = recording }
                    session.onPermissionFailure = { [weak self] error in self?.handleCaptureFailure(error) }
                    var finishedVideo: URL?
                    session.onFinished = { finishedVideo = $0 }
                    await session.run(startImmediately: true)
                    videoSession = nil; isRecordingVideo = false
                    // Restore the sheet's host before routing the finished recording to the editor.
                    hiddenWindows.reversed().forEach { $0.orderFront(nil) }
                    hiddenWindows.first?.makeKeyAndOrderFront(nil)
                    hiddenWindows.removeAll()
                    if session.hasLibraryChanges { await onVideoLibraryChange?() }
                    if let finishedVideo, !Task.isCancelled { await onVideoCapture(finishedVideo) }
                    return
                }
                var image = try desktop.crop(selected)
                if scrolling {
                    // Closing the frozen selector must return focus to the selected
                    // content, including a browser in its own full-screen Space.
                    let center = CaptureGeometry.quartzPoint(fromAppKit: CGPoint(x: selected.rect.midX, y: selected.rect.midY),
                        primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
                    if let target = windows.first(where: { $0.frame.contains(center) })?.processID,
                       let app = NSRunningApplication(processIdentifier: target) {
                        app.activate(options: [])
                    }
                    try await Task.sleep(for: .milliseconds(350))
                    // Seed the live session after focus/Space transitions have settled.
                    // Every accepted section now uses the same live capture path.
                    image = try await service.scrollFrame(selected)
                    try await Task.sleep(for: .milliseconds(220))
                    let first = image, stable = try await service.scrollFrame(selected)
                    try await Task.detached {
                        try ScrollStitcher.requireStable(ScrollCaptureProcessor.frame(first), ScrollCaptureProcessor.frame(stable))
                    }.value
                    try Task.checkCancellation()
                    let session = ManualScrollSession(selection: selected, first: image)
                    scrollSession = session
                    status = String(localized: "Manuell scrollen und Abschnitte hinzufügen …")
                    guard let stitched = await session.run() else { return }
                    image = stitched
                    scrollSession = nil
                }
                try Task.checkCancellation()
                hiddenWindows.reversed().forEach { $0.orderFront(nil) }
                hiddenWindows.removeAll()
                NSApp.activate(ignoringOtherApps: true)
                onCapture(image)
            } catch is CancellationError {
                // Escape and Cancel leave the existing editor image untouched.
            } catch {
                handleCaptureFailure(error)
                NSApp.activate(ignoringOtherApps: true)
                onFailure()
            }
        }
    }

    func cancel() {
        task?.cancel()
        selector?.cancel()
        scrollSession?.cancel()
        if let videoSession { Task { await videoSession.closeSafely() } }
    }
    func stopVideo() { if let videoSession { Task { await videoSession.stop() } } }
    func showVideoControls() { videoSession?.show() }
    var hasVideoSession: Bool { videoSession != nil }
    func finishBeforeQuitting() async {
        if let videoSession { await videoSession.closeSafely() }
        else { cancel() }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// CPU work stays outside MainActor; only the small controller below owns AppKit views.
enum ScrollCaptureProcessor {
    static func frame(_ image: CGImage) throws -> ScrollFrame {
        guard image.width >= 40, image.height >= 80, image.width <= 4096, image.height <= 4096 else { throw ScrollStitchError.dimensions }
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        let valid = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard valid else { throw ScrollStitchError.limit }
        return try ScrollFrame(width: image.width, height: image.height, pixels: pixels)
    }
    static func append(previous: CGImage, next: CGImage, stable: CGImage, accumulated: CGImage, count: Int) throws -> CGImage {
        let a = try frame(previous), b = try frame(next)
        try ScrollStitcher.requireStable(b, frame(stable))
        let delta = try ScrollStitcher.displacement(from: a, to: b)
        let height = accumulated.height + delta
        try ScrollStitcher.validateSize(width: next.width, height: height, count: count + 1)
        guard accumulated.width == next.width,
              let strip = next.cropping(to: CGRect(x: 0, y: next.height - delta, width: next.width, height: delta)),
              let context = CGContext(data: nil, width: next.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScrollStitchError.dimensions }
        context.draw(accumulated, in: CGRect(x: 0, y: delta, width: accumulated.width, height: accumulated.height))
        context.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: delta))
        guard let result = context.makeImage() else { throw ScrollStitchError.limit }
        return result
    }
}

@MainActor
final class ManualScrollSession: NSObject, NSWindowDelegate {
    private let selection: ScreenshotSelection
    private var previous: CGImage
    private var result: CGImage
    private(set) var count = 1
    private let captureFrame: @MainActor @Sendable () async throws -> CGImage
    private let firstFrame: CGImage
    private var insets = ScrollContentInsets()
    private var undoState: (previous: CGImage, result: CGImage, count: Int)?
    private var detailPanel: NSPanel?
    private var automaticTask: Task<Void, Never>?
    private let automatic = NSButton(checkboxWithTitle: String(localized: "Abschnitte automatisch ergänzen"), target: nil, action: nil)
    private let undoSection = NSButton(title: String(localized: "Letzten Abschnitt zurücknehmen"), target: nil, action: nil)
    private let topInset = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bottomInset = NSPopUpButton(frame: .zero, pullsDown: false)
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var captureTask: Task<Void, Never>?
    private let panel = ScrollCapturePanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 620), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    private let preview = NSImageView(frame: CGRect(x: 20, y: 394, width: 320, height: 124))
    private let message = NSTextField(wrappingLabelWithString: "")
    private let add = NSButton(title: String(localized: "Abschnitt hinzufügen"), target: nil, action: nil)
    private let done = NSButton(title: String(localized: "Im Editor öffnen"), target: nil, action: nil)

    init(selection: ScreenshotSelection, first: CGImage, captureFrame: (@MainActor @Sendable () async throws -> CGImage)? = nil) {
        self.captureFrame = captureFrame ?? { try await ScreenshotService().scrollFrame(selection) }
        self.selection = selection; previous = first; result = first; firstFrame = first
        super.init()
    }
    func run() async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            panel.title = String(localized: "Scroll-Aufnahme · Vorschau")
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let body = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 360, height: 620))
            body.material = .hudWindow; body.blendingMode = .behindWindow; body.state = .active
            panel.contentView = body
            let instructions = NSTextField(wrappingLabelWithString: String(localized: "Scrolle im gewählten Bereich nach unten, warte kurz und füge den nächsten Abschnitt hinzu. Mindestens ein Drittel Überlappung behalten. Fenster und Bereich nicht verschieben."))
            instructions.frame = CGRect(x: 20, y: 534, width: 320, height: 76); instructions.font = .systemFont(ofSize: 12)
            body.addSubview(instructions)
            preview.imageScaling = .scaleProportionallyDown
            preview.setAccessibilityLabel(String(localized: "Vorschau der zusammengefügten Aufnahme"))
            body.addSubview(preview)
            message.frame = CGRect(x: 20, y: 314, width: 320, height: 72); message.font = .systemFont(ofSize: 12)
            message.setAccessibilityIdentifier("scroll.status"); body.addSubview(message)
            for (popup, label, x) in [(topInset, String(localized: "Oben auslassen"), CGFloat(20)), (bottomInset, String(localized: "Unten auslassen"), CGFloat(185))] {
                let title = NSTextField(labelWithString: label); title.frame = CGRect(x: x, y: 290, width: 155, height: 18); body.addSubview(title)
                popup.addItems(withTitles: ["0 %", "5 %", "10 %", "15 %", "20 %"])
                popup.frame = CGRect(x: x, y: 258, width: 155, height: 28); popup.target = self; popup.action = #selector(changeInsets)
                popup.setAccessibilityLabel(label); body.addSubview(popup)
            }
            automatic.frame = CGRect(x: 20, y: 222, width: 320, height: 28); automatic.target = self; automatic.action = #selector(toggleAutomatic); body.addSubview(automatic)
            undoSection.frame = CGRect(x: 20, y: 184, width: 320, height: 32); undoSection.bezelStyle = .rounded
            undoSection.target = self; undoSection.action = #selector(undoLastSection); body.addSubview(undoSection)
            add.frame = CGRect(x: 20, y: 136, width: 320, height: 32); add.target = self; add.action = #selector(addSection)
            add.bezelStyle = .rounded; add.setAccessibilityIdentifier("scroll.add"); body.addSubview(add)
            done.frame = CGRect(x: 20, y: 90, width: 320, height: 32); done.target = self; done.action = #selector(openEditor)
            done.bezelStyle = .rounded; done.keyEquivalent = "\r"; done.keyEquivalentModifierMask = [.command]; done.setAccessibilityIdentifier("scroll.finish"); body.addSubview(done)
            let cancel = NSButton(title: String(localized: "Abbrechen"), target: self, action: #selector(cancelPressed))
            cancel.frame = CGRect(x: 20, y: 44, width: 320, height: 32); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"; body.addSubview(cancel)
            let inspect = NSButton(title: String(localized: "Vorschau in Originalgröße"), target: self, action: #selector(inspectResult))
            inspect.frame = CGRect(x: 20, y: 6, width: 320, height: 30); inspect.bezelStyle = .rounded; body.addSubview(inspect)
            updatePreview()
            // Prefer a location outside the capture rectangle. Own app windows are also excluded by SCK.
            let screen = selection.screenFrame
            let x = selection.rect.maxX + 380 < screen.maxX ? selection.rect.maxX + 12 : max(screen.minX + 12, selection.rect.minX - 372)
            panel.setFrameOrigin(CGPoint(x: x, y: min(max(screen.minY + 12, selection.rect.maxY - 650), screen.maxY - 650)))
            panel.makeKeyAndOrderFront(nil)
            panel.makeMain()
            panel.makeFirstResponder(add)
            panel.orderFrontRegardless()
        }
    }
    @objc private func inspectResult() {
        detailPanel?.close()
        let detail = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        detail.title = String(localized: "Scroll-Aufnahme · Originalgröße"); detail.isReleasedWhenClosed = false
        detail.level = .floating
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let image = NSImageView(frame: CGRect(x: 0, y: 0, width: result.width, height: result.height))
        image.image = NSImage(cgImage: result, size: image.frame.size); image.imageScaling = .scaleNone
        scroll.documentView = image; detail.contentView = scroll; detail.center(); detail.makeKeyAndOrderFront(nil)
        detailPanel = detail
    }
    @objc private func changeInsets() {
        guard count == 1, captureTask == nil else { return }
        let next = ScrollContentInsets(topPercent: topInset.indexOfSelectedItem * 5, bottomPercent: bottomInset.indexOfSelectedItem * 5)
        do {
            let rect = try next.rect(width: firstFrame.width, height: firstFrame.height)
            guard let cropped = firstFrame.cropping(to: rect) else { throw ScrollStitchError.dimensions }
            insets = next; previous = cropped; result = cropped; undoState = nil; updatePreview()
        } catch {
            topInset.selectItem(at: insets.topPercent / 5); bottomInset.selectItem(at: insets.bottomPercent / 5)
            message.stringValue = error.localizedDescription
        }
    }
    @objc private func toggleAutomatic() {
        automaticTask?.cancel(); automaticTask = nil
        guard automatic.state == .on else { return }
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                guard let self, continuation != nil else { return }
                if captureTask == nil { addSection() }
            }
        }
    }
    @objc private func undoLastSection() {
        guard captureTask == nil, let state = undoState else { return }
        automatic.state = .off; toggleAutomatic()
        previous = state.previous; result = state.result; count = state.count; undoState = nil; updatePreview()
    }
    private func updatePreview() {
        preview.image = NSImage(cgImage: result, size: CGSize(width: result.width, height: result.height))
        let sections = String(localized: "\(count) Abschnitte")
        message.stringValue = String(localized: "\(sections) · \(result.width) × \(result.height) Pixel\nPrüfe die Übergänge in der Vorschau.")
        done.isEnabled = count > 1
        undoSection.isEnabled = undoState != nil && captureTask == nil
        topInset.isEnabled = count == 1 && captureTask == nil; bottomInset.isEnabled = topInset.isEnabled
    }
    @objc private func addSection() {
        guard captureTask == nil, continuation != nil else { return }
        add.isEnabled = false; done.isEnabled = false; undoSection.isEnabled = false; topInset.isEnabled = false; bottomInset.isEnabled = false; message.stringValue = String(localized: "Abschnitt prüfen und zusammenfügen …")
        captureTask = Task { [self] in
            defer {
                captureTask = nil; add.isEnabled = true; done.isEnabled = count > 1
                undoSection.isEnabled = undoState != nil
                topInset.isEnabled = count == 1; bottomInset.isEnabled = topInset.isEnabled
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let capturedNext = try await captureFrame()
                try await Task.sleep(for: .milliseconds(220))
                let capturedStable = try await captureFrame()
                let rect = try insets.rect(width: capturedNext.width, height: capturedNext.height)
                guard let next = capturedNext.cropping(to: rect), let stable = capturedStable.cropping(to: rect),
                      capturedNext.width == firstFrame.width, capturedNext.height == firstFrame.height,
                      capturedStable.width == firstFrame.width, capturedStable.height == firstFrame.height else { throw ScrollStitchError.dimensions }
                let prior = previous, accumulated = result, sections = count
                let stitched = try await Task.detached(priority: .userInitiated) {
                    try ScrollCaptureProcessor.append(previous: prior, next: next, stable: stable, accumulated: accumulated, count: sections)
                }.value
                try Task.checkCancellation()
                guard continuation != nil else { return }
                undoState = (previous, result, count)
                previous = next; result = stitched; count += 1; updatePreview()
            } catch is CancellationError { }
            catch {
                if automatic.state == .on, let issue = error as? ScrollStitchError, issue == .unchanged || issue == .moving {
                    if continuation != nil { message.stringValue = String(localized: "Warte auf einen neuen, stillstehenden Abschnitt …") }
                    return
                }
                automatic.state = .off; toggleAutomatic()
                if continuation != nil { message.stringValue = String(localized: "Nicht hinzugefügt: \(error.localizedDescription)") }
            }
        }
    }
    @objc private func openEditor() { if captureTask == nil, count > 1 { finish(result) } }
    @objc private func cancelPressed() { cancel() }
    func cancel() { captureTask?.cancel(); finish(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    private func finish(_ image: CGImage?) {
        guard let continuation else { return }
        automaticTask?.cancel(); automaticTask = nil
        detailPanel?.close(); detailPanel = nil
        self.continuation = nil; panel.orderOut(nil); panel.close()
        continuation.resume(returning: image)
    }
}

/// A scroll session is the app's active workspace while the editor is hidden.
/// Making it main also exposes its controls to native accessibility clients.
final class ScrollCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
