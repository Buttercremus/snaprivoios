import AppKit
import SwiftUI

/// A disposable, immutable flattened snapshot; never holds a project or its original.
@MainActor final class PinnedImageController: NSObject, NSWindowDelegate {
    static let shared = PinnedImageController()
    private var panels: [NSPanel] = []
    var panelCount: Int { panels.count }
    var allPinsIgnoreMouseEvents: Bool { !panels.isEmpty && panels.allSatisfy(\.ignoresMouseEvents) }
    var opacities: [CGFloat] { panels.map(\.alphaValue) }
    private let presentMenu: @MainActor (NSMenu, CGPoint, NSView) -> Void
    init(presentMenu: @escaping @MainActor (NSMenu, CGPoint, NSView) -> Void = { menu, point, view in
        menu.popUp(positioning: nil, at: point, in: view)
    }) {
        self.presentMenu = presentMenu
        super.init()
    }
    fileprivate func showMenu(_ menu: NSMenu, at point: CGPoint, in view: NSView) { presentMenu(menu, point, view) }
    func show(_ image: CGImage, title: String) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1000, height: 700)
        let factor = min(1, available.width * 0.65 / CGFloat(image.width), available.height * 0.65 / CGFloat(image.height))
        let size = CGSize(width: max(160, CGFloat(image.width) * factor), height: max(100, CGFloat(image.height) * factor))
        let panel = PinnedImagePanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        // Image only: the system keeps rounded corners, shadow and edge resizing; the title stays for accessibility.
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
        panel.title = title; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = CGSize(width: 160, height: 100)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        let view = PinnedImageView(controller: self, panel: panel)
        view.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel(String(localized: "Angeheftete Aufnahme"))
        panel.contentView = view; panel.initialFirstResponder = view; panel.isMovableByWindowBackground = true
        panel.delegate = self; panels.append(panel)
        panel.center(); panel.orderFrontRegardless()
    }

    func setClickThrough(_ enabled: Bool, for panel: NSPanel) {
        panel.ignoresMouseEvents = enabled
        (panel.contentView as? PinnedImageView)?.isClickThrough = enabled
    }
    func toggleClickThrough() {
        for panel in panels {
            panel.ignoresMouseEvents.toggle()
            if let view = panel.contentView as? PinnedImageView { view.isClickThrough = panel.ignoresMouseEvents }
        }
    }
    /// Restores interaction for every pin, including pins that currently ignore mouse events.
    @objc func unlockAll() {
        for panel in panels {
            panel.ignoresMouseEvents = false
            (panel.contentView as? PinnedImageView)?.isClickThrough = false
        }
    }
    @objc func closeAll() { panels.forEach { $0.close() } }
    func setOpacity(_ opacity: CGFloat, for panel: NSPanel) { panel.alphaValue = min(1, max(0.2, opacity)) }
    func close(_ panel: NSPanel) { panel.close() }
    func windowWillClose(_ notification: Notification) {
        panels.removeAll { $0 === notification.object as? NSWindow }
    }
}

private final class PinnedImagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private func focusImageIfNeeded() -> Bool {
        guard firstResponder === self || firstResponder == nil, let contentView, contentView.canBecomeKeyView else { return false }
        return makeFirstResponder(contentView)
    }
    override func becomeKey() { super.becomeKey(); _ = focusImageIfNeeded() }
    override func resignKey() { super.resignKey(); _ = makeFirstResponder(nil) }
    override func selectNextKeyView(_ sender: Any?) {
        if !focusImageIfNeeded() { super.selectNextKeyView(sender) }
    }
    override func selectPreviousKeyView(_ sender: Any?) {
        if !focusImageIfNeeded() { super.selectPreviousKeyView(sender) }
    }
}

