import Foundation
import Testing
@testable import SnagForgeDomain

@Test func textRecognitionMapsSelectionThroughCropAndResize() throws {
    let plan = try TextRecognitionPlan(sourceSize: PixelSize(width: 2000, height: 1000)!,
                                       crop: CGRect(x: 300, y: 200, width: 1000, height: 600),
                                       resizedSize: PixelSize(width: 500, height: 300)!,
                                       selection: CGRect(x: 0.1, y: 0.25, width: 0.4, height: 0.5))
    #expect(plan.sourceArea == CGRect(x: 400, y: 350, width: 400, height: 300))
    #expect(plan.outputSize == PixelSize(width: 200, height: 150))
    #expect(!plan.isDownsampled)
}

@Test func textRecognitionLimitsLargeImagesAndRetainsSmallRegions() throws {
    let size = PixelSize(width: 10000, height: 10000)!
    let full = try TextRecognitionPlan(sourceSize: size)
    #expect(full.isDownsampled && full.outputSize.width <= 4096 && full.outputSize.height <= 4096)
    #expect(full.outputSize.width * full.outputSize.height <= 12_000_000)
    let region = try TextRecognitionPlan(sourceSize: size, selection: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.05))
    #expect(region.sourceArea == CGRect(x: 1000, y: 2000, width: 1000, height: 500))
    #expect(region.outputSize == PixelSize(width: 1000, height: 500) && !region.isDownsampled)
    let long = try TextRecognitionPlan(sourceSize: PixelSize(width: 1000, height: 32768)!)
    #expect(long.outputSize.height == 4096 && long.outputSize.width == 125)
}

@Test func textRecognitionRejectsInvalidRegionsAndRoundsSubpixels() throws {
    let size = PixelSize(width: 100, height: 100)!
    for region in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 1, height: 1),
                   CGRect(x: 0.5, y: 0.5, width: -0.1, height: 0.1),
                   CGRect(x: 0.5, y: 0.5, width: 0.1, height: -0.1),
                   CGRect(x: 0.1, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: CGFloat.nan, height: 1)] {
        #expect(throws: TextRecognitionPlanError.self) { try TextRecognitionPlan(sourceSize: size, selection: region) }
    }
    #expect(throws: TextRecognitionPlanError.self) { try TextRecognitionPlan(sourceSize: size, maximumDimension: 0) }
    #expect(throws: TextRecognitionPlanError.self) { try TextRecognitionPlan(sourceSize: size, crop: CGRect(x: 99, y: 0, width: 5, height: 100)) }
    let tiny = try TextRecognitionPlan(sourceSize: size, selection: CGRect(x: 0.991, y: 0.991, width: 0.001, height: 0.001))
    #expect(tiny.sourceArea == CGRect(x: 99, y: 99, width: 1, height: 1))
    let cropped = try TextRecognitionPlan(sourceSize: PixelSize(width: 1000, height: 1000)!,
                                         crop: CGRect(x: 100, y: 300, width: 100, height: 100),
                                         selection: CGRect(x: 0.999, y: 0.999, width: 0.0001, height: 0.0001))
    #expect(cropped.sourceArea == CGRect(x: 199, y: 399, width: 1, height: 1))
}

@Test func textRecognitionDragClampsAndNormalizesBothDirections() {
    let region = TextRecognitionPlan.selection(from: CGPoint(x: 1.2, y: 0.8), to: CGPoint(x: 0.2, y: -1))
    #expect(region == CGRect(x: 0.2, y: 0, width: 0.8, height: 0.8))
    #expect(TextRecognitionPlan.selection(from: .zero, to: .zero) == nil)
    #expect(TextRecognitionPlan.selection(from: .zero, to: CGPoint(x: CGFloat.infinity, y: 1)) == nil)
}

@Test func textRecognitionPreservesReadingOrderAndFlagsUncertainty() {
    let result = TextRecognitionResult(lines: [
        RecognizedTextLine(text: "Second column", confidence: 0.99, bounds: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.1)),
        RecognizedTextLine(text: "First column", confidence: 0.79, bounds: CGRect(x: 0, y: 0, width: 0.5, height: 0.1)),
        RecognizedTextLine(text: " \n", confidence: 0, bounds: .zero)])
    #expect(result.text == "Second column\nFirst column" && result.lines.count == 2 && result.hasUncertainText)
    #expect(TextRecognitionResult(lines: []).text.isEmpty)
    #expect(TextRecognitionResult(lines: [RecognizedTextLine(text: "Review", confidence: .nan, bounds: .zero)]).hasUncertainText)
    #expect(!TextRecognitionResult(lines: [RecognizedTextLine(text: "Review", confidence: 1, bounds: .zero)]).hasUncertainText)
}
