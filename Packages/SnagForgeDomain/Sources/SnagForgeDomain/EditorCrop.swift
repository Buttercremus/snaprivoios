import Foundation
import CoreGraphics

/// A crop is an integer pixel rectangle in the immutable original's top-left space.
/// Annotation coordinates never change. Nil in a document means the full canvas.
public enum EditorCrop {
    public static func fullRect(_ size: PixelSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }
    /// Round each edge to the nearest pixel, clamp to the supplied bounds and retain at least one pixel.
    public static func normalized(_ rect: CGRect, in size: PixelSize) -> CGRect? {
        normalized(rect, in: fullRect(size))
    }
    public static func normalized(_ rect: CGRect, in bounds: CGRect) -> CGRect? {
        guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite),
              rect.width != 0, rect.height != 0 else { return nil }
        let rect = rect.standardized
        let left = min(bounds.maxX - 1, max(bounds.minX, rect.minX.rounded()))
        let top = min(bounds.maxY - 1, max(bounds.minY, rect.minY.rounded()))
        let right = min(bounds.maxX, max(left + 1, rect.maxX.rounded()))
        let bottom = min(bounds.maxY, max(top + 1, rect.maxY.rounded()))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    public static func isValid(_ rect: CGRect, in size: PixelSize) -> Bool {
        isValid(rect, in: fullRect(size))
    }
    public static func isValid(_ rect: CGRect, in bounds: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite && $0.rounded() == $0 } &&
        rect.size.width >= 1 && rect.size.height >= 1 && rect.minX >= bounds.minX && rect.minY >= bounds.minY &&
        rect.maxX <= bounds.maxX && rect.maxY <= bounds.maxY
    }
    public static func moved(_ rect: CGRect, by delta: CGSize, in size: PixelSize) -> CGRect {
        moved(rect, by: delta, in: fullRect(size))
    }
    public static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return rect }
        return CGRect(x: min(bounds.maxX - rect.width, max(bounds.minX, rect.minX + delta.width.rounded())),
                      y: min(bounds.maxY - rect.height, max(bounds.minY, rect.minY + delta.height.rounded())),
                      width: rect.width, height: rect.height)
    }
    /// Each edge is limited before resizing, so the opposite edge stays fixed at the image boundary.
    public static func resized(_ rect: CGRect, handle: EditorResizeHandle, by delta: CGSize, in size: PixelSize) -> CGRect {
        resized(rect, handle: handle, by: delta, in: fullRect(size))
    }
    public static func resized(_ rect: CGRect, handle: EditorResizeHandle, by delta: CGSize, in bounds: CGRect) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return rect }
        let left = handle.movesLeft ? min(rect.maxX - 1, max(bounds.minX, rect.minX + delta.width.rounded())) : rect.minX
        let right = handle.movesRight ? max(rect.minX + 1, min(bounds.maxX, rect.maxX + delta.width.rounded())) : rect.maxX
        let top = handle.movesTop ? min(rect.maxY - 1, max(bounds.minY, rect.minY + delta.height.rounded())) : rect.minY
        let bottom = handle.movesBottom ? max(rect.minY + 1, min(bounds.maxY, rect.maxY + delta.height.rounded())) : rect.maxY
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// Integer source-space canvas, including transparent space beyond the immutable original.
public enum EditorCanvasExtent {
    public static func isValid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite && $0.rounded() == $0 && abs($0) <= 1_000_000 } &&
        rect.width >= 1 && rect.height >= 1 && rect.width <= 32768 && rect.height <= 32768 && rect.width * rect.height <= 100_000_000
    }
    public static func expanded(_ current: CGRect, including content: CGRect) -> CGRect? {
        guard isValid(current), !content.isNull,
              [content.minX, content.minY, content.maxX, content.maxY].allSatisfy(\.isFinite) else { return nil }
        let left = min(current.minX, floor(content.minX)), top = min(current.minY, floor(content.minY))
        let right = max(current.maxX, ceil(content.maxX)), bottom = max(current.maxY, ceil(content.maxY))
        let next = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return isValid(next) ? next : nil
    }
}
