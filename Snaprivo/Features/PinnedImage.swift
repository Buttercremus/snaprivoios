import AppKit
import SwiftUI

/// A disposable, immutable flattened snapshot; never holds a project or its original.
@MainActor final class PinnedImageController: NSObject, NSWindowDelegate {
    static let shared = PinnedImageController()
    private var panels: [NSPanel] = []
    func show(_ image: CGImage, title: String) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1000, height: 700)
        let factor = min(1, available.width * 0.65 / CGFloat(image.width), available.height * 0.65 / CGFloat(image.height))
        let size = CGSize(width: max(160, CGFloat(image.width) * factor), height: max(100, CGFloat(image.height) * factor))
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = CGSize(width: 160, height: 100)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        let view = NSImageView()
        view.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel(String(localized: "Angeheftete Aufnahme"))
        panel.contentView = view; panel.isMovableByWindowBackground = true
        panel.delegate = self; panels.append(panel)
        panel.center(); panel.orderFrontRegardless()
    }
    func windowWillClose(_ notification: Notification) {
        panels.removeAll { $0 === notification.object as? NSWindow }
    }
}

struct PinImageButton: View {
    let model: EditorModel
    let size: EditorToolbarSize
    @State private var busy = false
    var body: some View {
        Button {
            guard model.hasExportableImage, !busy else { return }
            model.endStyleEditing(); model.finishTextEditing()
            let image = model.image, objects = model.history.objects, crop = model.history.crop, resized = model.history.resizedSize
            let title = model.name
            busy = true
            Task {
                defer { busy = false }
                do {
                    let flattened = try await Task.detached(priority: .userInitiated) {
                        try EditorRenderer.render(image: image, objects: objects, crop: crop, resizedSize: resized)
                    }.value
                    PinnedImageController.shared.show(flattened, title: title)
                } catch { model.error = error.localizedDescription }
            }
        } label: { EditorToolbarLabel(title: String(localized: "Anheften"), symbol: "pin", size: size) }
        .disabled(busy || !model.hasConfirmedImageForToolbar)
        .help(String(localized: "Bearbeitetes Bild über anderen Fenstern anzeigen"))
        .accessibilityIdentifier("editor.pin")
    }
}
