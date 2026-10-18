import Foundation
import CoreGraphics
import CoreText
import ImageIO
import SnagForgeDomain

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
    static func cleanCopy(_ document: GuideDocument) throws -> GuideDocument {
        var value = try document.validated()
        for i in value.steps.indices {
            try Task.checkCancellation()
            // Re-encode imported pixels too: PNG ancillary metadata is never an output asset.
            value.steps[i].png = try EditorRenderer.png(image: image(value.steps[i].png), objects: [])
            value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil
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
                                             resizedSize: document.resizedSize, maxDimension: 2560)
        return GuideStep(title: String(document.title.prefix(256)), png: try EditorRenderer.png(image: flat, objects: []),
                         sourceProjectID: document.id, sourceLibrary: library)
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
            try writer.newPage()
            try writer.text("\(index + 1). \(step.title)", size: 20, bold: true)
            writer.cursor += 16
            let image = try image(step.png)
            if writer.available < 120 { try writer.newPage() }
            let maxHeight = min(writer.available - 16, document.style == .compact ? 330 : 420)
            let scale = min(writer.width / CGFloat(image.width), maxHeight / CGFloat(image.height))
            let rect = CGRect(x: box.midX - CGFloat(image.width) * scale / 2,
                              y: box.height - writer.cursor - CGFloat(image.height) * scale,
                              width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high; context.draw(image, in: rect)
            writer.cursor += rect.height + 16
            try writer.text(step.caption, size: document.style == .compact ? 11 : 12)
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
