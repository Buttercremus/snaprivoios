import Foundation
import CoreGraphics

/// View-only projection. Document coordinates and output pixels never change.
public struct EditorViewport: Equatable, Sendable {
    public static let zoomRange: ClosedRange<CGFloat> = 0.05...16
    /// Nil fits without enlarging past actual pixels; 1 means one image pixel per screen pixel.
    public private(set) var zoom: CGFloat?
    public private(set) var offset = CGSize.zero
    public init(fitsImage: Bool = true) { zoom = fitsImage ? nil : 1 }

    public func scale(image: CGSize, in bounds: CGRect, backingScale: CGFloat) -> CGFloat {
        if let zoom { return zoom / max(1, backingScale) }
        return min(1 / max(1, backingScale),
                   max(0.001, min(max(1, bounds.width - 48) / max(1, image.width),
                                  max(1, bounds.height - 48) / max(1, image.height))))
    }
    public func imageRect(image: CGSize, in bounds: CGRect, backingScale: CGFloat) -> CGRect {
        let scale = scale(image: image, in: bounds, backingScale: backingScale)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let pan = clampedOffset(offset, imageSize: size, bounds: bounds)
        // Fractional device-pixel origins soften even a 100% image. Keep drawing,
        // hit testing and text on the same pixel-aligned projection.
        let backing = max(1, backingScale)
        let screenScale = scale * backing
        let alignsPixels = screenScale >= 1 && abs(screenScale - screenScale.rounded()) < 0.0001
        let originX = bounds.midX - size.width / 2 + pan.width
        let originY = bounds.midY - size.height / 2 + pan.height
        let x = alignsPixels ? (originX * backing).rounded() / backing : originX
        let y = alignsPixels ? (originY * backing).rounded() / backing : originY
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    public func imagePoint(from viewPoint: CGPoint, image: CGSize, in bounds: CGRect, backingScale: CGFloat) -> CGPoint {
        let rect = imageRect(image: image, in: bounds, backingScale: backingScale)
        let scale = scale(image: image, in: bounds, backingScale: backingScale)
        return CGPoint(x: (viewPoint.x - rect.minX) / scale, y: (viewPoint.y - rect.minY) / scale)
    }
    public mutating func fit() { zoom = nil; offset = .zero }
    public mutating func setZoom(_ value: CGFloat, at anchor: CGPoint, image: CGSize, in bounds: CGRect, backingScale: CGFloat) {
        guard value.isFinite, image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let point = imagePoint(from: anchor, image: image, in: bounds, backingScale: backingScale)
        zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value))
        let scale = scale(image: image, in: bounds, backingScale: backingScale)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        offset = clampedOffset(CGSize(width: anchor.x - point.x * scale - (bounds.midX - size.width / 2),
                                     height: anchor.y - point.y * scale - (bounds.midY - size.height / 2)),
                               imageSize: size, bounds: bounds)
    }
    public mutating func pan(by delta: CGSize, image: CGSize, in bounds: CGRect, backingScale: CGFloat) {
        guard zoom != nil, delta.width.isFinite, delta.height.isFinite else { return }
        let rect = imageRect(image: image, in: bounds, backingScale: backingScale)
        let actual = CGSize(width: rect.midX - bounds.midX, height: rect.midY - bounds.midY)
        offset = clampedOffset(CGSize(width: actual.width + delta.width, height: actual.height + delta.height),
                               imageSize: rect.size, bounds: bounds)
    }
    private func clampedOffset(_ offset: CGSize, imageSize: CGSize, bounds: CGRect) -> CGSize {
        func clamped(_ value: CGFloat, image: CGFloat, view: CGFloat) -> CGFloat {
            guard image > view else { return 0 }
            let limit = (image - view) / 2 + 24
            return min(limit, max(-limit, value))
        }
        return CGSize(width: clamped(offset.width, image: imageSize.width, view: bounds.width),
                      height: clamped(offset.height, image: imageSize.height, view: bounds.height))
    }
}
