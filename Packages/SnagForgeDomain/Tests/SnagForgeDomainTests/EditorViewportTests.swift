import CoreGraphics
import Foundation
import Testing
@testable import SnagForgeDomain

@Test func openingAtActualPixelsDoesNotDependOnAnAlreadyLaidOutView() {
    let viewport = EditorViewport(fitsImage: false)
    #expect(viewport.zoom == 1 && viewport.offset == .zero)
    for backing: CGFloat in [1, 2] {
        let image = CGSize(width: 4097, height: 513)
        let rect = viewport.imageRect(image: image, in: CGRect(x: 0, y: 0, width: 801, height: 603), backingScale: backing)
        #expect(rect.width * backing == image.width && rect.height * backing == image.height)
        #expect(rect.minX * backing == (rect.minX * backing).rounded())
    }
    #expect(EditorViewport(fitsImage: true) == EditorViewport())
}

@Test func fitViewportCentersWithConstantMarginAndFollowsWindowSize() {
    let viewport = EditorViewport(), image = CGSize(width: 2400, height: 1600)
    let bounds = CGRect(x: 10, y: 20, width: 480, height: 320)
    let rect = viewport.imageRect(image: image, in: bounds, backingScale: 2)
    #expect(abs(rect.minX - 46) < 0.0001 && abs(rect.minY - 44) < 0.0001)
    #expect(abs(rect.width - 408) < 0.0001 && abs(rect.height - 272) < 0.0001)
    #expect(viewport.imageRect(image: image, in: bounds, backingScale: 1) == viewport.imageRect(image: image, in: bounds, backingScale: 2))
    #expect(viewport.scale(image: image, in: CGRect(x: 0, y: 0, width: 288, height: 208), backingScale: 2) == 0.1)
}

@Test func fitNeverUpscalesSmallImagesOnStandardOrRetinaDisplays() {
    let viewport = EditorViewport(), image = CGSize(width: 449, height: 441)
    for backing: CGFloat in [1, 2] {
        for size in [CGSize(width: 800, height: 600), CGSize(width: 1601, height: 1203)] {
            let rect = viewport.imageRect(image: image, in: CGRect(origin: .zero, size: size), backingScale: backing)
            #expect(rect.width * backing == image.width && rect.height * backing == image.height)
            #expect(abs(rect.midX - size.width / 2) <= 0.5 / backing)
            #expect(abs(rect.midY - size.height / 2) <= 0.5 / backing)
            #expect(rect.minX * backing == (rect.minX * backing).rounded())
            #expect(rect.minY * backing == (rect.minY * backing).rounded())
        }
        let small = CGRect(x: 0, y: 0, width: 200, height: 180)
        let rect = viewport.imageRect(image: image, in: small, backingScale: backing)
        #expect(rect.width * backing < image.width && rect.height <= small.height - 48)
        #expect(abs(rect.width / rect.height - image.width / image.height) < 0.0001)
    }
}

@Test func actualPixelsRemainAlignedAfterFractionalPanAndWindowResize() {
    let image = CGSize(width: 3841, height: 2161), anchor = CGPoint(x: 310.3, y: 250.2)
    for backing: CGFloat in [1, 2] {
        var viewport = EditorViewport()
        let bounds = CGRect(x: 0, y: 0, width: 801, height: 603)
        viewport.setZoom(1, at: anchor, image: image, in: bounds, backingScale: backing)
        viewport.pan(by: CGSize(width: 13.27, height: -21.12), image: image, in: bounds, backingScale: backing)
        for size in [bounds.size, CGSize(width: 923, height: 701)] {
            let rect = viewport.imageRect(image: image, in: CGRect(origin: .zero, size: size), backingScale: backing)
            #expect(rect.width * backing == image.width && rect.height * backing == image.height)
            #expect(rect.minX * backing == (rect.minX * backing).rounded())
            #expect(rect.minY * backing == (rect.minY * backing).rounded())
        }
    }
}

@Test func actualPixelsAccountForRetinaBackingScale() {
    let image = CGSize(width: 3840, height: 2160), bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    for backing: CGFloat in [1, 2] {
        var viewport = EditorViewport()
        viewport.setZoom(1, at: CGPoint(x: 400, y: 300), image: image, in: bounds, backingScale: backing)
        let rect = viewport.imageRect(image: image, in: bounds, backingScale: backing)
        #expect(rect.width * backing == image.width)
        #expect(rect.height * backing == image.height)
        #expect(viewport.imagePoint(from: CGPoint(x: 400, y: 300), image: image, in: bounds, backingScale: backing) == CGPoint(x: 1920, y: 1080))
    }
}

