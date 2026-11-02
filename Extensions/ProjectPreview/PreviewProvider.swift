import Quartz

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest, completionHandler handler: @escaping (QLPreviewReply?, (any Error)?) -> Void) {
        let url = request.fileURL, completion = QuickLookCompletion(handler)
        Task { @MainActor in
            do {
                let image = try await ProjectPreviewRenderer.shared.image(at: url, maximumDimension: 2048)
                let size = CGSize(width: image.width, height: image.height)
                let reply = QLPreviewReply(contextSize: size, isBitmap: true) { @Sendable context, _ in
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                }
                completion.finish(reply)
            } catch { completion.finish(nil, error: error) }
        }
    }
}
