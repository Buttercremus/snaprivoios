import QuickLookThumbnailing
import CoreGraphics

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let url = request.fileURL, size = request.maximumSize, scale = request.scale
        let completion = QuickLookCompletion(handler)
        Task { @MainActor in
            do {
                let dimension = try ProjectPreviewRenderer.thumbnailDimension(size: size, scale: scale)
                let image = try await ProjectPreviewRenderer.shared.image(at: url, maximumDimension: dimension)
                let reply = QLThumbnailReply(contextSize: size) { @Sendable context in
                    context.interpolationQuality = .high
                    context.draw(image, in: ProjectPreviewRenderer.fittedRect(image: image, in: size))
                    return true
                }
                completion.finish(reply)
            } catch { completion.finish(nil, error: error) }
        }
    }
}
