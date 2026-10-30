import Foundation
import Testing
@testable import SnagForgeDomain

@Test func presentationGeometryContainsRotatedPixelsAndIsInvertible() throws {
    let size = PixelSize(width: 120, height: 80)!
    for angle in [-180.0, -123.4, -90, -22.5, 0, 17.3, 45, 90, 180] {
        for alignment in PresentationAlignment.allCases {
            var style = EditorPresentation(); style.rotationDegrees = angle; style.padding = 12; style.aspectRatio = .wide; style.alignment = alignment
            let geometry = try #require(style.geometry(for: size))
            let canvas = CGRect(x: 0, y: 0, width: geometry.outputSize.width, height: geometry.outputSize.height).insetBy(dx: -0.001, dy: -0.001)
            for point in [CGPoint.zero, CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 80), CGPoint(x: 0, y: 80)] {
                let output = point.applying(geometry.imageTransform)
                #expect(canvas.contains(output))
                let recovered = output.applying(geometry.imageTransform.inverted())
                #expect(abs(recovered.x - point.x) < 0.00001 && abs(recovered.y - point.y) < 0.00001)
            }
            #expect(abs(Double(geometry.outputSize.width) / Double(geometry.outputSize.height) - 16.0 / 9) < 0.02)
        }
    }
    var quarter = EditorPresentation(); quarter.rotationDegrees = 90
    #expect(quarter.geometry(for: size)?.outputSize == PixelSize(width: 80, height: 120))
}

@Test func presentationHistoryGroupsSliderAndSurvivesOtherChanges() {
    var history = EditorHistory()
    var style = EditorPresentation(); style.rotationDegrees = 5
    history.beginTransaction(); history.updatePresentationTransaction(style)
    style.rotationDegrees = 27.5; style.padding = 40
    history.updatePresentationTransaction(style); history.endTransaction()
    history.commitTransform(.mirrored)
    history.commit([EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 30, y: 20))])
    history.undo(); #expect(history.presentation == style && history.objects.isEmpty)
    history.undo(); #expect(history.transform == .identity && history.presentation == style)
    history.undo(); #expect(history.presentation.isIdentity)
    history.redo(); #expect(history.presentation == style)
}

@Test func presentationProjectMigratesVersion15WithoutLosingItsTransform() throws {
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 120, height: 80)!, transform: .mirroredClockwise90)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    json["schemaVersion"] = 15
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated.transform == .mirroredClockwise90 && migrated.presentation == nil)
    var style = EditorPresentation(); style.rotationDegrees = 33.3; style.padding = 40
    let current = ProjectDocument(title: "Synthetic", pixelSize: document.pixelSize, transform: document.transform, presentation: style)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(current)) == current)
    #expect(ProjectArchive.copy(current, id: UUID()).presentation == style)
    json["presentation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style))
    #expect(throws: ProjectError.self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func presentationRejectsInvalidAnglesDimensionsAndExternalPaths() throws {
    for angle in [Double.nan, .infinity, -181, 181] {
        var style = EditorPresentation(); style.rotationDegrees = angle
        #expect(!style.isValid && style.geometry(for: PixelSize(width: 10, height: 10)!) == nil)
    }
    var style = EditorPresentation(); style.background = .image(path: "/tmp/not-portable.png", blur: 0)
    #expect(!style.isValid)
    style.background = nil; style.rotationDegrees = 45
    #expect(style.geometry(for: PixelSize(width: 32768, height: 1000)!) == nil)
    style.rotationDegrees = 0; style.padding = -1
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 120, height: 80)!, presentation: style)
    #expect(throws: ProjectError.self) { try document.validated() }
    let invalidCrop = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 120, height: 80)!, crop: .zero, presentation: EditorPresentation())
    #expect(throws: ProjectError.self) { try invalidCrop.validated() }
}

@Test func previewKeepsScaleAtEveryAngleAndMigratesVersion16() throws {
    let size = PixelSize(width: 2705, height: 1114)!, bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    var style = EditorPresentation(); style.padding = 40
    let reference = style.previewReferenceSize(for: size)
    let viewport = EditorViewport()
    let scale = viewport.scale(image: reference, in: bounds, backingScale: 2)
    for angle in stride(from: -180.0, through: 180, by: 7.5) {
        style.rotationDegrees = angle
        #expect(style.previewReferenceSize(for: size) == reference)
        let geometry = try #require(style.geometry(for: size))
        let rect = try #require(style.previewRect(for: size, viewport: viewport, in: bounds, backingScale: 2))
        #expect(abs(rect.width / CGFloat(geometry.outputSize.width) - scale) < 0.00001)
        #expect(abs(rect.midX - bounds.midX) < 0.00001 && abs(rect.midY - bounds.midY) < 0.00001)
    }
    let document = ProjectDocument(title: "Synthetic", pixelSize: size, presentation: style)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    json["schemaVersion"] = 16
    #expect(try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)).presentation == style)
    style.border = EditorImageBorder(width: 4)
    let framed = ProjectDocument(title: "Synthetic", pixelSize: size, presentation: style)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(framed)).presentation?.border == style.border)
    json["presentation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style))
    #expect(throws: ProjectError.self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func addedPaddingOnlyExpandsCanvasAtLockedPreviewScale() throws {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    for size in [PixelSize(width: 2705, height: 1114)!, PixelSize(width: 32768, height: 1000)!] {
        var viewport = EditorViewport(), style = EditorPresentation()
        let imageSize = CGSize(width: size.width, height: size.height)
        let originalScale = viewport.scale(image: imageSize, in: bounds, backingScale: 2)
        viewport.lockScale(image: imageSize, in: bounds, backingScale: 2)
        for padding in [0, 40, 200, 500] {
            style.padding = padding
            let reference = style.previewReferenceSize(for: size)
            #expect(abs(viewport.scale(image: reference, in: bounds, backingScale: 2) - originalScale) < 0.000001)
            // The largest supported source cannot gain extra export pixels;
            // its viewport still preserves the small fitted scale correctly.
            if size.width < 32768 {
                let geometry = try #require(style.geometry(for: size))
                #expect(geometry.outputSize.width == size.width + 2 * padding)
                #expect(geometry.outputSize.height == size.height + 2 * padding)
                #expect(CGPoint.zero.applying(geometry.imageTransform) == CGPoint(x: padding, y: padding))
            }
        }
    }
}
