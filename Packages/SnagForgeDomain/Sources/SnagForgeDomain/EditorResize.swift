import Foundation
import CoreGraphics

/// Final document scale. Original pixels, crop and annotation geometry stay immutable in source space.
public enum EditorResize {
    public static func isValid(_ size: PixelSize) -> Bool {
        size.width <= 32768 && size.height <= 32768 && Int64(size.width) * Int64(size.height) <= 100_000_000
    }
    public static func size(width: Double, height: Double) -> PixelSize? {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= 32768, height <= 32768,
              let value = PixelSize(width: Int(width.rounded()), height: Int(height.rounded())), isValid(value) else { return nil }
        return value
    }
    public static func linkedDimension(value: Double, changingWidth: Bool, ratio: CGSize) -> Double? {
        guard value.isFinite, (1...32768).contains(value), ratio.width.isFinite, ratio.height.isFinite,
              ratio.width >= 1, ratio.height >= 1, ratio.width <= 32768, ratio.height <= 32768 else { return nil }
        return max(1, (value * (changingWidth ? ratio.height / ratio.width : ratio.width / ratio.height)).rounded())
    }
    /// Crop changes preserve the existing X/Y scale rather than stretching the new crop to old dimensions.
    public static func preservingScale(from previous: CGRect, to next: CGRect, output: PixelSize?) throws -> PixelSize? {
        guard let output else { return nil }
        guard previous.width > 0, previous.height > 0,
              let size = size(width: max(1, next.width * CGFloat(output.width) / previous.width),
                              height: max(1, next.height * CGFloat(output.height) / previous.height)) else { throw ProjectError.invalidDocument }
        return CGSize(width: size.width, height: size.height) == next.size ? nil : size
    }
}

/// Shared affine projection also supports a deliberately unlocked aspect ratio.
public struct EditorImageProjection: Sendable {
    public let source: CGRect
    public let destination: CGRect
    public var scaleX: CGFloat { destination.width / source.width }
    public var scaleY: CGFloat { destination.height / source.height }
    public init(source: CGRect, destination: CGRect) { self.source = source; self.destination = destination }
    public func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: destination.minX + (point.x - source.minX) * scaleX,
                y: destination.minY + (point.y - source.minY) * scaleY)
    }
    public func sourcePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: source.minX + (point.x - destination.minX) / scaleX,
                y: source.minY + (point.y - destination.minY) / scaleY)
    }
    public func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot((a.x - b.x) * scaleX, (a.y - b.y) * scaleY)
    }
}
