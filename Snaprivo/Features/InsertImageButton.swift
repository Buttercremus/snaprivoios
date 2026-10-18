import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SnagForgeDomain

struct InsertImageButton: View {
    let model: EditorModel
    let size: EditorToolbarSize
    @State private var busy = false
    var body: some View {
        Button {
            guard model.hasExportableImage, !busy else { return }
            guard model.requestFeature(.insertedImages) else { return }
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            model.endStyleEditing(); model.finishTextEditing(); busy = true
            Task {
                defer { busy = false }
                do {
                    let asset = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try ProjectArchive.readRegularFile(url, limit: 32_000_000)
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: 4096,
                                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ProjectError.invalidDocument }
                        let png = try EditorRenderer.png(image: image, objects: [])
                        let asset = try EditorImageAsset(png: png, size: PixelSize(width: image.width, height: image.height)!)
                        guard EditorRenderer.assetImage(asset) != nil else { throw ProjectError.invalidDocument }
                        return asset
                    }.value
                    guard !model.isSwitchingImage, model.history.objects.count < 10_000 else { return }
                    let area = model.document.outputRect
                    let factor = min(1, area.width * 0.65 / CGFloat(asset.size.width), area.height * 0.65 / CGFloat(asset.size.height))
                    let w = max(1, CGFloat(asset.size.width) * factor), h = max(1, CGFloat(asset.size.height) * factor)
                    var object = EditorObject(kind: .image, start: CGPoint(x: area.midX - w / 2, y: area.midY - h / 2), end: CGPoint(x: area.midX + w / 2, y: area.midY + h / 2))
                    object.imageAsset = asset
                    var validation = model.document; validation.objects = model.history.objects + [object]
                    _ = try validation.validated()
                    model.commit(validation.objects); model.tool = .selection; model.selection = object.id; model.focusRequest += 1
                } catch { model.error = error.localizedDescription }
            }
        } label: { EditorToolbarLabel(title: String(localized: "Bild einfügen"), symbol: "photo.badge.plus", size: size, extraWidth: 18) }
        .disabled(busy || !model.hasConfirmedImageForToolbar)
    }
}
