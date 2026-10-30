import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

private func rotationImage() throws -> EditorObject {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")!
    var image = EditorObject(kind: .image, start: CGPoint(x: 100, y: 80), end: CGPoint(x: 220, y: 140))
    image.imageAsset = try EditorImageAsset(png: png, size: PixelSize(width: 1, height: 1)!)
    return image
}

@Test func imageRotationPreservesCenterAndInverseAtEveryAngle() throws {
    var image = try rotationImage()
    for angle in [-180.0, -93.5, -45, 0, 29.8, 90, 180] {
        image.imageRotationDegrees = angle
        let transform = image.imageRotationTransform
        let center = CGPoint(x: image.rect.midX, y: image.rect.midY)
        let mapped = center.applying(transform)
        #expect(abs(mapped.x - center.x) < 0.000001 && abs(mapped.y - center.y) < 0.000001)
        let restored = image.start.applying(transform).applying(transform.inverted())
        #expect(abs(restored.x - image.start.x) < 0.000001 && abs(restored.y - image.start.y) < 0.000001)
        let moved = image.translated(by: CGSize(width: -300, height: 50))
        #expect(moved.imageRotationDegrees == angle)
        #expect(abs(moved.rotatedImageBounds.minX - (image.rotatedImageBounds.minX - 300)) < 0.000001)
    }
    image.imageRotationDegrees = 90
    #expect(image.rotatedImageBounds == CGRect(x: 130, y: 50, width: 60, height: 120))
}

@Test func imageRotationPersistsRejectsInvalidAnglesAndMigratesOldDocuments() throws {
    var image = try rotationImage(); image.imageRotationDegrees = 27.5
    func document(_ object: EditorObject) -> ProjectDocument { ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 400, height: 300)!, objects: [object]) }
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document(image))).objects == [image])
    #expect(image.duplicated(by: CGSize(width: 10, height: 20)).imageRotationDegrees == 27.5)
    for angle in [Double.nan, .infinity, -180.1, 180.1] {
        var invalid = image; invalid.imageRotationDegrees = angle
        #expect(throws: ProjectError.invalidDocument) { try document(invalid).validated() }
    }
    var unrelated = EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 20, y: 20)); unrelated.imageRotationDegrees = 25
    #expect(throws: ProjectError.invalidDocument) { try document(unrelated).validated() }
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document(image))) as! [String: Any]
    json["schemaVersion"] = 18
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    image.imageRotationDegrees = nil
    json["objects"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([image]))
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated.schemaVersion == 19 && migrated.objects == [image])
}

@Test func imageRotationAndExpandedCanvasShareOneUndoTransaction() throws {
    let image = try rotationImage()
    var rotated = image; rotated.imageRotationDegrees = 40
    var history = EditorHistory(objects: [image])
    history.beginTransaction(); history.updateTransaction([rotated])
    let canvas = CGRect(x: -20, y: -40, width: 500, height: 360)
    history.updateTransaction([rotated], canvasRect: canvas, crop: nil, resizedSize: nil); history.endTransaction()
    history.undo(); #expect(history.objects == [image] && history.canvasRect == nil)
    history.redo(); #expect(history.objects == [rotated] && history.canvasRect == canvas)
}
