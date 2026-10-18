import Foundation
import CoreGraphics

/// Coordinate conversions are pure and do not depend on AppKit screen objects.
public enum CaptureGeometry {
    /// Movement smaller than this remains a click on the detected window.
    public static func isSelectionDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= 4
    }
    public static func quartzPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func appKitRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func selection(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
    }

    /// Local top-left display points, aligned outwards to full output pixels.
    public static func sourceRect(selection: CGRect, screen: CGRect, scale: CGFloat) -> CGRect? {
        guard scale.isFinite, scale > 0 else { return nil }
        let clipped = selection.intersection(screen)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        let x0 = floor((clipped.minX - screen.minX) * scale)
        let y0 = floor((screen.maxY - clipped.maxY) * scale)
        let x1 = ceil((clipped.maxX - screen.minX) * scale)
        let y1 = ceil((screen.maxY - clipped.minY) * scale)
        return CGRect(x: x0 / scale, y: y0 / scale, width: (x1 - x0) / scale, height: (y1 - y0) / scale)
    }
}

/// A pending selection. Moving or resizing a detected window turns it into a
/// display crop; an untouched window retains its independent capture identity.
public struct CaptureSelectionDraft: Equatable, Sendable {
    public var rect: CGRect
    public var windowID: UInt32?

    public init(rect: CGRect, windowID: UInt32? = nil) {
        self.rect = rect
        self.windowID = windowID
    }

    public func moving(by delta: CGSize, within bounds: CGRect) -> Self {
        let width = min(rect.width, bounds.width), height = min(rect.height, bounds.height)
        let moved = CGRect(x: min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - width),
                           y: min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - height),
                           width: width, height: height)
        return Self(rect: moved, windowID: moved == rect ? windowID : nil)
    }

    public func resizing(_ handle: CaptureSelectionHandle, by delta: CGSize, within bounds: CGRect) -> Self {
        let minimum: CGFloat = 2
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        if handle.changesLeft { left = min(max(left + delta.width, bounds.minX), right - minimum) }
        if handle.changesRight { right = max(min(right + delta.width, bounds.maxX), left + minimum) }
        if handle.changesBottom { bottom = min(max(bottom + delta.height, bounds.minY), top - minimum) }
        if handle.changesTop { top = max(min(top + delta.height, bounds.maxY), bottom + minimum) }
        let resized = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        return Self(rect: resized, windowID: resized == rect ? windowID : nil)
    }
}

public enum CaptureSelectionHandle: CaseIterable, Sendable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

    var changesLeft: Bool { self == .bottomLeft || self == .left || self == .topLeft }
    var changesRight: Bool { self == .bottomRight || self == .right || self == .topRight }
    var changesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var changesTop: Bool { self == .topLeft || self == .top || self == .topRight }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: changesLeft ? rect.minX : changesRight ? rect.maxX : rect.midX,
                y: changesBottom ? rect.minY : changesTop ? rect.maxY : rect.midY)
    }
}
