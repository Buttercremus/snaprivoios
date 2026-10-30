import AppKit
import Observation
import ScreenCaptureKit
import SnagForgeDomain

@MainActor
@Observable
final class ScreenshotCoordinator {
    @ObservationIgnored var authorizeCapture: @MainActor (_ scrolling: Bool, _ video: Bool) -> Bool = { _, _ in true }
    private(set) var isBusy = false
    private(set) var status = ""
    var errorMessage: String?
    var needsPermission = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var selector: ScreenshotSelector?
    @ObservationIgnored private var scrollSession: ScrollCaptureSession?
    @ObservationIgnored private var videoSession: VideoRecordingSession?
    private(set) var isRecordingVideo = false
    var videoFiles = VideoRecordingFiles()
    var onVideoLibraryChange: (@MainActor () async -> Void)?

    @ObservationIgnored private let preflight: @MainActor () -> Bool
    @ObservationIgnored private let requestAccess: @MainActor () -> Bool
    private(set) var permissionWasRequested = false
    private(set) var needsRestart = false
    private(set) var lastSelection: ScreenshotSelection?
    private var lastSelectionScale: CGFloat?
    var hasLastSelection: Bool { lastSelection != nil }
    @ObservationIgnored var onSelectionConfirmed: (@MainActor (ScreenshotSelection) -> Void)?

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

