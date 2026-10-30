import CoreGraphics
import Foundation

public enum EditorDrawingStyle: String, CaseIterable, Codable, Sendable { case precise, handDrawn, sketch, marker }

/// Fixed curves in image coordinates: no random jitter between frames, saves or exports.
public enum EditorHandDrawn {
    public static func path(for object: EditorObject) -> CGPath {
        let base = singlePath(for: object)
        guard object.effectiveDrawingStyle == .sketch else { return base }
        let path = CGMutablePath(); path.addPath(base)
        // Two deterministic pen passes, in local coordinates so moving does not change the style.
        let offset = CGAffineTransform(translationX: max(1.5, object.lineWidth * 0.6), y: -max(1, object.lineWidth * 0.4))
        path.addPath(base, transform: offset)
        return path
    }
    private static func singlePath(for object: EditorObject) -> CGPath {
        let path = CGMutablePath()
        if object.kind == .arrow {
            let dx = object.end.x - object.start.x, dy = object.end.y - object.start.y
            let distance = hypot(dx, dy)
            guard distance > 0 else { return path }
            let nx = -dy / distance, ny = dx / distance
            let bend = distance * 0.27
            var c1 = CGPoint(x: object.start.x + dx * 0.32 + nx * bend,
                             y: object.start.y + dy * 0.32 + ny * bend)
            var c2 = CGPoint(x: object.start.x + dx * 0.77 + nx * bend,
                             y: object.start.y + dy * 0.77 + ny * bend)
            if object.effectiveDrawingStyle == .marker {
                c1 = CGPoint(x: object.start.x + dx / 3 + nx * distance * 0.12, y: object.start.y + dy / 3 + ny * distance * 0.12)
                c2 = CGPoint(x: object.start.x + dx * 2 / 3 + nx * distance * 0.12, y: object.start.y + dy * 2 / 3 + ny * distance * 0.12)
            }
            if object.arrowBend != nil {
                let control = EditorArrow.control(for: object)
                c1 = CGPoint(x: object.start.x + (control.x - object.start.x) * 2 / 3,
                             y: object.start.y + (control.y - object.start.y) * 2 / 3)
                c2 = CGPoint(x: object.end.x + (control.x - object.end.x) * 2 / 3,
                             y: object.end.y + (control.y - object.end.y) * 2 / 3)
            }
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
        } else if object.kind == .rectangle, (object.cornerRadius ?? 0) > 0 {
            let r = object.rect, radius = min(object.cornerRadius ?? 0, r.width / 2, r.height / 2)
            let wobble = min(r.width, r.height) * 0.015
            path.move(to: CGPoint(x: r.minX + radius, y: r.minY))
            path.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.minY), control: CGPoint(x: r.midX, y: r.minY - wobble))
            path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
            path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - radius), control: CGPoint(x: r.maxX - wobble, y: r.midY))
            path.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
            path.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.maxY), control: CGPoint(x: r.midX, y: r.maxY + wobble))
            path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
            path.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + radius), control: CGPoint(x: r.minX + wobble, y: r.midY))
            path.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: r.origin)
            path.closeSubpath()
        } else if object.kind.isShape {
            let r = object.rect
            guard r.width > 0, r.height > 0 else { return path }
            let vertices: [CGPoint]
            switch object.kind {
            case .triangle: vertices = [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            case .diamond: vertices = [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
            case .star:
                vertices = (0..<10).map { i in
                    let angle = CGFloat(i) * .pi / 5 - .pi / 2
                    let radius: CGFloat = i.isMultiple(of: 2) ? 1 : 0.42
                    return CGPoint(x: r.midX + cos(angle) * r.width / 2 * radius, y: r.midY + sin(angle) * r.height / 2 * radius)
                }
            default: vertices = [r.origin, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            }
            path.move(to: vertices[0])
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                let amount = min(r.width, r.height) * 0.025 * (i.isMultiple(of: 2) ? 1 : -1)
                path.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + amount, y: (a.y + b.y) / 2 - amount))
            }
            path.closeSubpath()
        }
        if object.effectiveDrawingStyle == .marker {
            // A loose, slanted felt-tip contour, distinct from the pen and double-pass sketch.
            let origin = object.rect.origin
            var transform = CGAffineTransform(a: 1, b: 0.015, c: -0.025, d: 0.98,
                                              tx: origin.y * 0.025, ty: -origin.x * 0.015 + origin.y * 0.02)
            // Explicit bends must continue to pass through the dragged handle and endpoints.
            if object.kind != .arrow { return path.copy(using: &transform)! }
        }
        return path
    }
}
