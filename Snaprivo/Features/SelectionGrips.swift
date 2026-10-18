import AppKit
import SnagForgeDomain

/// Selection chrome uses view points, independently of image zoom or output aspect ratio.
@MainActor enum SelectionGrips {
    enum Shape { case corner, horizontal, vertical }

    static func rect(at centre: CGPoint, shape: Shape) -> CGRect {
        let size: CGSize = switch shape {
        case .corner: CGSize(width: 10, height: 10)
        case .horizontal: CGSize(width: 22, height: 8)
        case .vertical: CGSize(width: 8, height: 22)
        }
        return CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
    }

    static func hitRect(at centre: CGPoint, shape: Shape) -> CGRect {
        rect(at: centre, shape: shape).insetBy(dx: -7, dy: -7)
    }

    static func draw(at centre: CGPoint, shape: Shape, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let box = rect(at: centre, shape: shape), radius = min(box.width, box.height) / 2
        let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setShouldAntialias(true)
        context.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor); context.addPath(path); context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1.5)
        context.addPath(path); context.strokePath()
    }
}

extension EditorResizeHandle {
    var gripShape: SelectionGrips.Shape {
        switch self { case .top, .bottom: .horizontal; case .left, .right: .vertical; default: .corner }
    }
}

extension CaptureSelectionHandle {
    var gripShape: SelectionGrips.Shape {
        switch self { case .top, .bottom: .horizontal; case .left, .right: .vertical; default: .corner }
    }
}