@Test func zoomKeepsImagePixelUnderPointerAndPanUsesSameProjection() {
    let image = CGSize(width: 3840, height: 2160), bounds = CGRect(x: 15, y: 25, width: 800, height: 600)
    let anchor = CGPoint(x: 310, y: 250)
    var viewport = EditorViewport()
    let pixel = viewport.imagePoint(from: anchor, image: image, in: bounds, backingScale: 2)
    viewport.setZoom(2, at: anchor, image: image, in: bounds, backingScale: 2)
    let after = viewport.imagePoint(from: anchor, image: image, in: bounds, backingScale: 2)
    // Pixel alignment may move the anchor by at most half a device pixel.
    #expect(abs(after.x - pixel.x) <= 0.25 && abs(after.y - pixel.y) <= 0.25)
    viewport.pan(by: CGSize(width: 100, height: -60), image: image, in: bounds, backingScale: 2)
    let rect = viewport.imageRect(image: image, in: bounds, backingScale: 2)
    let scale = viewport.scale(image: image, in: bounds, backingScale: 2)
    let projected = CGPoint(x: rect.minX + pixel.x * scale, y: rect.minY + pixel.y * scale)
    #expect(abs(projected.x - anchor.x - 100) <= 0.25 && abs(projected.y - anchor.y + 60) <= 0.25)
    #expect(viewport.imagePoint(from: projected, image: image, in: bounds, backingScale: 2) == pixel)
}

@Test func panReachesEveryEdgeAndSmallImagesStayCentered() {
    let image = CGSize(width: 3840, height: 2160), bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    var viewport = EditorViewport()
    viewport.setZoom(1, at: CGPoint(x: 400, y: 300), image: image, in: bounds, backingScale: 2)
    viewport.pan(by: CGSize(width: 100_000, height: 100_000), image: image, in: bounds, backingScale: 2)
    let first = viewport.imageRect(image: image, in: bounds, backingScale: 2)
    #expect(first.minX == 24 && first.minY == 24)
    viewport.pan(by: CGSize(width: -100_000, height: -100_000), image: image, in: bounds, backingScale: 2)
    let last = viewport.imageRect(image: image, in: bounds, backingScale: 2)
    #expect(last.maxX == bounds.maxX - 24 && last.maxY == bounds.maxY - 24)
    viewport.setZoom(0.1, at: .zero, image: image, in: bounds, backingScale: 2)
    viewport.pan(by: CGSize(width: 100, height: 100), image: image, in: bounds, backingScale: 2)
    #expect(viewport.offset == .zero)
    #expect(viewport.imageRect(image: image, in: bounds, backingScale: 2).midX == bounds.midX)
}

@Test func panRespondsImmediatelyAfterWindowResizeAndFitClearsViewState() {
    let image = CGSize(width: 2000, height: 2000), small = CGRect(x: 0, y: 0, width: 400, height: 400)
    let larger = CGRect(x: 0, y: 0, width: 800, height: 800)
    var viewport = EditorViewport()
    viewport.setZoom(1, at: CGPoint(x: 200, y: 200), image: image, in: small, backingScale: 2)
    viewport.pan(by: CGSize(width: 5000, height: 5000), image: image, in: small, backingScale: 2)
    let before = viewport.imageRect(image: image, in: larger, backingScale: 2)
    viewport.pan(by: CGSize(width: -10, height: -10), image: image, in: larger, backingScale: 2)
    #expect(viewport.imageRect(image: image, in: larger, backingScale: 2).minX == before.minX - 10)
    viewport.fit()
    #expect(viewport.zoom == nil && viewport.offset == .zero)
    let fitted = viewport
    viewport.pan(by: CGSize(width: 100, height: 100), image: image, in: small, backingScale: 2)
    #expect(viewport == fitted)
}

@Test func zoomIsBoundedAndRejectsInvalidRequests() {
    let image = CGSize(width: 3840, height: 2160), bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    var viewport = EditorViewport()
    viewport.setZoom(100, at: .zero, image: image, in: bounds, backingScale: 2)
    #expect(viewport.zoom == 16)
    viewport.setZoom(-1, at: .zero, image: image, in: bounds, backingScale: 2)
    #expect(viewport.zoom == 0.05)
    let before = viewport
    viewport.setZoom(.nan, at: .zero, image: image, in: bounds, backingScale: 2)
    viewport.setZoom(1, at: .zero, image: image, in: .zero, backingScale: 2)
    viewport.pan(by: CGSize(width: CGFloat.infinity, height: 0), image: image, in: bounds, backingScale: 2)
    #expect(viewport == before)
}
