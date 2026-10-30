import Foundation
import CoreGraphics

public struct EditorPenStroke: Equatable, Codable, Sendable {
    public static let maximumPoints = 10_000
    public var points: [CGPoint]
    public var isSmoothed: Bool
    public init(points: [CGPoint], isSmoothed: Bool = true) {
        self.points = points; self.isSmoothed = isSmoothed
    }
    /// Quadratic midpoint smoothing keeps the original endpoints and a single-point dot.
    public var path: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.001, y: first.y)); return path }
        guard isSmoothed, points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }; return path
        }
        for index in 1..<points.count - 1 {
            let current = points[index], next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

public enum EditorSpotlightShape: String, CaseIterable, Codable, Sendable { case rectangle, ellipse }

public struct EditorSpotlightStyle: Equatable, Codable, Sendable {
    public var shape: EditorSpotlightShape
    public var opacity: Double
    public init(shape: EditorSpotlightShape = .rectangle, opacity: Double = 0.55) {
        self.shape = shape; self.opacity = opacity
    }
    public func path(in rect: CGRect) -> CGPath {
        if shape == .ellipse { return CGPath(ellipseIn: rect, transform: nil) }
        let radius = min(10, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
