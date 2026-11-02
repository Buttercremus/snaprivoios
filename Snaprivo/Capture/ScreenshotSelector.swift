import AppKit
import QuartzCore
import SnagForgeDomain

@MainActor
final class ScreenshotSelector {
    private var panels: [NSPanel] = []
    private var views: [SelectionView] = []
    private weak var reviewView: SelectionView?
    private var continuation: CheckedContinuation<ScreenshotSelection?, Never>?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []
    private var mode = CaptureSource.automatic
    private var candidates: [CapturableWindow] = []
    private var hovered: CapturableWindow?
    private var primaryHeight: CGFloat = 0
    private var isFinishing = false
    private var scrollOverlay: CaptureSelectionOverlay?
    private var videoOverlay: CaptureSelectionOverlay?

    func select(source: CaptureSource, windows: [CapturableWindow], desktop: FrozenDesktop, media: CaptureMedia = .image, allowsVideoAction: Bool = true, scrolling: Bool = false, allowsScrolling: Bool = true, destination: CaptureImageDestination = .image, confirmsImmediately: Bool = false) async throws -> ScreenshotSelection? {
        let screens = NSScreen.screens
        let screenChoices = screens.compactMap { screen -> CaptureScreenChoice? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return CaptureScreenChoice(id: id, name: screen.localizedName, frame: screen.frame)
        }
        guard desktop.displays.count == screens.count, screens.allSatisfy({ screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return desktop.displays.contains { $0.displayID == id && $0.screenFrame == screen.frame }
        }) else { throw ScreenshotError.invalidRegion }
        // Screenshot aliases keep the shared selector; video retains its source choice.
        mode = media == .image && source == .window ? .automatic : source
        candidates = windows
        primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // The panels manage their own keyboard focus. Avoid explicitly activating
        // Snaprivo, which can bring its Space / Stage Manager set forward.
        hideAppWindows()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in screens {
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                      let frozen = desktop.displays.first(where: { $0.displayID == id }) else { continue }
                let panel = SelectionPanel(screenFrame: screen.frame)
                panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.acceptsMouseMovedEvents = true
                let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.screenFrame = screen.frame
                view.displayID = id; view.screenChoices = screenChoices
                view.onSelectScreen = { [weak self, weak view] displayID in
                    guard let self, let view else { return }
                    self.selectScreen(displayID, keeping: view)
                }
                view.onSelectSource = { [weak self, weak view] source in
                    guard let self, let view else { return }
                    self.selectSource(source, keeping: view)
                }
                view.frozenImage = frozen.image
                view.pixelScale = frozen.scale
                view.mode = mode
                view.allowsVideoAction = allowsVideoAction
                view.allowsScrolling = allowsScrolling
                view.isVideo = media == .video
                view.isScrolling = scrolling
                view.confirmsImmediately = confirmsImmediately
                view.imageDestination = destination
                view.onDestinationChange = { [weak self] value in
                    self?.views.forEach { $0.imageDestination = value }
                }
                view.onMediaChange = { [weak self] video in
                    self?.views.forEach { $0.isVideo = video }
                }
                view.setAccessibilityElement(true)
                view.setAccessibilityRole(.group)
                view.setAccessibilityLabel(media == .video ? String(localized: "Video-Auswahl") : String(localized: "Screenshot aufnehmen"))
                view.onHover = { [weak self] point in self?.hover(at: point) }
                view.onDragStart = { [weak self] in
                    self?.hovered = nil
                    self?.views.forEach { $0.highlight = nil; $0.needsDisplay = true }
                }
                view.onPropose = { [weak self, weak view, weak panel] rect in
                    guard let self, let view else { return }
                    let draft: CaptureSelectionDraft
                    if let rect {
                        draft = CaptureSelectionDraft(rect: rect)
                    } else if let hovered = self.hovered {
                        let windowRect = CaptureGeometry.appKitRect(fromQuartz: hovered.frame, primaryHeight: self.primaryHeight)
                        draft = CaptureSelectionDraft(rect: windowRect.intersection(screen.frame), windowID: hovered.id)
                    } else { return }
                    self.review(draft, in: view)
                    panel?.makeKey()
                    panel?.makeFirstResponder(view)
                }
                view.onConfirm = { [weak self, weak view] draft in
                    self?.finish(ScreenshotSelection(displayID: id, draft: draft, screenFrame: screen.frame, media: view?.isVideo == true ? .video : .image, isScrolling: view?.isScrolling == true, destination: view?.imageDestination ?? .image))
                }
                view.onRestart = { [weak self] in self?.restart() }
                view.onCancel = { [weak self] in self?.finish(nil) }
                panel.contentView = view
                panels.append(panel)
                views.append(view)
            }
            guard !panels.isEmpty else { finish(nil); return }
            // Draw the desktop, shade and first frame together. Starting either
            // chrome or hover fades here delays feedback after New Capture.
            hover(at: NSEvent.mouseLocation)
            views.forEach { $0.preparePresentation() }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                panels.forEach { $0.orderFrontRegardless(); $0.displayIfNeeded() }
            }
            let active = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels[0]
            active.makeKey()
            active.makeFirstResponder(active.contentView)
            refreshCursorAtMouseLocation()
            // Ordering/focus can enqueue a final AppKit cursor reset. Reapply
            // once after that handoff, even if the pointer has already stopped.
            DispatchQueue.main.async { [weak self] in self?.refreshCursorAtMouseLocation() }
            for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
                focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let changedWindow = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        if let changedWindow, changedWindow.level.rawValue >= NSWindow.Level.statusBar.rawValue { return }
                        if self?.reviewView?.isEditingSize == true { return }
                        self?.hideAppWindows()
                        let panel = self?.reviewView?.window ?? self?.panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                        panel?.makeKey()
                        panel?.makeFirstResponder(panel?.contentView)
                        self?.refreshCursorAtMouseLocation()
                    }
                })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if let view = self?.reviewView, view.isEditingSize {
                    if event.keyCode == 53 { view.dismissSizeEditor(); return nil }
                    return event
                }
                if event.keyCode == 53 { self?.finish(nil); return nil }
                if (event.keyCode == 36 || event.keyCode == 76), self?.reviewView != nil {
                    self?.reviewView?.confirm(); return nil
                }
                return event
            }
            let layout = Self.screenLayout()
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if Self.screenLayout() != layout { self?.finish(nil, animated: false) }
                }
            }
        }
    }

    func cancel() {
        finish(nil)
        scrollOverlay?.close(); scrollOverlay = nil
        videoOverlay?.close(); videoOverlay = nil
    }

    func takeScrollOverlay() -> CaptureSelectionOverlay? {
        defer { scrollOverlay = nil }
        return scrollOverlay
    }

    func takeVideoOverlay() -> CaptureSelectionOverlay? {
        defer { videoOverlay = nil }
        return videoOverlay
    }

    private func refreshCursorAtMouseLocation() {
        guard !isFinishing else { return }
        let panel = panels.first { $0.frame.contains(NSEvent.mouseLocation) }
        (panel?.contentView as? SelectionView)?.refreshCursorAtMouseLocation()
    }

    private func hideAppWindows() {
        NSApp.windows.filter { $0.isVisible && $0.level.rawValue < NSWindow.Level.statusBar.rawValue }.forEach { $0.orderOut(nil) }
    }

    private static func screenLayout() -> [String] {
        NSScreen.screens.map {
            "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? ""):\($0.frame):\($0.backingScaleFactor)"
        }
    }

    private func restart() {
        guard !isFinishing else { return }
        reviewView = nil
        views.forEach { $0.isReviewing = false; $0.reviewDraft = nil; $0.highlight = nil }
        hover(at: NSEvent.mouseLocation)
    }

    private func review(_ draft: CaptureSelectionDraft, in view: SelectionView) {
        reviewView = view
        for candidate in views {
            candidate.isReviewing = true; candidate.highlight = nil
            candidate.reviewDraft = candidate === view ? draft : nil
        }
        NSAccessibility.post(element: view, notification: .valueChanged)
    }

    private func selectScreen(_ id: CGDirectDisplayID, keeping source: SelectionView) {
        guard !isFinishing, let target = views.first(where: { $0.displayID == id }) else { return }
        source.dismissSizeEditor()
        target.isVideo = source.isVideo; target.isScrolling = source.isScrolling
        review(CaptureSelectionDraft(rect: target.screenFrame), in: target)
        target.window?.makeKey(); target.window?.makeFirstResponder(target)
    }

    private func selectSource(_ source: CaptureSource, keeping view: SelectionView) {
        guard !isFinishing, source != .display else { return }
        view.dismissSizeEditor()
        mode = source
        views.forEach { $0.mode = source }
        if source == .region, let draft = view.reviewDraft {
            review(CaptureSelectionDraft(rect: draft.rect), in: view)
        } else if source == .window {
            restart()
        }
        view.window?.makeKey(); view.window?.makeFirstResponder(view)
    }

    private func hover(at point: CGPoint) {
        guard !isFinishing, reviewView == nil, !views.contains(where: { $0.isSelectingRegion }) else { return }
        let quartz = CaptureGeometry.quartzPoint(fromAppKit: point, primaryHeight: primaryHeight)
        hovered = mode == .window || mode == .automatic ? candidates.first(where: { $0.frame.contains(quartz) }) : nil
        for view in views {
            view.setHoveredWindow(hovered.map { CaptureGeometry.appKitRect(fromQuartz: $0.frame, primaryHeight: primaryHeight) })
            view.caption = switch mode {
            case .automatic:
                hovered.map { String(localized: "\($0.applicationName ?? String(localized: "Fenster")) auswählen: Klicken · Freier Bereich: Ziehen · Esc: Abbrechen") }
                    ?? String(localized: "Freien Bereich aufziehen · Esc: Abbrechen")
            case .window:
                hovered.map { String(localized: "\($0.applicationName ?? String(localized: "Fenster")) auswählen: Klicken · Esc: Abbrechen") }
                    ?? String(localized: "Kein aufnehmbares Fenster · Esc: Abbrechen")
            case .region: String(localized: "Freien Bereich aufziehen · Esc: Abbrechen")
            case .display: String(localized: "Bildschirm auswählen: Klicken · Esc: Abbrechen")
            }
        }
    }

    private func finish(_ result: ScreenshotSelection?, animated: Bool = true) {
        guard continuation != nil, !isFinishing else { return }
        isFinishing = true
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        views.forEach { $0.isFinishing = true }
        if result?.isScrolling == true || result?.media == .video {
            // Transfer these exact windows, shade and selection chrome. Only the
            // selected content goes live while the source app/capture prepares.
            let overlay = CaptureSelectionOverlay(panels: panels, views: views,
                identifierPrefix: result?.media == .video ? "video.selection" : "scroll")
            if result?.media == .video { videoOverlay = overlay }
            else { scrollOverlay = overlay }
            panels.removeAll(); views.removeAll()
            completeFinish(result)
            return
        }
        // Confirmed photos can start encoding/opening immediately. Cancellation
        // keeps the gentle fade back to the desktop.
        if animated, result == nil, panels.contains(where: \.isVisible) {
            CaptureOverlayMotion.animate({ self.views.forEach { $0.setChromeVisible(false) } }) { [weak self] in
                self?.completeFinish(result)
            }
        } else {
            completeFinish(result)
        }
    }

    private func completeFinish(_ result: ScreenshotSelection?) {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        views.removeAll()
        reviewView = nil
        let pending = continuation
        continuation = nil
        isFinishing = false
        pending?.resume(returning: result)
    }
}

