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

    func select(source: CaptureSource, windows: [CapturableWindow], desktop: FrozenDesktop, media: CaptureMedia = .image, allowsVideoAction: Bool = true) async throws -> ScreenshotSelection? {
        let screens = NSScreen.screens
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
                view.frozenImage = frozen.image
                view.pixelScale = frozen.scale
                view.mode = mode
                view.allowsVideoAction = allowsVideoAction
                view.isVideo = media == .video
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
                    self.reviewView = view
                    for candidate in self.views {
                        candidate.isReviewing = true
                        candidate.highlight = nil
                        candidate.reviewDraft = candidate === view ? draft : nil
                    }
                    panel?.makeKey()
                    panel?.makeFirstResponder(view)
                }
                view.onConfirm = { [weak self, weak view] draft in
                    self?.finish(ScreenshotSelection(displayID: id, draft: draft, screenFrame: screen.frame, media: view?.isVideo == true ? .video : .image))
                }
                view.onRestart = { [weak self] in self?.restart() }
                view.onCancel = { [weak self] in self?.finish(nil) }
                panel.contentView = view
                panels.append(panel)
                views.append(view)
            }
            guard !panels.isEmpty else { finish(nil); return }
            // The frozen desktop appears at its final size and stays opaque.
            // Only the shade/frame/hints fade, never the desktop-sized panel.
            hover(at: NSEvent.mouseLocation)
            views.forEach { $0.preparePresentation() }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                panels.forEach { $0.orderFrontRegardless(); $0.displayIfNeeded() }
            }
            CaptureOverlayMotion.animate { self.views.forEach { $0.setChromeVisible(true) } }
            let active = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels[0]
            active.makeKey()
            active.makeFirstResponder(active.contentView)
            for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
                focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let changedWindow = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        if let changedWindow, changedWindow.level.rawValue >= NSWindow.Level.statusBar.rawValue { return }
                        self?.hideAppWindows()
                        let panel = self?.reviewView?.window ?? self?.panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                        panel?.makeKey()
                        panel?.makeFirstResponder(panel?.contentView)
                    }
                })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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

    func cancel() { finish(nil) }

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
        guard !isFinishing else { return }
        isFinishing = true
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        views.forEach { $0.isFinishing = true }
        if animated, panels.contains(where: \.isVisible) {
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
}

