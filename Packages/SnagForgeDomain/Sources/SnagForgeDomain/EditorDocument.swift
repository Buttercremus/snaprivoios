import Foundation
import CoreGraphics

public struct EditorObject: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Equatable, Codable, Sendable {
        case image, arrow, text, rectangle, ellipse, triangle, diamond, star, callout, blur, redact, highlight, step
        public var isShape: Bool {
            switch self {
            case .rectangle, .ellipse, .triangle, .diamond, .star: true
            default: false
            }
        }
    }
    public private(set) var id: UUID
    public var imageAsset: EditorImageAsset?
    public var groupID: UUID?
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
    public var effectiveTextStyle: EditorTextStyle { textStyle ?? EditorTextStyle() }
    public var fontSize: CGFloat
    public var color = EditorColor()
    public var blurRadius: CGFloat = 12
    /// Optional additions to format 1. Missing fill preserves the original callout background.
    public var fill: EditorFill?
    public var cornerRadius: CGFloat?
    /// Missing stroke keeps the solid, enabled outline of existing projects.
    public var drawingStyle: EditorDrawingStyle?
    public var effectiveDrawingStyle: EditorDrawingStyle { drawingStyle ?? .precise }
    public var supportsHandDrawn: Bool { kind == .arrow || kind == .ellipse }
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
        if let tip = calloutTip { result.calloutTip = CGPoint(x: tip.x + delta.width, y: tip.y + delta.height) }
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
        if effectiveDrawingStyle == .handDrawn {
            return EditorHandDrawn.path(for: self).copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
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
    private struct State: Equatable, Sendable { var objects: [EditorObject]; var crop: CGRect?; var resizedSize: PixelSize? }
    private var state: State
    public var objects: [EditorObject] { state.objects }
    public var crop: CGRect? { state.crop }
    public var resizedSize: PixelSize? { state.resizedSize }
    private var past: [State] = []
    private var future: [State] = []
    private var transactionStart: State?
    public init(objects: [EditorObject] = [], crop: CGRect? = nil, resizedSize: PixelSize? = nil) { state = State(objects: objects, crop: crop, resizedSize: resizedSize) }
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
        commit(State(objects: next, crop: crop, resizedSize: resizedSize))
    }
    public mutating func commitCrop(_ next: CGRect?, resizedSize: PixelSize? = nil) {
        commit(State(objects: objects, crop: next, resizedSize: resizedSize))
    }
    public mutating func commitResize(_ size: PixelSize?) {
        commit(State(objects: objects, crop: crop, resizedSize: size))
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
    public init(family: String? = nil, weight: Weight = .semibold, italic: Bool = false, alignment: Alignment = .left) {
        self.family = family; self.weight = weight; self.italic = italic; self.alignment = alignment
    }
}
