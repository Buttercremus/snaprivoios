import CoreGraphics
import Foundation

/// Geometry operations shared by the editor canvas and non-UI tests.
public enum EditorArrangement {
    public enum Alignment: String, CaseIterable, Sendable { case left, center, right, top, middle, bottom }
    public enum Distribution: String, CaseIterable, Sendable { case horizontal, vertical }
    public enum GuideAxis: String, Sendable { case vertical, horizontal }
    public struct Guide: Equatable, Sendable {
        public var axis: GuideAxis
        public var position: CGFloat
        public init(axis: GuideAxis, position: CGFloat) { self.axis = axis; self.position = position }
    }
    public struct SnapResult: Equatable, Sendable {
        public var delta: CGSize
        public var guides: [Guide]
        public init(delta: CGSize = .zero, guides: [Guide] = []) { self.delta = delta; self.guides = guides }
    }

    /// Finds the nearest edge or centre on each axis. `tolerance` is in image
    /// points, so callers can convert a view-point tolerance through the current
    /// non-uniform projection before calling this method.
    public static func snap(rect: CGRect, candidates: [CGRect], canvas: CGRect,
                            tolerance: CGSize) -> SnapResult {
        let xTargets = candidates.flatMap { [$0.minX, $0.midX, $0.maxX] } + [canvas.minX, canvas.midX, canvas.maxX]
        let yTargets = candidates.flatMap { [$0.minY, $0.midY, $0.maxY] } + [canvas.minY, canvas.midY, canvas.maxY]
        let xSources = [rect.minX, rect.midX, rect.maxX], ySources = [rect.minY, rect.midY, rect.maxY]
        func nearest(_ sources: [CGFloat], _ targets: [CGFloat], _ limit: CGFloat) -> (CGFloat, CGFloat)? {
            var best: (distance: CGFloat, delta: CGFloat, target: CGFloat)?
            for source in sources {
                for target in targets {
                    let delta = target - source, distance = abs(delta)
                    guard distance <= limit else { continue }
                    if best == nil || distance < best!.distance ||
                        (distance == best!.distance && (target < best!.target || (target == best!.target && delta < best!.delta))) {
                        best = (distance, delta, target)
                    }
                }
            }
            return best.map { ($0.delta, $0.target) }
        }
        let x = nearest(xSources, xTargets, max(0, tolerance.width))
        let y = nearest(ySources, yTargets, max(0, tolerance.height))
        var guides: [Guide] = []
        if let x { guides.append(Guide(axis: .vertical, position: x.1)) }
        if let y { guides.append(Guide(axis: .horizontal, position: y.1)) }
        return SnapResult(delta: CGSize(width: x?.0 ?? 0, height: y?.0 ?? 0), guides: guides)
    }

    /// Maps every geometric point of an object from one group bounding box to
    /// another. Style dimensions use the geometric mean so non-uniform resizing
    /// remains visually balanced while text wrapping follows the x scale.
    public static func scaled(object: EditorObject, from source: CGRect, to target: CGRect) -> EditorObject {
        var result = object
        let sx = source.width == 0 ? 1 : target.width / source.width
        let sy = source.height == 0 ? 1 : target.height / source.height
        let scale = sqrt(abs(sx * sy))
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: target.minX + (p.x - source.minX) * sx, y: target.minY + (p.y - source.minY) * sy)
        }
        result.start = point(object.start); result.end = point(object.end)
        if let source = object.magnifierSource { result.magnifierSource = point(source) }
        if let tip = object.calloutTip { result.calloutTip = point(tip) }
        if let bend = object.arrowBend { result.arrowBend = point(bend) }
        if var highlight = object.highlightStyle {
            highlight.points = highlight.points.map(point); result.highlightStyle = highlight
        }
        if var pen = object.penStroke {
            pen.points = pen.points.map(point); result.penStroke = pen
        }
        result.lineWidth = min(1000, max(0.5, object.lineWidth * scale))
        result.fontSize = min(1000, max(1, object.fontSize * scale))
        if let width = object.textWidth { result.textWidth = min(10000, max(1, width * abs(sx))) }
        if let height = object.textHeight { result.textHeight = min(10000, max(1, height * abs(sy))) }
        if let radius = object.cornerRadius { result.cornerRadius = min(1000, max(0, radius * scale)) }
        result.blurRadius = min(1000, max(0, object.blurRadius * scale))
        return result
    }
}
