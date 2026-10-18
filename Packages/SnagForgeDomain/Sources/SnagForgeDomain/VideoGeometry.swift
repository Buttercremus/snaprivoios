import Foundation
import CoreGraphics

public enum VideoGeometryError: Error { case invalidRegion }

/// SCK source coordinates are display-local points; H.264 output uses even pixels.
public struct VideoGeometry: Equatable, Sendable {
    public let sourceRect: CGRect
    public let pixelSize: PixelSize
    /// Window capture uses its complete content size, independent of desktop position.
    public init(contentSize: CGSize, scale: CGFloat) throws {
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { throw VideoGeometryError.invalidRegion }
        let bounds = CGRect(origin: .zero, size: contentSize)
        try self.init(selection: bounds, screen: bounds, scale: scale)
    }
    public init(selection: CGRect, screen: CGRect, scale: CGFloat) throws {
        guard [selection.minX, selection.minY, selection.width, selection.height,
               screen.minX, screen.minY, screen.width, screen.height, scale].allSatisfy(\.isFinite),
              screen.width > 0, screen.height > 0,
              let source = CaptureGeometry.sourceRect(selection: selection, screen: screen, scale: scale) else {
            throw VideoGeometryError.invalidRegion
        }
        let width = source.width * scale, height = source.height * scale
        guard width.isFinite, height.isFinite, width >= 2, height >= 2 else { throw VideoGeometryError.invalidRegion }
        let ratio = min(1, 1920 / width, 1080 / height)
        let w = Int((width * ratio / 2).rounded(.down)) * 2
        let h = Int((height * ratio / 2).rounded(.down)) * 2
        guard w >= 2, h >= 2, let size = PixelSize(width: w, height: h) else { throw VideoGeometryError.invalidRegion }
        sourceRect = source; pixelSize = size
    }
}
