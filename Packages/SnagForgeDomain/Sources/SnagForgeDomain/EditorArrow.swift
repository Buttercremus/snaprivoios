import CoreGraphics

/// Shared image-space geometry for bending, rendering and hit testing.
public enum EditorArrow {
    public static func bendHandle(for object: EditorObject) -> CGPoint {
        if let bend = object.arrowBend { return bend }
        let dx = object.end.x - object.start.x, dy = object.end.y - object.start.y
        if object.effectiveDrawingStyle == .marker {
            return CGPoint(x: object.start.x + dx * 0.5 - dy * 0.09, y: object.start.y + dy * 0.5 + dx * 0.09)
        }
        if object.effectiveDrawingStyle != .precise {
            // Midpoint of the original hand-drawn cubic, preserved for existing documents.
            return CGPoint(x: object.start.x + dx * 0.53375 - dy * 0.2025,
                           y: object.start.y + dy * 0.53375 + dx * 0.2025)
        }
        return CGPoint(x: (object.start.x + object.end.x) / 2, y: (object.start.y + object.end.y) / 2)
    }

    public static func control(for object: EditorObject) -> CGPoint {
        let bend = bendHandle(for: object)
        return CGPoint(x: 2 * bend.x - (object.start.x + object.end.x) / 2,
                       y: 2 * bend.y - (object.start.y + object.end.y) / 2)
    }

    public static func shaft(for object: EditorObject, trimHead: Bool = false) -> CGPath {
        let path = CGMutablePath(); path.move(to: object.start)
        if object.arrowBend != nil {
            let control = control(for: object)
            if trimHead {
                // Stop underneath the filled head, so the round shaft cap cannot
                // protrude past its point. Subdivide the original quadratic.
                let speed = 2 * hypot(object.end.x - control.x, object.end.y - control.y)
                let t = max(0, 1 - headLength(for: object) / max(1, speed)), u = 1 - t
                let end = CGPoint(x: u * u * object.start.x + 2 * u * t * control.x + t * t * object.end.x,
                                  y: u * u * object.start.y + 2 * u * t * control.y + t * t * object.end.y)
                path.addQuadCurve(to: end, control: CGPoint(x: object.start.x + t * (control.x - object.start.x),
                                                          y: object.start.y + t * (control.y - object.start.y)))
            } else { path.addQuadCurve(to: object.end, control: control) }
        }
        else { path.addLine(to: object.end) }
        return path
    }

    private static func headLength(for object: EditorObject) -> CGFloat {
        min(hypot(object.end.x - object.start.x, object.end.y - object.start.y) * 0.45, object.lineWidth * 4)
    }

    public static func head(for object: EditorObject) -> CGPath {
        let tangent = object.arrowBend == nil ? object.start : control(for: object)
        let angle = atan2(object.end.y - tangent.y, object.end.x - tangent.x)
        let length = headLength(for: object)
        let back = CGPoint(x: object.end.x - cos(angle) * length, y: object.end.y - sin(angle) * length)
        let path = CGMutablePath(); path.move(to: object.end)
        path.addLine(to: CGPoint(x: back.x - sin(angle) * length * 0.45, y: back.y + cos(angle) * length * 0.45))
        path.addLine(to: CGPoint(x: back.x + sin(angle) * length * 0.45, y: back.y - cos(angle) * length * 0.45))
        path.closeSubpath(); return path
    }

    public static func path(for object: EditorObject) -> CGPath {
        if object.effectiveDrawingStyle != .precise { return EditorHandDrawn.path(for: object) }
        let path = CGMutablePath(); path.addPath(shaft(for: object)); path.addPath(head(for: object)); return path
    }
}