extension CaptureSelectionOverlay {
    convenience init(panels: [NSPanel], views: [SelectionView], identifierPrefix: String = "scroll") {
        self.init(panels: panels)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0; context.allowsImplicitAnimation = false
            for (panel, view) in zip(panels, views) {
                panel.isOpaque = false; panel.backgroundColor = .clear
                panel.ignoresMouseEvents = true; panel.resignKey()
                panel.setAccessibilityIdentifier(identifierPrefix + (view.reviewDraft == nil ? ".mask" : ".border"))
                panel.setAccessibilityElement(false)
                view.prepareForLiveCapture()
                panel.displayIfNeeded()
            }
        }
    }

    convenience init(selection: ScreenshotSelection) {
        let panel = SelectionPanel(screenFrame: selection.screenFrame)
        panel.level = Self.level
        let view = SelectionView(frame: CGRect(origin: .zero, size: selection.screenFrame.size))
        view.screenFrame = selection.screenFrame; view.isReviewing = true
        view.reviewDraft = CaptureSelectionDraft(rect: selection.rect)
        panel.contentView = view
        self.init(panels: [panel], views: [view])
        panel.orderFrontRegardless()
    }

}

@MainActor
private enum CaptureOverlayMotion {
    static func animate(_ changes: () -> Void, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.10 : 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}

/// Presentation geometry only. The hit-tested target changes immediately and
/// never comes from an intermediate animation frame.
struct CaptureHoverHighlight {
    struct Presentation: Equatable {
        var rect: CGRect?
        var visibility: CGFloat
    }
    private struct Transition {
        let from: Presentation
        let to: Presentation
        let start: CFTimeInterval
        let duration: CFTimeInterval