private final class PinnedImageView: NSImageView {
    weak var controller: PinnedImageController?
    weak var panel: NSPanel?
    var isClickThrough = false { didSet { updateControlsVisibility() } }
    private var controls: NSHostingView<PinnedImageControls>?
    private var showsControls = false
    private var isHovered = false
    private var hoverTracking: NSTrackingArea?
    init(controller: PinnedImageController, panel: NSPanel) {
        self.controller = controller; self.panel = panel; super.init(frame: .zero); setAccessibilityElement(true)
        refusesFirstResponder = false; focusRingType = .exterior
        setAccessibilityHelp(String(localized: "Mit Leertaste oder Eingabetaste die Bildaktionen öffnen."))
        let controls = NSHostingView(rootView: PinnedImageControls(
            setOpacity: { [weak self] value in if let panel = self?.panel { self?.controller?.setOpacity(value, for: panel) } },
            clickThrough: { [weak self] in self?.toggleClick() },
            close: { [weak self] in self?.closePanel() }))
        controls.isHidden = true; controls.alphaValue = 0
        addSubview(controls); self.controls = controls
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isClickThrough && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted && !isClickThrough { setControlsVisible(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            Task { [weak self] in self?.updateControlsVisibility() }
        }
        return resigned
    }
    override var mouseDownCanMoveWindow: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Bottom trailing keeps the controls clear of the transparent title bar's drag area.
        guard let controls else { return }
        let size = controls.fittingSize
        controls.frame = CGRect(x: max(8, newSize.width - size.width - 10), y: 10, width: size.width, height: size.height)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; updateControlsVisibility() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateControlsVisibility() }
    private func updateControlsVisibility() {
        let focused = (window?.firstResponder as? NSView).map { $0 === self || $0.isDescendant(of: self) } ?? false
        setControlsVisible(!isClickThrough && (isHovered || focused))
    }
    private func setControlsVisible(_ visible: Bool) {
        guard let controls, visible != showsControls else { return }
        showsControls = visible
        // Hidden controls take neither clicks nor window drags.
        if visible { controls.isHidden = false }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            controls.alphaValue = visible ? 1 : 0; controls.isHidden = !visible; return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            controls.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.showsControls == false { controls.isHidden = true } }
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        showActions(at: convert(event.locationInWindow, from: nil))
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard panel != nil else { return false }
        showActions(at: CGPoint(x: bounds.midX, y: 10)); return true
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let opacity = [0.4, 0.6, 0.8, 1.0].map { value in
            NSAccessibilityCustomAction(name: String(localized: "Deckkraft") + ": \(Int(value * 100))%") { [weak self] in
                guard let self, let panel, let controller else { return false }
                controller.setOpacity(value, for: panel); return true
            }
        }
        return opacity + [
            NSAccessibilityCustomAction(name: isClickThrough ? String(localized: "Klicks wieder aktivieren") : String(localized: "Klicks durchlassen")) { [weak self] in
                guard let self, panel != nil else { return false }; toggleClick(); return true
            },
            NSAccessibilityCustomAction(name: String(localized: "Schließen")) { [weak self] in
                guard let self, panel != nil else { return false }; closePanel(); return true
            }
        ]
    }
    private func showActions(at point: CGPoint) {
        let menu = NSMenu()
        let click = NSMenuItem(title: isClickThrough ? String(localized: "Klicks wieder aktivieren") : String(localized: "Klicks durchlassen"), action: #selector(toggleClick), keyEquivalent: "")
        click.target = self; menu.addItem(click)
        let opacity = NSMenuItem(title: String(localized: "Deckkraft"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(); [0.4, 0.6, 0.8, 1.0].forEach { value in
            let item = NSMenuItem(title: "\(Int(value * 100))%", action: #selector(setMenuOpacity(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value; submenu.addItem(item)
        }; opacity.submenu = submenu; menu.addItem(opacity)
        menu.addItem(.separator()); let close = NSMenuItem(title: String(localized: "Schließen"), action: #selector(closePanel), keyEquivalent: "w"); close.keyEquivalentModifierMask = [.command]; close.target = self; menu.addItem(close)
        controller?.showMenu(menu, at: point, in: self)
    }
    @objc fileprivate func toggleClick() { if let panel { controller?.setClickThrough(!panel.ignoresMouseEvents, for: panel) } }
    @objc private func setMenuOpacity(_ item: NSMenuItem) { if let value = item.representedObject as? Double, let panel { controller?.setOpacity(CGFloat(value), for: panel) } }
    @objc fileprivate func closePanel() { if let panel { controller?.close(panel) } }
    override func keyDown(with event: NSEvent) {
        guard let panel else { super.keyDown(with: event); return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 2
        var origin = panel.frame.origin
        switch event.keyCode {
        case 36, 49: _ = accessibilityPerformShowMenu(); return
        case 123: origin.x -= step
        case 124: origin.x += step
        case 125: origin.y -= step
        case 126: origin.y += step
        case 53: controller?.close(panel)
        default: super.keyDown(with: event); return
        }
        panel.setFrameOrigin(origin)
    }
}

/// Appears while hovering a pin; the context menu and keyboard keep the same actions.
private struct PinnedImageControls: View {
    let setOpacity: (CGFloat) -> Void
    let clickThrough: () -> Void
    let close: () -> Void
    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Menu {
                    ForEach([0.4, 0.6, 0.8, 1.0], id: \.self) { value in
                        Button { setOpacity(value) } label: { Text(verbatim: "\(Int(value * 100))%") }
                    }
                } label: { Label(String(localized: "Deckkraft"), systemImage: "circle.lefthalf.filled") }
                    .menuIndicator(.hidden).menuStyle(.button).help(String(localized: "Deckkraft"))
                Button(String(localized: "Klicks durchlassen"), systemImage: "cursorarrow.click", action: clickThrough)
                    .help(String(localized: "Klicks durchlassen. Wieder aktivieren mit „Alle Anheftungen entsperren“ im Menüleistensymbol."))
                Button(String(localized: "Schließen"), systemImage: "xmark", action: close).help(String(localized: "Schließen"))
            }
        }
        .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.small)
        .padding(1)
    }
}

struct PinImageButton: View {
    let model: EditorModel
    let size: EditorToolbarSize
    var iconOnly = false
    @State private var busy = false
    var body: some View {
        Button {
            guard model.hasExportableImage, !busy else { return }
            model.endStyleEditing(); model.finishTextEditing()
            let image = model.image, objects = model.history.objects, crop = model.history.crop, resized = model.history.resizedSize, canvasRect = model.history.canvasRect, transform = model.history.transform, presentation = model.history.presentation
            let title = model.name
            busy = true
            Task {
                defer { busy = false }
                do {
                    let flattened = try await Task.detached(priority: .userInitiated) {
                        try EditorRenderer.render(image: image, objects: objects, crop: crop, resizedSize: resized, canvasRect: canvasRect, transform: transform, presentation: presentation)
                    }.value
                    PinnedImageController.shared.show(flattened, title: title)
                } catch { model.error = error.localizedDescription }
            }
        } label: {
            if iconOnly { Label(String(localized: "Anheften"), systemImage: "pin").labelStyle(.iconOnly) }
            else { EditorToolbarLabel(title: String(localized: "Anheften"), symbol: "pin", size: size) }
        }
        .disabled(busy || !model.hasConfirmedImageForToolbar)
        .help(String(localized: "Bearbeitetes Bild über anderen Fenstern anzeigen"))
        .accessibilityIdentifier("editor.pin")
    }
}
