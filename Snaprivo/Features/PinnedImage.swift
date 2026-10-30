import AppKit
import SwiftUI

/// A disposable, immutable flattened snapshot; never holds a project or its original.
@MainActor final class PinnedImageController: NSObject, NSWindowDelegate {
    static let shared = PinnedImageController()
    private var panels: [NSPanel] = []
    var panelCount: Int { panels.count }
    var allPinsIgnoreMouseEvents: Bool { !panels.isEmpty && panels.allSatisfy(\.ignoresMouseEvents) }
    var opacities: [CGFloat] { panels.map(\.alphaValue) }
    override init() {
        super.init()
    }
    func show(_ image: CGImage, title: String) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1000, height: 700)
        let factor = min(1, available.width * 0.65 / CGFloat(image.width), available.height * 0.65 / CGFloat(image.height))
        let size = CGSize(width: max(160, CGFloat(image.width) * factor), height: max(100, CGFloat(image.height) * factor))
        let panel = PinnedImagePanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = CGSize(width: 160, height: 100)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        let view = PinnedImageView(controller: self, panel: panel)
        view.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel(String(localized: "Angeheftete Aufnahme"))
        panel.contentView = view; panel.isMovableByWindowBackground = true
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
}

private final class PinnedImageView: NSImageView {
    weak var controller: PinnedImageController?
    weak var panel: NSPanel?
    var isClickThrough = false
    init(controller: PinnedImageController, panel: NSPanel) { self.controller = controller; self.panel = panel; super.init(frame: .zero); setAccessibilityElement(true) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var acceptsFirstResponder: Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let click = NSMenuItem(title: isClickThrough ? String(localized: "Klicks wieder aktivieren") : String(localized: "Klicks durchlassen"), action: #selector(toggleClick), keyEquivalent: "")
        click.target = self; menu.addItem(click)
        let opacity = NSMenuItem(title: String(localized: "Deckkraft"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(); [0.4, 0.6, 0.8, 1.0].forEach { value in
            let item = NSMenuItem(title: "\(Int(value * 100))%", action: #selector(setMenuOpacity(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value; submenu.addItem(item)
        }; opacity.submenu = submenu; menu.addItem(opacity)
        menu.addItem(.separator()); let close = NSMenuItem(title: String(localized: "Schließen"), action: #selector(closePanel), keyEquivalent: "w"); close.keyEquivalentModifierMask = [.command]; close.target = self; menu.addItem(close)
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
    @objc private func toggleClick() { if let panel { controller?.setClickThrough(!panel.ignoresMouseEvents, for: panel) } }
    @objc private func setMenuOpacity(_ item: NSMenuItem) { if let value = item.representedObject as? Double, let panel { controller?.setOpacity(CGFloat(value), for: panel) } }
    @objc private func closePanel() { if let panel { controller?.close(panel) } }
    override func keyDown(with event: NSEvent) {
        guard let panel else { super.keyDown(with: event); return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 2
        var origin = panel.frame.origin
        switch event.keyCode { case 123: origin.x -= step; case 124: origin.x += step; case 125: origin.y -= step; case 126: origin.y += step; case 53: controller?.close(panel); default: super.keyDown(with: event); return }
        panel.setFrameOrigin(origin)
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