        func value(at time: CFTimeInterval) -> Presentation {
            let progress = min(1, max(0, (time - start) / duration))
            if progress >= 1 { return to }
            // Cubic ease-out: immediate response, gentle settling, no overshoot.
            let amount = CGFloat(1 - pow(1 - progress, 3))
            let startRect = from.rect ?? to.rect
            let endRect = to.rect ?? from.rect
            let rect = startRect.flatMap { a in
                endRect.map { b in
                    CGRect(x: a.minX + (b.minX - a.minX) * amount,
                           y: a.minY + (b.minY - a.minY) * amount,
                           width: a.width + (b.width - a.width) * amount,
                           height: a.height + (b.height - a.height) * amount)
                }
            }
            return Presentation(rect: rect, visibility: from.visibility + (to.visibility - from.visibility) * amount)
        }
    }
    static let movementDuration: CFTimeInterval = 0.18
    static let fadeDuration: CFTimeInterval = 0.10
    private(set) var target: CGRect?
    private var settled = Presentation(rect: nil, visibility: 0)
    private var transition: Transition?
    var isAnimating: Bool { transition != nil }

    func presentation(at time: CFTimeInterval) -> Presentation { transition?.value(at: time) ?? settled }

    @discardableResult
    mutating func setTarget(_ rect: CGRect?, within display: CGRect, at time: CFTimeInterval, animated: Bool) -> Bool {
        // Mouse movement within the same window must not restart the transition.
        guard target != rect || (!animated && isAnimating) else { return false }
        let current = presentation(at: time)
        target = rect
        let visibleRect = rect.flatMap { $0.intersection(display).isEmpty ? nil : $0 }
        let destination = Presentation(rect: visibleRect, visibility: visibleRect == nil ? 0 : 1)
        settled = destination
        if animated, current != destination {
            transition = Transition(from: current, to: destination, start: time,
                duration: current.rect != nil && destination.rect != nil ? Self.movementDuration : Self.fadeDuration)
        } else { transition = nil }
        return true
    }

    mutating func advance(to time: CFTimeInterval) {
        if let transition, time >= transition.start + transition.duration { self.transition = nil }
    }

    mutating func freeze(at time: CFTimeInterval) {
        settled = presentation(at: time)
        transition = nil
    }
}

final class SelectionPanel: NSPanel {
    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // A desktop-sized snapshot must appear at its final size immediately;
        // AppKit's inferred order-in/out animation otherwise looks like a zoom.
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        // A transparent NSView must never start native window dragging instead
        // of delivering the capture gesture to its content view.
        isMovable = false
        isMovableByWindowBackground = false
        // Fully transparent window areas can pass through at the window server,
        // even when NSView.hitTest returns this view. Keep every pixel covered.
        isOpaque = true
        backgroundColor = .black
        ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func becomeKey() {
        super.becomeKey()
        (contentView as? SelectionView)?.refreshCursorAtMouseLocation()
    }
}

@MainActor
final class SelectionView: NSView {
    var screenFrame = CGRect.zero
    var displayID: CGDirectDisplayID = 0
    var screenChoices: [CaptureScreenChoice] = []
    var onSelectScreen: ((CGDirectDisplayID) -> Void)?
    var onSelectSource: ((CaptureSource) -> Void)?
    var frozenImage: CGImage? {
        didSet {
            backgroundImage = frozenImage.map { NSImage(cgImage: $0, size: bounds.size) }
            needsDisplay = true
        }
    }
    var pixelScale: CGFloat?
    private var backgroundImage: NSImage?
    var mode = CaptureSource.automatic { didSet { updateReview() } }
    var allowsVideoAction = true
    var allowsScrolling = true
    var isScrolling = false
    /// The selecting gesture also confirms a photo; ⌥ on release keeps the bar for adjustments.
    var confirmsImmediately = false
    private var capturesOnRelease: Bool { confirmsImmediately && !isVideo && !isScrolling && !keepsReview }
    /// Once the bar was requested with ⌥ or is showing, later gestures of this selection keep it.
    private var keepsReview = false
    var imageDestination: CaptureImageDestination = .image { didSet { updateReview() } }
    var onDestinationChange: ((CaptureImageDestination) -> Void)?
    var onMediaChange: ((Bool) -> Void)?
    var isVideo = false {
        didSet {
            setAccessibilityLabel(isVideo ? String(localized: "Video-Auswahl") : String(localized: "Screenshot aufnehmen"))
            updateReview()
        }
    }
    private var hoverHighlight = CaptureHoverHighlight()
    private var hoverDisplayLink: CADisplayLink?
    var highlight: CGRect? {
        get { hoverHighlight.target }
        set { setHoveredWindow(newValue, animated: false) }
    }
    var caption = String(localized: "Freien Bereich aufziehen · Esc: Abbrechen") {
        didSet {
            if caption != oldValue { setAccessibilityValue(caption); chrome.needsDisplay = true }
        }
    }
    var onHover: ((CGPoint) -> Void)?
    var onDragStart: (() -> Void)?
    var onPropose: ((CGRect?) -> Void)?
    var onConfirm: ((CaptureSelectionDraft) -> Void)?
    var onRestart: (() -> Void)?
    var onCancel: (() -> Void)?
    var isReviewing = false {
        didSet {
            if isReviewing { setHoveredWindow(highlight, animated: false) }
            chrome.needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var isFinishing = false {
        didSet {
            if isFinishing {
                hoverHighlight.freeze(at: CACurrentMediaTime())
                stopHoverDisplayLink()
                chrome.needsDisplay = true
            }
        }
    }
    var reviewDraft: CaptureSelectionDraft? { didSet { updateReview() } }
    private var start: CGPoint?
    private var isDragging = false
    private var adjustment: (start: CGPoint, draft: CaptureSelectionDraft, handle: CaptureSelectionHandle?)?
    private var toolbar: CaptureReviewToolbar?
    private let chrome = CaptureSelectionChrome()
    private var sizePopover: NSPopover?
    var isEditingSize: Bool { sizePopover?.isShown == true }
    private(set) var isLiveCapture = false
    var isSelectingRegion: Bool { start != nil && isDragging }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { !isLiveCapture }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chrome.owner = self
        chrome.frame = bounds
        chrome.autoresizingMask = [.width, .height]
        chrome.wantsLayer = true
        chrome.setAccessibilityElement(false)
        addSubview(chrome)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHoveredWindow(_ rect: CGRect?, animated: Bool = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                          at time: CFTimeInterval = CACurrentMediaTime()) {
        let animates = animated && !isReviewing && !isFinishing && !isSelectingRegion
        guard hoverHighlight.setTarget(rect, within: screenFrame, at: time, animated: animates) else { return }
        chrome.needsDisplay = true
        if hoverHighlight.isAnimating {
            if hoverDisplayLink == nil {
                let driver = CaptureHoverFrameDriver(view: self)
                let link = displayLink(target: driver, selector: #selector(CaptureHoverFrameDriver.tick(_:)))
                hoverDisplayLink = link
                link.add(to: .main, forMode: .common)
            }
        } else { stopHoverDisplayLink() }
    }

    func hoverPresentation(at time: CFTimeInterval = CACurrentMediaTime()) -> CaptureHoverHighlight.Presentation {
        hoverHighlight.presentation(at: time)
    }

    fileprivate func advanceHoverAnimation() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { setHoveredWindow(highlight, animated: false); return }
        hoverHighlight.advance(to: CACurrentMediaTime())
        chrome.needsDisplay = true
        if !hoverHighlight.isAnimating { stopHoverDisplayLink() }
    }

    private func stopHoverDisplayLink() {
        hoverDisplayLink?.invalidate()
        hoverDisplayLink = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopHoverDisplayLink(); dismissSizeEditor() }
        super.viewWillMove(toWindow: newWindow)
    }

    func preparePresentation() {
        setHoveredWindow(highlight, animated: false)
        chrome.alphaValue = 1
        toolbar?.alphaValue = 1
        chrome.needsDisplay = true
    }
    func prepareForLiveCapture() {
        dismissSizeEditor()
        isLiveCapture = true
        isFinishing = true
        toolbar?.removeFromSuperview(); toolbar = nil
        chrome.alphaValue = 1; chrome.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    func setChromeVisible(_ visible: Bool) {
        chrome.animator().alphaValue = visible ? 1 : 0
        toolbar?.animator().alphaValue = visible ? 1 : 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect], owner: self))
    }

