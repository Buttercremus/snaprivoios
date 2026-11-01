import Foundation
import CoreGraphics
import CoreText
import ImageIO
import SnagForgeDomain

/// Bounded, transient UI pixels that are never persisted.
struct GuideImagePreviews: Sendable {
    struct Entry: Sendable {
        let data: Data
        let overview: CGImage
        let detail: CGImage?
    }
    var entries: [UUID: Entry] = [:]
    func image(for step: GuideStep, overview: Bool) -> CGImage? {
        guard let entry = entries[step.id], entry.data == step.png else { return nil }
        return overview ? entry.overview : entry.detail
    }
}

enum GuideExporter {
    static func image(_ data: Data) throws -> CGImage {
        guard let size = GuideDocument.pngSize(data), let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              image.width == size.width, image.height == size.height else { throw ProjectError.invalidDocument }
        return image
    }
    static func validateImages(_ document: GuideDocument) throws {
        _ = try document.validated()
        for step in document.steps { try Task.checkCancellation(); _ = try image(step.png) }
    }
    /// Reuse the mandatory validation decode so new views have pixels in their first frame.
    /// Detail pixels are limited to the first three steps and an optional search target.
    static func preparePreviews(_ document: GuideDocument, revealing target: UUID? = nil) throws -> GuideImagePreviews {
        _ = try document.validated()
        var result = GuideImagePreviews()
        for (index, step) in document.steps.enumerated() {
            try Task.checkCancellation()
            let pixels = try image(step.png)
            let detail = index < 3 || step.id == target ? try scaledPreview(pixels, maximumDimension: 1280) : nil
            result.entries[step.id] = GuideImagePreviews.Entry(data: step.png,
                overview: try scaledPreview(pixels, maximumDimension: 112), detail: detail)
        }
        return result
    }
    static func scaledPreview(_ image: CGImage, maximumDimension: Int) throws -> CGImage {
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ProjectError.invalidDocument
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let preview = context.makeImage() else { throw ProjectError.invalidDocument }
        return preview
    }
    static func cleanCopy(_ document: GuideDocument) throws -> GuideDocument {
        var value = try document.validated()
        for i in value.steps.indices {
            try Task.checkCancellation()
            // Re-encode imported pixels too: PNG ancillary metadata is never an output asset.
            value.steps[i].png = try EditorRenderer.png(image: image(value.steps[i].png), objects: [])
            value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil; value.steps[i].sourceRevision = nil
        }
        return value
    }
    static func snapshot(_ loaded: LoadedProject, library: String) throws -> GuideStep {
        guard let source = CGImageSourceCreateWithData(loaded.original as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              original.width == loaded.document.pixelSize.width,
              original.height == loaded.document.pixelSize.height else { throw ProjectError.invalidDocument }
        let document = loaded.document
        let flat = try EditorRenderer.render(image: original, objects: document.objects, crop: document.crop,
                                             resizedSize: document.resizedSize, maxDimension: 2560, canvasRect: document.canvasRect, transform: document.transform, presentation: document.presentation)
        return GuideStep(title: String(document.title.prefix(256)), png: try EditorRenderer.png(image: flat, objects: []),
                         sourceProjectID: document.id, sourceLibrary: library, sourceRevision: loaded.generation)
    }
    static func pdf(_ document: GuideDocument) throws -> Data {
        try validateImages(document)
        guard !document.steps.isEmpty else { throw ProjectError.invalidDocument }
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ProjectError.invalidDocument }
        let writer = PDFWriter(context: context, box: box)
        try writer.newPage()
        try writer.text(document.title, size: 28, bold: true)
        writer.cursor += 20
        try writer.text(document.introduction, size: 12)
        for (index, step) in document.steps.enumerated() {
            try Task.checkCancellation()
            let image = try image(step.png)
            let title = "\(index + 1). \(step.title)", captionSize: CGFloat = document.style == .compact ? 11 : 12
            let imageHeight = min(document.style == .compact ? 220.0 : 420.0, writer.width * CGFloat(image.height) / CGFloat(image.width))
            let titleHeight = writer.textHeight(title, size: 20, bold: true)
            let captionHeight = writer.textHeight(step.caption, size: captionSize)
            let entireStep = titleHeight + 16 + imageHeight + 16 + captionHeight + 16
            let minimumStep = titleHeight + 16 + imageHeight + 16 + min(captionHeight, captionSize * 3)
            let needed = entireStep <= writer.pageHeight ? entireStep : minimumStep
            if document.style == .standard && (document.includesCover || index > 0) {
                try writer.newPage()
            } else if index == 0 && document.includesCover || writer.available < needed {
                try writer.newPage()
            }
            try writer.text(title, size: 20, bold: true)
            writer.cursor += 16
            if writer.available < 120 { try writer.newPage() }
            let maxHeight = min(writer.available - 16, imageHeight)
            let scale = min(writer.width / CGFloat(image.width), maxHeight / CGFloat(image.height))
            let rect = CGRect(x: box.midX - CGFloat(image.width) * scale / 2,
                              y: box.height - writer.cursor - CGFloat(image.height) * scale,
                              width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high; context.draw(image, in: rect)
            writer.cursor += rect.height + 16
            try writer.text(step.caption, size: captionSize)
            writer.cursor += 16
        }
        writer.endPage(); context.closePDF()
        return bytes as Data
    }
    /// A new, complete folder is published only after every image and the Markdown exist.
    static func markdown(_ document: GuideDocument, to destination: URL) throws {
        try validateImages(document)
        guard !document.steps.isEmpty else { throw ProjectError.invalidDocument }
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".guide-\(UUID())")
        try files.createDirectory(at: staging.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        try Data(GuideMarkdown.text(document).utf8).write(to: staging.appendingPathComponent("Anleitung.md"))
        for (index, step) in document.steps.enumerated() {
            try Task.checkCancellation()
            let pixels = try EditorRenderer.png(image: image(step.png), objects: [])
            try pixels.write(to: staging.appendingPathComponent("images/\(String(format: "%04d", index + 1)).png"))
        }
        try Task.checkCancellation()
        try files.moveItem(at: staging, to: destination)
    }
}

private final class PDFWriter {
    let context: CGContext
    let box: CGRect
    let margin: CGFloat = 48
    var cursor: CGFloat = 48
    var page = 0
    var width: CGFloat { box.width - 2 * margin }
    var available: CGFloat { box.height - margin - cursor }
    var pageHeight: CGFloat { box.height - 2 * margin }
    init(context: CGContext, box: CGRect) { self.context = context; self.box = box }
    func newPage() throws {
        try Task.checkCancellation()
        endPage(); page += 1
        guard page <= 1000 else { throw ProjectError.documentTooLarge }
        context.beginPDFPage(nil); cursor = margin
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
    }
    func endPage() {
        guard page > 0 else { return }
        let line = CTLineCreateWithAttributedString(attributed("\(page)", size: 9, bold: false))
        context.textMatrix = .identity; context.textPosition = CGPoint(x: box.midX - 4, y: 24)
        CTLineDraw(line, context); context.endPDFPage()
    }
    func attributed(_ value: String, size: CGFloat, bold: Bool) -> CFAttributedString {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        return CFAttributedStringCreate(nil, value as CFString,
            [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.12, alpha: 1)] as CFDictionary)!
    }
    func textHeight(_ value: String, size: CGFloat, bold: Bool = false) -> CGFloat {
        guard !value.isEmpty else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(attributed(value, size: size, bold: bold))
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(measured.height) + size * 0.5 + 6
    }
    func text(_ value: String, size: CGFloat, bold: Bool = false) throws {
        guard !value.isEmpty else { return }
        let string = attributed(value, size: size, bold: bold)
        let setter = CTFramesetterCreateWithAttributedString(string)
        let length = CFAttributedStringGetLength(string)
        var offset = 0
        while offset < length {
            if available < size * 2 { try newPage() }
            let bounds = CGSize(width: width, height: available)
            var fit = CFRange()
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: offset, length: length - offset), nil, bounds, &fit)
            let height = min(available, ceil(measured.height) + size * 0.5)
            let rect = CGRect(x: margin, y: box.height - cursor - height, width: width, height: height)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: length - offset), CGPath(rect: rect, transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw ProjectError.invalidDocument }
            context.textMatrix = .identity; CTFrameDraw(frame, context)
            offset += visible.length; cursor += height + 6
            if offset < length { try newPage() }
        }
    }
}
