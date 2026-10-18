import Foundation
import Testing
@testable import SnagForgeDomain

@Test func videoRegionUsesTopLeftPointsAndEvenRetinaPixels() throws {
    let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
    let selection = CGRect(x: -1400, y: 900, width: 301.5, height: 101.5)
    let plan = try VideoGeometry(selection: selection, screen: screen, scale: 2)
    #expect(plan.sourceRect == CGRect(x: 40, y: 98.5, width: 301.5, height: 101.5))
    #expect(plan.pixelSize == PixelSize(width: 602, height: 202))
}
@Test func videoRegionCapsEncoderSizeAndClipsToDisplay() throws {
    let screen = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    let plan = try VideoGeometry(selection: screen, screen: screen, scale: 2)
    #expect(plan.pixelSize == PixelSize(width: 1620, height: 1080))
    let clip = try VideoGeometry(selection: CGRect(x: -20, y: -20, width: 120, height: 120), screen: screen, scale: 1)
    #expect(clip.sourceRect == CGRect(x: 0, y: 1900, width: 100, height: 100))
    #expect(throws: VideoGeometryError.self) { try VideoGeometry(selection: .zero, screen: screen, scale: 1) }
    #expect(throws: VideoGeometryError.self) { try VideoGeometry(selection: screen, screen: screen, scale: .nan) }
}

@Test func videoWindowUsesFullContentAtRetinaScale() throws {
    let plan = try VideoGeometry(contentSize: CGSize(width: 701.5, height: 401.5), scale: 2)
    #expect(plan.sourceRect == CGRect(x: 0, y: 0, width: 701.5, height: 401.5))
    #expect(plan.pixelSize == PixelSize(width: 1402, height: 802))
}
@Test func videoWindowCapsPortraitAndLandscapeWithEvenPixels() throws {
    #expect(try VideoGeometry(contentSize: CGSize(width: 2560, height: 1440), scale: 2).pixelSize == PixelSize(width: 1920, height: 1080))
    #expect(try VideoGeometry(contentSize: CGSize(width: 800, height: 1600), scale: 2).pixelSize == PixelSize(width: 540, height: 1080))
}
@Test func videoWindowRejectsMissingAndInvalidContent() {
    for size in [CGSize.zero, CGSize(width: -40, height: 60), CGSize(width: 60, height: CGFloat.infinity), CGSize(width: CGFloat.nan, height: 60)] {
        #expect(throws: VideoGeometryError.self) { try VideoGeometry(contentSize: size, scale: 2) }
    }
    #expect(throws: VideoGeometryError.self) { try VideoGeometry(contentSize: CGSize(width: 1, height: 1), scale: 1) }
}
