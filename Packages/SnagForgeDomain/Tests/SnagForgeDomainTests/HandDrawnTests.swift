import Testing
import Foundation
import CoreGraphics
@testable import SnagForgeDomain

@Test func handDrawnArrowSelectionFollowsCurveAndPreservesTranslation() {
    var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 450, y: 50))
    arrow.drawingStyle = .handDrawn
    // Cubic midpoint lies below the straight chord.
    let midpoint = CGPoint(x: 263.5, y: 131)
    #expect(arrow.hitsArrow(midpoint, tolerance: 5))
    #expect(!arrow.hitsArrow(CGPoint(x: 250, y: 50), tolerance: 5))
    let moved = arrow.translated(by: CGSize(width: 23, height: -18))
    #expect(moved.hitsArrow(CGPoint(x: midpoint.x + 23, y: midpoint.y - 18), tolerance: 5))
    var t = CGAffineTransform(translationX: 23, y: -18)
    #expect(EditorHandDrawn.path(for: arrow).copy(using: &t)! == EditorHandDrawn.path(for: moved))
    #expect(EditorHandDrawn.path(for: arrow) == EditorHandDrawn.path(for: arrow.duplicated(by: .zero)))
}

@Test func handDrawnPersistsAndOldProjectsKeepOrganization() throws {
    var ellipse = EditorObject(kind: .ellipse, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 280, y: 190))
    ellipse.drawingStyle = .handDrawn
    let doc = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 600, height: 400)!, objects: [ellipse], tags: ["Test"], collections: ["Examples"])
    let decoded = try ProjectDocument.decode(JSONEncoder().encode(doc))
    #expect(decoded == doc)
    #expect(EditorHandDrawn.path(for: decoded.objects[0]) == EditorHandDrawn.path(for: ellipse))
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
    legacy["schemaVersion"] = 7
    var objects = try #require(legacy["objects"] as? [[String: Any]])
    objects[0].removeValue(forKey: "drawingStyle"); legacy["objects"] = objects
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy))
    #expect(migrated.tags == doc.tags && migrated.collections == doc.collections)
    #expect(migrated.objects[0].effectiveDrawingStyle == .precise)
    #expect(migrated.schemaVersion == ProjectDocument.currentVersion)
}

@Test func handDrawnSavedStylesAndHistoryPreserveGeometry() throws {
    var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 280, y: 190))
    arrow.drawingStyle = .handDrawn
    let style = try JSONDecoder().decode(EditorSavedStyle.self, from: JSONEncoder().encode(EditorSavedStyle(object: arrow)))
    var target = arrow; target.drawingStyle = nil; target.end.x = 350
    let styled = try #require(style.applying(to: target))
    #expect(styled.end == target.end && styled.id == target.id && styled.effectiveDrawingStyle == .handDrawn)
    var history = EditorHistory(objects: [target]); history.commit([styled]); history.undo()
    #expect(history.objects == [target]); history.redo(); #expect(history.objects == [styled])
    var ellipse = arrow; ellipse.kind = .ellipse
    var rectangle = target; rectangle.kind = .rectangle
    #expect(EditorSavedStyle(object: ellipse).applying(to: rectangle)?.drawingStyle == .handDrawn)
}
