import Testing
import Foundation
import CoreGraphics
@testable import SnagForgeDomain

@Test func penAndSpotlightPersistAndMigrateVersionTwelve() throws {
    var pen = EditorObject(kind: .pen, start: CGPoint(x: -10, y: 50), end: CGPoint(x: 210, y: 90))
    pen.penStroke = EditorPenStroke(points: [pen.start, CGPoint(x: 80, y: 25), pen.end])
    var focus = EditorObject(kind: .spotlight, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 240, y: 220))
    focus.spotlightStyle = .init(shape: .ellipse, opacity: 0.65)
    let document = ProjectDocument(title: "Synthetic drawing", pixelSize: PixelSize(width: 640, height: 480)!, objects: [pen, focus])
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    let delta = CGSize(width: 20, height: -15), moved = pen.translated(by: delta)
    #expect(moved.penStroke?.points[1] == CGPoint(x: 100, y: 10))
    #expect(pen.duplicated(by: delta).penStroke == moved.penStroke)
    var source = document; source.objects = []
    source.canvasRect = CGRect(x: -30, y: -20, width: 700, height: 520)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
    json["schemaVersion"] = 12
    #expect(try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)).canvasRect == source.canvasRect)
    json["objects"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([pen]))
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func drawingFieldsValidateAndStylesNeverCopyStrokeCoordinates() throws {
    func document(_ object: EditorObject) -> ProjectDocument {
        ProjectDocument(title: "Validate", pixelSize: PixelSize(width: 640, height: 480)!, objects: [object])
    }
    var pen = EditorObject(kind: .pen, start: .zero, end: CGPoint(x: 100, y: 100))
    #expect(throws: ProjectError.invalidDocument) { try document(pen).validated() }
    pen.penStroke = EditorPenStroke(points: [.zero, CGPoint(x: 50, y: 70)])
    let style = EditorSavedStyle(object: pen)
    var target = pen.translated(by: CGSize(width: 100, height: 100)); target.penStroke?.isSmoothed = false
    #expect(style.applying(to: target)?.penStroke?.points == target.penStroke?.points)
    #expect(style.applying(to: target)?.penStroke?.isSmoothed == true)
    pen.penStroke?.points.append(CGPoint(x: CGFloat.infinity, y: 1))
    #expect(throws: ProjectError.invalidDocument) { try document(pen).validated() }
    var focus = EditorObject(kind: .spotlight, start: .zero, end: CGPoint(x: 50, y: 60))
    focus.spotlightStyle = .init(opacity: 1.1)
    #expect(throws: ProjectError.invalidDocument) { try document(focus).validated() }
    focus.spotlightStyle = .init(opacity: 0.5)
    #expect(try document(focus).validated().objects == [focus])
    focus.kind = .rectangle
    #expect(throws: ProjectError.invalidDocument) { try document(focus).validated() }
}
