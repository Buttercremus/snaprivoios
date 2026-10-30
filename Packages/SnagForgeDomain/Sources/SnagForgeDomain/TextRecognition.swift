import Foundation
import CoreGraphics

/// OCR selections use normalized, top-left coordinates in the visible editor image.
public struct TextRecognitionPlan: Equatable, Sendable {
    public static let maximumDimension = 4096
    public static let maximumPixels = 12_000_000
    public let sourceArea: CGRect
    public let outputSize: PixelSize
    public let isDownsampled: Bool

    public init(sourceSize: PixelSize, crop: CGRect? = nil, resizedSize: PixelSize? = nil,
                selection: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                maximumDimension: Int = Self.maximumDimension, canvasRect: CGRect? = nil) throws {
        let full = canvasRect ?? EditorCrop.fullRect(sourceSize)
        let visible = crop ?? full
        guard EditorCanvasExtent.isValid(full), full.contains(EditorCrop.fullRect(sourceSize)), EditorCrop.isValid(visible, in: full), maximumDimension > 0,
              [selection.minX, selection.minY, selection.width, selection.height].allSatisfy(\.isFinite),
              selection.size.width > 0, selection.size.height > 0,
              selection.minX >= 0, selection.minY >= 0, selection.maxX <= 1, selection.maxY <= 1,
              resizedSize.map(EditorResize.isValid) ?? true else { throw TextRecognitionPlanError.invalidArea }
        let area = CGRect(x: selection.minX * visible.width,
                          y: selection.minY * visible.height,
                          width: selection.width * visible.width, height: selection.height * visible.height)
        let visibleSize = PixelSize(width: Int(visible.width), height: Int(visible.height))!
        guard let integral = EditorCrop.normalized(area, in: visibleSize) else { throw TextRecognitionPlanError.invalidArea }
        sourceArea = integral.offsetBy(dx: visible.minX, dy: visible.minY)
        let visibleOutput = resizedSize.map { CGSize(width: $0.width, height: $0.height) } ?? visible.size
        let width = max(1, visibleOutput.width * sourceArea.width / visible.width)
        let height = max(1, visibleOutput.height * sourceArea.height / visible.height)
        let factor = min(1, CGFloat(min(maximumDimension, Self.maximumDimension)) / max(width, height),
                         sqrt(CGFloat(Self.maximumPixels) / (width * height)))
        outputSize = PixelSize(width: max(1, Int(floor(width * factor))), height: max(1, Int(floor(height * factor))))!
        isDownsampled = factor < 1
    }

    public static func selection(from start: CGPoint, to end: CGPoint) -> CGRect? {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else { return nil }
        let x1 = min(1, max(0, start.x)), x2 = min(1, max(0, end.x))
        let y1 = min(1, max(0, start.y)), y2 = min(1, max(0, end.y))
        guard abs(x2 - x1) > 0, abs(y2 - y1) > 0 else { return nil }
        return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }
}

public enum TextRecognitionPlanError: Error { case invalidArea }

public struct RecognizedTextLine: Equatable, Sendable {
    public let text: String
    public let confidence: Float
    /// Top-left coordinates, normalized within the recognized area.
    public let bounds: CGRect
    public init(text: String, confidence: Float, bounds: CGRect) {
        self.text = text; self.confidence = confidence; self.bounds = bounds
    }
}

public struct TextRecognitionResult: Equatable, Sendable {
    public let lines: [RecognizedTextLine]
    public let usedFastRecognition: Bool
    public init(lines: [RecognizedTextLine], usedFastRecognition: Bool = false) {
        self.usedFastRecognition = usedFastRecognition
        // Vision supplies reading order, including right-to-left scripts. Preserve it.
        self.lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    public var text: String { lines.map(\.text).joined(separator: "\n") }
    /// A review hint, never a guarantee that text or redactions are complete.
    public var hasUncertainText: Bool { lines.contains { !$0.confidence.isFinite || $0.confidence < 0.8 } }
}
