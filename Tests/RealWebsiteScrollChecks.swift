import Foundation
import ImageIO
import CoreGraphics
import SnagForgeDomain

@main struct RealWebsiteScrollChecks {
    static func frame(_ url: URL, crop: CGRect?) throws -> ScrollFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let image = crop.flatMap({ original.cropping(to: original.width < 1000 ? CGRect(x: 20, y: 120, width: original.width - 40, height: original.height - 140) : $0) }) ?? Optional(original) else { throw ScrollStitchError.dimensions }
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        let valid = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard valid else { throw ScrollStitchError.dimensions }
        return try ScrollFrame(width: image.width, height: image.height, pixels: pixels)
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for (site, crop) in [("apple", CGRect(x: 430, y: 100, width: 780, height: 600)),
                             ("swift", CGRect(x: 430, y: 65, width: 780, height: 635)),
                             ("wiki", CGRect(x: 270, y: 180, width: 710, height: 510))] {
            for cropped in [false, true] {
                let frames = try (0...2).map { try frame(root.appendingPathComponent("\(site)-\($0).png"), crop: cropped ? crop : nil) }
                for i in 0..<2 {
                    do { print("\(site) \(cropped ? "content" : "full") \(i): displacement=\(try ScrollStitcher.displacement(from: frames[i], to: frames[i+1]))") }
                    catch { print("\(site) \(cropped ? "content" : "full") \(i): rejected=\(error)") }
                }
            }
        }
    }
}