@MainActor
final class SelectionView: NSView {
    var screenFrame = CGRect.zero
    var frozenImage: CGImage? {
        didSet {
            backgroundImage = frozenImage.map { NSImage(cgImage: $0, size: bounds.size) }
            needsDisplay = true
        }
    }
    var pixelScale: CGFloat?
    private var backgroundImage: NSImage?
    var mode = CaptureSource.automatic
    var allowsVideoAction = true
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
    var isSelectingRegion: Bool { start != nil && isDragging }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
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
        if newWindow == nil { stopHoverDisplayLink() }
        super.viewWillMove(toWindow: newWindow)
    }

    func preparePresentation() { chrome.alphaValue = 0 }
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
        selectionCursor(at: convert(event.locationInWindow, from: nil)).set()
    }
    override func mouseEntered(with event: NSEvent) {
        cursorUpdate(with: event)
    }
    func selectionCursor(at point: CGPoint) -> NSCursor {
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
        if adjustment != nil { adjustment = nil; return }
        guard let start else { return }
        let point = screenPoint(event)
        let selectsRegion = mode != .display && (isDragging || CaptureGeometry.isSelectionDrag(from: start, to: point))
        if selectsRegion { updateRegion(from: start, to: point) }
        self.start = nil
        isDragging = false
        if mode == .display { onPropose?(screenFrame); return }
        if mode != .region && !selectsRegion {
            onHover?(point); onPropose?(nil); return
        }
        let rect = CaptureGeometry.selection(from: start, to: point, within: screenFrame)
        if !rect.isNull, rect.width >= 2, rect.height >= 2 { onPropose?(rect) }
        else { isDragging = false; onHover?(screenPoint(event)) }
    }
    private func updateRegion(from start: CGPoint, to point: CGPoint) {
        if !isDragging { isDragging = true; onDragStart?() }
        highlight = CaptureGeometry.selection(from: start, to: point, within: screenFrame)
        if let highlight { caption = String(localized: "\(pixelDimensions(highlight)) · Loslassen: Auswahl prüfen · Esc: Abbrechen") }
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
                let controls = CaptureReviewToolbar(isVideo: isVideo, allowsVideoAction: allowsVideoAction)
                controls.onCapture = { [weak self] video in
                    guard let self else { return }
                    self.isVideo = video
                    self.onMediaChange?(video)
                    self.confirm()
                }
                controls.onRestart = { [weak self] in self?.onRestart?() }
                controls.onCancel = { [weak self] in self?.onCancel?() }
                addSubview(controls)
                toolbar = controls
            }
            let local = localRect(draft.rect)
            toolbar?.setVideo(isVideo)
            let width: CGFloat = allowsVideoAction ? 448 : 336, height: CGFloat = 52, margin: CGFloat = 12
            let x = min(max(local.midX - width / 2, margin), bounds.maxX - width - margin)
            let below = local.minY - height - 8, above = local.maxY + 8
            let y = below >= margin ? below : above + height <= bounds.maxY - margin ? above : margin
            toolbar?.frame = CGRect(x: x, y: y, width: width, height: height)
            toolbar?.dimensions.stringValue = pixelDimensions(draft.rect)
            if isVideo && draft.windowID != nil {
                caption = String(localized: "Ganzes Fenster aufnehmen und beim Verschieben folgen. Rahmen ändern: fester Bereich. Enter: Bestätigen. Esc: Abbrechen.")
            } else {
                caption = String(localized: "Auswahl: \(pixelDimensions(draft.rect)). Im Bild ziehen: neuer Bereich. Rahmenkante: verschieben. Griffe: Größe ändern. Enter: \(isVideo ? String(localized: "Bereich bestätigen") : String(localized: "Aufnehmen")). Esc: Abbrechen.")
            }
            toolbar?.toolTip = String(localized: "Im Bild ziehen: neuer Bereich · Rahmenkante ziehen: verschieben · Griffe ziehen: Größe ändern")
        } else {
            toolbar?.removeFromSuperview()
            toolbar = nil
        }
        needsDisplay = true
        chrome.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
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

@MainActor
private final class CaptureReviewToolbar: NSVisualEffectView {
    let dimensions = NSTextField(labelWithString: "")
    var onCapture: ((Bool) -> Void)?
    private let capture = CaptureActionButton()
    private var videoButton: NSButton?
    var onRestart: (() -> Void)?
    var onCancel: (() -> Void)?

