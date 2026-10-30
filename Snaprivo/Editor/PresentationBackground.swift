import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SnagForgeDomain

extension PresentationAspectRatio {
    var label: String { switch self { case .natural: String(localized: "Natürlich"); case .square: "1:1"; case .landscape: "4:3"; case .wide: "16:9"; case .portrait: "9:16" } }
}
extension PresentationAlignment {
    var label: String { switch self { case .topLeading: String(localized: "Oben links"); case .top: String(localized: "Oben"); case .topTrailing: String(localized: "Oben rechts"); case .leading: String(localized: "Links"); case .center: String(localized: "Mitte"); case .trailing: String(localized: "Rechts"); case .bottomLeading: String(localized: "Unten links"); case .bottom: String(localized: "Unten"); case .bottomTrailing: String(localized: "Unten rechts") } }
}

enum PresentationBackgroundCatalog {
    static let gradients: [PresentationGradient] = {
        let palettes: [[(Double, Double, Double)]] = [
            [(0.98,0.35,0.48),(0.49,0.22,0.95)], [(0.11,0.78,0.88),(0.17,0.32,0.89)], [(1,0.63,0.25),(0.95,0.16,0.39)], [(0.18,0.9,0.65),(0.12,0.45,0.72)], [(0.36,0.18,0.87),(0.94,0.28,0.72)], [(0.99,0.82,0.37),(0.95,0.4,0.21)], [(0.03,0.18,0.36),(0.12,0.52,0.75)], [(0.8,0.91,1),(0.54,0.7,0.98)], [(0.93,0.95,0.98),(0.72,0.8,0.9)], [(0.12,0.12,0.2),(0.35,0.18,0.6)], [(0.96,0.45,0.66),(0.99,0.78,0.48)], [(0.05,0.7,0.58),(0.42,0.2,0.78)], [(0.98,0.94,0.75),(0.98,0.56,0.3)], [(0.12,0.33,0.6),(0.36,0.88,0.8)], [(0.54,0.27,0.84),(0.2,0.63,0.88)], [(0.95,0.28,0.28),(0.97,0.59,0.25)], [(0.1,0.1,0.16),(0.46,0.46,0.62)], [(0.34,0.78,0.99),(0.86,0.38,0.98)], [(0.98,0.69,0.76),(0.72,0.47,0.98)], [(0.4,0.9,0.77),(0.95,0.92,0.4)]
        ]
        return palettes.enumerated().map { PresentationGradient(colors: $0.element.map { EditorColor(red: $0.0, green: $0.1, blue: $0.2) }, angle: Double(($0.offset * 37) % 360)) }
    }()
}

enum PresentationBackgroundStorage {
    /// Normalize and embed bounded source pixels; projects never depend on an external path.
    static func importAsset(from source: URL) throws -> EditorImageAsset {
        let data = try ProjectArchive.readRegularFile(source, limit: Int(maxBytes))
        guard let ref = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(ref, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8000, height <= 8000, Int64(width) * Int64(height) <= 64_000_000 else { throw ProjectError.invalidDocument }
        for dimension in [4096, 3072, 2048, 1536, 1024] {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateThumbnailAtIndex(ref, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw ProjectError.invalidDocument }
            let png = try EditorRenderer.png(image: image, objects: [])
            if png.count <= 8_000_000 { return try EditorImageAsset(png: png, size: PixelSize(width: image.width, height: image.height)!) }
        }
        throw ProjectError.fileTooLarge
    }
    static let maxBytes: Int64 = 100 * 1024 * 1024
    static func importImage(from source: URL, storingIn destinationRoot: URL? = nil) throws -> URL {
        let data = try ProjectArchive.readRegularFile(source, limit: Int(maxBytes))
        guard let sourceRef = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(sourceRef) >= 1,
              let props = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8000, height <= 8000,
              Int64(width) * Int64(height) <= 64_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let dir: URL
        if let destinationRoot { dir = destinationRoot }
        else { dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Snaprivo/PresentationBackgrounds", isDirectory: true) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        guard let image = CGImageSourceCreateThumbnailAtIndex(sourceRef, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 8000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let out = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { try? FileManager.default.removeItem(at: destination); throw CocoaError(.fileWriteUnknown) }
        return destination
    }
}
