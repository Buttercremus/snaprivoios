import CoreGraphics
import Foundation

public enum EditorDrawingStyle: String, Codable, Sendable { case precise, handDrawn }

/// Fixed curves in image coordinates: no random jitter between frames, saves or exports.
public enum EditorHandDrawn {
    public static func path(for object: EditorObject) -> CGPath {
        let path = CGMutablePath()
        if object.kind == .arrow {
            let dx = object.end.x - object.start.x, dy = object.end.y - object.start.y
            let distance = hypot(dx, dy)
            guard distance > 0 else { return path }
            let nx = -dy / distance, ny = dx / distance
            let bend = distance * 0.27
            let c1 = CGPoint(x: object.start.x + dx * 0.32 + nx * bend,
                             y: object.start.y + dy * 0.32 + ny * bend)
            let c2 = CGPoint(x: object.start.x + dx * 0.77 + nx * bend,
                             y: object.start.y + dy * 0.77 + ny * bend)
            path.move(to: object.start)
            path.addCurve(to: object.end, control1: c1, control2: c2)
            let angle = atan2(object.end.y - c2.y, object.end.x - c2.x)
            let head = min(distance * 0.25, max(object.lineWidth * 3.5, distance * 0.10))
            func wing(_ angle: CGFloat, _ length: CGFloat) -> CGPoint {
                CGPoint(x: object.end.x - cos(angle) * length, y: object.end.y - sin(angle) * length)
            }
            path.move(to: wing(angle - 0.52, head))
            path.addQuadCurve(to: object.end, control: wing(angle - 0.35, head * 0.45))
            path.addQuadCurve(to: wing(angle + 0.57, head * 0.88), control: wing(angle + 0.35, head * 0.43))
        } else if object.kind == .ellipse {
            let r = object.rect
            guard r.width > 0, r.height > 0 else { return path }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
            path.move(to: p(0.84, 0.13))
            path.addCurve(to: p(0.48, 0.025), control1: p(0.75, 0.04), control2: p(0.62, 0.015))
            path.addCurve(to: p(0.02, 0.49), control1: p(0.23, 0.025), control2: p(0.02, 0.22))
            path.addCurve(to: p(0.49, 0.98), control1: p(0.02, 0.78), control2: p(0.20, 0.98))
            path.addCurve(to: p(0.98, 0.53), control1: p(0.80, 0.98), control2: p(0.98, 0.80))
            path.addCurve(to: p(0.82, 0.04), control1: p(0.98, 0.30), control2: p(0.94, 0.14))
        }
        return path
    }
}