    init(isVideo: Bool = false, allowsVideoAction: Bool = true) {
        super.init(frame: CGRect(x: 0, y: 0, width: 448, height: 52))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        setAccessibilityLabel(String(localized: "Aufnahme bestätigen"))
        setAccessibilityIdentifier("capture.reviewToolbar")
        let offset: CGFloat = allowsVideoAction ? 112 : 0
        capture.cell = CaptureActionCell()
        capture.hoverColor = .white
        capture.target = self; capture.action = #selector(capturePressed)
        capture.title = String(localized: "Foto")
        capture.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        capture.imagePosition = .imageLeading
        capture.bezelStyle = .rounded
        capture.controlSize = .large
        capture.font = .systemFont(ofSize: 15, weight: .semibold)
        capture.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        capture.frame = CGRect(x: 8, y: 8, width: 116, height: 36)
        capture.setAccessibilityIdentifier("capture.confirm")
        addSubview(capture)
        if allowsVideoAction {
            let video = CaptureActionButton()
            video.cell = CaptureActionCell()
            video.hoverColor = .white
            video.title = String(localized: "Video"); video.target = self; video.action = #selector(videoPressed)
            video.image = NSImage(systemSymbolName: "video", accessibilityDescription: nil)
            video.imagePosition = .imageLeading
            video.bezelStyle = .rounded
            video.controlSize = .large
            video.font = .systemFont(ofSize: 15, weight: .semibold)
            video.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            video.frame = CGRect(x: 132, y: 8, width: 104, height: 36)
            video.setAccessibilityIdentifier("capture.video")
            videoButton = video
            addSubview(video)
        }
        dimensions.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        dimensions.alignment = .center
        dimensions.textColor = .white
        dimensions.frame = CGRect(x: 132 + offset, y: 16, width: 104, height: 20)
        dimensions.setAccessibilityLabel(String(localized: "Auswahlgröße"))
        addSubview(dimensions)
        let restart = CaptureActionButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)!, target: self, action: #selector(restartPressed))
        restart.bezelStyle = .rounded
        restart.frame = CGRect(x: 244 + offset, y: 8, width: 36, height: 36)
        restart.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        restart.toolTip = String(localized: "Neu auswählen")
        restart.setAccessibilityLabel(String(localized: "Neu auswählen"))
        restart.setAccessibilityIdentifier("capture.restart")
        addSubview(restart)
        let cancel = CaptureActionButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)!, target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: 288 + offset, y: 8, width: 36, height: 36)
        cancel.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        cancel.hoverColor = .systemRed
        cancel.toolTip = String(localized: "Abbrechen (Esc)")
        cancel.setAccessibilityLabel(String(localized: "Abbrechen"))
        cancel.setAccessibilityIdentifier("capture.cancel")
        addSubview(cancel)
        setVideo(isVideo)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setVideo(_ video: Bool) {
        capture.bezelColor = .systemBlue
        videoButton?.bezelColor = .systemBlue
        capture.toolTip = video ? String(localized: "Screenshot aufnehmen") : String(localized: "Screenshot aufnehmen (Enter)")
        videoButton?.toolTip = video ? String(localized: "Video aufnehmen (Enter)") : String(localized: "Video aufnehmen")
    }
    @objc private func capturePressed() { onCapture?(false) }
    @objc private func videoPressed() { onCapture?(true) }
    @objc private func restartPressed() { onRestart?() }
    @objc private func cancelPressed() { onCancel?() }
}


/// Keeps the visible symbol box and label gap identical for both capture actions,
/// independent of the symbol's intrinsic width and AppKit's image/title allocation.
@MainActor
private final class CaptureActionCell: NSButtonCell {
    override func drawInterior(withFrame frame: NSRect, in view: NSView) {
        let label = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        let labelSize = label.size()
        let iconWidth: CGFloat = 26, gap: CGFloat = 6
        let start = frame.midX - (iconWidth + gap + labelSize.width) / 2
        if let image {
            let symbol = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)) ?? image
            super.drawImage(symbol, withFrame: CGRect(x: start, y: frame.midY - 13, width: iconWidth, height: 26), in: view)
        }
        super.drawTitle(label, withFrame: CGRect(x: start + iconWidth + gap,
            y: frame.midY - labelSize.height / 2, width: labelSize.width, height: labelSize.height), in: view)
    }
}

/// Retains native button actions, focus and accessibility while adding a short
/// hover tint. Reduced motion applies the same feedback without interpolation.
@MainActor
private final class CaptureActionButton: NSButton {
    var hoverColor: NSColor = .systemBlue
    private var hoverTracking: NSTrackingArea?
    private let hoverLayer = CALayer()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                      owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        if hoverLayer.superlayer == nil {
            hoverLayer.opacity = 0
            layer?.addSublayer(hoverLayer)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverLayer.frame = bounds.insetBy(dx: 1, dy: 3)
        hoverLayer.cornerRadius = title.isEmpty ? 7 : hoverLayer.bounds.height / 2
        hoverLayer.backgroundColor = hoverColor.withAlphaComponent(hoverColor == .white ? 0.16 : 0.28).cgColor
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); setHovered(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard isEnabled else { return }
        let target: Float = hovered ? 1 : 0
        let previous = hoverLayer.presentation()?.opacity ?? hoverLayer.opacity
        hoverLayer.removeAnimation(forKey: "hover")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverLayer.opacity = target
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = previous; animation.toValue = target
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        hoverLayer.add(animation, forKey: "hover")
    }
}
