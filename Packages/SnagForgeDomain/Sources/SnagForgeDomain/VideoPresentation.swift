import Foundation
import CoreGraphics

/// Portable video styling. No external images or capture/UI dependencies.
public struct VideoPresentation: Codable, Equatable, Sendable {
    public enum Backdrop: String, Codable, CaseIterable, Sendable { case none, solid, gradient }
    public var backdrop: Backdrop = .none
    public var color = EditorColor(red: 0.13, green: 0.16, blue: 0.24)
    public var secondColor = EditorColor(red: 0.38, green: 0.24, blue: 0.78)
    public var padding = 0
    public var cornerRadius = 0.0
    public var shadow = 0.0
    public var aspectRatio: PresentationAspectRatio = .natural
    public init() {}
    public var isIdentity: Bool {
        backdrop == .none && padding == 0 && cornerRadius == 0 && shadow == 0 && aspectRatio == .natural
    }
    public var isValid: Bool {
        [color, secondColor].allSatisfy { c in
            [c.red, c.green, c.blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
        } && (0...240).contains(padding) && cornerRadius.isFinite && (0...120).contains(cornerRadius)
            && shadow.isFinite && (0...1).contains(shadow)
    }
    public func geometry(for size: PixelSize) -> VideoPresentationGeometry? {
        guard isValid, size.width <= 8192, size.height <= 8192 else { return nil }
        var style = EditorPresentation()
        style.padding = padding; style.aspectRatio = aspectRatio
        guard let geometry = style.geometry(for: size) else { return nil }
        // H.264 output dimensions must be even. Keep all source pixels; add at most one pixel per edge.
        let width = (geometry.outputSize.width + 1) / 2 * 2
        let height = (geometry.outputSize.height + 1) / 2 * 2
        guard width <= 8192, height <= 8192, Int64(width) * Int64(height) <= 16_777_216,
              let output = PixelSize(width: width, height: height) else { return nil }
        let frame = CGRect(x: (CGFloat(width) - CGFloat(size.width)) / 2,
                           y: (CGFloat(height) - CGFloat(size.height)) / 2,
                           width: CGFloat(size.width), height: CGFloat(size.height))
        return VideoPresentationGeometry(outputSize: output, videoFrame: frame)
    }
}

public struct VideoPresentationGeometry: Sendable {
    public let outputSize: PixelSize
    /// Source placement in output pixel coordinates; centered on both axes.
    public let videoFrame: CGRect
}
