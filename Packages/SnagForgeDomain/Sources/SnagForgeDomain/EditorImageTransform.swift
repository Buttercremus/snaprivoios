import Foundation
import CoreGraphics

/// Lossless quarter turns and reflections of the complete visible composition.
/// Annotation geometry remains in the immutable original's coordinate system.
public enum EditorImageTransform: Int, CaseIterable, Codable, Sendable {
    case identity, clockwise90, clockwise180, clockwise270
    case mirrored, mirroredClockwise90, mirroredClockwise180, mirroredClockwise270

    public var quarterTurns: Int { rawValue % 4 }
    public var isMirrored: Bool { rawValue >= 4 }
    public var swapsAxes: Bool { quarterTurns % 2 == 1 }
    private static func value(turns: Int, mirrored: Bool) -> Self {
        Self(rawValue: (turns % 4 + 4) % 4 + (mirrored ? 4 : 0))!
    }
    public func rotated(clockwise: Bool = true) -> Self {
        Self.value(turns: quarterTurns + (clockwise ? 1 : -1), mirrored: isMirrored)
    }
    public func flippedHorizontally() -> Self {
        Self.value(turns: -quarterTurns, mirrored: !isMirrored)
    }
    public func flippedVertically() -> Self {
        Self.value(turns: 2 - quarterTurns, mirrored: !isMirrored)
    }
    public func applying(to size: PixelSize) -> PixelSize {
        swapsAxes ? PixelSize(width: size.height, height: size.width)! : size
    }
    /// Coordinates have their origin at the top left; rotations are clockwise.
    public func affineTransform(size: CGSize) -> CGAffineTransform {
        let rotation: CGAffineTransform
        switch quarterTurns {
        case 1: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        case 2: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height)
        case 3: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
        default: rotation = .identity
        }
        return isMirrored
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0).concatenating(rotation)
            : rotation
    }
    public func sourceVector(fromDisplayed vector: CGSize) -> CGSize {
        let inverse = affineTransform(size: CGSize(width: 1, height: 1)).inverted()
        return CGSize(width: inverse.a * vector.width + inverse.c * vector.height,
                      height: inverse.b * vector.width + inverse.d * vector.height)
    }
    public func sourceUnitRect(fromDisplayed rect: CGRect) -> CGRect {
        rect.applying(affineTransform(size: CGSize(width: 1, height: 1)).inverted()).standardized
    }
}
