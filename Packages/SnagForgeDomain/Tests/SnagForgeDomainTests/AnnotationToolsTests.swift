import Testing
import Foundation
import CoreGraphics
@testable import SnagForgeDomain

@Test func bentArrowsFollowHandleInEveryStyleAndTranslateAsAWhole() throws {
    for style in EditorDrawingStyle.allCases {
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 40, y: 50), end: CGPoint(x: 440, y: 50))
        arrow.drawingStyle = style; arrow.arrowBend = CGPoint(x: 240, y: 180)
        #expect(arrow.hitsArrow(arrow.arrowBend!, tolerance: 2))
        #expect(!arrow.hitsArrow(CGPoint(x: 240, y: 50), tolerance: 2))
        let delta = CGSize(width: -80, height: 35), moved = arrow.translated(by: delta)
        #expect(moved.arrowBend == CGPoint(x: 160, y: 215))
        var transform = CGAffineTransform(translationX: delta.width, y: delta.height)
        let translatedBounds = EditorArrow.path(for: arrow).copy(using: &transform)!.boundingBoxOfPath
        let movedBounds = EditorArrow.path(for: moved).boundingBoxOfPath
        #expect(abs(translatedBounds.minX - movedBounds.minX) < 0.000001 && abs(translatedBounds.maxY - movedBounds.maxY) < 0.000001)
        #expect(moved.hitsArrow(CGPoint(x: 160, y: 215), tolerance: 2))
        #expect(arrow.duplicated(by: delta).arrowBend == moved.arrowBend)
        let doc = ProjectDocument(title: "Bend", pixelSize: PixelSize(width: 640, height: 480)!, objects: [arrow])
        #expect(try ProjectDocument.decode(JSONEncoder().encode(doc)) == doc)
        var history = EditorHistory(objects: [arrow]); history.commit([moved]); history.undo()
        #expect(history.objects == [arrow]); history.redo(); #expect(history.objects == [moved])
    }
}

@Test func magnifierAndNewStyleValidationRejectsInvalidFieldsAndMigratesCanvas() throws {
    var lens = EditorObject(kind: .magnifier, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 260, y: 260))
    lens.magnification = 3
    let size = PixelSize(width: 640, height: 480)!
    func document(_ object: EditorObject) -> ProjectDocument { ProjectDocument(title: "Lens", pixelSize: size, objects: [object]) }
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document(lens))).objects == [lens])
    for value: CGFloat in [1, 5.1, .infinity, .nan] {
        var invalid = lens; invalid.magnification = value
        #expect(throws: ProjectError.invalidDocument) { try document(invalid).validated() }
    }
    var invalid = lens; invalid.arrowBend = .zero
    #expect(throws: ProjectError.invalidDocument) { try document(invalid).validated() }
    invalid = lens; invalid.kind = .rectangle
    #expect(throws: ProjectError.invalidDocument) { try document(invalid).validated() }
    var legacy = ProjectDocument(title: "Version 11", pixelSize: size, canvasRect: CGRect(x: -20, y: -30, width: 700, height: 550))
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    json["schemaVersion"] = 11
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated.canvasRect == legacy.canvasRect && migrated.schemaVersion == ProjectDocument.currentVersion)
    legacy.objects = [lens]
    json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    json["schemaVersion"] = 11
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func magnifierStylesKeepPlacementAndOldStylesDecode() throws {
    var lens = EditorObject(kind: .magnifier, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 260, y: 260))
    lens.magnification = 4
    let style = EditorSavedStyle(object: lens)
    let target = lens.translated(by: CGSize(width: 30, height: -20))
    let applied = try #require(style.applying(to: target))
    #expect(applied.start == target.start && applied.end == target.end && applied.magnification == 4)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
    json.removeValue(forKey: "magnification")
    #expect(try JSONDecoder().decode(EditorSavedStyle.self, from: JSONSerialization.data(withJSONObject: json)).isValid)
}

@Test func offsetMagnifierPersistsAndValidatesSource() throws {
    var lens = EditorObject(kind: .magnifier, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 320, y: 220))
    lens.magnifierSource = CGPoint(x: 50, y: 60)
    let doc = ProjectDocument(title: "Offset lens", pixelSize: PixelSize(width: 640, height: 480)!, objects: [lens])
    #expect(try ProjectDocument.decode(JSONEncoder().encode(doc)) == doc)
    #expect(lens.translated(by: CGSize(width: 10, height: 20)).magnifierSource == CGPoint(x: 60, y: 80))
    lens.magnifierSource = CGPoint(x: CGFloat.infinity, y: 0)
    let invalid = ProjectDocument(title: "Invalid", pixelSize: PixelSize(width: 640, height: 480)!, objects: [lens])
    #expect(throws: ProjectError.self) { try invalid.validated() }
}