    func start(configuration: CaptureConfiguration, requestPermission: Bool = false, scrolling: Bool = false, videoMouseClicks: Bool = false, videoAudio: VideoAudioOptions = .init(), imageOnly: Bool = false, destination: CaptureImageDestination = .image, activatesOnImageCapture: Bool = true,
               onFailure: @escaping @MainActor () -> Void = {},
               authorizeRecognition: @escaping @MainActor () -> Bool = { false },
               onRecognitionCapture: @escaping @MainActor (CGImage, Bool) -> Void = { _, _ in },
               onVideoCapture: @escaping @MainActor (URL) async -> Void = { _ in },
               onCapture: @escaping @MainActor (CGImage) -> Void) {
        guard !isBusy else { return }
        guard authorizeCapture(scrolling, configuration.media == .video) else { return }
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
                let windowsHiddenAt = ContinuousClock.now
                hiddenWindows.forEach { $0.orderOut(nil) }
                let service = ScreenshotService()
                let content = try await service.content()
                // freeze() excludes this application's windows in its SCK filter.
                // Wait for order-out only if SCK cannot identify our application.
                let excludesOwnWindows = content.applications.contains { $0.processID == ProcessInfo.processInfo.processIdentifier }
                if !hiddenWindows.isEmpty, !excludesOwnWindows {
                    try await Task.sleep(until: windowsHiddenAt.advanced(by: .milliseconds(180)), clock: .continuous)
                }
                try Task.checkCancellation()
                guard !content.displays.isEmpty else { throw ScreenshotError.noDisplays }
                let windows = service.windows(in: content)
                status = String(localized: "Bildschirm einfrieren …")
                let desktop = try await service.freeze(content, cursor: scrolling ? false : configuration.includesCursor)
                try Task.checkCancellation()
                let selectionUI = ScreenshotSelector()
                selector = selectionUI
                status = String(localized: "Fenster oder Bereich auswählen …")
                guard let selected = try await selectionUI.select(source: scrolling ? .region : configuration.source, windows: windows, desktop: desktop, media: configuration.media, allowsVideoAction: !scrolling && !imageOnly, scrolling: scrolling && !imageOnly, allowsScrolling: !imageOnly, destination: destination) else { return }
                try Task.checkCancellation()
                guard !imageOnly || (selected.media == .image && !selected.isScrolling) else { throw ScreenshotError.invalidRegion }
                if selected.destination != .image { guard authorizeRecognition() else { return } }
                if !imageOnly && selected.media == .image && !selected.isScrolling && selected.destination == .image {
                    lastSelection = selected
                    lastSelectionScale = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == selected.displayID })?.backingScaleFactor
                    onSelectionConfirmed?(selected)
                }
                let shouldScroll = selected.media == .image && selected.isScrolling
                // The selection overlay can switch an image request to video.
                guard authorizeCapture(shouldScroll, selected.media == .video) else { return }
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
                    guard authorizeCapture(false, true) else { return }
                    let session = VideoRecordingSession(selection: selected, includesCursor: configuration.includesCursor, showsMouseClicks: videoMouseClicks,
                                                        selectionOverlay: selectionUI.takeVideoOverlay(),
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
                if shouldScroll {
                    // Keep the selector's shade/frame while releasing its frozen
                    // desktop and mouse interception. The initial crop preserves
                    // the top even if scrolling begins immediately after confirming.
                    let center = CaptureGeometry.quartzPoint(fromAppKit: CGPoint(x: selected.rect.midX, y: selected.rect.midY),
                        primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
                    if let target = windows.first(where: { $0.frame.contains(center) })?.processID,
                       let app = NSRunningApplication(processIdentifier: target) {
                        app.activate(options: [])
                    }
                    try Task.checkCancellation()
                    let source = try ScrollFrameSource(selection: selected, content: content)
                    let session = ScrollCaptureSession(selection: selected, first: image,
                        overlay: selectionUI.takeScrollOverlay(), captureFrame: { try await source.capture() })
                    scrollSession = session
                    status = String(localized: "Scrollen und mit Fertig abschließen …")
                    guard let stitched = await session.run() else { return }
                    image = stitched
                    scrollSession = nil
                }
                try Task.checkCancellation()
                Self.restoreAfterImageCapture(hiddenWindows, opensEditor: selected.destination == .image && activatesOnImageCapture)
                hiddenWindows.removeAll()
                if selected.destination == .image {
                    if activatesOnImageCapture { NSApp.activate(ignoringOtherApps: true) }
                    onCapture(image)
                } else { onRecognitionCapture(image, selected.destination == .code) }
            } catch is CancellationError {
                // Escape and Cancel leave the existing editor image untouched.
            } catch {
                handleCaptureFailure(error)
                NSApp.activate(ignoringOtherApps: true)
                onFailure()
            }
        }
    }

    /// A successful quick preview/recognition must not bring its hidden editor or
    /// setup host back in front of the user's work. Cancellation still restores
    /// every original window through the capture task's defer.
    static func restoreAfterImageCapture(_ windows: [NSWindow], opensEditor: Bool) {
        for window in windows.reversed() {
            if opensEditor || (window is NSPanel && window.styleMask.contains(.nonactivatingPanel)) {
                window.orderFront(nil)
            } else {
                // SwiftUI's native window identifiers may differ from scene IDs.
                // Only floating previews/pins return after a background capture.
                window.orderOut(nil)
            }
        }
    }

    /// Re-capture the last confirmed rectangle without showing the selector.
    /// The display frame and backing scale must still match exactly.
    func repeatLast(configuration: CaptureConfiguration, onFailure: @escaping @MainActor () -> Void = {}, onCapture: @escaping @MainActor (CGImage) -> Void) {
        repeatSelection(lastSelection, expectedScale: lastSelectionScale, configuration: configuration, onFailure: onFailure, onCapture: onCapture)
    }

    func repeatSelection(_ requested: ScreenshotSelection?, expectedScale: CGFloat? = nil, configuration: CaptureConfiguration, onFailure: @escaping @MainActor () -> Void = {}, onCapture: @escaping @MainActor (CGImage) -> Void) {
        guard checkPermission(requestIfNeeded: true) else { onFailure(); return }
        guard !isBusy, let selection = requested, selection.media == .image,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == selection.displayID }),
              screen.frame == selection.screenFrame,
              expectedScale.map({ abs($0 - screen.backingScaleFactor) < 0.001 }) ?? true else { errorMessage = ScreenshotError.invalidRegion.localizedDescription; onFailure(); return }
        isBusy = true; status = String(localized: "Letzten Bereich aufnehmen …")
        task = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; status = ""; task = nil }
            do {
                let service = ScreenshotService(); let content = try await service.content()
                let desktop = try await service.freeze(content, cursor: configuration.includesCursor)
                try Task.checkCancellation(); let image = try desktop.crop(selection)
                onCapture(image)
            } catch is CancellationError { } catch { errorMessage = error.localizedDescription; onFailure() }
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
    static func append(previous: CGImage, next: CGImage, stable: CGImage? = nil, accumulated: CGImage, count: Int, allowsScrolling: Bool = false) throws -> CGImage {
        let a = try frame(previous), b = try frame(next)
        if let stable {
            let verification = try frame(stable)
            do { try ScrollStitcher.requireStable(b, verification) }
            catch ScrollStitchError.moving where allowsScrolling {
                _ = try ScrollStitcher.displacement(from: b, to: verification)
            }
        }
        let delta = try ScrollStitcher.displacement(from: a, to: b)
        let height = accumulated.height + delta
        if allowsScrolling { try ScrollStitcher.validateOutputSize(width: next.width, height: height) }
        else { try ScrollStitcher.validateSize(width: next.width, height: height, count: count + 1) }
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
final class ScrollCaptureSession: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let selection: ScreenshotSelection
    private var previous: CGImage
    private var result: CGImage
    private var firstFrame: CGImage
    private(set) var count = 1
    private(set) var isFinishing = false
    private var captureIssue: String?
    private var canRetryFinalSample = false
    private var requiresPartialConfirmation = false
    private var isChangingInsets = false
    private let captureFrame: @MainActor @Sendable () async throws -> CGImage
    private var overlay: CaptureSelectionOverlay?
    private var insets = ScrollContentInsets()
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var automaticTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var detailPanel: NSPanel?
    private let panel = ScrollCapturePanel(contentRect: CGRect(x: 0, y: 0, width: 560, height: CaptureToolbarSurface.barHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let previewPanel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 172, height: 236), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let preview = NSImageView(frame: CGRect(x: 8, y: 28, width: 156, height: 200))
    private let message = NSTextField(labelWithString: "")
    private let dimensions = NSTextField(labelWithString: "")
    private let done = CaptureFlatButton(frame: .zero)
    private let options = CaptureFlatButton(frame: .zero)

    init(selection: ScreenshotSelection, first: CGImage, overlay: CaptureSelectionOverlay? = nil, captureFrame: (@MainActor @Sendable () async throws -> CGImage)? = nil) {
        self.captureFrame = captureFrame ?? { try await ScreenshotService().scrollFrame(selection) }
        self.overlay = overlay
        self.selection = selection; previous = first; result = first; firstFrame = first
        super.init()
    }
    func run() async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            panel.title = String(localized: "Scroll-Aufnahme")
            panel.level = CaptureSelectionOverlay.controlsLevel; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.setAccessibilityIdentifier("scroll.controls")
            let surface = CaptureToolbarSurface(frame: CGRect(x: 0, y: 0, width: 560, height: CaptureToolbarSurface.barHeight), subdued: true)
            panel.contentView = surface
            let body = surface.controls
            done.frame = CGRect(x: 10, y: 10, width: 88, height: CaptureToolbarSurface.controlHeight)
            done.title = String(localized: "Fertig")
            CaptureToolbarSurface.styleFlat(done, prominent: true)
            done.target = self; done.action = #selector(openEditor); done.keyEquivalent = "\r"
            done.setAccessibilityIdentifier("scroll.finish"); body.addSubview(done)
            body.addSubview(CaptureToolbarSurface.divider(frame: CGRect(x: 108, y: 12, width: 1, height: 32)))
            message.frame = CGRect(x: 120, y: 29, width: 326, height: 17)
            message.font = .systemFont(ofSize: 12, weight: .medium); message.textColor = .white
            message.lineBreakMode = .byTruncatingTail
            message.setAccessibilityIdentifier("scroll.status"); body.addSubview(message)
            dimensions.frame = CGRect(x: 120, y: 11, width: 326, height: 14)
            dimensions.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            dimensions.textColor = NSColor.white.withAlphaComponent(0.68); body.addSubview(dimensions)
            body.addSubview(CaptureToolbarSurface.divider(frame: CGRect(x: 452, y: 12, width: 1, height: 32)))
            options.frame = CGRect(x: 462, y: 10, width: 36, height: CaptureToolbarSurface.controlHeight)
            CaptureToolbarSurface.styleFlat(options); options.title = ""; options.imagePosition = .imageOnly
            options.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
            options.target = self; options.action = #selector(showOptions(_:)); options.menu = NSMenu()
            options.menu?.delegate = self
            options.setAccessibilityLabel(String(localized: "Optionen für die Scroll-Aufnahme"))
            options.setAccessibilityIdentifier("scroll.options"); body.addSubview(options)
            let cancel = CaptureFlatButton(frame: CGRect(x: 508, y: 10, width: 36, height: CaptureToolbarSurface.controlHeight))
            cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            cancel.target = self; cancel.action = #selector(cancelPressed)
            CaptureToolbarSurface.styleFlat(cancel)
            cancel.keyEquivalent = "\u{1b}"; cancel.toolTip = String(localized: "Abbrechen (Esc)")
            cancel.setAccessibilityLabel(String(localized: "Abbrechen")); cancel.setAccessibilityIdentifier("scroll.cancel"); body.addSubview(cancel)
            if overlay == nil { overlay = CaptureSelectionOverlay(selection: selection) }
            configurePreview()
            updatePreview()
            let screen = selection.screenFrame
            let width = panel.frame.width, height = panel.frame.height
            let x = min(max(selection.rect.midX - width / 2, screen.minX + 12), screen.maxX - width - 12)
            let below = selection.rect.minY - height - 12, above = selection.rect.maxY + 12
            let y = below >= screen.minY + 12 ? below : above + height <= screen.maxY - 12 ? above : screen.minY + 12
            panel.setFrameOrigin(CGPoint(x: x, y: y))
            panel.makeKeyAndOrderFront(nil); panel.makeMain(); panel.makeFirstResponder(done)
            startAutomatic()
        }
    }
    private func configurePreview() {
        previewPanel.title = String(localized: "Vorschau")
        previewPanel.level = CaptureSelectionOverlay.controlsLevel; previewPanel.hidesOnDeactivate = false; previewPanel.isReleasedWhenClosed = false
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        previewPanel.setAccessibilityIdentifier("scroll.preview")
        let body = NSView(frame: CGRect(x: 0, y: 0, width: 172, height: 236))
        body.wantsLayer = true; body.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        body.layer?.cornerRadius = 10; body.layer?.masksToBounds = true
        preview.imageScaling = .scaleProportionallyDown
        preview.setAccessibilityLabel(String(localized: "Wachsende Vorschau der Scroll-Aufnahme"))
        body.addSubview(preview)
        let title = NSTextField(labelWithString: String(localized: "Vorschau"))
        title.frame = CGRect(x: 8, y: 6, width: 156, height: 18); title.alignment = .center; title.font = .systemFont(ofSize: 11)
        body.addSubview(title); previewPanel.contentView = body
        let screen = selection.screenFrame
        let right = selection.rect.maxX + 12, left = selection.rect.minX - 184
        let x = right + 172 <= screen.maxX - 12 ? right : left >= screen.minX + 12 ? left : screen.maxX - 184
        previewPanel.setFrameOrigin(CGPoint(x: x, y: max(screen.minY + 100, min(selection.rect.minY, screen.maxY - 248))))
        previewPanel.orderFrontRegardless()
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.autoenablesItems = false
        menu.removeAllItems()
        func item(_ title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            menu.addItem(item); return item
        }
        let restart = item(String(localized: "Neu beginnen"), action: #selector(restartCapture))
        restart.isEnabled = captureTask == nil && !isFinishing
        for top in [true, false] {
            let parent = NSMenuItem(title: top ? String(localized: "Oben auslassen") : String(localized: "Unten auslassen"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for value in 0...4 {
                let choice = NSMenuItem(title: "\(value * 5) %", action: top ? #selector(changeTopInset(_:)) : #selector(changeBottomInset(_:)), keyEquivalent: "")
                choice.target = self; choice.tag = value * 5
                choice.state = choice.tag == (top ? insets.topPercent : insets.bottomPercent) ? .on : .off
                choice.isEnabled = count == 1 && !isChangingInsets && !isFinishing
                submenu.addItem(choice)
            }
            parent.submenu = submenu; menu.addItem(parent)
        }
        menu.addItem(.separator())
        _ = item(String(localized: "Vorschau in Originalgröße"), action: #selector(inspectResult))
    }
    @objc private func showOptions(_ sender: NSButton) {
        options.menu?.popUp(positioning: nil, at: CGPoint(x: sender.frame.minX, y: sender.frame.minY), in: panel.contentView)
    }
    @objc private func changeTopInset(_ sender: NSMenuItem) { changeInsets(top: sender.tag, bottom: insets.bottomPercent) }
    @objc private func changeBottomInset(_ sender: NSMenuItem) { changeInsets(top: insets.topPercent, bottom: sender.tag) }
    private func changeInsets(top: Int, bottom: Int) {
        guard count == 1, !isChangingInsets, !isFinishing else { return }
        let next = ScrollContentInsets(topPercent: top, bottomPercent: bottom)
        isChangingInsets = true; done.isEnabled = false
        automaticTask?.cancel(); captureTask?.cancel()
        Task { [self] in
            await captureTask?.value
            defer {
                isChangingInsets = false
                if continuation != nil, !isFinishing { done.isEnabled = true; startAutomatic() }
            }
            guard continuation != nil, !isFinishing,
                  let rect = try? next.rect(width: firstFrame.width, height: firstFrame.height),
                  let cropped = firstFrame.cropping(to: rect) else { return }
            insets = next; previous = cropped; result = cropped
            captureIssue = nil; canRetryFinalSample = false; requiresPartialConfirmation = false; done.title = String(localized: "Fertig")
            updatePreview()
        }
    }
    private func startAutomatic() {
        automaticTask?.cancel()
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, continuation != nil, !isFinishing, !isChangingInsets else { return }
                if captureTask == nil { beginSample() }
                await captureTask?.value
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            }
        }
    }
    private func beginSample() {
        guard captureTask == nil, continuation != nil else { return }
        captureTask = Task { [self] in
            defer { captureTask = nil }
            do {
                let capturedNext = try await captureFrame()
                let rect = try insets.rect(width: capturedNext.width, height: capturedNext.height)
                guard capturedNext.width == firstFrame.width, capturedNext.height == firstFrame.height,
                      let next = capturedNext.cropping(to: rect) else { throw ScrollStitchError.dimensions }
                let prior = previous, accumulated = result, sections = count
                let stitched = try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    // A matched translation of the overlap is the verification.
                    // Waiting for a second stationary frame loses live scrolling.
                    return try ScrollCaptureProcessor.append(previous: prior, next: next, accumulated: accumulated, count: sections, allowsScrolling: true)
                }.value
                try Task.checkCancellation()
                guard continuation != nil else { return }
                previous = next; result = stitched; count += 1; captureIssue = nil; canRetryFinalSample = false; updatePreview()
            } catch is CancellationError { }
            catch let issue as ScrollStitchError {
                guard continuation != nil else { return }
                captureIssue = issue == .unchanged ? nil : issue.localizedDescription
                canRetryFinalSample = issue == .uncertain || issue == .moving || issue == .fixedContent
                guard !isFinishing else { return }
                switch issue {
                case .unchanged, .moving:
                    message.stringValue = String(localized: "Langsam nach unten scrollen · Dann Fertig.")
                case .uncertain:
                    message.stringValue = String(localized: "Scrolle etwas zurück und langsamer weiter.")
                case .fixedContent:
                    automaticTask?.cancel()
                    message.stringValue = String(localized: "Feste Kopf- oder Fußzeile: Wähle nur den scrollenden Inhalt.")
                case .dimensions, .limit:
                    automaticTask?.cancel(); message.stringValue = issue.localizedDescription
                }
            } catch {
                guard continuation != nil else { return }
                captureIssue = error.localizedDescription
                canRetryFinalSample = false
                guard !isFinishing else { return }
                automaticTask?.cancel()
                message.stringValue = String(localized: "Scroll-Aufnahme unterbrochen: \(error.localizedDescription)")
            }
        }
    }
    private func updatePreview() {
        preview.image = NSImage(cgImage: result, size: CGSize(width: result.width, height: result.height))
        dimensions.stringValue = String(localized: "\(result.width) × \(result.height) Pixel · Wird automatisch zusammengefügt")
        if !isFinishing {
            message.stringValue = String(localized: "Langsam nach unten scrollen · Dann Fertig.")
            message.toolTip = nil
        }
    }
    @objc private func restartCapture() {
        guard captureTask == nil, continuation != nil, !isFinishing else { return }
        automaticTask?.cancel()
        captureTask = Task { [self] in
            defer { captureTask = nil; if continuation != nil { startAutomatic() } }
            do {
                let image = try await captureFrame()
                try Task.checkCancellation()
                let rect = try insets.rect(width: image.width, height: image.height)
                guard let cropped = image.cropping(to: rect) else { throw ScrollStitchError.dimensions }
                firstFrame = image; previous = cropped; result = cropped; count = 1
                captureIssue = nil; canRetryFinalSample = false; requiresPartialConfirmation = false; done.title = String(localized: "Fertig"); updatePreview()
            } catch { if continuation != nil { message.stringValue = error.localizedDescription } }
        }
    }
    @objc private func inspectResult() {
        detailPanel?.close()
        let detail = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        detail.title = String(localized: "Scroll-Aufnahme · Originalgröße"); detail.isReleasedWhenClosed = false; detail.level = CaptureSelectionOverlay.controlsLevel
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let image = NSImageView(frame: CGRect(x: 0, y: 0, width: result.width, height: result.height))
        image.image = NSImage(cgImage: result, size: image.frame.size); image.imageScaling = .scaleNone
        scroll.documentView = image; detail.contentView = scroll; detail.center(); detail.makeKeyAndOrderFront(nil); detailPanel = detail
    }
    @objc private func openEditor() {
        guard continuation != nil, !isFinishing, !isChangingInsets else { return }
        if requiresPartialConfirmation { finish(result); return }
        isFinishing = true; done.isEnabled = false; options.isEnabled = false
        message.stringValue = String(localized: "Scroll-Aufnahme abschließen …")
        automaticTask?.cancel()
        Task { [self] in
            await captureTask?.value
            guard continuation != nil else { return }
            // A click can arrive during momentum/overscroll or an unsettled
            // browser repaint. Retry only matching failures, for a bounded time;
            // unchanged content is already included and completes immediately.
            for attempt in 0..<4 {
                if attempt > 0 {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                }
                guard continuation != nil else { return }
                beginSample(); await captureTask?.value
                guard captureIssue != nil, canRetryFinalSample else { break }
            }
            guard continuation != nil else { return }
            if let captureIssue {
                isFinishing = false; requiresPartialConfirmation = true
                done.title = String(localized: "Übernehmen"); done.isEnabled = true; options.isEnabled = true
                message.stringValue = String(localized: "Ende unklar. Übernehmen öffnet das bisherige Bild.")
                message.toolTip = captureIssue
                return
            }
            finish(result)
        }
    }
    @objc private func cancelPressed() { cancel() }
    func cancel() { captureTask?.cancel(); finish(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    private func finish(_ image: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil; automaticTask?.cancel(); automaticTask = nil
        detailPanel?.close(); detailPanel = nil
        overlay?.close(); overlay = nil
        previewPanel.orderOut(nil); previewPanel.close(); panel.orderOut(nil); panel.close()
        continuation.resume(returning: image)
    }
}

/// A scroll session is the app's active workspace while the editor is hidden.
/// Making it main also exposes its controls to native accessibility clients.
final class ScrollCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
