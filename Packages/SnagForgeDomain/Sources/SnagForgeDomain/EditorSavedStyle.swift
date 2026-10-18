import Foundation
import CoreGraphics

public enum EditorStyleFamily: String, Codable, CaseIterable, Sendable {
    case arrow, text, shape, callout, blur, redact, highlight, step
    public init(kind: EditorObject.Kind) {
        switch kind {
        case .arrow: self = .arrow
        case .text: self = .text
        case .callout: self = .callout
        case .blur: self = .blur
        case .redact: self = .redact
        case .highlight: self = .highlight
        case .step: self = .step
        default: self = .shape
        }
    }
}

/// Appearance only: never store source text, coordinates, paths or step values.
public struct EditorSavedStyle: Equatable, Codable, Sendable {
    public let family: EditorStyleFamily
    public let color: EditorColor
    public let lineWidth: CGFloat
    public let fontSize: CGFloat
    public let blurRadius: CGFloat
    public let fill: EditorFill
    public let cornerRadius: CGFloat?
    public let drawingStyle: EditorDrawingStyle?
    public let stroke: EditorStroke
    public let textStyle: EditorTextStyle
    public let highlightOpacity: Double
    public let stepShape: EditorStepShape
    public let stepTextColor: EditorColor
    public let stepSize: CGFloat

    public init(object: EditorObject) {
        family = EditorStyleFamily(kind: object.kind)
        color = object.color; lineWidth = object.lineWidth; fontSize = object.fontSize
        blurRadius = object.blurRadius; fill = object.effectiveFill
        cornerRadius = object.kind == .rectangle ? object.cornerRadius ?? 0 : nil
        drawingStyle = object.drawingStyle
        stroke = object.effectiveStroke
        textStyle = object.effectiveTextStyle; highlightOpacity = object.effectiveHighlightStyle.opacity
        stepShape = object.stepStyle?.shape ?? .circle
        stepTextColor = object.stepStyle?.textColor ?? EditorColor(red: 1, green: 1, blue: 1)
        stepSize = family == .step ? min(object.rect.width, object.rect.height) : 72
    }

    public var isValid: Bool {
        [color, fill.color, stepTextColor].allSatisfy { color in
            [color.red, color.green, color.blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
        } && lineWidth.isFinite && (0.1...1000).contains(lineWidth)
            && fontSize.isFinite && (1...1000).contains(fontSize)
            && blurRadius.isFinite && (0...1000).contains(blurRadius)
            && (cornerRadius.map { $0.isFinite && (0...1000).contains($0) } ?? true)
            && fill.opacity.isFinite && (0...1).contains(fill.opacity)
            && highlightOpacity.isFinite && (0...1).contains(highlightOpacity)
            && stepSize.isFinite && (1...1_000_000).contains(stepSize)
            && (textStyle.family.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
    }

    public func applying(to object: EditorObject) -> EditorObject? {
        guard isValid, EditorStyleFamily(kind: object.kind) == family else { return nil }
        var result = object
        if object.supportsHandDrawn { result.drawingStyle = drawingStyle }
        if family != .blur { result.color = color }
        switch family {
        case .arrow: result.lineWidth = lineWidth
        case .shape:
            result.lineWidth = lineWidth
            if object.effectiveFill != fill { result.fill = fill }
            if object.effectiveStroke != stroke { result.stroke = stroke }
            if object.kind == .rectangle, let cornerRadius, (object.cornerRadius ?? 0) != cornerRadius { result.cornerRadius = cornerRadius }
        case .text:
            result.fontSize = fontSize
            if object.effectiveTextStyle != textStyle { result.textStyle = textStyle }
        case .callout:
            result.lineWidth = lineWidth; result.fontSize = fontSize
            if object.effectiveFill != fill { result.fill = fill }
            if object.effectiveTextStyle != textStyle { result.textStyle = textStyle }
        case .blur: result.blurRadius = blurRadius
        case .redact: break
        case .highlight:
            result.lineWidth = lineWidth
            var highlight = object.effectiveHighlightStyle
            highlight.opacity = highlightOpacity; result.highlightStyle = highlight
        case .step:
            var step = object.stepStyle ?? EditorStepStyle()
            step.shape = stepShape; step.textColor = stepTextColor; result.stepStyle = step
            let center = CGPoint(x: object.rect.midX, y: object.rect.midY)
            result.start = CGPoint(x: center.x - stepSize / 2, y: center.y - stepSize / 2)
            result.end = CGPoint(x: center.x + stepSize / 2, y: center.y + stepSize / 2)
        }
        return result
    }
}

public struct EditorNamedStyle: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public let style: EditorSavedStyle
    public init(id: UUID = UUID(), name: String, style: EditorSavedStyle) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.style = style
    }
}

public enum EditorStyleLibraryError: Error { case invalidName, duplicateName, limitReached, invalidLibrary }

public struct EditorStyleLibrary: Equatable, Codable, Sendable {
    public static let maximumStyles = 100
    public static let maximumNameLength = 80
    public let version: Int
    public private(set) var styles: [EditorNamedStyle]
    public init() { version = 1; styles = [] }

    public func validated() throws -> Self {
        guard version == 1, styles.count <= Self.maximumStyles,
              Set(styles.map(\.id)).count == styles.count else { throw EditorStyleLibraryError.invalidLibrary }
        for item in styles {
            try Self.validateName(item.name)
            guard item.style.isValid else { throw EditorStyleLibraryError.invalidLibrary }
            guard !styles.contains(where: { $0.id != item.id && Self.sameName($0, item) }) else {
                throw EditorStyleLibraryError.duplicateName
            }
        }
        return self
    }
    public mutating func add(_ item: EditorNamedStyle) throws {
        guard styles.count < Self.maximumStyles else { throw EditorStyleLibraryError.limitReached }
        var next = self; next.styles.append(item)
        self = try next.validated()
    }
    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
        var next = self
        next.styles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self = try next.validated()
    }
    public mutating func remove(_ id: UUID) { styles.removeAll { $0.id == id } }
    private static func validateName(_ name: String) throws {
        guard !name.isEmpty, name.count <= maximumNameLength, name.utf8.count <= 1024,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw EditorStyleLibraryError.invalidName
        }
    }
    private static func sameName(_ lhs: EditorNamedStyle, _ rhs: EditorNamedStyle) -> Bool {
        lhs.style.family == rhs.style.family && lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            == rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
