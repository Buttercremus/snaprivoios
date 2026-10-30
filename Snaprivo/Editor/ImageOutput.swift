import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SnagForgeDomain

enum ImageOutputFormat: String, CaseIterable, Codable, Sendable { case png, jpeg, pdf
    var type: UTType { switch self { case .png: .png; case .jpeg: .jpeg; case .pdf: .pdf } }
}
struct ImageOutputOptions: Equatable, Codable, Sendable {
    var includesBackground: Bool?
    var rotationDegrees = 0.0
    var format = ImageOutputFormat.jpeg
    var quality = 0.9
    var background = EditorColor(red: 1, green: 1, blue: 1)
    var padding = 0
    var border: EditorImageBorder?
    var cornerRadius = 0.0
    var shadow = false
    var shadowStrength = 0.0
    var backgroundStyle = PresentationBackground.solid(EditorColor(red: 1, green: 1, blue: 1))
    var aspectRatio = PresentationAspectRatio.natural
    var alignment = PresentationAlignment.center
    init() {}
    var isValid: Bool {
        rotationDegrees.isFinite && (-180...180).contains(rotationDegrees) && backgroundStyle.isValid && quality.isFinite && (0.1...1).contains(quality) && (0...500).contains(padding) &&
        border?.isValid != false && cornerRadius.isFinite && (0...200).contains(cornerRadius) &&
        shadowStrength.isFinite && (0...1).contains(shadowStrength) &&
        [background.red, background.green, background.blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
    var hasPresentation: Bool { border != nil || includesBackground == true || rotationDegrees != 0 || padding != 0 || cornerRadius != 0 || shadow || shadowStrength != 0.0 || aspectRatio != .natural || backgroundStyle != .solid(EditorColor(red: 1, green: 1, blue: 1)) || background != EditorColor(red: 1, green: 1, blue: 1) }
    var withoutPresentation: Self {
        var value = self
        value.border = nil; value.includesBackground = false; value.rotationDegrees = 0; value.padding = 0; value.cornerRadius = 0; value.shadow = false
        value.shadowStrength = 0.0
        value.background = EditorColor(red: 1, green: 1, blue: 1)
        value.backgroundStyle = .solid(EditorColor(red: 1, green: 1, blue: 1))
        value.aspectRatio = .natural
        value.alignment = .center
        return value
    }
    enum CodingKeys: String, CodingKey { case border, includesBackground, rotationDegrees, format, quality, background, padding, cornerRadius, shadow, shadowStrength, backgroundStyle, aspectRatio, alignment }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        border = try c.decodeIfPresent(EditorImageBorder.self, forKey: .border)
        includesBackground = try c.decodeIfPresent(Bool.self, forKey: .includesBackground)
        rotationDegrees = try c.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        format = try c.decodeIfPresent(ImageOutputFormat.self, forKey: .format) ?? .jpeg
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.9
        background = try c.decodeIfPresent(EditorColor.self, forKey: .background) ?? EditorColor(red: 1, green: 1, blue: 1)
        padding = try c.decodeIfPresent(Int.self, forKey: .padding) ?? 0
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false
        shadowStrength = try c.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? (shadow ? 0.3 : 0.0)
        backgroundStyle = try c.decodeIfPresent(PresentationBackground.self, forKey: .backgroundStyle) ?? .solid(background)
        aspectRatio = try c.decodeIfPresent(PresentationAspectRatio.self, forKey: .aspectRatio) ?? .natural
        alignment = try c.decodeIfPresent(PresentationAlignment.self, forKey: .alignment) ?? .center
        guard isValid else { throw CocoaError(.propertyListReadCorrupt) }
    }
    init(presentation: EditorPresentation) {
        border = presentation.border
        includesBackground = presentation.background != nil
        rotationDegrees = presentation.rotationDegrees; padding = presentation.padding; cornerRadius = presentation.cornerRadius
        shadow = presentation.shadowStrength > 0; shadowStrength = presentation.shadowStrength
        backgroundStyle = presentation.background ?? .solid(EditorColor(red: 1, green: 1, blue: 1))
        if case .solid(let color) = backgroundStyle { background = color }
        aspectRatio = presentation.aspectRatio; alignment = presentation.alignment
    }
    var presentation: EditorPresentation {
        var result = EditorPresentation()
        result.border = border; result.rotationDegrees = rotationDegrees; result.padding = padding; result.cornerRadius = cornerRadius
        result.shadowStrength = shadow ? shadowStrength : 0
        result.background = (includesBackground ?? hasPresentation) ? (backgroundStyle == .solid(EditorColor(red: 1, green: 1, blue: 1)) ? .solid(background) : backgroundStyle) : nil
        result.aspectRatio = aspectRatio; result.alignment = alignment
        return result
    }
    static func restored() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "image.output.options.v1"),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.quality.isFinite, (0.1...1).contains(value.quality), (0...500).contains(value.padding),
              value.cornerRadius.isFinite, (0...200).contains(value.cornerRadius), value.shadowStrength.isFinite, (0...1).contains(value.shadowStrength),
              [value.background.red, value.background.green, value.background.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return Self() }
        return value
    }
}

enum ImageOutput {
    static func compose(_ image: CGImage, options: ImageOutputOptions) throws -> CGImage {
        var presentation = options.presentation
        presentation.padding = max(0, min(500, presentation.padding))
        var override: PresentationBackground?
        if case .image = presentation.background { override = presentation.background; presentation.background = nil }
        if options.format == .jpeg, presentation.background == nil, override == nil { presentation.background = .solid(options.background) }
        return try EditorRenderer.presented(image, by: presentation, backgroundOverride: override)
    }
    static func encode(_ image: CGImage, options: ImageOutputOptions) throws -> Data {
        let estimate = EditorRenderer.rasterMemoryEstimate(image: image, encoding: true)
        return try EditorRenderer.withRasterReservation(estimate) { try encodeUnbudgeted(image, options: options) }
    }
    private static func encodeUnbudgeted(_ image: CGImage, options: ImageOutputOptions) throws -> Data {
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
