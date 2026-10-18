import AppKit
import ImageIO
import UniformTypeIdentifiers
import SnagForgeDomain

enum ImageOutputFormat: String, CaseIterable, Codable, Sendable { case png, jpeg, pdf
    var type: UTType { switch self { case .png: .png; case .jpeg: .jpeg; case .pdf: .pdf } }
}
struct ImageOutputOptions: Equatable, Codable, Sendable {
    var format = ImageOutputFormat.jpeg
    var quality = 0.9
    var background = EditorColor(red: 1, green: 1, blue: 1)
    var padding = 0
    var cornerRadius = 0.0
    var shadow = false
    static func restored() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "image.output.options.v1"),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.quality.isFinite, (0.1...1).contains(value.quality), (0...500).contains(value.padding),
              value.cornerRadius.isFinite, (0...200).contains(value.cornerRadius),
              [value.background.red, value.background.green, value.background.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return Self() }
        return value
    }
}

enum ImageOutput {
    static func compose(_ image: CGImage, options: ImageOutputOptions) throws -> CGImage {
        let padding = max(0, min(500, options.padding)), width = image.width + 2 * padding, height = image.height + 2 * padding
        guard width <= 32768, height <= 32768, Int64(width) * Int64(height) <= 100_000_000,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProjectError.fileTooLarge }
        let color = options.background
        ctx.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1))
        // JPEG is always opaque; PNG/PDF retain source transparency when no presentation is requested.
        if options.format == .jpeg || padding > 0 || options.cornerRadius > 0 || options.shadow { ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        let rect = CGRect(x: padding, y: padding, width: image.width, height: image.height)
        let radius = max(0, min(options.cornerRadius, CGFloat(min(image.width, image.height)) / 2))
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if options.shadow {
            ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: CGColor(gray: 0, alpha: 0.3))
            ctx.addPath(path); ctx.fillPath(); ctx.restoreGState()
        }
        ctx.addPath(path); ctx.clip(); ctx.draw(image, in: rect)
        guard let output = ctx.makeImage() else { throw ProjectError.invalidDocument }
        return output
    }
    static func encode(_ image: CGImage, options: ImageOutputOptions) throws -> Data {
        let data = NSMutableData()
        if options.format == .pdf {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ProjectError.invalidDocument }
            context.beginPDFPage(nil); context.draw(image, in: box); context.endPDFPage(); context.closePDF()
        } else {
            guard let destination = CGImageDestinationCreateWithData(data, options.format.type.identifier as CFString, 1, nil) else { throw ProjectError.invalidDocument }
            CGImageDestinationAddImage(destination, image, options.format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: max(0.1, min(1, options.quality))] as CFDictionary : nil)
            guard CGImageDestinationFinalize(destination) else { throw ProjectError.invalidDocument }
        }
        return data as Data
    }
}

actor ImageOutputProcessor {
    static let shared = ImageOutputProcessor()
    func compose(_ image: CGImage, options: ImageOutputOptions) throws -> CGImage {
        try Task.checkCancellation()
        return try ImageOutput.compose(image, options: options)
    }
}
