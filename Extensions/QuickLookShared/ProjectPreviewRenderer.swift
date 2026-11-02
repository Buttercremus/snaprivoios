import AppKit
import ImageIO
import SnagForgeDomain

/// Serial, bounded rendering in each extension process. Never falls back to unredacted pixels.
actor ProjectPreviewRenderer {
    static let shared = ProjectPreviewRenderer()
    static let maximumArchiveBytes = 64_000_000
    static let maximumDecodedPixels = 16_000_000

    func image(at url: URL, maximumDimension: Int) throws -> CGImage {
        guard url.isFileURL, (1...2048).contains(maximumDimension) else { throw ProjectError.invalidDocument }
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try autoreleasepool {
            let data = try ProjectArchive.readRegularFile(url, limit: Self.maximumArchiveBytes)
            let archive = try PropertyListDecoder().decode(ProjectArchive.self, from: data)
            guard archive.document.count <= 8_000_000 else { throw ProjectError.documentTooLarge }
            let document = try archive.validatedDocument()
            guard document.objects.count <= 256,
                  document.objects.reduce(0, { $0 + $1.text.utf16.count }) <= 100_000 else { throw ProjectError.documentTooLarge }
            var pixels = 0
            func reserve(_ size: PixelSize) throws {
                let area = size.width.multipliedReportingOverflow(by: size.height)
                let sum = pixels.addingReportingOverflow(area.partialValue)
                guard !area.overflow, !sum.overflow, area.partialValue > 0,
                      sum.partialValue <= Self.maximumDecodedPixels else { throw ProjectError.fileTooLarge }
                pixels = sum.partialValue
            }
            try reserve(document.pixelSize)
            var assets = Set<String>()
            for asset in document.objects.compactMap(\.imageAsset) where assets.insert(asset.digest).inserted {
                try reserve(asset.size)
            }
            if let background = document.presentation?.background, case .asset(let asset, _) = background,
               assets.insert(asset.digest).inserted { try reserve(asset.size) }
            guard let source = CGImageSourceCreateWithData(archive.original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
                  image.width == document.pixelSize.width, image.height == document.pixelSize.height else { throw ProjectError.invalidDocument }
            try Task.checkCancellation()
            let rendered = try EditorRenderer.render(image: image, objects: document.objects, crop: document.crop,
                resizedSize: document.resizedSize, maxDimension: maximumDimension, canvasRect: document.canvasRect,
                transform: document.transform, presentation: document.presentation)
            try Task.checkCancellation()
            return rendered
        }
    }
    nonisolated static func thumbnailDimension(size: CGSize, scale: CGFloat) throws -> Int {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              (1...1024).contains(size.width), (1...1024).contains(size.height), (0.5...4).contains(scale),
              size.width * scale * size.height * scale <= 4_194_304 else { throw ProjectError.invalidDocument }
        return min(2048, max(1, Int(ceil(max(size.width, size.height) * scale))))
    }
    nonisolated static func fittedRect(image: CGImage, in size: CGSize) -> CGRect {
        let factor = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let width = CGFloat(image.width) * factor, height = CGFloat(image.height) * factor
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// Quick Look permits asynchronous completion. Retain its callback and deliver it once on MainActor.
final class QuickLookCompletion<Reply>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let handler: (Reply?, (any Error)?) -> Void
    init(_ handler: @escaping (Reply?, (any Error)?) -> Void) { self.handler = handler }
    @MainActor func finish(_ reply: Reply?, error: (any Error)? = nil) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true; lock.unlock()
        handler(reply, error)
    }
}
