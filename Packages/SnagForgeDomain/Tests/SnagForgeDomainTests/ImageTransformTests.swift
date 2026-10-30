import Foundation
import Testing
@testable import SnagForgeDomain

@Test func compositionTransformsFormLosslessSymmetries() {
    let size = PixelSize(width: 120, height: 80)!
    for transform in EditorImageTransform.allCases {
        #expect(transform.rotated().rotated().rotated().rotated() == transform)
        #expect(transform.flippedHorizontally().flippedHorizontally() == transform)
        #expect(transform.flippedVertically().flippedVertically() == transform)
        #expect(transform.rotated().rotated(clockwise: false) == transform)
        #expect(transform.applying(to: transform.applying(to: size)) == size)
        let affine = transform.affineTransform(size: CGSize(width: 120, height: 80))
        #expect(CGRect(x: 0, y: 0, width: 120, height: 80).applying(affine).origin == .zero)
        for point in [CGPoint.zero, CGPoint(x: 120, y: 80), CGPoint(x: 17, y: 31)] {
            #expect(point.applying(affine).applying(affine.inverted()) == point)
        }
    }
    #expect(EditorImageTransform.clockwise90.sourceVector(fromDisplayed: CGSize(width: 1, height: 0)) == CGSize(width: 0, height: -1))
}

@Test func transformHistoryPreservesGeometryAndTransactions() {
    let object = EditorObject(kind: .text, start: CGPoint(x: 20, y: 10), text: "Synthetic")
    let crop = CGRect(x: 5, y: 7, width: 100, height: 50)
    var history = EditorHistory(objects: [object], crop: crop, resizedSize: PixelSize(width: 200, height: 75))
    history.commitTransform(.clockwise90)
    history.beginTransaction(); history.updateTransaction([object.translated(by: CGSize(width: 4, height: 3))]); history.endTransaction()
    history.undo(); #expect(history.objects == [object] && history.transform == .clockwise90)
    history.undo(); #expect(history.transform == .identity && history.crop == crop)
    history.redo(); #expect(history.transform == .clockwise90 && history.resizedSize == PixelSize(width: 200, height: 75))
}

@Test func transformProjectMigrationAndDimensions() throws {
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 120, height: 80)!,
                                   resizedSize: PixelSize(width: 240, height: 60), transform: .mirroredClockwise90)
    #expect(document.outputPixelSize == PixelSize(width: 60, height: 240))
    #expect(document.untransformedOutputPixelSize == PixelSize(width: 240, height: 60))
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    let original = ProjectDocument(title: "Legacy", pixelSize: PixelSize(width: 120, height: 80)!)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    json["schemaVersion"] = 14
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated.transform == .identity && migrated.schemaVersion == ProjectDocument.currentVersion)
    json["imageTransform"] = EditorImageTransform.clockwise90.rawValue
    #expect(throws: ProjectError.self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    json["schemaVersion"] = ProjectDocument.currentVersion; json["imageTransform"] = 99
    #expect(throws: (any Error).self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}
