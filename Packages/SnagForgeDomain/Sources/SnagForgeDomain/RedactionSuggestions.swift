import Foundation
import CoreGraphics

/// A category of sensitive value that can be covered before sharing an image.
public enum RedactionSuggestionCategory: String, CaseIterable, Codable, Sendable {
    case email, phone, ipAddress, cardNumber, iban
    public var displayName: String {
        switch self {
        case .email: return String(localized: "E-Mail", bundle: DomainLocalization.bundle)
        case .phone: return String(localized: "Telefon", bundle: DomainLocalization.bundle)
        case .ipAddress: return String(localized: "IP-Adresse", bundle: DomainLocalization.bundle)
        case .cardNumber: return String(localized: "Kartennummer", bundle: DomainLocalization.bundle)
        case .iban: return String(localized: "IBAN", bundle: DomainLocalization.bundle)
        }
    }
}

public struct RedactionSuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let category: RedactionSuggestionCategory
    public let categories: [RedactionSuggestionCategory]
    /// Bounds in immutable original-image coordinates. UI must never use OCR text as an identifier.
    public let bounds: CGRect
    /// Vision currently returns line bounds, so the conservative mask covers the complete line.
    public let coversWholeLine: Bool
    public init(id: UUID = UUID(), category: RedactionSuggestionCategory, categories: [RedactionSuggestionCategory]? = nil, bounds: CGRect, coversWholeLine: Bool = true) {
        self.id = id; self.category = category; self.categories = categories ?? [category]; self.bounds = bounds; self.coversWholeLine = coversWholeLine
    }
}

public enum RedactionSuggestionDetector {
    private struct RectKey: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    }
    /// Finds sensitive-looking values without returning or persisting the OCR text.
    /// Bounds are normalized within the OCR area and mapped into `plan.sourceArea`.
    public static func detect(lines: [RecognizedTextLine], plan: TextRecognitionPlan, limit: Int = 10_000) -> [RedactionSuggestion] {
        guard limit > 0 else { return [] }
        let patterns: [(RedactionSuggestionCategory, NSRegularExpression)] = [
            (.email, try! NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])),
            (.iban, try! NSRegularExpression(pattern: #"\b[A-Z]{2}\d{2}(?:[ -]?[A-Z0-9]){11,30}\b"#, options: [.caseInsensitive])),
            (.ipAddress, try! NSRegularExpression(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#)),
            (.cardNumber, try! NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#)),
            (.phone, try! NSRegularExpression(pattern: #"(?<!\w)(?:\+|00)?\d[\d ()\-.]{6,}\d(?!\w)"#))
        ]
        var result: [RedactionSuggestion] = []
        var indexByRect: [RectKey: Int] = [:]
        for line in lines {
            guard [line.bounds.origin.x, line.bounds.origin.y, line.bounds.width, line.bounds.height].allSatisfy(\.isFinite),
                  !line.bounds.isNull, line.bounds.width > 0, line.bounds.height > 0 else { continue }
            let range = NSRange(line.text.startIndex..<line.text.endIndex, in: line.text)
            for (category, regex) in patterns where regex.firstMatch(in: line.text, range: range) != nil {
                let x = plan.sourceArea.minX + line.bounds.minX * plan.sourceArea.width
                let y = plan.sourceArea.minY + line.bounds.minY * plan.sourceArea.height
                let rect = CGRect(x: x, y: y, width: line.bounds.width * plan.sourceArea.width, height: line.bounds.height * plan.sourceArea.height).intersection(plan.sourceArea)
                guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
                if let index = indexByRect[RectKey(rect)] {
                    let existing = result[index]
                    if !existing.categories.contains(category) {
                        result[index] = RedactionSuggestion(id: existing.id, category: existing.category,
                                                            categories: existing.categories + [category], bounds: existing.bounds)
                    }
                } else {
                    indexByRect[RectKey(rect)] = result.count
                    result.append(RedactionSuggestion(category: category, bounds: rect))
                }
                if result.count >= limit { return result }
            }
        }
        return result
    }
}
