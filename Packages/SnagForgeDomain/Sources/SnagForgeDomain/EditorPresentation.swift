import Foundation
import CoreGraphics

public enum PresentationAspectRatio: String, CaseIterable, Codable, Sendable {
    case natural, square, landscape, wide, portrait
    public var value: CGFloat? {
        switch self { case .natural: nil; case .square: 1; case .landscape: 4.0 / 3; case .wide: 16.0 / 9; case .portrait: 9.0 / 16 }
    }
}
public enum PresentationAlignment: String, CaseIterable, Codable, Sendable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
    public var x: CGFloat { switch self { case .topLeading, .leading, .bottomLeading: 0; case .top, .center, .bottom: 0.5; default: 1 } }
    public var y: CGFloat { switch self { case .topLeading, .top, .topTrailing: 1; case .leading, .center, .trailing: 0.5; default: 0 } }
}
public struct PresentationGradient: Codable, Equatable, Sendable {
    public var colors: [EditorColor]
    public var angle: Double
    public init(colors: [EditorColor], angle: Double) { self.colors = colors; self.angle = angle }
}
public enum PresentationBackground: Codable, Equatable, Sendable {
    case solid(EditorColor), gradient(PresentationGradient), image(path: String, blur: Double), asset(EditorImageAsset, blur: Double)
    private enum CodingKeys: String, CodingKey { case kind, color, colors, angle, path, blur, asset }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "solid": self = .solid(try c.decode(EditorColor.self, forKey: .color))
        case "gradient": self = .gradient(PresentationGradient(colors: try c.decode([EditorColor].self, forKey: .colors), angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 135))
        case "image": self = .image(path: try c.decode(String.self, forKey: .path), blur: try c.decodeIfPresent(Double.self, forKey: .blur) ?? 0)
        case "asset": self = .asset(try c.decode(EditorImageAsset.self, forKey: .asset), blur: try c.decodeIfPresent(Double.self, forKey: .blur) ?? 0)
        default: throw ProjectError.invalidDocument
        }
        guard isValid else { throw ProjectError.invalidDocument }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let color): try c.encode("solid", forKey: .kind); try c.encode(color, forKey: .color)
        case .gradient(let gradient): try c.encode("gradient", forKey: .kind); try c.encode(gradient.colors, forKey: .colors); try c.encode(gradient.angle, forKey: .angle)
        case .image(let path, let blur): try c.encode("image", forKey: .kind); try c.encode(path, forKey: .path); try c.encode(blur, forKey: .blur)
        case .asset(let asset, let blur): try c.encode("asset", forKey: .kind); try c.encode(asset, forKey: .asset); try c.encode(blur, forKey: .blur)
        }
    }
    public var isValid: Bool {
        func valid(_ color: EditorColor) -> Bool { [color.red, color.green, color.blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
        switch self {
        case .solid(let color): return valid(color)
        case .gradient(let gradient): return (2...8).contains(gradient.colors.count) && gradient.colors.allSatisfy(valid) && gradient.angle.isFinite
        case .image(let path, let blur): return !path.isEmpty && path.count <= 4096 && blur.isFinite && (0...100).contains(blur)
        case .asset(let asset, let blur): return asset.isValid && blur.isFinite && (0...100).contains(blur)
        }
    }
}

public struct EditorImageBorder: Codable, Equatable, Sendable {
    public var width: Double
    public var color: EditorColor
    public init(width: Double = 2, color: EditorColor = EditorColor(red: 0, green: 0, blue: 0)) { self.width = width; self.color = color }
    public var isValid: Bool { width.isFinite && (0.0001...100).contains(width) && [color.red, color.green, color.blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

/// Presentation is independent of source/annotation coordinates. Image assets travel with the project.
public struct EditorPresentation: Codable, Equatable, Sendable {
    public var rotationDegrees = 0.0
    public var background: PresentationBackground?
    public var padding = 0
    public var border: EditorImageBorder?
    public var cornerRadius = 0.0
    public var shadowStrength = 0.0
    public var aspectRatio = PresentationAspectRatio.natural
    public var alignment = PresentationAlignment.center
    public init() {}
    public var isIdentity: Bool { self == Self() }
    /// Corners and an inset border alone retain the original image geometry.
    public var requiresCanvasLayout: Bool {
        rotationDegrees != 0 || background != nil || padding != 0 || shadowStrength != 0 || aspectRatio != .natural
    }
    public var isLayoutValid: Bool {
        guard rotationDegrees.isFinite, (-180...180).contains(rotationDegrees), (0...500).contains(padding),
              cornerRadius.isFinite, (0...200).contains(cornerRadius), shadowStrength.isFinite, (0...1).contains(shadowStrength), border?.isValid != false else { return false }
        if case .image = background { return false } // Legacy external paths are never saved in a project.
        return true
    }
    public var isValid: Bool { isLayoutValid && background?.isValid != false }
    /// A fixed enclosing canvas keeps the preview scale unchanged while the angle moves.
    public func previewReferenceSize(for size: PixelSize) -> CGSize {
        let diameter = ceil(hypot(Double(size.width), Double(size.height))) + Double(2 * padding)
        if let ratio = aspectRatio.value {
            return ratio >= 1 ? CGSize(width: diameter * ratio, height: diameter) : CGSize(width: diameter, height: diameter / ratio)
        }
        return CGSize(width: diameter, height: diameter)
    }
    public func previewRect(for size: PixelSize, viewport: EditorViewport, in bounds: CGRect, backingScale: CGFloat) -> CGRect? {
        guard let geometry = geometry(for: size) else { return nil }
        let reference = previewReferenceSize(for: size)
        let referenceRect = viewport.imageRect(image: reference, in: bounds, backingScale: backingScale)
        let scale = viewport.scale(image: reference, in: bounds, backingScale: backingScale)
        return CGRect(x: referenceRect.midX - CGFloat(geometry.outputSize.width) * scale / 2,
                      y: referenceRect.midY - CGFloat(geometry.outputSize.height) * scale / 2,
                      width: CGFloat(geometry.outputSize.width) * scale, height: CGFloat(geometry.outputSize.height) * scale)
    }
    public func geometry(for size: PixelSize) -> EditorPresentationGeometry? {
        guard isLayoutValid else { return nil }
        let radians = rotationDegrees * .pi / 180
        let w = CGFloat(size.width), h = CGFloat(size.height)
        let rotatedWidth = Int(ceil(abs(w * cos(radians)) + abs(h * sin(radians)) - 0.00000001))
        let rotatedHeight = Int(ceil(abs(w * sin(radians)) + abs(h * cos(radians)) - 0.00000001))
        var width = rotatedWidth + 2 * padding, height = rotatedHeight + 2 * padding
        if let ratio = aspectRatio.value {
            if CGFloat(width) / CGFloat(height) < ratio { width = Int(ceil(CGFloat(height) * ratio)) }
            else { height = Int(ceil(CGFloat(width) / ratio)) }
        }
        guard width > 0, height > 0, width <= 32768, height <= 32768,
              Int64(width) * Int64(height) <= 100_000_000, let output = PixelSize(width: width, height: height) else { return nil }
        let x = CGFloat(padding) + CGFloat(width - rotatedWidth - 2 * padding) * alignment.x
        let y = CGFloat(padding) + CGFloat(height - rotatedHeight - 2 * padding) * (1 - alignment.y)
        let mapping = CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: x + CGFloat(rotatedWidth) / 2, y: y + CGFloat(rotatedHeight) / 2))
        return EditorPresentationGeometry(outputSize: output, imageTransform: mapping)
    }
}
public struct EditorPresentationGeometry: Sendable {
    public let outputSize: PixelSize
    /// Top-left image pixels to top-left output pixels, clockwise rotation.
    public let imageTransform: CGAffineTransform
}
