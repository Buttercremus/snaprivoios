import Foundation
import CoreGraphics

public enum EditorBlurStyle: String, CaseIterable, Codable, Sendable {
    case gaussian, pixelate, mosaic
}

public struct EditorObject: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Equatable, Codable, Sendable {
        case image, arrow, text, rectangle, ellipse, triangle, diamond, star, callout, blur, redact, highlight, step, magnifier, pen, spotlight
        public var isShape: Bool {
            switch self {
            case .rectangle, .ellipse, .triangle, .diamond, .star: true
            default: false
            }
        }
    }
    public private(set) var id: UUID
    public var imageAsset: EditorImageAsset?
    public var imageRotationDegrees: Double?
    public var imageRotationTransform: CGAffineTransform {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = (imageRotationDegrees ?? 0) * .pi / 180
        let c = abs(cos(angle)) < 0.000000000001 ? 0 : cos(angle)
        let s = abs(sin(angle)) < 0.000000000001 ? 0 : sin(angle)
        return CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(a: c, b: s, c: -s, d: c, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
    public var rotatedImageBounds: CGRect { rect.applying(imageRotationTransform) }
    public var groupID: UUID?
    public var name: String?
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    /// Nil preserves the auto-growing text in older projects; a width enables word wrapping.
    public var textWidth: CGFloat?
    /// Optional minimum text area height for resized callouts. Text may grow beyond it.
    public var textHeight: CGFloat?
    public var textStyle: EditorTextStyle?
    public var calloutTip: CGPoint?
    /// A point on the shaft at t = 0.5. Nil retains the original straight/hand-drawn curve.
    public var arrowBend: CGPoint?
    public var penStroke: EditorPenStroke?
    public var spotlightStyle: EditorSpotlightStyle?
    public var effectiveSpotlightStyle: EditorSpotlightStyle { spotlightStyle ?? .init() }
    public var magnifierSource: CGPoint?
    public var magnifierSourceRect: CGRect {
        let center = magnifierSource ?? CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / effectiveMagnification / 2
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
    public var magnification: CGFloat?
    public var effectiveMagnification: CGFloat { magnification ?? 2 }
    public var effectiveTextStyle: EditorTextStyle { textStyle ?? EditorTextStyle() }
    public var fontSize: CGFloat
    public var color = EditorColor()
    public var blurRadius: CGFloat = 12
    /// Missing on older projects: retain Gaussian blur exactly.
    public var blurStyle: EditorBlurStyle?
    public var effectiveBlurStyle: EditorBlurStyle { blurStyle ?? .gaussian }
    /// Optional additions to format 1. Missing fill preserves the original callout background.
    public var fill: EditorFill?
    public var cornerRadius: CGFloat?
    /// Missing stroke keeps the solid, enabled outline of existing projects.
    public var drawingStyle: EditorDrawingStyle?
    public var effectiveDrawingStyle: EditorDrawingStyle { drawingStyle ?? .precise }
    public var supportsHandDrawn: Bool { kind == .arrow || kind.isShape }
    public var stroke: EditorStroke?
    public var highlightStyle: EditorHighlightStyle?
    public var stepStyle: EditorStepStyle?
    public var effectiveHighlightStyle: EditorHighlightStyle { highlightStyle ?? EditorHighlightStyle() }
    public var effectiveStroke: EditorStroke { stroke ?? EditorStroke() }
    public var effectiveFill: EditorFill { fill ?? EditorFill(isEnabled: kind == .callout) }
    public var rect: CGRect { CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)) }
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint = .zero,
                text: String = "", fontSize: CGFloat = 32, lineWidth: CGFloat = 5, textWidth: CGFloat? = nil) {
        self.id = id; self.kind = kind; self.start = start; self.end = end
        self.text = text; self.fontSize = fontSize; self.lineWidth = lineWidth
        self.textWidth = textWidth
    }

    public func translated(by delta: CGSize) -> Self {
        var result = self
        result.start.x += delta.width; result.start.y += delta.height
        result.end.x += delta.width; result.end.y += delta.height
        if let source = magnifierSource { result.magnifierSource = CGPoint(x: source.x + delta.width, y: source.y + delta.height) }
        if let tip = calloutTip { result.calloutTip = CGPoint(x: tip.x + delta.width, y: tip.y + delta.height) }
        if let bend = arrowBend { result.arrowBend = CGPoint(x: bend.x + delta.width, y: bend.y + delta.height) }
        if var pen = penStroke {
            pen.points = pen.points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
            result.penStroke = pen
        }
        if var highlight = highlightStyle {
            highlight.points = highlight.points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
            result.highlightStyle = highlight
        }
        return result
    }

    /// A value copy preserves all supported style fields, including future additions.
    public func duplicated(by delta: CGSize) -> Self {
        var copy = translated(by: delta)
        copy.id = UUID()
        return copy
    }

    public func hitsArrow(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if effectiveDrawingStyle != .precise || arrowBend != nil {
            return EditorArrow.path(for: self).copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        }
        let dx = end.x - start.x, dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else { return false }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength))
        return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy) <= tolerance
    }
}

