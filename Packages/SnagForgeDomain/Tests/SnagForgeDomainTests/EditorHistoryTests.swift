import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func wholeDragUndoesInOneStepAndNewEditClearsRedo() {
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 80, y: 90))
    var history = EditorHistory()
    history.commit([arrow])
    history.commit([arrow.translated(by: CGSize(width: 30, height: -10))])
    history.undo()
    #expect(history.objects == [arrow])
    history.redo()
    #expect(history.objects[0].end == CGPoint(x: 110, y: 80))
    history.undo()
    history.commit([])
    #expect(!history.canRedo)
    history.undo()
    #expect(history.objects == [arrow])
}

@Test func noOpDoesNotConsumeUndoAndDocumentsHaveSeparateHistory() {
    var history = EditorHistory()
    history.commit([])
    #expect(!history.canUndo)
    history.commit([EditorObject(kind: .text, start: .zero, text: "Hello")])
    var replacement = EditorHistory()
    replacement.undo()
    #expect(replacement.objects.isEmpty)
    #expect(history.objects.count == 1)
}

@Test func arrowHitTestingUsesSegmentNotBoundingBox() {
    let arrow = EditorObject(kind: .arrow, start: .zero, end: CGPoint(x: 100, y: 100))
    #expect(arrow.hitsArrow(CGPoint(x: 50, y: 53), tolerance: 4))
    #expect(!arrow.hitsArrow(CGPoint(x: 5, y: 95), tolerance: 4))
    #expect(!arrow.hitsArrow(CGPoint(x: 150, y: 150), tolerance: 4))
}

@Test func stylesAndNewObjectsUndoTogether() {
    for kind in [EditorObject.Kind.rectangle, .ellipse, .callout, .blur] {
        var history = EditorHistory()
        let object = EditorObject(kind: kind, start: CGPoint(x: 80, y: 70), end: CGPoint(x: 20, y: 10))
        history.commit([object])
        var changed = object
        changed.color = EditorColor(red: 0, green: 1, blue: 0)
        changed.fontSize = 48; changed.lineWidth = 12; changed.blurRadius = 30
        history.commit([changed])
        history.undo(); #expect(history.objects == [object])
        history.redo(); #expect(history.objects == [changed])
        #expect(object.rect == CGRect(x: 20, y: 10, width: 60, height: 60))
    }
}

@Test func inlineTypingIsLiveButFinishesAsOneUndoStep() {
    var history = EditorHistory()
    var text = EditorObject(kind: .text, start: CGPoint(x: 20, y: 30), text: "H")
    history.beginTransaction()
    history.updateTransaction([text])
    #expect(history.objects == [text])
    #expect(history.canUndo && !history.canRedo)
    text.text = "Hallo\nWelt"
    history.updateTransaction([text])
    #expect(history.objects[0].text == "Hallo\nWelt")
    history.endTransaction()
    history.undo(); #expect(history.objects.isEmpty)
    history.redo(); #expect(history.objects == [text])
}

@Test func cancellingInlineEditPreservesObjectsAndRedo() {
    var history = EditorHistory()
    let text = EditorObject(kind: .text, start: .zero, text: "Original")
    history.commit([text]); history.undo()
    history.beginTransaction(); history.updateTransaction([text]); history.cancelTransaction()
    #expect(history.objects.isEmpty && history.canRedo)
    history.redo(); #expect(history.objects == [text])
    history.beginTransaction(); history.updateTransaction([]); history.endTransaction()
    history.undo(); #expect(history.objects == [text])
}

