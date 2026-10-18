import Foundation
import CoreGraphics

/// A crop is an integer pixel rectangle in the immutable original's top-left space.
/// Annotation coordinates never change. Nil in a document means the full original.
public enum EditorCrop {
    public static func fullRect(_ size: PixelSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }
    /// Round each edge to the nearest pixel, clamp to the original and retain at least one pixel.
    public static func normalized(_ rect: CGRect, in size: PixelSize) -> CGRect? {
        guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite),
              rect.width != 0, rect.height != 0 else { return nil }
        let rect = rect.standardized
        let left = min(CGFloat(size.width - 1), max(0, rect.minX.rounded()))
        let top = min(CGFloat(size.height - 1), max(0, rect.minY.rounded()))
        let right = min(CGFloat(size.width), max(left + 1, rect.maxX.rounded()))
        let bottom = min(CGFloat(size.height), max(top + 1, rect.maxY.rounded()))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    public static func isValid(_ rect: CGRect, in size: PixelSize) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite && $0.rounded() == $0 } &&
        rect.size.width >= 1 && rect.size.height >= 1 && rect.minX >= 0 && rect.minY >= 0 &&
        rect.maxX <= CGFloat(size.width) && rect.maxY <= CGFloat(size.height)
    }
    public static func moved(_ rect: CGRect, by delta: CGSize, in size: PixelSize) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return rect }
        return CGRect(x: min(CGFloat(size.width) - rect.width, max(0, rect.minX + delta.width.rounded())),
                      y: min(CGFloat(size.height) - rect.height, max(0, rect.minY + delta.height.rounded())),
                      width: rect.width, height: rect.height)
    }
    /// Each edge is limited before resizing, so the opposite edge stays fixed at the image boundary.
    public static func resized(_ rect: CGRect, handle: EditorResizeHandle, by delta: CGSize, in size: PixelSize) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return rect }
        let left = handle.movesLeft ? min(rect.maxX - 1, max(0, rect.minX + delta.width.rounded())) : rect.minX
        let right = handle.movesRight ? max(rect.minX + 1, min(CGFloat(size.width), rect.maxX + delta.width.rounded())) : rect.maxX
        let top = handle.movesTop ? min(rect.maxY - 1, max(0, rect.minY + delta.height.rounded())) : rect.minY
        let bottom = handle.movesBottom ? max(rect.minY + 1, min(CGFloat(size.height), rect.maxY + delta.height.rounded())) : rect.maxY
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
