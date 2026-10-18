import Foundation
import CoreGraphics

/// Handles use the editor's top-left image coordinates, independent of view scale.
public enum EditorResizeHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    public var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    public var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    public var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    public var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX,
                y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
    }
}

public enum EditorGeometry {
    /// Shift drawing: squares/circles and arrow directions in 45-degree increments.
    public static func constrainedEnd(from start: CGPoint, to end: CGPoint, kind: EditorObject.Kind) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if kind == .arrow {
            let step = CGFloat.pi / 4, angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        guard kind.isShape else { return end }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    /// The opposite edge/corner stays fixed; crossing it clamps at the minimum size.
    /// Constrained side handles grow the other dimension about its centre.
    public static func resized(_ rect: CGRect, handle: EditorResizeHandle, delta: CGSize,
                               minimum: CGSize, aspectRatio: CGFloat? = nil) -> CGRect {
        guard delta != .zero else { return rect }
        var width = max(minimum.width, rect.width + (handle.movesLeft ? -delta.width : handle.movesRight ? delta.width : 0))
        var height = max(minimum.height, rect.height + (handle.movesTop ? -delta.height : handle.movesBottom ? delta.height : 0))
        if let ratio = aspectRatio, ratio.isFinite, ratio > 0 {
            if handle.isCorner {
                // Follow the dominant movement so a horizontal/vertical pull can
                // shrink a constrained corner as naturally as it can enlarge it.
                if abs(delta.width) < abs(delta.height) * ratio { width = height * ratio }
                width = max(width, minimum.width, minimum.height * ratio)
                height = width / ratio
            } else if handle.movesLeft || handle.movesRight {
                width = max(width, minimum.height * ratio); height = width / ratio
            } else {
                height = max(height, minimum.width / ratio); width = height * ratio
            }
        }
        let x = handle.movesLeft ? rect.maxX - width : handle.movesRight ? rect.minX : rect.midX - width / 2
        let y = handle.movesTop ? rect.maxY - height : handle.movesBottom ? rect.minY : rect.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