/// A completed gesture is committed once. Previews do not enter history.
public struct EditorHistory: Sendable {
    private struct State: Equatable, Sendable { var objects: [EditorObject]; var crop: CGRect?; var resizedSize: PixelSize?; var canvasRect: CGRect?; var transform: EditorImageTransform; var presentation: EditorPresentation }
    private var state: State
    public var objects: [EditorObject] { state.objects }
    public var crop: CGRect? { state.crop }
    public var resizedSize: PixelSize? { state.resizedSize }
    public var canvasRect: CGRect? { state.canvasRect }
    public var transform: EditorImageTransform { state.transform }
    public var presentation: EditorPresentation { state.presentation }
    private var past: [State] = []
    private var future: [State] = []
    private var transactionStart: State?
    public init(objects: [EditorObject] = [], crop: CGRect? = nil, resizedSize: PixelSize? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation = .init()) { state = State(objects: objects, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation) }
    public var canUndo: Bool { !past.isEmpty || transactionStart.map { $0 != state } == true }
    public var canRedo: Bool { !future.isEmpty && (transactionStart == nil || transactionStart == state) }
    public mutating func beginTransaction() {
        endTransaction()
        transactionStart = state
    }
    /// Live text/style edits are visible/persistable, but become one document undo step.
    public mutating func updateTransaction(_ next: [EditorObject]) {
        guard transactionStart != nil else { commit(next); return }
        state.objects = next
    }
    public mutating func updateTransaction(_ next: [EditorObject], canvasRect: CGRect?, crop: CGRect?, resizedSize: PixelSize?) {
        guard transactionStart != nil else { commit(next, canvasRect: canvasRect, crop: crop, resizedSize: resizedSize); return }
        state.objects = next; state.canvasRect = canvasRect; state.crop = crop; state.resizedSize = resizedSize
    }
    public mutating func endTransaction() {
        guard let previous = transactionStart else { return }
        transactionStart = nil
        guard previous != state else { return }
        past.append(previous)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }
    public mutating func cancelTransaction() {
        guard let previous = transactionStart else { return }
        state = previous
        transactionStart = nil
    }
    public mutating func commit(_ next: [EditorObject]) {
        commit(State(objects: next, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation))
    }
    public mutating func commit(_ next: [EditorObject], canvasRect: CGRect?, crop: CGRect?, resizedSize: PixelSize?) {
        commit(State(objects: next, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation))
    }
    public mutating func commitCrop(_ next: CGRect?, resizedSize: PixelSize? = nil) {
        commit(State(objects: objects, crop: next, resizedSize: resizedSize, canvasRect: canvasRect, transform: transform, presentation: presentation))
    }
    public mutating func commitResize(_ size: PixelSize?) {
        commit(State(objects: objects, crop: crop, resizedSize: size, canvasRect: canvasRect, transform: transform, presentation: presentation))
    }
    public mutating func commitTransform(_ next: EditorImageTransform) {
        commit(State(objects: objects, crop: crop, resizedSize: resizedSize, canvasRect: canvasRect, transform: next, presentation: presentation))
    }
    public mutating func commitPresentation(_ next: EditorPresentation) {
        var nextState = state; nextState.presentation = next; commit(nextState)
    }
    public mutating func updatePresentationTransaction(_ next: EditorPresentation) {
        guard transactionStart != nil else { commitPresentation(next); return }
        state.presentation = next
    }
    private mutating func commit(_ next: State) {
        endTransaction()
        guard next != state else { return }
        past.append(state)
        if past.count > 100 { past.removeFirst() }
        state = next; future.removeAll()
    }
    public mutating func undo() {
        endTransaction()
        guard let previous = past.popLast() else { return }
        future.append(state); state = previous
    }
    public mutating func redo() {
        endTransaction()
        guard let next = future.popLast() else { return }
        past.append(state); state = next
    }
}

public struct EditorColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double = 0.95, green: Double = 0.16, blue: Double = 0.20) { self.red = red; self.green = green; self.blue = blue }
}

public struct EditorFill: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var color: EditorColor
    public var opacity: Double
    public init(isEnabled: Bool = false, color: EditorColor = EditorColor(red: 1, green: 1, blue: 1), opacity: Double = 1) {
        self.isEnabled = isEnabled; self.color = color; self.opacity = opacity
    }
}

public struct EditorStroke: Equatable, Codable, Sendable {
    public enum Style: String, CaseIterable, Codable, Sendable { case solid, dashed, dotted }
    public var isEnabled: Bool
    public var style: Style
    public init(isEnabled: Bool = true, style: Style = .solid) {
        self.isEnabled = isEnabled; self.style = style
    }
}

/// Nil on old objects preserves the original semibold system font and left alignment.
public struct EditorTextStyle: Equatable, Codable, Sendable {
    public enum Weight: String, Codable, Sendable { case regular, semibold, bold }
    public enum Alignment: String, CaseIterable, Codable, Sendable { case left, center, right }
    public var family: String?
    public var weight: Weight
    public var italic: Bool
    public var alignment: Alignment
    /// Format 20. Absent means not underlined, so unchanged text keeps its earlier encoding.
    public var underline: Bool?
    public var isUnderlined: Bool {
        get { underline == true }
        set { underline = newValue ? true : nil }
    }
    public init(family: String? = nil, weight: Weight = .semibold, italic: Bool = false, alignment: Alignment = .left, underline: Bool = false) {
        self.family = family; self.weight = weight; self.italic = italic; self.alignment = alignment
        self.underline = underline ? true : nil
    }
}
