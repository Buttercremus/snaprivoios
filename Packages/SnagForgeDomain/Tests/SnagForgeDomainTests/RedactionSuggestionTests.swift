import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func redactionDetectorFindsCategoriesAndMapsOriginalBounds() throws {
    let plan = try TextRecognitionPlan(sourceSize: PixelSize(width: 1000, height: 500)!, selection: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6))
    let lines = [
        RecognizedTextLine(text: "mail a@example.com", confidence: 0.99, bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1)),
        RecognizedTextLine(text: "host 192.168.0.4", confidence: 0.99, bounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.1)),
        RecognizedTextLine(text: "IBAN DE89370400440532013000", confidence: 0.99, bounds: CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.1))
    ]
    let values = RedactionSuggestionDetector.detect(lines: lines, plan: plan)
    #expect(values.map(\.category) == [.email, .ipAddress, .iban])
    #expect(values.allSatisfy { plan.sourceArea.contains($0.bounds) })
    #expect(values.allSatisfy { $0.coversWholeLine })
}

@Test func redactionDetectorRespectsLimitAndIgnoresPlainText() throws {
    let plan = try TextRecognitionPlan(sourceSize: PixelSize(width: 100, height: 100)!)
    let lines = [RecognizedTextLine(text: "hello world", confidence: 1, bounds: CGRect(x: 0, y: 0, width: 1, height: 0.2))]
    #expect(RedactionSuggestionDetector.detect(lines: lines, plan: plan, limit: 0).isEmpty)
    #expect(RedactionSuggestionDetector.detect(lines: lines, plan: plan).isEmpty)
}


@Test func redactionDetectorAcceptsFormattedValuesAndRejectsInvalidCoordinates() throws {
    let plan = try TextRecognitionPlan(sourceSize: PixelSize(width: 800, height: 400)!)
    let values = RedactionSuggestionDetector.detect(lines: [
        .init(text: "DE89 3704 0044 0532 0130 00", confidence: 1, bounds: CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.1)),
        .init(text: "+49 (30) 1234 5678", confidence: 1, bounds: CGRect(x: 0.1, y: 0.3, width: 0.6, height: 0.1)),
        .init(text: "4111 1111 1111 1111", confidence: 1, bounds: CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.1)),
        .init(text: "user@example.com", confidence: 1, bounds: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))
    ], plan: plan)
    #expect(values.count == 3)
    #expect(values[0].categories.contains(.iban))
    #expect(values[1].categories.contains(.phone))
    #expect(values[2].categories.contains(.cardNumber))
}
