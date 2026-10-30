import Foundation
import Testing
@testable import SnagForgeDomain

@Test func blurStylesRoundTripAndMigrateLegacyGaussian() throws {
    let size = PixelSize(width: 320, height: 160)!
    for style in EditorBlurStyle.allCases {
        var object = EditorObject(kind: .blur, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 220, y: 90))
        object.blurStyle = style; object.blurRadius = 24
        let document = ProjectDocument(title: "Synthetic", pixelSize: size, objects: [object])
        #expect(try ProjectDocument.decode(JSONEncoder().encode(document)).objects == [object])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        json["schemaVersion"] = 17
        #expect(throws: ProjectError.self) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
        var legacy = object; legacy.blurStyle = nil
        json["objects"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy]))
        let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated.schemaVersion == ProjectDocument.currentVersion && migrated.objects[0].effectiveBlurStyle == .gaussian)
    }
}

@Test func blurStylesSurviveDuplicationUndoAndSavedStyleLibraries() throws {
    for mode in EditorBlurStyle.allCases {
        var object = EditorObject(kind: .blur, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 80))
        object.blurStyle = mode; object.blurRadius = 32
        #expect(object.duplicated(by: CGSize(width: 10, height: 10)).effectiveBlurStyle == mode)
        let saved = EditorSavedStyle(object: object)
        let decoded = try JSONDecoder().decode(EditorSavedStyle.self, from: JSONEncoder().encode(saved))
        let plain = EditorObject(kind: .blur, start: .zero, end: CGPoint(x: 80, y: 40))
        #expect(decoded.applying(to: plain)?.effectiveBlurStyle == mode)
        #expect(decoded.applying(to: plain)?.blurRadius == 32)
        var history = EditorHistory(objects: [plain]); history.beginTransaction()
        history.updateTransaction([decoded.applying(to: plain)!]); history.endTransaction()
        history.undo(); #expect(history.objects == [plain]); history.redo()
        #expect(history.objects[0].effectiveBlurStyle == mode)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        legacy.removeValue(forKey: "blurStyle")
        let restored = try JSONDecoder().decode(EditorSavedStyle.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.applying(to: plain)?.effectiveBlurStyle == .gaussian)
    }
}

@Test func blurStyleCannotAttachToUnrelatedObjects() throws {
    var arrow = EditorObject(kind: .arrow, start: .zero, end: CGPoint(x: 30, y: 30)); arrow.blurStyle = .pixelate
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 120, height: 80)!, objects: [arrow])
    #expect(throws: ProjectError.self) { try document.validated() }
}