    private static let captureCursor: NSCursor = {
        let image = NSImage(size: CGSize(width: 40, height: 40), flipped: false) { _ in
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: 3, y: 20)); cross.line(to: CGPoint(x: 13, y: 20))
            cross.move(to: CGPoint(x: 27, y: 20)); cross.line(to: CGPoint(x: 37, y: 20))
            cross.move(to: CGPoint(x: 20, y: 3)); cross.line(to: CGPoint(x: 20, y: 13))
            cross.move(to: CGPoint(x: 20, y: 27)); cross.line(to: CGPoint(x: 20, y: 37))
            cross.appendOval(in: CGRect(x: 15, y: 15, width: 10, height: 10))
            NSColor.black.setStroke(); cross.lineWidth = 5; cross.stroke()
            NSColor.white.setStroke(); cross.lineWidth = 3; cross.stroke()
            NSColor.systemOrange.setStroke(); cross.lineWidth = 1.5; cross.stroke()
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: CGRect(x: 19, y: 19, width: 2, height: 2)).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 20, y: 20))
    }()
    override func resetCursorRects() {
        guard !isFinishing, !isLiveCapture else { return }
        if start != nil || adjustment != nil {
            addCursorRect(bounds, cursor: selectionCursor(at: .zero))
            return
        }
        addCursorRect(bounds, cursor: Self.captureCursor)
        if let draft = reviewDraft {
            let local = localRect(draft.rect)
            for edge in moveEdges(in: local) { addCursorRect(edge, cursor: .openHand) }
            for handle in CaptureSelectionHandle.allCases {
                addCursorRect(handleRect(handle, in: local), cursor: Self.resizeCursor(handle))
            }
        }
        if let toolbar { addCursorRect(toolbar.frame, cursor: .arrow) }
    }
    override func cursorUpdate(with event: NSEvent) {
        guard !isFinishing, !isLiveCapture else { return }
        selectionCursor(at: convert(event.locationInWindow, from: nil)).set()
    }
    func refreshCursorAtMouseLocation() {
        guard !isFinishing, !isLiveCapture, !isEditingSize,
              let window, window.isVisible else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return }
        selectionCursor(at: point).set()
    }
    override func mouseEntered(with event: NSEvent) {
        cursorUpdate(with: event)
    }
    func selectionCursor(at point: CGPoint) -> NSCursor {
        if let adjustment { return adjustment.handle.map(Self.resizeCursor) ?? .openHand }
        if start != nil { return Self.captureCursor }
        if let toolbar, toolbar.frame.contains(point) { return .arrow }
        if let draft = reviewDraft {
            let local = localRect(draft.rect)
            if let handle = selectionHandle(at: point, in: local) {
                return Self.resizeCursor(handle)
            }
            if moveEdges(in: local).contains(where: { $0.contains(point) }) { return .openHand }
        }
        return Self.captureCursor
    }
    private static func resizeCursor(_ handle: CaptureSelectionHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch handle {
        case .top: .top
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .left: .left
        case .right: .right
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    private func localRect(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }
    private func handleRect(_ handle: CaptureSelectionHandle, in rect: CGRect) -> CGRect {
        SelectionGrips.hitRect(at: handle.point(in: rect), shape: handle.gripShape)
    }
    private func selectionHandle(at point: CGPoint, in rect: CGRect) -> CaptureSelectionHandle? {
        CaptureSelectionHandle.allCases.filter { handleRect($0, in: rect).contains(point) }.min {
            let a = $0.point(in: rect), b = $1.point(in: rect)
            return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
        }
    }
    private func moveEdges(in rect: CGRect) -> [CGRect] {
        let width: CGFloat = 6
        return [
            CGRect(x: rect.minX - width, y: rect.minY - width, width: rect.width + 2 * width, height: 2 * width),
            CGRect(x: rect.minX - width, y: rect.maxY - width, width: rect.width + 2 * width, height: 2 * width),
            CGRect(x: rect.minX - width, y: rect.minY, width: 2 * width, height: rect.height),
            CGRect(x: rect.maxX - width, y: rect.minY, width: 2 * width, height: rect.height)
        ]
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isFinishing else { return }
        // Dock/menu-bar cursor resets need not cross a tracking-area boundary.
        // Reassert the cursor on movement as well as AppKit's cursorUpdate event.
        cursorUpdate(with: event)
        if !isReviewing, start == nil, adjustment == nil { onHover?(screenPoint(event)) }
    }
    override func mouseDown(with event: NSEvent) {
        guard !isFinishing else { return }
        defer {
            window?.invalidateCursorRects(for: self)
            cursorUpdate(with: event)
        }
        start = nil
        isDragging = false
        adjustment = nil
        let point = screenPoint(event)
        if let draft = reviewDraft {
            let localPoint = convert(event.locationInWindow, from: nil)
            if let handle = selectionHandle(at: localPoint, in: localRect(draft.rect)) {
                adjustment = (point, draft, handle); return
            }
            if moveEdges(in: localRect(draft.rect)).contains(where: { $0.contains(localPoint) }) {
                adjustment = (point, draft, nil); return
            }
        }
        if isReviewing { onRestart?() }
        start = point
        isDragging = false
        onHover?(point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !isFinishing else { return }
        defer { cursorUpdate(with: event) }
        let point = screenPoint(event)
        if let adjustment {
            let delta = CGSize(width: point.x - adjustment.start.x, height: point.y - adjustment.start.y)
            reviewDraft = adjustment.handle.map { adjustment.draft.resizing($0, by: delta, within: screenFrame) }
                ?? adjustment.draft.moving(by: delta, within: screenFrame)
        } else if let start, mode != .display,
                  isDragging || CaptureGeometry.isSelectionDrag(from: start, to: point) {
            updateRegion(from: start, to: point)
        } else { return }
        needsDisplay = true
        displayIfNeeded()
    }
    override func mouseUp(with event: NSEvent) {
        guard !isFinishing else { return }
        defer {
            window?.invalidateCursorRects(for: self)
            cursorUpdate(with: event)
        }
        if adjustment != nil { adjustment = nil; return }
        guard let start else { return }
        let point = screenPoint(event)
        let selectsRegion = mode != .display && (isDragging || CaptureGeometry.isSelectionDrag(from: start, to: point))
        if selectsRegion { updateRegion(from: start, to: point) }
        self.start = nil
        isDragging = false
        let capturesNow = capturesOnRelease && !isReviewing && !event.modifierFlags.contains(.option)
        if confirmsImmediately && !capturesNow { keepsReview = true }
        if mode == .display { onPropose?(screenFrame); if capturesNow { confirm() }; return }
        if mode != .region && !selectsRegion {
            onHover?(point); onPropose?(nil); if capturesNow { confirm() }; return
        }
        let rect = CaptureGeometry.selection(from: start, to: point, within: screenFrame)
        if !rect.isNull, rect.width >= 2, rect.height >= 2 { onPropose?(rect); if capturesNow { confirm() } }
        else { isDragging = false; onHover?(screenPoint(event)) }
    }
    private func updateRegion(from start: CGPoint, to point: CGPoint) {
        if !isDragging { isDragging = true; onDragStart?() }
        highlight = CaptureGeometry.selection(from: start, to: point, within: screenFrame)
        if let highlight {
            caption = capturesOnRelease ? String(localized: "\(pixelDimensions(highlight)) · Loslassen: Aufnehmen · Mit ⌥ loslassen: vorher prüfen · Esc: Abbrechen")
                : String(localized: "\(pixelDimensions(highlight)) · Loslassen: Auswahl prüfen · Esc: Abbrechen")
        }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { confirm() }
        else { super.keyDown(with: event) }
    }
    func confirm() {
        guard !isFinishing, let draft = reviewDraft else { return }
        onConfirm?(draft)
    }

    private func pixelDimensions(_ rect: CGRect) -> String {
        let scale = pixelScale ?? window?.backingScaleFactor ?? 1
        let crop = CaptureGeometry.sourceRect(selection: rect, screen: screenFrame, scale: scale)
        return "\(Int(((crop?.width ?? rect.width) * scale).rounded())) × \(Int(((crop?.height ?? rect.height) * scale).rounded())) px"
    }
    private func updateReview() {
        if let draft = reviewDraft {
            if toolbar == nil {
                let controls = CaptureReviewToolbar(isVideo: isVideo, allowsVideoAction: allowsVideoAction, allowsScrolling: allowsScrolling)
                controls.onCapture = { [weak self] video in
                    guard let self else { return }
                    self.isVideo = video
                    self.isScrolling = false
                    self.onMediaChange?(video)
                    self.confirm()
                }
                controls.onDestinationCapture = { [weak self] destination in
                    guard let self else { return }
                    self.imageDestination = destination
                    self.isScrolling = false; self.isVideo = false
                    self.onDestinationChange?(destination); self.onMediaChange?(false)
                    self.confirm()
                }
                controls.onScrollCapture = { [weak self] in
                    guard let self else { return }
                    guard self.allowsScrolling else { return }
                    self.isScrolling = true; self.isVideo = false
                    self.onMediaChange?(false); self.confirm()
                }
                controls.onRestart = { [weak self] in self?.onRestart?() }
                controls.onCancel = { [weak self] in self?.onCancel?() }
                controls.onSelectScreen = { [weak self] id in self?.onSelectScreen?(id) }
                controls.onSelectSource = { [weak self] source in self?.onSelectSource?(source) }
                controls.onEditSize = { [weak self] button in self?.showSizeEditor(from: button) }
                addSubview(controls)
                toolbar = controls
            }
            let local = localRect(draft.rect)
            toolbar?.setVideo(isVideo)
            toolbar?.setScrolling(isScrolling)
            toolbar?.setDestination(imageDestination)
            toolbar?.source = mode
            toolbar?.screenChoices = screenChoices
            toolbar?.selectedScreenID = draft.rect == screenFrame ? displayID : nil
            let margin: CGFloat = 12, height = CaptureReviewToolbar.height
            let width = min(CaptureReviewToolbar.preferredWidth(allowsVideoAction: allowsVideoAction), bounds.width - 2 * margin)
            let x = min(max(local.midX - width / 2, margin), bounds.maxX - width - margin)
            let below = local.minY - height - 8, above = local.maxY + 8
            let y = below >= margin ? below : above + height <= bounds.maxY - margin ? above : margin
            toolbar?.frame = CGRect(x: x, y: y, width: width, height: height)
            toolbar?.setDimensions(pixelDimensions(draft.rect).replacingOccurrences(of: " px", with: ""))
            toolbar?.needsLayout = true
            if isVideo && draft.windowID != nil {
                caption = String(localized: "Ganzes Fenster aufnehmen und beim Verschieben folgen. Rahmen ändern: fester Bereich. Enter: Bestätigen. Esc: Abbrechen.")
            } else {
                caption = String(localized: "Auswahl: \(pixelDimensions(draft.rect)). Im Bild ziehen: neuer Bereich. Rahmenkante: verschieben. Griffe: Größe ändern. Enter: \(isVideo ? String(localized: "Bereich bestätigen") : String(localized: "Aufnehmen")). Esc: Abbrechen.")
            }
            toolbar?.toolTip = String(localized: "Im Bild ziehen: neuer Bereich · Rahmenkante ziehen: verschieben · Griffe ziehen: Größe ändern")
        } else {
            dismissSizeEditor()
            toolbar?.removeFromSuperview()
            toolbar = nil
        }
        needsDisplay = true
        chrome.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func resizeSelection(to pixels: CGSize) {
        guard !isFinishing, let draft = reviewDraft, pixels.width.isFinite, pixels.height.isFinite else { return }
        let scale = pixelScale ?? window?.backingScaleFactor ?? 1
        guard let source = CaptureGeometry.sourceRect(selection: draft.rect, screen: screenFrame, scale: scale) else { return }
        let left = screenFrame.minX + source.minX, top = screenFrame.maxY - source.minY
        let width = min(max(ceil(2 * scale), pixels.width.rounded()) / scale, screenFrame.maxX - left)
        let height = min(max(ceil(2 * scale), pixels.height.rounded()) / scale, top - screenFrame.minY)
        let rect = CGRect(x: left, y: top - height, width: width, height: height)
        reviewDraft = CaptureSelectionDraft(rect: rect, windowID: rect == draft.rect ? draft.windowID : nil)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func showSizeEditor(from button: NSButton) {
        guard let draft = reviewDraft else { return }
        dismissSizeEditor()
        let scale = pixelScale ?? window?.backingScaleFactor ?? 1
        guard let source = CaptureGeometry.sourceRect(selection: draft.rect, screen: screenFrame, scale: scale) else { return }
        let editor = CaptureSizeEditor(size: CGSize(width: (source.width * scale).rounded(), height: (source.height * scale).rounded()),
            maximum: CGSize(width: ((screenFrame.width - source.minX) * scale).rounded(.down),
                            height: ((screenFrame.height - source.minY) * scale).rounded(.down)), minimum: ceil(2 * scale))
        editor.onApply = { [weak self] size in self?.resizeSelection(to: size); self?.dismissSizeEditor() }
        let popover = NSPopover(); popover.contentViewController = editor; popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        sizePopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }
    func dismissSizeEditor() { sizePopover?.close(); sizePopover = nil }

    override func draw(_ dirtyRect: NSRect) {
        if isLiveCapture {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.clear(bounds)
            // Preserve the exact frozen surround as well as its shade. Only the
            // selected hole goes live; changing applications cannot brighten or
            // rearrange the outside of the selection during this handoff.
            guard backgroundImage != nil else { return }
            context.saveGState()
            let outside = NSBezierPath(rect: bounds)
            if let rect = reviewDraft?.rect {
                outside.append(NSBezierPath(rect: localRect(rect)))
                outside.windingRule = .evenOdd
            }
            outside.addClip()
            NSColor.black.setFill(); bounds.fill()
            backgroundImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
            return
        }
        // Draw the unchanged desktop beneath every highlight and selection.
        // The selected hole is visual only; no pixel becomes click-through.
        NSColor.black.setFill()
        bounds.fill()
        backgroundImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    fileprivate func drawSelectionChrome() {
        let presentation = hoverPresentation()
        let selected = reviewDraft?.rect ?? presentation.rect
        let visibility: CGFloat = reviewDraft == nil ? presentation.visibility : 1
        let baseShade: CGFloat = (isReviewing ? 0.42 : 0.16) * (1 - visibility)
        NSColor.black.withAlphaComponent(baseShade).setFill()
        bounds.fill()
        let shade = NSBezierPath(rect: bounds)
        if let selected, !selected.isNull {
            let local = localRect(selected).intersection(bounds)
            if !local.isNull {
                shade.append(NSBezierPath(rect: local))
                shade.windingRule = .evenOdd
                NSColor.black.withAlphaComponent(0.42 * visibility / (1 - baseShade)).setFill()
                shade.fill()
                let border = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
                NSColor.white.withAlphaComponent(visibility).setStroke(); border.lineWidth = 3; border.stroke()
                NSColor.controlAccentColor.withAlphaComponent(visibility).setStroke(); border.lineWidth = 1.5; border.stroke()
                if reviewDraft != nil {
                    for handle in CaptureSelectionHandle.allCases {
                        if let context = NSGraphicsContext.current?.cgContext {
                            SelectionGrips.draw(at: handle.point(in: local), shape: handle.gripShape, in: context)
                        }
                    }
                }
            }
        }
        guard !isReviewing else { return }
        let text = (isVideo ? (reviewDraft?.windowID != nil ? String(localized: "Video-Fenster · ") : String(localized: "Video-Bereich · ")) : String(localized: "Screenshot · ")) + caption
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let width = min(bounds.width - 32, (text as NSString).size(withAttributes: attributes).width + 28)
        let box = CGRect(x: (bounds.width - width) / 2, y: 24, width: width, height: 34)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(in: box.insetBy(dx: 14, dy: 9), withAttributes: attributes)
    }
}

/// CADisplayLink retains its target. A weak view avoids keeping a closed selector alive.
@MainActor
private final class CaptureHoverFrameDriver: NSObject {
    weak var view: SelectionView?
    init(view: SelectionView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.advanceHoverAnimation()
    }
}

/// A separate composited layer keeps transitions away from frozen image pixels.
@MainActor
private final class CaptureSelectionChrome: NSView {
    weak var owner: SelectionView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawSelectionChrome() }
}

struct CaptureScreenChoice: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
}

@MainActor
final class CaptureReviewToolbar: CaptureToolbarSurface {
    static let height = CaptureToolbarSurface.barHeight
    static func preferredWidth(allowsVideoAction: Bool) -> CGFloat { allowsVideoAction ? 728 : 640 }
    /// The pixel size is itself the control for entering an exact size, like the source and screen menus.
    let size = CaptureFlatButton(frame: .zero)
    var onCapture: ((Bool) -> Void)?
    var onScrollCapture: (() -> Void)?
    var onDestinationCapture: ((CaptureImageDestination) -> Void)?
    var onRestart: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelectScreen: ((CGDirectDisplayID) -> Void)?
    var onSelectSource: ((CaptureSource) -> Void)?
    var onEditSize: ((NSButton) -> Void)?
    var screenChoices: [CaptureScreenChoice] = []
    var selectedScreenID: CGDirectDisplayID?
    var source = CaptureSource.automatic {
        didSet { sourceButton.title = source == .window ? String(localized: "Fenster") : String(localized: "Bereich") }
    }
    private let capture = CaptureFlatButton(frame: .zero)
    private let choices = CaptureFlatButton(frame: .zero)
    private let mediaGroup = NSView()
    private let photoSelection = NSView()
    private let screen = CaptureFlatButton(frame: .zero)
    private let sourceButton = CaptureFlatButton(frame: .zero)
    private let restart = CaptureFlatButton(frame: .zero)
    private let cancel = CaptureFlatButton(frame: .zero)
    private var dividers: [NSView] = []
    private var isScrolling = false
    private var destination: CaptureImageDestination = .image
    private var videoButton: CaptureFlatButton?
    private(set) var actionButtons: [NSButton] = []

    private let allowsScrolling: Bool
    init(isVideo: Bool = false, allowsVideoAction: Bool = true, allowsScrolling: Bool = true) {
        self.allowsScrolling = allowsScrolling
        super.init(frame: CGRect(x: 0, y: 0, width: Self.preferredWidth(allowsVideoAction: allowsVideoAction), height: Self.height), subdued: true)
        setAccessibilityLabel(String(localized: "Aufnahme bestätigen"))
        setAccessibilityIdentifier("capture.reviewToolbar")
        mediaGroup.wantsLayer = true; mediaGroup.layer?.cornerRadius = 18; mediaGroup.layer?.masksToBounds = true
        mediaGroup.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        controls.addSubview(mediaGroup)
        photoSelection.wantsLayer = true; photoSelection.layer?.cornerRadius = 16
        photoSelection.layer?.backgroundColor = Self.accent.cgColor
        mediaGroup.addSubview(photoSelection)
        configure(capture, title: String(localized: "Foto"), symbol: "camera", action: #selector(capturePressed), identifier: "capture.confirm", parent: mediaGroup)
        capture.flatCell.iconSize = 24
        configure(choices, title: "", symbol: "chevron.down", action: #selector(showPhotoChoices(_:)), identifier: "capture.photoChoices", parent: mediaGroup)
        choices.isHidden = false
        choices.flatCell.iconSize = 10
        choices.setAccessibilityLabel(String(localized: "Aufnahmeart wählen"))
        choices.toolTip = String(localized: "Foto, Textaufnahme oder QR-Code")
        if allowsVideoAction {
            let video = CaptureFlatButton(frame: .zero)
            configure(video, title: String(localized: "Video"), symbol: "video", action: #selector(videoPressed), identifier: "capture.video", parent: mediaGroup)
            video.flatCell.iconSize = 24; videoButton = video
        }
        configure(screen, title: String(localized: "Bildschirm"), symbol: "display", action: #selector(showScreenChoices(_:)), identifier: "capture.screenChoices")
        screen.flatCell.showsChevron = true
        screen.flatCell.iconSize = 22
        screen.setAccessibilityRole(.popUpButton)
        screen.setAccessibilityLabel(String(localized: "Ganzen Bildschirm auswählen"))
        screen.toolTip = String(localized: "Ganzen Bildschirm auswählen")
        configure(sourceButton, title: String(localized: "Bereich"), symbol: "rectangle.split.2x2", action: #selector(showSourceChoices(_:)), identifier: "capture.sourceChoices")
        sourceButton.flatCell.showsChevron = true
        sourceButton.flatCell.iconSize = 20
        sourceButton.setAccessibilityRole(.popUpButton)
        sourceButton.setAccessibilityLabel(String(localized: "Auswahlart"))
        configure(size, title: "", symbol: "", action: #selector(editSize(_:)), identifier: "capture.size")
        size.image = nil; size.imagePosition = .noImage
        size.flatCell.showsChevron = true
        size.setAccessibilityRole(.popUpButton)
        size.setAccessibilityLabel(String(localized: "Auswahlgröße")); size.toolTip = String(localized: "Genaue Größe in Pixeln eingeben")
        configure(restart, title: "", symbol: "arrow.counterclockwise", action: #selector(restartPressed), identifier: "capture.restart")
        restart.flatCell.iconSize = 24
        restart.setAccessibilityLabel(String(localized: "Neu auswählen")); restart.toolTip = String(localized: "Neu auswählen")
        configure(cancel, title: "", symbol: "xmark", action: #selector(cancelPressed), identifier: "capture.cancel")
        cancel.flatCell.iconSize = 20
        cancel.setAccessibilityLabel(String(localized: "Abbrechen")); cancel.toolTip = String(localized: "Abbrechen (Esc)")
        for _ in 0..<5 {
            let divider = Self.divider()
            controls.addSubview(divider); dividers.append(divider)
        }
        setVideo(isVideo); setScrolling(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: CaptureFlatButton, title: String, symbol: String, action: Selector, identifier: String, parent: NSView? = nil) {
        button.title = title; button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.target = self; button.action = action; button.setAccessibilityIdentifier(identifier)
        (parent ?? controls).addSubview(button); actionButtons.append(button)
    }
    override func layout() {
        super.layout()
        let withoutVideo: CGFloat = videoButton == nil ? 88 : 0
        let baseWidth = Self.preferredWidth(allowsVideoAction: videoButton != nil)
        let scale = min(1, bounds.width / baseWidth)
        let left = (bounds.width - baseWidth * scale) / 2
        let height = Self.controlHeight * scale, y = (bounds.height - height) / 2
        func rect(_ x: CGFloat, _ width: CGFloat) -> NSRect {
            NSRect(x: left + x * scale, y: y, width: width * scale, height: height)
        }
        mediaGroup.frame = rect(10, 196 - withoutVideo)
        mediaGroup.layer?.cornerRadius = 18 * scale
        photoSelection.frame = NSRect(x: 0, y: 0, width: 108 * scale, height: height)
        photoSelection.layer?.cornerRadius = 16 * scale
        capture.frame = NSRect(x: 0, y: 0, width: 86 * scale, height: height)
        choices.frame = NSRect(x: 86 * scale, y: 0, width: 22 * scale, height: height)
        videoButton?.frame = NSRect(x: 108 * scale, y: 0, width: 88 * scale, height: height)
        for (button, x, width) in [(screen, CGFloat(226), CGFloat(116)), (sourceButton, 362, 96), (size, 476, 136), (restart, 626, 36), (cancel, 682, 36)] {
            button.frame = rect(x - withoutVideo, width)
        }
        for button in actionButtons.compactMap({ $0 as? CaptureFlatButton }) {
            let primary = button === capture || button === videoButton
            button.font = .systemFont(ofSize: (primary ? 14 : 12) * scale,
                                      weight: button === capture ? .semibold : primary ? .medium : .regular)
            button.flatCell.contentScale = scale; button.needsDisplay = true
        }
        // Monospaced digits keep the size steady while dragging; long values shrink to fit beside the chevron.
        let digits = NSFont.monospacedDigitSystemFont(ofSize: 12 * scale, weight: .medium)
        let available = size.frame.width - 40 * scale
        size.font = .monospacedDigitSystemFont(ofSize: min(12 * scale, 12 * scale * available / max(1, (size.title as NSString).size(withAttributes: [.font: digits]).width)), weight: .medium)
        size.flatCell.foreground = NSColor.white.withAlphaComponent(0.82)
        for (divider, x) in zip(dividers, [CGFloat(216), 352, 468, 618, 672]) {
            divider.frame = NSRect(x: left + (x - withoutVideo) * scale, y: (bounds.height - 32 * scale) / 2, width: 1, height: 32 * scale)
        }
    }
    func setDimensions(_ text: String) {
        guard size.title != text else { return }
        size.title = text; size.setAccessibilityValue(text); needsLayout = true
    }
    func setVideo(_ video: Bool) {
        photoSelection.isHidden = video
        capture.flatCell.foreground = .white; choices.flatCell.foreground = .white
        videoButton?.flatCell.fill = video ? Self.accent : nil
        videoButton?.flatCell.foreground = .white
        capture.toolTip = video ? String(localized: "Screenshot aufnehmen") : String(localized: "Screenshot aufnehmen (Enter)")
        videoButton?.toolTip = video ? String(localized: "Video aufnehmen (Enter)") : String(localized: "Video aufnehmen")
        capture.needsDisplay = true; choices.needsDisplay = true; videoButton?.needsDisplay = true
    }
    func setScrolling(_ scrolling: Bool) {
        isScrolling = scrolling
        updateDestinationLabel()
    }
    func setDestination(_ value: CaptureImageDestination) {
        destination = value; updateDestinationLabel()
    }
    private func updateDestinationLabel() {
        let title: String, symbol: String, hint: String
        if isScrolling {
            title = String(localized: "Scrollen"); symbol = "arrow.down.square"; hint = String(localized: "Scroll-Aufnahme starten (Enter)")
        } else {
            switch destination {
            case .image: title = String(localized: "Foto"); symbol = "camera"; hint = String(localized: "Screenshot aufnehmen (Enter)")
            case .text: title = String(localized: "Text"); symbol = "text.viewfinder"; hint = String(localized: "Text erfassen und kopieren (Enter)")
            case .code: title = String(localized: "QR"); symbol = "qrcode.viewfinder"; hint = String(localized: "QR-Code scannen (Enter)")
            }
        }
        capture.title = title; capture.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        capture.toolTip = hint; capture.setAccessibilityLabel(hint)
    }
    func photoChoicesMenu() -> NSMenu {
        let menu = NSMenu()
        let entries = [(String(localized: "Foto aufnehmen"), #selector(photoChosen)), (String(localized: "Textaufnahme – nur Text kopieren"), #selector(textChosen)), (String(localized: "QR-Code scannen"), #selector(codeChosen))] + (allowsScrolling ? [(String(localized: "Scroll-Aufnahme"), #selector(scrollChosen))] : [])
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        return menu
    }
    func screenChoicesMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: String(localized: "Bildschirm"), action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil); menu.addItem(title)
        for choice in screenChoices {
            let item = NSMenuItem(title: choice.name, action: #selector(screenChosen(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = NSNumber(value: choice.id)
            item.state = selectedScreenID == choice.id ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
    func sourceChoicesMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, value) in [(String(localized: "Automatisch"), CaptureSource.automatic), (String(localized: "Bereich"), .region), (String(localized: "Fenster"), .window)] {
            let item = NSMenuItem(title: title, action: #selector(sourceChosen(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value.rawValue; item.state = source == value ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
    @objc private func showPhotoChoices(_ sender: NSButton) { show(photoChoicesMenu(), from: sender) }
    @objc private func showScreenChoices(_ sender: NSButton) { show(screenChoicesMenu(), from: sender) }
    @objc private func showSourceChoices(_ sender: NSButton) { show(sourceChoicesMenu(), from: sender) }
    private func show(_ menu: NSMenu, from button: NSButton) {
        menu.popUp(positioning: nil, at: CGPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
    }
    @objc private func photoChosen() { setScrolling(false); setDestination(.image); onDestinationCapture?(.image) }
    @objc private func textChosen() { onDestinationCapture?(.text) }
    @objc private func codeChosen() { onDestinationCapture?(.code) }
    @objc private func scrollChosen() { onScrollCapture?() }
    @objc private func capturePressed() { if isScrolling { onScrollCapture?() } else { onDestinationCapture?(destination) } }
    @objc private func videoPressed() { onCapture?(true) }
    @objc private func screenChosen(_ sender: NSMenuItem) { if let id = sender.representedObject as? NSNumber { onSelectScreen?(id.uint32Value) } }
    @objc private func sourceChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let value = CaptureSource(rawValue: raw) { onSelectSource?(value) }
    }
    @objc private func editSize(_ sender: NSButton) { onEditSize?(sender) }
    @objc private func restartPressed() { onRestart?() }
    @objc private func cancelPressed() { onCancel?() }
}

@MainActor
private final class CaptureSizeEditor: NSViewController {
    private let size: CGSize
    private let maximum: CGSize
    private let minimum: CGFloat
    private let width = NSTextField(), height = NSTextField()
    var onApply: ((CGSize) -> Void)?
    init(size: CGSize, maximum: CGSize, minimum: CGFloat) { self.size = size; self.maximum = maximum; self.minimum = minimum; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: 172))
        let title = NSTextField(labelWithString: String(localized: "Auswahlgröße"))
        title.font = .systemFont(ofSize: 13, weight: .semibold); title.frame = CGRect(x: 16, y: 138, width: 228, height: 20); view.addSubview(title)
        for (field, label, value, limit, y) in [
            (width, String(localized: "Breite"), size.width, maximum.width, CGFloat(96)),
            (height, String(localized: "Höhe"), size.height, maximum.height, CGFloat(60))
        ] {
            let caption = NSTextField(labelWithString: label); caption.frame = CGRect(x: 16, y: y + 4, width: 76, height: 20); view.addSubview(caption)
            field.frame = CGRect(x: 100, y: y, width: 108, height: 28)
            let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 0
            formatter.minimum = NSNumber(value: Double(minimum)); formatter.maximum = NSNumber(value: Double(limit))
            field.formatter = formatter; field.doubleValue = value; field.alignment = .right
            field.setAccessibilityLabel(label); field.setAccessibilityIdentifier(field === width ? "capture.size.width" : "capture.size.height")
            view.addSubview(field)
            let unit = NSTextField(labelWithString: "px"); unit.frame = CGRect(x: 216, y: y + 4, width: 28, height: 20); unit.textColor = .secondaryLabelColor; view.addSubview(unit)
        }
        let apply = NSButton(title: String(localized: "Übernehmen"), target: self, action: #selector(applySize))
        apply.frame = CGRect(x: 132, y: 12, width: 112, height: 32); apply.bezelStyle = .glass; apply.keyEquivalent = "\r"
        apply.setAccessibilityIdentifier("capture.size.apply"); view.addSubview(apply)
    }
    @objc private func applySize() {
        guard view.window?.makeFirstResponder(nil) != false else { return }
        onApply?(CGSize(width: width.doubleValue, height: height.doubleValue))
    }
}