@Test func textBoxWidthRoundTripsAndOlderProjectsStillOpen() throws {
    let text = EditorObject(kind: .text, start: CGPoint(x: 20, y: 30), text: "Eine lange Zeile", textWidth: 140)
    let document = ProjectDocument(title: "Text", pixelSize: PixelSize(width: 240, height: 160)!, objects: [text])
    let data = try JSONEncoder().encode(document)
    #expect(try ProjectDocument.decode(data).objects[0].textWidth == 140)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var objects = legacy["objects"] as! [[String: Any]]
    objects[0].removeValue(forKey: "textWidth"); legacy["objects"] = objects
    let decoded = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy))
    #expect(decoded.objects[0].textWidth == nil)
    var invalid = document
    invalid.objects[0].textWidth = 0
    #expect(throws: ProjectError.invalidDocument) { try invalid.validated() }
    invalid.objects[0].textWidth = .infinity
    #expect(throws: ProjectError.invalidDocument) { try invalid.validated() }
}

@Test func optionalShapeStylesPreserveLegacyAppearance() throws {
    let kinds: [EditorObject.Kind] = [.rectangle, .ellipse, .callout]
    let document = ProjectDocument(title: "Legacy", pixelSize: PixelSize(width: 240, height: 160)!, objects: kinds.map {
        EditorObject(kind: $0, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 100, y: 70), text: "Text")
    })
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    var objects = json["objects"] as! [[String: Any]]
    for index in objects.indices {
        objects[index].removeValue(forKey: "fill")
        objects[index].removeValue(forKey: "cornerRadius")
        objects[index].removeValue(forKey: "stroke")
    }
    json["objects"] = objects
    let legacy = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(legacy.objects[0].cornerRadius == nil)
    #expect(legacy.objects.allSatisfy { $0.stroke == nil && $0.effectiveStroke == EditorStroke() })
    #expect(!legacy.objects[0].effectiveFill.isEnabled && !legacy.objects[1].effectiveFill.isEnabled)
    #expect(legacy.objects[2].effectiveFill == EditorFill(isEnabled: true))
    var explicit = legacy
    explicit.objects[2].fill = EditorFill(isEnabled: false)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(explicit)).objects[2].effectiveFill.isEnabled == false)
}

@Test func optionalCalloutHeightPreservesOldLayoutAndRejectsInvalidSizes() throws {
    var callout = EditorObject(kind: .callout, start: CGPoint(x: 20, y: 30), text: "Text", textWidth: 120)
    callout.textHeight = 90
    var document = ProjectDocument(title: "Callout", pixelSize: PixelSize(width: 240, height: 160)!, objects: [callout])
    let data = try JSONEncoder().encode(document)
    #expect(try ProjectDocument.decode(data).objects[0].textHeight == 90)
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var objects = json["objects"] as! [[String: Any]]
    objects[0].removeValue(forKey: "textHeight"); json["objects"] = objects
    #expect(try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)).objects[0].textHeight == nil)
    for height: CGFloat in [0, -1, .infinity, .nan, 1_000_001] {
        document.objects[0].textHeight = height
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
}

@Test func unknownStrokeStyleCannotSilentlyChangeAppearance() throws {
    var object = EditorObject(kind: .triangle, start: .zero, end: CGPoint(x: 50, y: 70))
    object.stroke = EditorStroke(style: .dashed)
    let document = ProjectDocument(title: "Stroke", pixelSize: PixelSize(width: 240, height: 160)!, objects: [object])
    let data = try JSONEncoder().encode(document)
    let unsupported = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "dashed", with: "unknown")
    #expect(throws: (any Error).self) { try ProjectDocument.decode(Data(unsupported.utf8)) }
}

@Test func invalidFillAndCornerValuesAreRejected() throws {
    var document = ProjectDocument(title: "Validation", pixelSize: PixelSize(width: 240, height: 160)!,
        objects: [EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 100, y: 100))])
    for opacity in [-0.1, 1.1, Double.infinity, Double.nan] {
        document.objects[0].fill = EditorFill(isEnabled: true, opacity: opacity)
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
    document.objects[0].fill = EditorFill(color: EditorColor(red: -1, green: 1, blue: 0))
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    document.objects[0].fill = nil
    for radius: CGFloat in [-1, 1001, .infinity, .nan] {
        document.objects[0].cornerRadius = radius
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
}
