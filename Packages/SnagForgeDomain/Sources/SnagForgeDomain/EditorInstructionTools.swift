import Foundation
import CoreGraphics

public enum EditorHighlightMode: String, CaseIterable, Codable, Sendable { case rectangle, freehand }

public struct EditorHighlightStyle: Equatable, Codable, Sendable {
    public static let maximumPoints = 10_000
    public var mode: EditorHighlightMode
    public var opacity: Double
    public var points: [CGPoint]
    public init(mode: EditorHighlightMode = .rectangle, opacity: Double = 0.35, points: [CGPoint] = []) {
        self.mode = mode; self.opacity = opacity; self.points = points
    }
}

public enum EditorStepNumbering: String, CaseIterable, Codable, Sendable {
    case numbers, letters
    public func label(for index: Int) -> String {
        guard (1...EditorSteps.maximumIndex).contains(index) else { return "" }
        if self == .numbers { return String(index) }
        var remaining = index, label = ""
        while remaining > 0 {
            remaining -= 1
            label.insert(Character(UnicodeScalar(65 + remaining % 26)!), at: label.startIndex)
            remaining /= 26
        }
        return label
    }
}

public enum EditorStepShape: String, CaseIterable, Codable, Sendable { case circle, roundedRectangle, diamond, pointer }

public struct EditorStepStyle: Equatable, Codable, Sendable {
    public var index: Int
    public var numbering: EditorStepNumbering
    public var shape: EditorStepShape
    public var textColor: EditorColor
    public var label: String { numbering.label(for: index) }
    public init(index: Int = 1, numbering: EditorStepNumbering = .numbers, shape: EditorStepShape = .circle,
                textColor: EditorColor = EditorColor(red: 1, green: 1, blue: 1)) {
        self.index = index; self.numbering = numbering; self.shape = shape; self.textColor = textColor
    }
}

public enum EditorSteps {
    public static let maximumIndex = 10_000
    /// Existing labels stay stable when deleting or arranging objects. Undo and
    /// reopening derive the next number from the restored document, not a UI counter.
    public static func nextIndex(in objects: [EditorObject], numbering: EditorStepNumbering) -> Int? {
        let highest = objects.filter { $0.kind == .step }.compactMap(\.stepStyle)
            .filter { $0.numbering == numbering }.map(\.index).max() ?? 0
        return highest < maximumIndex ? highest + 1 : nil
    }
}
