import Foundation
import Testing
@testable import SnagForgeDomain

@Test func typographyAndTailRoundTripAndLegacyMigration() throws {
    var object = EditorObject(kind: .callout, start: CGPoint(x: 100, y: 120), text: "Text", textWidth: 150)
    let legacy = ProjectDocument(title: "Legacy", pixelSize: PixelSize(width: 600, height: 400)!, objects: [object],
                                 crop: CGRect(x: 10, y: 10, width: 500, height: 300), resizedSize: PixelSize(width: 250, height: 150))
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
    json["schemaVersion"] = 3
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated == legacy && migrated.schemaVersion == ProjectDocument.currentVersion)
    #expect(migrated.objects[0].textStyle == nil && migrated.objects[0].calloutTip == nil)
    #expect(migrated.objects[0].effectiveTextStyle == EditorTextStyle())
    object.textStyle = EditorTextStyle(family: "Helvetica", weight: .bold, italic: true, alignment: .right)
    object.calloutTip = CGPoint(x: 35, y: 55)
    var changed = legacy; changed.objects = [object]
    #expect(try ProjectDocument.decode(JSONEncoder().encode(changed)) == changed)
    let copy = object.duplicated(by: CGSize(width: 16, height: 24))
    #expect(copy.id != object.id && copy.textStyle == object.textStyle)
    #expect(copy.calloutTip == CGPoint(x: 51, y: 79))
    #expect(copy.start == CGPoint(x: 116, y: 144))
    var history = EditorHistory(objects: legacy.objects)
    history.commit([object]); history.undo(); #expect(history.objects == legacy.objects)
    history.redo(); #expect(history.objects == [object])
}

@Test func rejectInvalidTypographyAndTailCoordinates() throws {
    var object = EditorObject(kind: .callout, start: .zero, text: "Test")
    var document = ProjectDocument(title: "Invalid", pixelSize: PixelSize(width: 100, height: 100)!)
    for tip in [CGPoint(x: CGFloat.infinity, y: 1), CGPoint(x: 1, y: CGFloat.nan), CGPoint(x: 1_000_001, y: 0)] {
        object.calloutTip = tip; document.objects = [object]
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
    object.calloutTip = nil
    for family in ["", String(repeating: "a", count: 257)] {
        object.textStyle = EditorTextStyle(family: family); document.objects = [object]
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
}
